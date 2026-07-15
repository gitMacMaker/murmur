import AppKit
import Foundation

/// Local, instant cleanup of dictated text plus an optional AI polish pass
/// that pipes the transcript through the `claude` CLI.
enum TextCleaner {

    /// Strips filler words and tidies whitespace/punctuation artifacts.
    static func tidy(_ text: String) -> String {
        var s = text
        let fillers = AppSettings.shared.fillerWords
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        for f in fillers.map({ NSRegularExpression.escapedPattern(for: $0) }) {
            s = s.replacingOccurrences(
                of: "(?i)(^|[\\s,])\(f)([\\s,.!?]|$)",
                with: "$1$2",
                options: .regularExpression)
        }
        s = s.replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\s+([,.!?])", with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: "([,.])\\1+", with: "$1", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Converts spoken commands into formatting: "new line" → \n,
    /// "new paragraph" → blank line. Eats surrounding commas/periods the
    /// recognizer tends to add around them.
    static func applyCommands(_ text: String) -> String {
        var s = text
        let lineCommands: [(String, String)] = [
            ("new paragraph", "\n\n"),
            ("new line", "\n"),
        ]
        for (spoken, inserted) in lineCommands {
            s = s.replacingOccurrences(
                of: "[,.]?\\s*(?i:\\b\(spoken)\\b)[,.]?\\s*",
                with: inserted,
                options: .regularExpression)
        }
        let symbolCommands: [(String, String)] = [
            ("bullet point", "• "),
            ("em dash", "— "),
            ("smiley face", "🙂"),
            ("winky face", "😉"),
            ("heart emoji", "❤️"),
            ("fire emoji", "🔥"),
            ("thumbs up emoji", "👍"),
            ("thumbs up", "👍"),
            ("rocket emoji", "🚀"),
            ("check mark", "✅"),
            ("shrug emoji", #"¯\_(ツ)_/¯"#),
            ("open paren", "("),
            ("close paren", ")"),
            ("open quote", "\u{201C}"),
            ("close quote", "\u{201D}"),
            ("tab key", "\t"),
        ]
        for (spoken, symbol) in symbolCommands {
            s = s.replacingOccurrences(
                of: "(?i)\\b\(spoken)\\b[,.]?",
                with: regexTemplate(symbol),
                options: .regularExpression)
        }
        let df = DateFormatter(); df.dateStyle = .medium
        let tf = DateFormatter(); tf.timeStyle = .short
        s = s.replacingOccurrences(of: "(?i)\\btoday's date\\b[,.]?",
                                   with: regexTemplate(df.string(from: Date())),
                                   options: .regularExpression)
        s = s.replacingOccurrences(of: "(?i)\\bcurrent time\\b[,.]?",
                                   with: regexTemplate(tf.string(from: Date())),
                                   options: .regularExpression)
        return s
    }

    /// Expands {date}, {time}, and {clipboard} placeholders (usable in
    /// dictionary replacement values).
    static func expandVariables(_ text: String) -> String {
        guard text.contains("{") else { return text }
        var s = text
        let df = DateFormatter(); df.dateStyle = .medium
        let tf = DateFormatter(); tf.timeStyle = .short
        s = s.replacingOccurrences(of: "{date}", with: df.string(from: Date()))
        s = s.replacingOccurrences(of: "{time}", with: tf.string(from: Date()))
        if s.contains("{clipboard}") {
            s = s.replacingOccurrences(of: "{clipboard}",
                                       with: NSPasteboard.general.string(forType: .string) ?? "")
        }
        return s
    }

    /// Capitalizes standalone "i" (and i'm / i'll / i've / i'd).
    static func capitalizeI(_ text: String) -> String {
        text.replacingOccurrences(of: "(^|[\\s\u{201C}\\(])i(?=[\\s.,!?';:\\)]|$|'m|'ll|'ve|'d)",
                                  with: "$1I",
                                  options: .regularExpression)
    }

    /// Straight quotes → curly, double-hyphen → em dash.
    static func smartPunctuation(_ text: String) -> String {
        var s = text
        s = s.replacingOccurrences(of: "(?<=\\w)'", with: "\u{2019}", options: .regularExpression)
        s = s.replacingOccurrences(of: "'(?=\\w)", with: "\u{2018}", options: .regularExpression)
        s = s.replacingOccurrences(of: "(^|\\s)\"", with: "$1\u{201C}", options: .regularExpression)
        s = s.replacingOccurrences(of: "\"", with: "\u{201D}")
        s = s.replacingOccurrences(of: "\\s--\\s", with: " \u{2014} ", options: .regularExpression)
        return s
    }

    /// Did `applyCommands` change anything? (Used for the Commander achievement.)
    static func containsCommand(_ text: String) -> Bool {
        applyCommands(text) != text
    }

    /// Applies the user's dictionary: longer phrases first so "my work email"
    /// wins over "my email". Case-insensitive, word-boundary matches.
    static func applyReplacements(_ text: String, _ replacements: [Replacement]) -> String {
        var s = text
        let usable = replacements
            .filter { $0.enabled && !$0.phrase.isEmpty && !$0.replacement.isEmpty }
            .sorted { $0.phrase.count > $1.phrase.count }
        let flag = AppSettings.shared.caseSensitiveReplacements ? "" : "(?i)"
        for r in usable {
            let escaped = NSRegularExpression.escapedPattern(for: r.phrase)
            s = s.replacingOccurrences(
                of: "\(flag)\\b\(escaped)\\b",
                with: regexTemplate(r.replacement),
                options: .regularExpression)
        }
        return s
    }

    static func applyCase(_ text: String, _ c: OutputCase) -> String {
        switch c {
        case .asSpoken: return text
        case .lowercase: return text.lowercased()
        case .uppercase: return text.uppercased()
        }
    }

    /// Escapes `\` and `$` so replacement text is inserted literally.
    private static func regexTemplate(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "$", with: "\\$")
    }

    /// Rewrites the transcript with Claude for punctuation, paragraphs, and
    /// false-start removal. Falls back to the raw text on any failure.
    static func polish(_ text: String, tone: PolishTone, custom: String = "",
                       completion: @escaping (String) -> Void) {
        let instruction = polishPrompt(tone: tone, custom: custom)
        // Prefer the user's own Anthropic API key when they chose that engine;
        // otherwise shell out to the local claude CLI.
        if AppSettings.shared.polishBackend == .api, let key = APIKeyStore.load() {
            APIPolish.polish(text, instruction: instruction, apiKey: key, completion: completion)
            return
        }
        cliPolish(text, instruction: instruction, completion: completion)
    }

    static func polishPrompt(tone: PolishTone, custom: String) -> String {
            let toneInstruction: String
            switch tone {
            case .custom where !custom.trimmingCharacters(in: .whitespaces).isEmpty:
                toneInstruction = "Additionally, follow this instruction from the user: \(custom)"
            case .clean, .custom:
                toneInstruction = "Keep the speaker's exact meaning, tone, and wording otherwise."
            case .email:
                toneInstruction = """
                Shape it into polished, professional prose suitable for a work \
                email — clear and courteous, but keep the speaker's meaning and \
                don't add greetings or sign-offs that weren't dictated.
                """
            case .casual:
                toneInstruction = """
                Keep it relaxed and conversational — preserve slang and \
                personality, just make it read smoothly.
                """
            }
            return """
            Clean up this dictated text: fix punctuation, capitalization, and \
            paragraph breaks; remove filler words and false starts. \
            \(toneInstruction) Output ONLY the cleaned text, nothing else.
            """
    }

    private static func cliPolish(_ text: String, instruction: String,
                                  completion: @escaping (String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let prompt = instruction
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
            proc.arguments = ["-lc", "claude -p " + shellQuote(prompt)]
            let inPipe = Pipe(), outPipe = Pipe()
            proc.standardInput = inPipe
            proc.standardOutput = outPipe
            proc.standardError = Pipe()

            do {
                try proc.run()
                inPipe.fileHandleForWriting.write(Data(text.utf8))
                inPipe.fileHandleForWriting.closeFile()
            } catch {
                DispatchQueue.main.async { completion(text) }
                return
            }

            // Don't hang forever if the CLI stalls.
            let deadline = DispatchWorkItem { if proc.isRunning { proc.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: deadline)

            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            deadline.cancel()

            let out = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            DispatchQueue.main.async {
                completion(proc.terminationStatus == 0 && !out.isEmpty ? out : text)
            }
        }
    }

    private static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
