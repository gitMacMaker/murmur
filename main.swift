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
snap(OnboardingView(onDone: {}), width: 440, height: 560, path: "preview_onboarding.png")
