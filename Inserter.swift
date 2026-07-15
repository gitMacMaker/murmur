import AppKit

/// Puts text into the frontmost app — clipboard-swap + synthetic ⌘V by
/// default, or key-by-key typing when the user enabled that mode.
/// Shared by the dictation pipeline, menu items, and the History pane.
enum Inserter {
    static func insert(_ text: String) {
        if AppSettings.shared.typeInsteadOfPaste, AXIsProcessTrusted() {
            type(text)
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

        let src = CGEventSource(stateID: .combinedSessionState)
        let vDown = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true)
        let vUp = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)
        vDown?.flags = .maskCommand
        vUp?.flags = .maskCommand
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
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
