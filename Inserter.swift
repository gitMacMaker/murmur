import AppKit

/// Puts text into the frontmost app — clipboard-swap + synthetic ⌘V by
/// default, or key-by-key typing when the user enabled that mode.
/// Shared by the dictation pipeline, menu items, and the History pane.
enum Inserter {
    /// Splits out a {cursor} marker: returns the clean text and how many
    /// characters sit after the marker (→ left-arrow presses post-insert).
    static func extractCursor(_ text: String) -> (text: String, stepsBack: Int) {
        guard let range = text.range(of: "{cursor}") else { return (text, 0) }
        let after = text[range.upperBound...]
        var clean = text
        clean.removeSubrange(range)
        return (clean, after.count)
    }

    static func insert(_ raw: String) {
        let (text, stepsBack) = extractCursor(raw)
        if AppSettings.shared.typeInsteadOfPaste, AXIsProcessTrusted() {
            type(text)
            stepBack(stepsBack)
            return
        }
        let pb = NSPasteboard.general
        let saved: [[NSPasteboard.PasteboardType: Data]] = (pb.pasteboardItems ?? []).map { item in
            var copy: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types { copy[type] = item.data(forType: type) }
            return copy
        }
        pb.clearContents()
        pb.setString(text, forType: .string)

        guard AXIsProcessTrusted() else { return } // stays in clipboard; user pastes manually

        // Optional pause for apps that are slow to regain focus.
        let delay = AppSettings.shared.insertDelay
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, delay)) {
            let src = CGEventSource(stateID: .combinedSessionState)
            // ⌥⇧⌘V = Paste and Match Style, when the user opted in.
            let flags: CGEventFlags = AppSettings.shared.pasteMatchStyle
                ? [.maskCommand, .maskShift, .maskAlternate] : .maskCommand
            let vDown = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true)
            let vUp = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)
            vDown?.flags = flags
            vUp?.flags = flags
            vDown?.post(tap: .cghidEventTap)
            vUp?.post(tap: .cghidEventTap)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { stepBack(stepsBack) }
        }

        let restoreAfter = max(0.3, AppSettings.shared.restoreDelay) + max(0, delay)
        DispatchQueue.main.asyncAfter(deadline: .now() + restoreAfter) {
            guard !AppSettings.shared.keepTranscriptOnClipboard, !saved.isEmpty else { return }
            pb.clearContents()
            let items = saved.map { dict -> NSPasteboardItem in
                let item = NSPasteboardItem()
                for (type, data) in dict { item.setData(data, forType: type) }
                return item
            }
            pb.writeObjects(items)
        }
    }

    /// Left-arrow presses that walk the cursor back to a {cursor} marker.
    private static func stepBack(_ steps: Int) {
        guard steps > 0, AXIsProcessTrusted() else { return }
        let src = CGEventSource(stateID: .combinedSessionState)
        for _ in 0..<steps {
            CGEvent(keyboardEventSource: src, virtualKey: 123, keyDown: true)?.post(tap: .cghidEventTap)
            CGEvent(keyboardEventSource: src, virtualKey: 123, keyDown: false)?.post(tap: .cghidEventTap)
            usleep(4000)
        }
    }

    /// Copies to the clipboard only (clipboard-only insert mode).
    static func copyOnly(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    /// Types text directly via synthetic key events — slower than paste but
    /// works in apps that block or remap ⌘V. Newlines become Return presses.
    static func type(_ text: String) {
        let src = CGEventSource(stateID: .combinedSessionState)
        let lines = text.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() {
            let chars = Array(line.utf16)
            var index = 0
            while index < chars.count {
                var buffer = Array(chars[index..<min(index + 16, chars.count)])
                let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true)
                down?.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: &buffer)
                down?.post(tap: .cghidEventTap)
                let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false)
                up?.post(tap: .cghidEventTap)
                usleep(9000)
                index += 16
            }
            if i < lines.count - 1 {
                let ret = CGEvent(keyboardEventSource: src, virtualKey: 36, keyDown: true)
                ret?.post(tap: .cghidEventTap)
                let retUp = CGEvent(keyboardEventSource: src, virtualKey: 36, keyDown: false)
                retUp?.post(tap: .cghidEventTap)
                usleep(9000)
            }
        }
    }
}
