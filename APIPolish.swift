import Foundation
import Security

// MARK: - Keychain storage for the user's Anthropic API key
// The key never touches UserDefaults, the settings backup, or the repo.

enum APIKeyStore {
    private static let service = "com.blake.murmur"
    private static let account = "anthropic-api-key"

    static func save(_ key: String) {
        delete()
        guard !key.isEmpty, let data = key.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    static var exists: Bool { load() != nil }
}

// MARK: - Claude CLI detection

enum ClaudeCLI {
    /// Cached result of the last detection.
    private(set) static var found: Bool?

    /// Checks whether the `claude` CLI is on the login shell's PATH.
    static func detect(_ completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
            proc.arguments = ["-lc", "command -v claude"]
            proc.standardOutput = Pipe()
            proc.standardError = Pipe()
            let ok = (try? proc.run()) != nil
            if ok { proc.waitUntilExit() }
            let result = ok && proc.terminationStatus == 0
            DispatchQueue.main.async {
                found = result
                completion(result)
            }
        }
    }
}

// MARK: - Direct Anthropic API polish

enum APIPolish {
    /// Rewrites the transcript via the Anthropic Messages API using the
    /// user's own key. Calls `completion` with the polished text, or the
    /// original text on any failure.
    static func polish(_ text: String, instruction: String, apiKey: String,
                       completion: @escaping (String) -> Void) {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = TimeInterval(AppSettings.shared.polishTimeout)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": AppSettings.shared.apiModel,
            "max_tokens": 16000,
            "system": instruction,
            "messages": [["role": "user", "content": text]],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else {
            DispatchQueue.main.async { completion(text) }
            return
        }
        request.httpBody = data

        URLSession.shared.dataTask(with: request) { data, response, _ in
            var polished = text
            if let http = response as? HTTPURLResponse, http.statusCode == 200,
               let data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let content = json["content"] as? [[String: Any]] {
                let joined = content
                    .filter { $0["type"] as? String == "text" }
                    .compactMap { $0["text"] as? String }
                    .joined()
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !joined.isEmpty { polished = joined }
            }
            DispatchQueue.main.async { completion(polished) }
        }.resume()
    }
}
