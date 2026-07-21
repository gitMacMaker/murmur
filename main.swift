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

func snap<V: View>(_ view: V, width: CGFloat, height: CGFloat, path: String,
                   light: Bool = false) {
    // Back the view with the window background color: vibrancy-based labels
    // don't draw into cacheDisplay without a backdrop.
    let backed = ZStack { Color(nsColor: .windowBackgroundColor); view }
    let host = NSHostingView(rootView: backed)
    host.frame = NSRect(x: 0, y: 0, width: width, height: height)
    host.appearance = NSAppearance(named: light ? .aqua : .darkAqua)
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

// Spoken punctuation: words become marks attached to the previous word.
let spokenOut = TextCleaner.applySpokenPunctuation("hello period how are you question mark")
print("spoken: \(spokenOut.debugDescription)")
assert(spokenOut == "hello. how are you?", "spoken: \(spokenOut)")

// Scratch that: keep only what follows the last occurrence.
let scratchOut = TextCleaner.applyScratchThat("this is wrong, scratch that, this is right")
print("scratch: \(scratchOut.debugDescription)")
assert(scratchOut == "this is right", "scratch: \(scratchOut)")
assert(TextCleaner.applyScratchThat("no command here") == "no command here", "scratch no-op")

// Censor: first letter + asterisks, word-boundary, case-insensitive.
let censorOut = TextCleaner.censor("Damn, that darn thing", words: ["damn", "darn"])
print("censor: \(censorOut.debugDescription)")
assert(censorOut == "D***, that d*** thing", "censor: \(censorOut)")

// New template variables.
let wkOut = TextCleaner.expandVariables("{weekday} in {month} {year}")
print("varsNew: \(wkOut)")
assert(!wkOut.contains("{"), "varsNew: \(wkOut)")

// Numbers to digits: compounds and singles.
let numOut = TextCleaner.numbersToDigits("twenty five dollars and seven cents")
print("numbers: \(numOut.debugDescription)")
assert(numOut == "25 dollars and 7 cents", "numbers: \(numOut)")

// Doubled words collapse (case-insensitive).
let dblOut = TextCleaner.removeDoubledWords("the the quick brown brown brown fox")
print("doubled: \(dblOut.debugDescription)")
assert(dblOut == "the quick brown fox", "doubled: \(dblOut)")

// End punctuation only when missing.
assert(TextCleaner.ensureEndPunctuation("hello") == "hello.", "endPunct add")
assert(TextCleaner.ensureEndPunctuation("hello!") == "hello!", "endPunct keep")

// Starter words stripped repeatedly.
let startOut = TextCleaner.stripStarterWords("So, well, this is the point")
print("starters: \(startOut.debugDescription)")
assert(startOut == "this is the point", "starters: \(startOut)")

// Censor styles.
assert(TextCleaner.censor("damn", words: ["damn"], style: .bullets) == "••••", "censor bullets")
assert(TextCleaner.censor("damn", words: ["damn"], style: .redacted) == "[redacted]", "censor redacted")

// {cursor} extraction.
let cur = Inserter.extractCursor("Dear {cursor},\nBest")
print("cursor: \(cur)")
assert(cur.text == "Dear ,\nBest" && cur.stepsBack == 6, "cursor: \(cur)")
assert(Inserter.extractCursor("plain").stepsBack == 0, "cursor no-op")

// Emoji gate: off leaves the phrase alone, on converts.
assert(TextCleaner.applyCommands("fire emoji", includeEmoji: false) == "fire emoji", "emoji gate off")
assert(TextCleaner.applyCommands("fire emoji", includeEmoji: true).contains("🔥"), "emoji gate on")

// Backup Extra2 round-trip.
let bk2 = try! AppSettings.shared.exportBackup()
let dec2 = try! JSONDecoder().decode(AppSettings.Backup.self, from: bk2)
assert(dec2.extra2 != nil, "backup missing extra2")
assert(dec2.extra2?.barWidth == AppSettings.shared.barWidth, "extra2 roundtrip")
print("backup extra2 OK")

// v2.7 engine features.
assert(TextCleaner.collapseBlankLines("a\n\n\n\n\nb") == "a\n\nb", "collapse blank lines")
assert(TextCleaner.ensureSentenceSpacing("End.Next one!Go") == "End. Next one! Go", "sentence spacing")
assert(TextCleaner.capitalizeProperNouns("i love github and iphone", ["GitHub", "iPhone"])
       == "i love GitHub and iPhone", "proper nouns")
assert(TextCleaner.stripMarkdown("**bold** and *em* and `code`\n# Head") == "bold and em and code\nHead",
       "strip markdown")
assert(TextCleaner.lowercaseFirst("Hello there") == "hello there", "lowercase first")
assert(TextCleaner.capitalizeAfterColon("note: this is it") == "note: This is it", "cap after colon")
assert(TextCleaner.trimSurroundingQuotes("\u{201C}quoted\u{201D}") == "quoted", "trim quotes")
assert(TextCleaner.trimSurroundingQuotes("no quotes") == "no quotes", "trim quotes no-op")
let greet = TextCleaner.greeting()
assert(greet.hasPrefix("Good "), "greeting: \(greet)")

// Backup Extra4 round-trip.
let bk5 = try! AppSettings.shared.exportBackup()
let dec5 = try! JSONDecoder().decode(AppSettings.Backup.self, from: bk5)
assert(dec5.extra4 != nil, "backup missing extra4")
assert(dec5.extra4?.undoDepth == AppSettings.shared.undoDepth, "extra4 roundtrip")
assert(dec5.extra4?.commandHotkey?.keyCode == AppSettings.shared.commandHotkey.keyCode,
       "command hotkey backup roundtrip")
print("v2.7 engine + backup OK")

// AppRule.grammar back-compat + rule with grammar round-trips.
let gRule = try! JSONDecoder().decode([AppRule].self,
    from: Data(#"[{"appName":"Mail","grammar":true}]"#.utf8))
assert(gRule[0].grammar == true && gRule[0].tone == .clean, "grammar rule decode")
let oldRule2 = try! JSONDecoder().decode([AppRule].self,
    from: Data(#"[{"appName":"Mail"}]"#.utf8))
assert(oldRule2[0].grammar == nil, "grammar back-compat")
print("apps tab rules OK")

// An even 100 skins (99 named + Custom), every spec resolving to a palette.
assert(AppSkin.allCases.count == 100, "skin count: \(AppSkin.allCases.count)")
for skin in AppSkin.allCases where skin.spec != nil {
    _ = skin.spec!.palette  // touch every generated palette
}
print("skins: \(AppSkin.allCases.count)")

// v2.8 workflow features.
let webOut = TextCleaner.applyWebShortcuts("go to getmurmur dot com or w w w dot example dot org")
print("web: \(webOut.debugDescription)")
assert(webOut == "go to getmurmur.com or www.example.org", "web shortcuts: \(webOut)")

let sendYes = TextCleaner.extractSendIt("on my way, send it")
assert(sendYes.text == "on my way" && sendYes.send, "send it strip: \(sendYes)")
let sendNo = TextCleaner.extractSendIt("please send it to Bob tomorrow")
assert(!sendNo.send, "send it mid-sentence must not trigger")
let sendThat = TextCleaner.extractSendIt("sounds good. Send that!")
assert(sendThat.text == "sounds good" && sendThat.send, "send that: \(sendThat)")

let ruleNew = try! JSONDecoder().decode([AppRule].self,
    from: Data(#"[{"appName":"Slack","pressEnter":true,"typeInsert":false}]"#.utf8))
assert(ruleNew[0].pressEnter == true && ruleNew[0].typeInsert == false, "rule new fields")
let ruleOld3 = try! JSONDecoder().decode([AppRule].self, from: Data(#"[{"appName":"X"}]"#.utf8))
assert(ruleOld3[0].pressEnter == nil, "rule back-compat pressEnter")

let bk6 = try! AppSettings.shared.exportBackup()
let dec6 = try! JSONDecoder().decode(AppSettings.Backup.self, from: bk6)
assert(dec6.extra5 != nil, "backup missing extra5")
assert(dec6.extra5?.translateTo == AppSettings.shared.translateTo, "extra5 roundtrip")
print("v2.8 workflow OK")

// Comprehensive backup integrity: mutate one field per Extra block, export,
// decode, confirm each survived (guards against dropped fields on refactors).
do {
    let a = AppSettings.shared
    a.barWidth = 4.5; a.polishTimeout = 47; a.undoDepth = 7
    a.translateTo = "Klingon"; a.dailyGoal = 1234
    let data = try! a.exportBackup()
    let d = try! JSONDecoder().decode(AppSettings.Backup.self, from: data)
    assert(d.extra2?.barWidth == 4.5, "extra2 lost")
    assert(d.extra3?.polishTimeout == 47, "extra3 lost")
    assert(d.extra4?.undoDepth == 7, "extra4 lost")
    assert(d.extra5?.translateTo == "Klingon", "extra5 lost")
    assert(d.dailyGoal == 1234, "base lost")
    print("backup integrity OK — all 5 extra blocks round-trip")
}

// Textures: enum count, spec assignments, custom texture in share/backup.
assert(SkinTexture.allCases.count == 10, "texture count")
assert(AppSkin.honey.spec?.texture == .hexagons, "honey hexagons")
assert(AppSkin.cosmos.spec?.texture == .stars, "cosmos stars")
assert(AppSkin.crimson.spec?.texture == SkinTexture.none, "untextured default")
let origTex = AppSettings.shared.customSkinTexture
AppSettings.shared.customSkinTexture = .dots
assert(AppSkin.custom.spec?.texture == .dots, "custom texture flows to spec")
let bkTex = try! AppSettings.shared.exportBackup()
let decTex = try! JSONDecoder().decode(AppSettings.Backup.self, from: bkTex)
assert(decTex.extra4?.customSkinTexture == "dots", "texture backup roundtrip")
AppSettings.shared.customSkinTexture = origTex
print("textures OK")

// Language list: full recognizer catalog, no artificial cap.
let langCount = GeneralPane.languages.count
let onDeviceCount = GeneralPane.onDeviceLocales.count
print("languages: \(langCount) total, \(onDeviceCount) on-device")
assert(langCount > 16, "language cap not lifted: \(langCount)")
assert(!GeneralPane.languages.contains { $0.1.isEmpty }, "language names resolve")

// Command Mode: verify the call routes without crashing synchronously.
TextCleaner.command(selection: "hello world", instruction: "uppercase it") { _ in }
print("command mode wired")

// v2.6 engine features.
let dblWl = TextCleaner.removeDoubledWords("it was very very good good", whitelist: ["very"])
print("dblWl: \(dblWl.debugDescription)")
assert(dblWl == "it was very very good", "doubled whitelist: \(dblWl)")

let startCustom = TextCleaner.stripStarterWords("Honestly, this works", words: ["honestly"])
assert(startCustom == "this works", "custom starters: \(startCustom)")

let spokenNew = TextCleaner.applySpokenPunctuation("snake case hyphen test underscore done")
print("spokenNew: \(spokenNew.debugDescription)")
assert(spokenNew.contains("-") && spokenNew.contains("_"), "spoken dash/underscore")

assert(TextCleaner.censor("scandal", words: ["and"], insideWords: true).contains("a**"),
       "censor inside words")
assert(TextCleaner.censor("scandal", words: ["and"], insideWords: false) == "scandal",
       "censor word-boundary")

// AppRule back-compat: old JSON without the new fields still decodes.
let oldRule = #"[{"appName":"Mail","tone":"email","ocase":"asSpoken"}]"#
let rules = try! JSONDecoder().decode([AppRule].self, from: Data(oldRule.utf8))
assert(rules[0].customPrompt == "" && rules[0].blocked == false && rules[0].localeID == nil,
       "AppRule back-compat")
print("appRule back-compat OK")

// Backup Extra3 round-trip.
let bk4 = try! AppSettings.shared.exportBackup()
let dec4 = try! JSONDecoder().decode(AppSettings.Backup.self, from: bk4)
assert(dec4.extra3 != nil, "backup missing extra3")
assert(dec4.extra3?.polishTimeout == AppSettings.shared.polishTimeout, "extra3 roundtrip")
print("backup extra3 OK")

// Skin Studio: hex round-trip and custom colors in backups.
let hexIn = "#3FA268"
let parsed = AppSettings.parseHex(hexIn)
assert(parsed != nil, "hex parse failed")
assert(AppSettings.hexString(parsed!) == hexIn, "hex roundtrip: \(AppSettings.hexString(parsed!))")
let origTextHex = AppSettings.shared.customTextHex
AppSettings.shared.customTextHex = "#FFEEDD"
let bk3 = try! AppSettings.shared.exportBackup()
let dec3 = try! JSONDecoder().decode(AppSettings.Backup.self, from: bk3)
assert(dec3.extra2?.customTextHex == "#FFEEDD", "custom color backup roundtrip")
AppSettings.shared.customTextHex = origTextHex
print("skin studio hex OK")

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

// Sketch-mode fixes proof: card outlines must hug corners (not cut across
// row text), and corner/border/glow must now restyle the sketch pill.
let origSkinS = AppSettings.shared.skin
let origCornerS = AppSettings.shared.pillCorner
let origBorderS = AppSettings.shared.pillBorderWidth
let origGlowS = AppSettings.shared.glowIntensity
AppSettings.shared.skin = .sketch
snap(AppearancePreview(), width: 524, height: 560, path: "preview_sketch_pill_default.png")
AppSettings.shared.pillCorner = .square
AppSettings.shared.pillBorderWidth = 3.0
AppSettings.shared.glowIntensity = 2.0
snap(AppearancePreview(), width: 524, height: 560, path: "preview_sketch_pill_square.png")
AppSettings.shared.pillCorner = origCornerS
AppSettings.shared.pillBorderWidth = origBorderS
AppSettings.shared.glowIntensity = origGlowS
AppSettings.shared.skin = origSkinS

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
// Skin Studio proof: a user-built dark green skin, studio card visible.
let origCustomHue = AppSettings.shared.customSkinHue
let origCustomSat = AppSettings.shared.customSkinSat
let origCustomDark = AppSettings.shared.customSkinDark
AppSettings.shared.customSkinHue = 0.38
AppSettings.shared.customSkinSat = 0.6
AppSettings.shared.customSkinDark = true
AppSettings.shared.skin = .custom
struct StudioPreview: View {
    var body: some View {
        AppearancePane(settings: AppSettings.shared)
            .background(Palette.of(.dark).bg)
            .frame(width: 524, height: 1800)
    }
}
snap(StudioPreview(), width: 524, height: 1800, path: "preview_studio.png")
AppSettings.shared.customSkinDark = false
snap(StudioPreview(), width: 524, height: 1800, path: "preview_studio_light.png", light: true)
AppSettings.shared.customSkinHue = origCustomHue
AppSettings.shared.customSkinSat = origCustomSat
AppSettings.shared.customSkinDark = origCustomDark

// Apps tab render (with a sample rule so the card shows).
let hadRules = AppSettings.shared.appRules
if hadRules.isEmpty {
    AppSettings.shared.appRules = [AppRule(appName: "Slack", customPrompt: "Casual with emojis", grammar: true)]
}
struct AppsPreview: View {
    var body: some View {
        AppsPane(settings: AppSettings.shared)
            .background(Palette.of(.dark).bg)
            .frame(width: 524, height: 760)
    }
}
snap(AppsPreview(), width: 524, height: 760, path: "preview_apps.png")
AppSettings.shared.appRules = hadRules

AppSettings.shared.skin = .honey
snap(SettingsRootView(), width: 700, height: 500, path: "preview_honey_window.png", light: true)
AppSettings.shared.skin = .ocean
snap(SettingsRootView(), width: 700, height: 500, path: "preview_ocean.png")
AppSettings.shared.skin = .honey
snap(AppearancePreview(), width: 524, height: 560, path: "preview_honey_pill.png", light: true)
AppSettings.shared.skin = .midnight
snap(SettingsRootView(), width: 700, height: 500, path: "preview_midnight.png")
AppSettings.shared.skin = .paper
snap(SettingsRootView(), width: 700, height: 500, path: "preview_paper.png", light: true)
AppSettings.shared.skin = .forest
snap(AppearancePreview(), width: 524, height: 560, path: "preview_forest_pill.png")
AppSettings.shared.skin = .candy
snap(SettingsRootView(), width: 700, height: 500, path: "preview_candy.png", light: true)
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
snap(OnboardingView(startStep: 0, onDone: {}), width: 440, height: 700, path: "preview_onb0.png")
snap(OnboardingView(startStep: 3, onDone: {}), width: 440, height: 700, path: "preview_onb3.png")
snap(OnboardingView(startStep: 4, onDone: {}), width: 440, height: 700, path: "preview_onb4.png")

// Cheat Sheet render
snap(CheatSheetView(), width: 420, height: 560, path: "preview_cheatsheet.png")
