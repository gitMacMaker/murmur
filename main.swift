// Offscreen preview renderer — snapshots the app's windows to PNGs so the
// design can be reviewed without launching the app. Not part of the app build.
// Usage: swiftc Theme.swift Settings.swift Onboarding.swift PillPanel.swift \
//        HotkeyManager.swift main.swift -o preview && ./preview
import AppKit
import SwiftUI

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
if let icon = NSImage(contentsOfFile: "icon_1024.png") {
    app.applicationIconImage = icon
}

func snap<V: View>(_ view: V, width: CGFloat, height: CGFloat, path: String) {
    // Back the view with the window background color: vibrancy-based labels
    // don't draw into cacheDisplay without a backdrop.
    let backed = ZStack { Color(nsColor: .windowBackgroundColor); view }
    let host = NSHostingView(rootView: backed)
    host.frame = NSRect(x: 0, y: 0, width: width, height: height)
    host.appearance = NSAppearance(named: .darkAqua)
    let window = NSWindow(contentRect: host.frame, styleMask: .borderless,
                          backing: .buffered, defer: false)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
        print("no rep for \(path)"); return
    }
    host.cacheDisplay(in: host.bounds, to: rep)
    guard let png = rep.representation(using: .png, properties: [:]) else {
        print("no png for \(path)"); return
    }
    try? png.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}

struct AppearancePreview: View {
    var body: some View {
        AppearancePane(settings: AppSettings.shared)
            .background(Palette.of(.dark).bg)
            .frame(width: 524, height: 500)
    }
}

// Text-pipeline smoke tests
let cmdIn = "First point, new line second point. New paragraph, the conclusion"
let cmdOut = TextCleaner.applyCommands(cmdIn)
print("commands: \(cmdOut.debugDescription)")
assert(cmdOut.contains("\n") && cmdOut.contains("\n\n"), "voice commands failed")

let reps = [Replacement(phrase: "my email", replacement: "you@example.com")]
let repOut = TextCleaner.applyReplacements("Send it to My Email please", reps)
print("replacement: \(repOut.debugDescription)")
assert(repOut.contains("you@example.com"), "replacement failed")

struct HistoryPreview: View {
    var body: some View {
        HistoryPane(settings: AppSettings.shared)
            .frame(width: 524, height: 500)
    }
}

let capOut = TextCleaner.capitalizeI("i think i'll go, since i'm ready")
print("capI: \(capOut)")
assert(capOut == "I think I'll go, since I'm ready", "capI failed: \(capOut)")

let smartOut = TextCleaner.smartPunctuation("it's \"quoted\" -- nice")
print("smart: \(smartOut)")
assert(smartOut.contains("\u{2019}") && smartOut.contains("\u{201C}") && smartOut.contains("\u{2014}"), "smart failed")

let varOut = TextCleaner.expandVariables("Sent on {date}")
print("vars: \(varOut)")
assert(!varOut.contains("{date}"), "vars failed")

// Sentence capitalization: first letter + after . ! ? and newlines.
let sentIn = "hello there. how are you? i am fine!\nnew line here"
let sentOut = TextCleaner.capitalizeSentences(sentIn)
print("sentences: \(sentOut.debugDescription)")
assert(sentOut == "Hello there. How are you? I am fine!\nNew line here", "sentences: \(sentOut)")

// Title case output.
let titleOut = TextCleaner.applyCase("the quick brown fox", .titleCase)
print("title: \(titleOut)")
assert(titleOut == "The Quick Brown Fox", "title: \(titleOut)")

// New voice symbols.
let symOut = TextCleaner.applyCommands("it was ninety degree sign hot, ellipsis right")
print("symbols: \(symOut.debugDescription)")
assert(symOut.contains("\u{00B0}") && symOut.contains("\u{2026}"), "symbols: \(symOut)")

// CSV round-trip: fields with commas, quotes, and newlines must survive.
let csvPhrase = "hello, \"world\""
let csvRepl = "line1\nline2"
let csvEsc: (String) -> String = { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
let csvText = "phrase,replacement\n\(csvEsc(csvPhrase)),\(csvEsc(csvRepl))\n"
let csvRows = DictionaryPane.parseCSV(csvText)
print("csv rows: \(csvRows.count) -> \(csvRows)")
assert(csvRows.count == 2, "csv row count: \(csvRows.count)")
assert(csvRows[1][0] == csvPhrase, "csv phrase: \(csvRows[1][0].debugDescription)")
assert(csvRows[1][1] == csvRepl, "csv repl: \(csvRows[1][1].debugDescription)")

// Backup round-trip: the new Extra block must export, and a backup without
// it (older format) must still decode instead of throwing.
let backupData = try! AppSettings.shared.exportBackup()
var decoded = try! JSONDecoder().decode(AppSettings.Backup.self, from: backupData)
print("backup extra present: \(decoded.extra != nil)")
assert(decoded.extra != nil, "backup missing extra block")
assert(decoded.extra?.waveBarCount == AppSettings.shared.waveBarCount, "backup extra roundtrip")
decoded.extra = nil
let stripped = try! JSONEncoder().encode(decoded)
let reDecoded = try! JSONDecoder().decode(AppSettings.Backup.self, from: stripped)
assert(reDecoded.extra == nil, "old-format backup should decode with nil extra")
print("backup back-compat OK")

struct StatsPreview2: View {
    var body: some View {
        StatsPane(settings: AppSettings.shared)
            .background(Palette.of(.dark).bg)
            .frame(width: 524, height: 760)
    }
}
snap(StatsPreview2(), width: 524, height: 760, path: "preview_stats2.png")

// Monochrome waveform proof (flip real default, snapshot, restore).
let origMono = AppSettings.shared.waveMonochrome
AppSettings.shared.waveMonochrome = true
snap(AppearancePreview(), width: 524, height: 500, path: "preview_mono.png")
AppSettings.shared.waveMonochrome = origMono

struct DictionaryPreview: View {
    var body: some View {
        DictionaryPane(settings: AppSettings.shared)
            .frame(width: 524, height: 500)
    }
}

// Skin renders (flip the real defaults, snapshot, restore)
let origSkin = AppSettings.shared.skin
AppSettings.shared.skin = .sketch
snap(SettingsRootView(), width: 700, height: 500, path: "preview_sketch_settings.png")
AppSettings.shared.skin = .terminal
snap(SettingsRootView(), width: 700, height: 500, path: "preview_terminal.png")
AppSettings.shared.skin = .retro
snap(SettingsRootView(), width: 700, height: 500, path: "preview_retro.png")
AppSettings.shared.skin = .neon
snap(AppearancePreview(), width: 524, height: 560, path: "preview_pill_neon.png")
AppSettings.shared.skin = origSkin

struct StatsPreview: View {
    var body: some View {
        StatsPane(settings: AppSettings.shared)
            .background(Palette.of(.dark).bg)
            .frame(width: 524, height: 620)
    }
}
snap(StatsPreview(), width: 524, height: 620, path: "preview_stats.png")

snap(HistoryPreview(), width: 524, height: 500, path: "preview_history.png")
snap(DictionaryPreview(), width: 524, height: 500, path: "preview_dictionary.png")
snap(SettingsRootView(), width: 700, height: 500, path: "preview_settings.png")
snap(AppearancePreview(), width: 524, height: 500, path: "preview_style.png")
snap(OnboardingView(onDone: {}), width: 440, height: 700, path: "preview_onboarding.png")
