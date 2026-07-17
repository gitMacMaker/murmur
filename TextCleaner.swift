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
    static func applyCommands(_ text: String, includeEmoji: Bool = true) -> String {
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
        let emojiCommands: [(String, String)] = includeEmoji ? [
            ("smiley face", "🙂"),
            ("winky face", "😉"),
            ("heart emoji", "❤️"),
            ("fire emoji", "🔥"),
            ("thumbs up emoji", "👍"),
            ("thumbs up", "👍"),
            ("rocket emoji", "🚀"),
            ("check mark", "✅"),
            ("shrug emoji", #"¯\_(ツ)_/¯"#),
        ] : []
        let symbolCommands: [(String, String)] = emojiCommands + [
            ("bullet point", "• "),
            ("em dash", "— "),
            ("open paren", "("),
            ("close paren", ")"),
            ("open quote", "\u{201C}"),
            ("close quote", "\u{201D}"),
            ("tab key", "\t"),
            ("degree sign", "\u{00B0}"),
            ("degree symbol", "\u{00B0}"),
            ("ellipsis", "\u{2026}"),
            ("dot dot dot", "\u{2026}"),
            ("copyright symbol", "\u{00A9}"),
            ("trademark symbol", "\u{2122}"),
            ("right arrow", "\u{2192}"),
            ("asterisk", "*"),
            ("hashtag", "#"),
            ("at sign", "@"),
            ("percent sign", "%"),
            ("ampersand", "&"),
        ]
        for (spoken, symbol) in symbolCommands {
            s = s.replacingOccurrences(
                of: "(?i)\\b\(spoken)\\b[,.]?",
                with: regexTemplate(symbol),
                options: .regularExpression)
        }
        let tf = DateFormatter(); tf.timeStyle = .short
        s = s.replacingOccurrences(of: "(?i)\\btoday's date\\b[,.]?",
                                   with: regexTemplate(AppSettings.shared.dateStyleChoice.format(Date())),
                                   options: .regularExpression)
        s = s.replacingOccurrences(of: "(?i)\\bcurrent time\\b[,.]?",
                                   with: regexTemplate(tf.string(from: Date())),
                                   options: .regularExpression)
        return s
    }

    /// Expands {date}, {time}, {weekday}, {month}, {year}, and {clipboard}
    /// placeholders (usable in dictionary replacement values).
    static func expandVariables(_ text: String) -> String {
        guard text.contains("{") else { return text }
        var s = text
        let tf = DateFormatter(); tf.timeStyle = .short
        let wf = DateFormatter(); wf.dateFormat = "EEEE"
        let mf = DateFormatter(); mf.dateFormat = "MMMM"
        let yf = DateFormatter(); yf.dateFormat = "yyyy"
        s = s.replacingOccurrences(of: "{date}",
                                   with: AppSettings.shared.dateStyleChoice.format(Date()))
        s = s.replacingOccurrences(of: "{time}", with: tf.string(from: Date()))
        s = s.replacingOccurrences(of: "{weekday}", with: wf.string(from: Date()))
        s = s.replacingOccurrences(of: "{month}", with: mf.string(from: Date()))
        s = s.replacingOccurrences(of: "{year}", with: yf.string(from: Date()))
        if s.contains("{greeting}") {
            s = s.replacingOccurrences(of: "{greeting}",
                                       with: greeting(style: AppSettings.shared.greetingStyle))
        }
        if s.contains("{app}") {
            s = s.replacingOccurrences(of: "{app}",
                                       with: NSWorkspace.shared.frontmostApplication?.localizedName ?? "")
        }
        if s.contains("{clipboard}") {
            s = s.replacingOccurrences(of: "{clipboard}",
                                       with: NSPasteboard.general.string(forType: .string) ?? "")
        }
        return s
    }

    /// Spelled-out numbers → digits ("twenty five" → 25, "seven" → 7).
    /// Handles zero–twenty, tens, and tens-plus-unit compounds.
    static func numbersToDigits(_ text: String) -> String {
        let units = ["zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
                     "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
                     "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14,
                     "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18,
                     "nineteen": 19, "twenty": 20]
        let tens = ["twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
                    "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90]
        var s = text
        // Compounds first ("twenty five" / "twenty-five"), then lone tens/units.
        for (tWord, tVal) in tens {
            for (uWord, uVal) in units where (1...9).contains(uVal) {
                s = s.replacingOccurrences(
                    of: "(?i)\\b\(tWord)[ -]\(uWord)\\b",
                    with: "\(tVal + uVal)",
                    options: .regularExpression)
            }
        }
        for (word, val) in tens.merging(units, uniquingKeysWith: { a, _ in a }) {
            s = s.replacingOccurrences(
                of: "(?i)\\b\(word)\\b",
                with: "\(val)",
                options: .regularExpression)
        }
        return s
    }

    /// Collapses accidental doubled words: "the the" → "the".
    /// Words in the whitelist ("very very") are left alone.
    static func removeDoubledWords(_ text: String,
                                   whitelist: [String] = AppSettings.shared.doubledWhitelist) -> String {
        var s = text
        let keep = Set(whitelist.map { $0.lowercased() })
        guard let regex = try? NSRegularExpression(pattern: "\\b(\\w+)(\\s+\\1)+\\b",
                                                   options: .caseInsensitive) else { return s }
        var previous: String
        repeat {
            previous = s
            let ns = s as NSString
            for m in regex.matches(in: s, range: NSRange(location: 0, length: ns.length)).reversed() {
                guard let full = Range(m.range, in: s),
                      let word = Range(m.range(at: 1), in: s) else { continue }
                if keep.contains(String(s[word]).lowercased()) { continue }
                s.replaceSubrange(full, with: String(s[word]))
            }
        } while s != previous
        return s
    }

    /// Adds a trailing period when the text doesn't already end in punctuation.
    static func ensureEndPunctuation(_ text: String) -> String {
        guard let last = text.last, !text.isEmpty else { return text }
        return ".!?…:;,".contains(last) ? text : text + "."
    }

    /// Strips leading conversational starters — the list is user-editable.
    static func stripStarterWords(_ text: String,
                                  words: [String] = AppSettings.shared.starterWords) -> String {
        let usable = words.map { NSRegularExpression.escapedPattern(for: $0.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.isEmpty }
        guard !usable.isEmpty else { return text }
        var s = text
        var previous: String
        repeat {
            previous = s
            s = s.replacingOccurrences(of: "(?i)^(\(usable.joined(separator: "|")))[,]?\\s+",
                                       with: "",
                                       options: .regularExpression)
        } while s != previous
        return s
    }

    /// Collapses 3+ consecutive newlines down to a single blank line.
    static func collapseBlankLines(_ text: String) -> String {
        text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
    }

    /// Ensures exactly one space after sentence punctuation ("a.Next" → "a. Next").
    static func ensureSentenceSpacing(_ text: String) -> String {
        text.replacingOccurrences(of: "([.!?])([A-Z])", with: "$1 $2", options: .regularExpression)
    }

    /// Forces any user-listed word to its exact typed casing wherever it
    /// appears — so "iphone"/"IPHONE" both become "iPhone".
    static func capitalizeProperNouns(_ text: String, _ words: [String]) -> String {
        var s = text
        for word in words.map({ $0.trimmingCharacters(in: .whitespaces) }) where word.count > 1 {
            let escaped = NSRegularExpression.escapedPattern(for: word)
            s = s.replacingOccurrences(of: "(?i)\\b\(escaped)\\b",
                                       with: word.replacingOccurrences(of: "$", with: "\\$"),
                                       options: .regularExpression)
        }
        return s
    }

    /// Strips common Markdown emphasis/heading syntax from polished text.
    static func stripMarkdown(_ text: String) -> String {
        var s = text
        s = s.replacingOccurrences(of: "(\\*\\*|__)(.+?)\\1", with: "$2", options: .regularExpression)
        s = s.replacingOccurrences(of: "(\\*|_)(.+?)\\1", with: "$2", options: .regularExpression)
        s = s.replacingOccurrences(of: "(?m)^#{1,6}\\s*", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "(?m)^\\s*[-*]\\s+", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "`(.+?)`", with: "$1", options: .regularExpression)
        return s
    }

    /// Lowercases the very first letter (for lowercase-chat style).
    static func lowercaseFirst(_ text: String) -> String {
        guard let first = text.first, first.isUppercase else { return text }
        return first.lowercased() + text.dropFirst()
    }

    /// Capitalizes the first letter after a colon+space.
    static func capitalizeAfterColon(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "(:\\s+)([a-z])") else { return text }
        var out = text
        let ns = out as NSString
        for m in regex.matches(in: out, range: NSRange(location: 0, length: ns.length)).reversed() {
            guard let r = Range(m.range(at: 2), in: out) else { continue }
            out.replaceSubrange(r, with: out[r].uppercased())
        }
        return out
    }

    /// Removes a matching pair of surrounding quotes.
    static func trimSurroundingQuotes(_ text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespaces)
        let pairs: [(Character, Character)] = [("\"", "\""), ("\u{201C}", "\u{201D}"), ("'", "'")]
        for (open, close) in pairs where t.count >= 2 && t.first == open && t.last == close {
            return String(t.dropFirst().dropLast())
        }
        return text
    }

    /// A time-of-day greeting for the {greeting} variable / prefix.
    static func greeting(style: Int = 0) -> String {
        let h = Calendar.current.component(.hour, from: Date())
        let part = h < 12 ? "morning" : (h < 18 ? "afternoon" : "evening")
        return style == 1 ? "Good \(part)," : "Good \(part)"
    }

    /// "scratch that" — drops everything dictated before (and including) the
    /// last occurrence, keeping only what was said after it.
    static func applyScratchThat(_ text: String) -> String {
        guard let range = text.range(of: "(?i)\\bscratch that\\b[,.]?\\s*",
                                     options: [.regularExpression, .backwards]) else { return text }
        return String(text[range.upperBound...])
            .trimmingCharacters(in: .whitespaces)
    }

    /// Explicit spoken punctuation: "period" → ".", "comma" → ",", etc.
    /// Attaches to the preceding word and eats the recognizer's own
    /// trailing punctuation on the spoken word.
    static func applySpokenPunctuation(_ text: String) -> String {
        var s = text
        let marks: [(String, String)] = [
            ("question mark", "?"),
            ("exclamation point", "!"),
            ("exclamation mark", "!"),
            ("semicolon", ";"),
            ("period", "."),
            ("comma", ","),
            ("colon", ":"),
            ("hyphen", "-"),
            ("underscore", "_"),
            ("forward slash", "/"),
        ]
        for (spoken, mark) in marks {
            s = s.replacingOccurrences(
                of: "\\s*(?i)\\b\(spoken)\\b[,.]?",
                with: mark,
                options: .regularExpression)
        }
        return s
    }

    /// Masks censored words in the chosen style: d*** / •••• / [redacted].
    /// `insideWords` also matches the word embedded in longer words.
    static func censor(_ text: String, words: [String],
                       style: CensorStyle = .asterisks,
                       insideWords: Bool = false) -> String {
        var s = text
        let b = insideWords ? "" : "\\b"
        for word in words.map({ $0.trimmingCharacters(in: .whitespaces) }) where word.count > 1 {
            let first = NSRegularExpression.escapedPattern(for: String(word.prefix(1)))
            let rest = NSRegularExpression.escapedPattern(for: String(word.dropFirst()))
            let replacement: String
            switch style {
            case .asterisks: replacement = "$1" + String(repeating: "*", count: word.count - 1)
            case .bullets: replacement = String(repeating: "\u{2022}", count: word.count)
            case .redacted: replacement = "[redacted]"
            }
            s = s.replacingOccurrences(
                of: "(?i)\(b)(\(first))\(rest)\(b)",
                with: replacement,
                options: .regularExpression)
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
    /// wins over "my email". Case-insensitive, word-boundary matches (both
    /// configurable), optionally preserving the spoken capitalization.
    static func applyReplacements(_ text: String, _ replacements: [Replacement]) -> String {
        var s = text
        let settings = AppSettings.shared
        let usable = replacements
            .filter { $0.enabled && !$0.phrase.isEmpty && !$0.replacement.isEmpty }
            .sorted { $0.phrase.count > $1.phrase.count }
        let flag = settings.caseSensitiveReplacements ? "" : "(?i)"
        let boundary = settings.matchInsideWords ? "" : "\\b"
        for r in usable {
            // Advanced mode: a phrase wrapped in slashes is a raw regex whose
            // replacement may use $1-style groups.
            let isRegex = settings.regexReplacements && r.phrase.count > 2
                && r.phrase.hasPrefix("/") && r.phrase.hasSuffix("/")
            let escaped = isRegex
                ? String(r.phrase.dropFirst().dropLast())
                : NSRegularExpression.escapedPattern(for: r.phrase)
            let pattern = isRegex ? "\(flag)\(escaped)" : "\(flag)\(boundary)\(escaped)\(boundary)"
            guard (try? NSRegularExpression(pattern: pattern)) != nil else { continue }
            if isRegex {
                s = s.replacingOccurrences(of: pattern, with: r.replacement,
                                           options: .regularExpression)
                continue
            }
            if settings.preserveCaseReplacements, !settings.caseSensitiveReplacements,
               let regex = try? NSRegularExpression(pattern: pattern) {
                // Walk matches back-to-front so ranges stay valid, matching
                // the replacement's capitalization to the spoken phrase's.
                let ns = s as NSString
                let matches = regex.matches(in: s, range: NSRange(location: 0, length: ns.length))
                var out = s
                for m in matches.reversed() {
                    guard let range = Range(m.range, in: out) else { continue }
                    let spoken = String(out[range])
                    var repl = r.replacement
                    if let first = spoken.first, first.isUppercase, let rFirst = repl.first {
                        repl = String(rFirst).uppercased() + repl.dropFirst()
                    }
                    out.replaceSubrange(range, with: repl)
                }
                s = out
            } else {
                s = s.replacingOccurrences(
                    of: pattern,
                    with: regexTemplate(r.replacement),
                    options: .regularExpression)
            }
        }
        return s
    }

    static func applyCase(_ text: String, _ c: OutputCase) -> String {
        switch c {
        case .asSpoken: return text
        case .lowercase: return text.lowercased()
        case .uppercase: return text.uppercased()
        case .titleCase: return text.capitalized
        }
    }

    /// Capitalizes the first letter of the text and of each sentence
    /// (after `.`, `!`, `?`, or a newline).
    static func capitalizeSentences(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var chars = Array(text)
        var capitalizeNext = true
        for i in chars.indices {
            let c = chars[i]
            if capitalizeNext, c.isLetter {
                chars[i] = Character(String(c).uppercased())
                capitalizeNext = false
            } else if ".!?\n".contains(c) {
                capitalizeNext = true
            } else if !c.isWhitespace && c != "\"" && c != "\u{201C}" && c != "(" {
                capitalizeNext = false
            }
        }
        return String(chars)
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
        // Post-process: optionally strip Markdown the model may add; if a
        // retry is allowed and polish returned the text unchanged (failure),
        // try once more.
        var attempted = false
        func finish(_ out: String) {
            let cleaned = AppSettings.shared.stripMarkdownOutput ? stripMarkdown(out) : out
            if AppSettings.shared.polishRetry, !attempted, cleaned == text {
                attempted = true
                run(text, instruction: instruction, completion: finish)
                return
            }
            completion(cleaned)
        }
        run(text, instruction: instruction, completion: finish)
    }

    /// AI Command Mode: apply a spoken instruction to selected text (or
    /// generate fresh text when nothing is selected). Routes through the same
    /// API-key / CLI backend as polish.
    static func command(selection: String, instruction: String,
                        completion: @escaping (String) -> Void) {
        let prompt: String
        if selection.isEmpty {
            prompt = """
            Follow this instruction and output ONLY the resulting text, with no \
            preamble, quotes, or explanation: \(instruction)
            """
        } else {
            prompt = """
            Apply the following instruction to the text below. Output ONLY the \
            rewritten text — no preamble, no quotes, no explanation.

            Instruction: \(instruction)

            Text:
            \(selection)
            """
        }
        // The composed prompt is the user message; the system role keeps the
        // model terse. (For the CLI backend the instruction becomes the
        // `-p` prompt and the text is piped as stdin — same shape as polish.)
        let system = "You are a precise writing assistant. Do exactly what the user asks and output only the resulting text."
        run(prompt, instruction: system, completion: completion)
    }

    /// One polish attempt via the user's chosen backend.
    private static func run(_ text: String, instruction: String,
                            completion: @escaping (String) -> Void) {
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
            let timeout = TimeInterval(AppSettings.shared.polishTimeout)
            let deadline = DispatchWorkItem { if proc.isRunning { proc.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)

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
