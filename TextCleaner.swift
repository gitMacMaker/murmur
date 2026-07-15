import Foundation

/// Local, instant cleanup of dictated text plus an optional AI polish pass
/// that pipes the transcript through the `claude` CLI.
enum TextCleaner {

    /// Strips filler words and tidies whitespace/punctuation artifacts.
    static func tidy(_ text: String) -> String {
        var s = text
        let fillers = ["um", "uh", "uhm", "erm", "er", "you know like"]
        for f in fillers {
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
        ]
        for (spoken, symbol) in symbolCommands {
            s = s.replacingOccurrences(
                of: "(?i)\\b\(spoken)\\b[,.]?",
                with: regexTemplate(symbol),
                options: .regularExpression)
        }
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
            .filter { !$0.phrase.isEmpty && !$0.replacement.isEmpty }
            .sorted { $0.phrase.count > $1.phrase.count }
        for r in usable {
            let escaped = NSRegularExpression.escapedPattern(for: r.phrase)
            s = s.replacingOccurrences(
                of: "(?i)\\b\(escaped)\\b",
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
