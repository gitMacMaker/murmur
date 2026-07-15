import SwiftUI
import AppKit
import ServiceManagement
import Speech

// MARK: - Hotkey model

/// Any key the user picked as push-to-talk — a modifier (tracked via
/// flagsChanged) or a regular key (tracked/consumed via event tap).
struct HotkeyKey: Codable, Equatable {
    var keyCode: UInt16
    var isModifier: Bool
    var name: String

    static let rightOption = HotkeyKey(keyCode: 61, isModifier: true, name: "Right ⌥")

    var modifierFlag: NSEvent.ModifierFlags? {
        switch keyCode {
        case 54, 55: return .command
        case 56, 60: return .shift
        case 57: return .capsLock
        case 58, 61: return .option
        case 59, 62: return .control
        case 63: return .function
        default: return nil
        }
    }

    static func modifierName(for keyCode: UInt16) -> String? {
        switch keyCode {
        case 54: return "Right ⌘"
        case 55: return "Left ⌘"
        case 56: return "Left ⇧"
        case 57: return "⇪ Caps Lock"
        case 58: return "Left ⌥"
        case 59: return "Left ⌃"
        case 60: return "Right ⇧"
        case 61: return "Right ⌥"
        case 62: return "Right ⌃"
        case 63: return "Fn 🌐"
        default: return nil
        }
    }

    static func displayName(for event: NSEvent) -> String {
        let specials: [UInt16: String] = [
            36: "↩ Return", 48: "⇥ Tab", 49: "Space", 51: "⌫ Delete", 76: "↩ Enter",
            114: "Help", 115: "↖ Home", 116: "⇞ Page Up", 117: "⌦ Fwd Delete",
            119: "↘ End", 121: "⇟ Page Down",
            123: "←", 124: "→", 125: "↓", 126: "↑",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
            105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17",
            79: "F18", 80: "F19", 90: "F20",
        ]
        if let s = specials[event.keyCode] { return s }
        if let chars = event.charactersIgnoringModifiers, !chars.isEmpty {
            return chars.uppercased()
        }
        return "Key \(event.keyCode)"
    }
}

// MARK: - Other choices

/// Preset accents — quick picks that position the color wheel.
enum AccentChoice: String, CaseIterable, Identifiable {
    case violet, blue, teal, green, pink, orange
    var id: String { rawValue }

    /// (hue, saturation) at brightness 1.
    var hs: (Double, Double) {
        switch self {
        case .violet: return (0.728, 0.58)
        case .blue: return (0.603, 0.65)
        case .teal: return (0.500, 0.71)
        case .green: return (0.383, 0.56)
        case .pink: return (0.924, 0.55)
        case .orange: return (0.076, 0.70)
        }
    }
    var color: Color { Color(hue: hs.0, saturation: hs.1, brightness: 1.0) }
    var label: String { rawValue.capitalized }
}

enum PillPosition: String, CaseIterable, Identifiable {
    case bottom, top
    var id: String { rawValue }
    var label: String { self == .bottom ? "Bottom" : "Top" }
}

struct HistoryItem: Codable, Identifiable {
    var id = UUID()
    let text: String
    let date: Date
    var pinned: Bool = false

    init(text: String, date: Date, pinned: Bool = false) {
        self.text = text
        self.date = date
        self.pinned = pinned
    }

    // Manual decoding so items saved before `pinned` existed still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try c.decode(String.self, forKey: .text)
        date = try c.decode(Date.self, forKey: .date)
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
    }
}

enum PillSize: String, CaseIterable, Identifiable {
    case compact, regular, large
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var factor: CGFloat {
        switch self {
        case .compact: return 0.85
        case .regular: return 1.0
        case .large: return 1.18
        }
    }
}

enum SoundEvent { case start, insert, cancel, unlock }

enum SoundTheme: String, CaseIterable, Identifiable {
    case soft, crisp, retro, arcade, bubbles
    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    func sound(for event: SoundEvent) -> String {
        switch (self, event) {
        case (.soft, .start): return "Pop"
        case (.soft, .insert): return "Glass"
        case (.soft, .cancel): return "Bottle"
        case (.crisp, .start): return "Tink"
        case (.crisp, .insert): return "Ping"
        case (.crisp, .cancel): return "Basso"
        case (.retro, .start): return "Morse"
        case (.retro, .insert): return "Hero"
        case (.retro, .cancel): return "Sosumi"
        case (.arcade, .start): return "Funk"
        case (.arcade, .insert): return "Blow"
        case (.arcade, .cancel): return "Basso"
        case (.bubbles, .start): return "Submarine"
        case (.bubbles, .insert): return "Purr"
        case (.bubbles, .cancel): return "Frog"
        case (_, .unlock): return "Funk"
        }
    }
}

enum InsertTarget: String, CaseIterable, Identifiable {
    case activeApp, clipboardOnly
    var id: String { rawValue }
    var label: String { self == .activeApp ? "Active App" : "Clipboard" }
}

enum PillTheme: String, CaseIterable, Identifiable {
    case dark, light, system
    var id: String { rawValue }
    var label: String { self == .system ? "Match System" : rawValue.capitalized }
}

enum WaveStyle: String, CaseIterable, Identifiable {
    case bars, dots, wave
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum PillAlignment: String, CaseIterable, Identifiable {
    case leading, center, trailing
    var id: String { rawValue }
    var label: String {
        switch self {
        case .leading: return "Left"
        case .center: return "Center"
        case .trailing: return "Right"
        }
    }
}

enum MenuIcon: String, CaseIterable, Identifiable {
    case waveform, mic, quote
    var id: String { rawValue }
    var label: String {
        switch self {
        case .waveform: return "Waveform"
        case .mic: return "Mic"
        case .quote: return "Quote"
        }
    }
    func symbol(recording: Bool) -> String {
        switch self {
        case .waveform: return recording ? "waveform.badge.mic" : "waveform"
        case .mic: return recording ? "mic.fill" : "mic"
        case .quote: return recording ? "quote.bubble.fill" : "quote.bubble"
        }
    }
}

enum AppSkin: String, CaseIterable, Identifiable {
    case clean, sketch, terminal, blueprint, retro, neon
    var id: String { rawValue }
    var label: String {
        switch self {
        case .clean: return "Clean"
        case .sketch: return "Sketch"
        case .terminal: return "Terminal"
        case .blueprint: return "Blueprint"
        case .retro: return "Retro Mac"
        case .neon: return "Neon"
        }
    }
    var symbol: String {
        switch self {
        case .clean: return "circle"
        case .sketch: return "pencil.and.outline"
        case .terminal: return "terminal"
        case .blueprint: return "ruler"
        case .retro: return "macwindow"
        case .neon: return "sparkles"
        }
    }
}

enum OutputCase: String, CaseIterable, Identifiable, Codable {
    case asSpoken, lowercase, uppercase
    var id: String { rawValue }
    var label: String {
        switch self {
        case .asSpoken: return "As Spoken"
        case .lowercase: return "lowercase"
        case .uppercase: return "UPPERCASE"
        }
    }
}

struct Achievement: Identifiable {
    let id: String
    let name: String
    let symbol: String
    let desc: String

    static let all: [Achievement] = [
        .init(id: "first", name: "First Words", symbol: "waveform",
              desc: "Complete your first dictation"),
        .init(id: "century", name: "Century", symbol: "100.circle",
              desc: "Dictate 100 total words"),
        .init(id: "wordsmith", name: "Wordsmith", symbol: "text.book.closed",
              desc: "Dictate 1,000 total words"),
        .init(id: "novelist", name: "Novelist", symbol: "books.vertical",
              desc: "Dictate 10,000 total words"),
        .init(id: "roll", name: "On a Roll", symbol: "flame",
              desc: "Dictate 3 days in a row"),
        .init(id: "unstoppable", name: "Unstoppable", symbol: "flame.fill",
              desc: "Dictate 7 days in a row"),
        .init(id: "motormouth", name: "Motor Mouth", symbol: "hare",
              desc: "60+ words in a single dictation"),
        .init(id: "nightowl", name: "Night Owl", symbol: "moon.stars",
              desc: "Dictate between midnight and 4 AM"),
        .init(id: "earlybird", name: "Early Bird", symbol: "sunrise",
              desc: "Dictate between 5 and 8 AM"),
        .init(id: "polyglot", name: "Polyglot", symbol: "globe",
              desc: "Dictate in a non-English language"),
        .init(id: "lexicographer", name: "Lexicographer", symbol: "character.book.closed",
              desc: "Keep 5+ dictionary replacements"),
        .init(id: "customizer", name: "Make It Yours", symbol: "paintbrush.pointed",
              desc: "Change the hotkey or wear a skin"),
        .init(id: "marathon", name: "Marathon", symbol: "figure.run",
              desc: "500 words in a single day"),
        .init(id: "dedicated", name: "Dedicated", symbol: "calendar",
              desc: "Dictate on 14 different days"),
        .init(id: "pincollector", name: "Pin Collector", symbol: "pin",
              desc: "Pin 3 transcripts"),
        .init(id: "polisher", name: "Polisher", symbol: "wand.and.stars",
              desc: "Deliver a dictation with AI polish on"),
        .init(id: "commander", name: "Commander", symbol: "command",
              desc: "Use a voice command mid-dictation"),
        .init(id: "goalgetter", name: "Goal Getter", symbol: "target",
              desc: "Hit your daily word goal"),
        .init(id: "weekend", name: "Weekend Warrior", symbol: "sun.max",
              desc: "Dictate on a weekend"),
        .init(id: "minimalist", name: "Minimalist", symbol: "minus.circle",
              desc: "Run a compact or text-free pill"),
    ]
}

enum PillCorner: String, CaseIterable, Identifiable, Codable {
    case capsule, rounded, square
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var radius: CGFloat? { self == .capsule ? nil : (self == .rounded ? 14 : 4) }
}

enum PillFont: String, CaseIterable, Identifiable, Codable {
    case system, rounded, mono, serif
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "System"
        case .rounded: return "Rounded"
        case .mono: return "Mono"
        case .serif: return "Serif"
        }
    }
    var design: Font.Design {
        switch self {
        case .system: return .default
        case .rounded: return .rounded
        case .mono: return .monospaced
        case .serif: return .serif
        }
    }
}

enum HistorySort: String, CaseIterable, Identifiable {
    case newest, oldest, longest
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

/// Per-app override: when dictating into a matching app, use this tone/case.
struct AppRule: Codable, Identifiable, Equatable {
    var id = UUID()
    var appName: String
    var tone: PolishTone = .clean
    var ocase: OutputCase = .asSpoken
}

/// A spoken phrase that gets swapped for custom text after transcription.
/// Phrases are also fed to the recognizer as vocabulary hints.
struct Replacement: Codable, Identifiable, Equatable {
    var id = UUID()
    var phrase: String
    var replacement: String
    var enabled: Bool = true

    init(phrase: String, replacement: String, enabled: Bool = true) {
        self.phrase = phrase
        self.replacement = replacement
        self.enabled = enabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        phrase = try c.decode(String.self, forKey: .phrase)
        replacement = try c.decode(String.self, forKey: .replacement)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }
}

enum PolishBackend: String, CaseIterable, Identifiable {
    case cli, api
    var id: String { rawValue }
    var label: String { self == .cli ? "Claude CLI" : "API Key" }
}

enum PolishTone: String, CaseIterable, Identifiable, Codable {
    case clean, email, casual, custom
    var id: String { rawValue }
    var label: String {
        switch self {
        case .clean: return "Clean"
        case .email: return "Email"
        case .casual: return "Casual"
        case .custom: return "Custom"
        }
    }
}

// MARK: - Settings store

final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let d = UserDefaults.standard

    @Published var hotkey: HotkeyKey {
        didSet { d.set((try? JSONEncoder().encode(hotkey)) ?? Data(), forKey: "hotkeyV2") }
    }
    @Published var accentHue: Double { didSet { d.set(accentHue, forKey: "accentHue") } }
    @Published var accentSat: Double { didSet { d.set(accentSat, forKey: "accentSat") } }
    var accentColor: Color { Color(hue: accentHue, saturation: accentSat, brightness: 1.0) }
    /// Legible text color on top of the accent — dark ink on light accents,
    /// white on dark ones.
    var accentContrastColor: Color {
        let c = NSColor(hue: accentHue, saturation: accentSat, brightness: 1.0, alpha: 1)
        let luminance = 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent
        return luminance > 0.66 ? Color(white: 0.12) : .white
    }

    var accentHex: String {
        let c = NSColor(hue: accentHue, saturation: accentSat, brightness: 1.0, alpha: 1)
        return String(format: "#%02X%02X%02X",
                      Int(round(c.redComponent * 255)),
                      Int(round(c.greenComponent * 255)),
                      Int(round(c.blueComponent * 255)))
    }
    @Published var pillPosition: PillPosition { didSet { d.set(pillPosition.rawValue, forKey: "pillPosition") } }
    @Published var soundsEnabled: Bool { didSet { d.set(soundsEnabled, forKey: "sounds") } }
    @Published var tidyEnabled: Bool { didSet { d.set(tidyEnabled, forKey: "tidy") } }
    @Published var polishEnabled: Bool { didSet { d.set(polishEnabled, forKey: "polish") } }
    @Published var totalWords: Int { didSet { d.set(totalWords, forKey: "totalWords") } }
    @Published var history: [HistoryItem] {
        didSet { d.set((try? JSONEncoder().encode(history)) ?? Data(), forKey: "historyV2") }
    }
    @Published var voiceCommandsEnabled: Bool { didSet { d.set(voiceCommandsEnabled, forKey: "voiceCommands") } }
    @Published var polishTone: PolishTone { didSet { d.set(polishTone.rawValue, forKey: "polishTone") } }
    @Published var polishBackend: PolishBackend { didSet { d.set(polishBackend.rawValue, forKey: "polishBackend") } }
    /// Mirrors whether an Anthropic API key is stored in the Keychain
    /// (the key itself never lives in UserDefaults or backups).
    @Published var hasAPIKey: Bool = APIKeyStore.exists

    func saveAPIKey(_ key: String) {
        APIKeyStore.save(key.trimmingCharacters(in: .whitespacesAndNewlines))
        hasAPIKey = APIKeyStore.exists
        if hasAPIKey { polishBackend = .api }
    }

    func removeAPIKey() {
        APIKeyStore.delete()
        hasAPIKey = false
        polishBackend = .cli
    }
    @Published var replacements: [Replacement] {
        didSet { d.set((try? JSONEncoder().encode(replacements)) ?? Data(), forKey: "replacements") }
    }
    @Published var localeID: String { didSet { d.set(localeID, forKey: "localeID") } }
    @Published var typeInsteadOfPaste: Bool { didSet { d.set(typeInsteadOfPaste, forKey: "typeInsert") } }
    @Published var dailyWords: [String: Int] { didSet { d.set(dailyWords, forKey: "dailyWords") } }
    @Published var autoStopEnabled: Bool { didSet { d.set(autoStopEnabled, forKey: "autoStop") } }
    @Published var dailyGoal: Int { didSet { d.set(dailyGoal, forKey: "dailyGoal") } }
    @Published var customPolishPrompt: String { didSet { d.set(customPolishPrompt, forKey: "customPolish") } }
    @Published var pillSize: PillSize { didSet { d.set(pillSize.rawValue, forKey: "pillSize") } }
    @Published var pillTheme: PillTheme { didSet { d.set(pillTheme.rawValue, forKey: "pillTheme") } }
    @Published var waveStyle: WaveStyle { didSet { d.set(waveStyle.rawValue, forKey: "waveStyle") } }
    @Published var pillOpacity: Double { didSet { d.set(pillOpacity, forKey: "pillOpacity") } }
    @Published var showTranscript: Bool { didSet { d.set(showTranscript, forKey: "showTranscript") } }
    @Published var showWordCount: Bool { didSet { d.set(showWordCount, forKey: "showWordCount") } }
    @Published var glowEnabled: Bool { didSet { d.set(glowEnabled, forKey: "glow") } }
    @Published var pillAlignment: PillAlignment { didSet { d.set(pillAlignment.rawValue, forKey: "pillAlign") } }
    @Published var menuIcon: MenuIcon { didSet { d.set(menuIcon.rawValue, forKey: "menuIcon") } }
    @Published var skin: AppSkin { didSet { d.set(skin.rawValue, forKey: "skin") } }
    @Published var pillMatchesSkin: Bool { didSet { d.set(pillMatchesSkin, forKey: "pillMatchesSkin") } }
    /// Convenience used by sketch-specific touches (tilt, wobble).
    var sketchMode: Bool { skin == .sketch }
    @Published var outputCase: OutputCase { didSet { d.set(outputCase.rawValue, forKey: "outputCase") } }
    @Published var showMenuBarCount: Bool { didSet { d.set(showMenuBarCount, forKey: "menuBarCount") } }
    @Published var totalSessions: Int { didSet { d.set(totalSessions, forKey: "totalSessions") } }
    @Published var maxStreak: Int { didSet { d.set(maxStreak, forKey: "maxStreak") } }
    @Published var earned: [String: Date] {
        didSet { d.set((try? JSONEncoder().encode(earned)) ?? Data(), forKey: "achievements") }
    }
    @Published var autoPunctuation: Bool { didSet { d.set(autoPunctuation, forKey: "autoPunct") } }
    @Published var tapThreshold: Double { didSet { d.set(tapThreshold, forKey: "tapThreshold") } }
    @Published var silenceSeconds: Double { didSet { d.set(silenceSeconds, forKey: "silenceSeconds") } }
    @Published var soundVolume: Double { didSet { d.set(soundVolume, forKey: "soundVolume") } }
    @Published var historyLimit: Int { didSet { d.set(historyLimit, forKey: "historyLimit") } }
    @Published var fillerWords: [String] { didSet { d.set(fillerWords, forKey: "fillerWords") } }
    @Published var appRules: [AppRule] {
        didSet { d.set((try? JSONEncoder().encode(appRules)) ?? Data(), forKey: "appRules") }
    }
    @Published var capitalizeI: Bool { didSet { d.set(capitalizeI, forKey: "capI") } }
    @Published var smartPunctuation: Bool { didSet { d.set(smartPunctuation, forKey: "smartPunct") } }
    @Published var trailingSpace: Bool { didSet { d.set(trailingSpace, forKey: "trailSpace") } }
    @Published var noTrailingPeriod: Bool { didSet { d.set(noTrailingPeriod, forKey: "noPeriod") } }
    @Published var discardShortWords: Int { didSet { d.set(discardShortWords, forKey: "discardShort") } }
    @Published var maxRecordSeconds: Int { didSet { d.set(maxRecordSeconds, forKey: "maxRecord") } }
    @Published var keepTranscriptOnClipboard: Bool { didSet { d.set(keepTranscriptOnClipboard, forKey: "keepClip") } }
    @Published var longToClipboardWords: Int { didSet { d.set(longToClipboardWords, forKey: "longClip") } }
    @Published var showMenuBarStreak: Bool { didSet { d.set(showMenuBarStreak, forKey: "menuStreak") } }
    @Published var caseSensitiveReplacements: Bool { didSet { d.set(caseSensitiveReplacements, forKey: "caseSensRepl") } }
    @Published var waveBarCount: Int { didSet { d.set(waveBarCount, forKey: "waveBars") } }
    @Published var pillCorner: PillCorner { didSet { d.set(pillCorner.rawValue, forKey: "pillCorner") } }
    @Published var recordTintAccent: Bool { didSet { d.set(recordTintAccent, forKey: "recTintAccent") } }
    @Published var pillBorderWidth: Double { didSet { d.set(pillBorderWidth, forKey: "pillBorder") } }
    @Published var glowIntensity: Double { didSet { d.set(glowIntensity, forKey: "glowIntensity") } }
    @Published var waveGain: Double { didSet { d.set(waveGain, forKey: "waveGain") } }
    @Published var pillEdgeOffset: Double { didSet { d.set(pillEdgeOffset, forKey: "pillOffset") } }
    @Published var idleIndicator: Bool { didSet { d.set(idleIndicator, forKey: "idleDot") } }
    @Published var pillFont: PillFont { didSet { d.set(pillFont.rawValue, forKey: "pillFont") } }
    @Published var reduceMotion: Bool { didSet { d.set(reduceMotion, forKey: "reduceMotion") } }
    @Published var historyMaxAgeDays: Int { didSet { d.set(historyMaxAgeDays, forKey: "histMaxAge") } }
    @Published var totalSpeakSeconds: Double { didSet { d.set(totalSpeakSeconds, forKey: "speakSecs") } }
    @Published var soundTheme: SoundTheme { didSet { d.set(soundTheme.rawValue, forKey: "soundTheme") } }
    @Published var insertTarget: InsertTarget { didSet { d.set(insertTarget.rawValue, forKey: "insertTarget") } }

    var minutesSaved: Double { Double(totalWords) * (1.0 / 40.0 - 1.0 / 150.0) }

    /// Records a delivered dictation and returns any newly unlocked achievements.
    @discardableResult
    func record(_ text: String, usedPolish: Bool = false, usedCommands: Bool = false) -> [Achievement] {
        // Pinned items always survive trimming.
        let pinnedItems = history.filter(\.pinned)
        let unpinned = [HistoryItem(text: text, date: Date())] + history.filter { !$0.pinned }
        history = pinnedItems + Array(unpinned.prefix(max(10, historyLimit - pinnedItems.count)))
        let words = text.split(whereSeparator: \.isWhitespace).count
        totalWords += words
        totalSessions += 1
        dailyWords[Self.dayKey(Date()), default: 0] += words
        if dailyWords.count > 90 {
            let keep = Set(dailyWords.keys.sorted().suffix(60))
            dailyWords = dailyWords.filter { keep.contains($0.key) }
        }
        maxStreak = max(maxStreak, streak())
        if historyMaxAgeDays > 0 {
            let cutoff = Calendar.current.date(byAdding: .day, value: -historyMaxAgeDays, to: Date()) ?? Date()
            history.removeAll { !$0.pinned && $0.date < cutoff }
        }
        return evaluateAchievements(sessionWords: words, usedPolish: usedPolish, usedCommands: usedCommands)
    }

    private func evaluateAchievements(sessionWords: Int, usedPolish: Bool, usedCommands: Bool) -> [Achievement] {
        var newly: [Achievement] = []
        func unlock(_ id: String) {
            guard earned[id] == nil else { return }
            earned[id] = Date()
            if let a = Achievement.all.first(where: { $0.id == id }) { newly.append(a) }
        }
        let hour = Calendar.current.component(.hour, from: Date())
        let weekday = Calendar.current.component(.weekday, from: Date())

        unlock("first")
        if totalWords >= 100 { unlock("century") }
        if totalWords >= 1_000 { unlock("wordsmith") }
        if totalWords >= 10_000 { unlock("novelist") }
        if streak() >= 3 { unlock("roll") }
        if streak() >= 7 { unlock("unstoppable") }
        if sessionWords >= 60 { unlock("motormouth") }
        if hour < 4 { unlock("nightowl") }
        if (5..<8).contains(hour) { unlock("earlybird") }
        if localeID != "en-US" { unlock("polyglot") }
        if replacements.count >= 5 { unlock("lexicographer") }
        if skin != .clean || hotkey != .rightOption { unlock("customizer") }
        if todayWords >= 500 { unlock("marathon") }
        if dailyWords.count >= 14 { unlock("dedicated") }
        if history.filter(\.pinned).count >= 3 { unlock("pincollector") }
        if usedPolish { unlock("polisher") }
        if usedCommands { unlock("commander") }
        if dailyGoal > 0, todayWords >= dailyGoal { unlock("goalgetter") }
        if weekday == 1 || weekday == 7 { unlock("weekend") }
        if pillSize == .compact || !showTranscript { unlock("minimalist") }
        return newly
    }

    // MARK: Backup / restore

    struct Backup: Codable {
        var hotkey: HotkeyKey
        var accentHue, accentSat, pillOpacity, tapThreshold, silenceSeconds: Double
        var pillPosition, soundTheme, skin, waveStyle, pillAlignment, menuIcon,
            insertTarget, outputCase, polishTone, localeID, pillSize, customPolishPrompt: String
        var sounds, tidy, polish, voiceCommands, typeInsert, autoStop, showTranscript,
            showWordCount, glow, menuBarCount, autoPunctuation: Bool
        var dailyGoal, totalWords, totalSessions, maxStreak: Int
        var replacements: [Replacement]
        var history: [HistoryItem]
        var dailyWords: [String: Int]
        var earned: [String: Date]
    }

    func exportBackup() throws -> Data {
        let b = Backup(
            hotkey: hotkey, accentHue: accentHue, accentSat: accentSat,
            pillOpacity: pillOpacity, tapThreshold: tapThreshold, silenceSeconds: silenceSeconds,
            pillPosition: pillPosition.rawValue, soundTheme: soundTheme.rawValue,
            skin: skin.rawValue, waveStyle: waveStyle.rawValue,
            pillAlignment: pillAlignment.rawValue, menuIcon: menuIcon.rawValue,
            insertTarget: insertTarget.rawValue, outputCase: outputCase.rawValue,
            polishTone: polishTone.rawValue, localeID: localeID,
            pillSize: pillSize.rawValue, customPolishPrompt: customPolishPrompt,
            sounds: soundsEnabled, tidy: tidyEnabled, polish: polishEnabled,
            voiceCommands: voiceCommandsEnabled, typeInsert: typeInsteadOfPaste,
            autoStop: autoStopEnabled, showTranscript: showTranscript,
            showWordCount: showWordCount, glow: glowEnabled,
            menuBarCount: showMenuBarCount, autoPunctuation: autoPunctuation,
            dailyGoal: dailyGoal, totalWords: totalWords,
            totalSessions: totalSessions, maxStreak: maxStreak,
            replacements: replacements, history: history,
            dailyWords: dailyWords, earned: earned)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(b)
    }

    func importBackup(_ data: Data) throws {
        let b = try JSONDecoder().decode(Backup.self, from: data)
        hotkey = b.hotkey
        accentHue = b.accentHue; accentSat = b.accentSat
        pillOpacity = b.pillOpacity; tapThreshold = b.tapThreshold; silenceSeconds = b.silenceSeconds
        pillPosition = PillPosition(rawValue: b.pillPosition) ?? .bottom
        soundTheme = SoundTheme(rawValue: b.soundTheme) ?? .soft
        skin = AppSkin(rawValue: b.skin) ?? .clean
        waveStyle = WaveStyle(rawValue: b.waveStyle) ?? .bars
        pillAlignment = PillAlignment(rawValue: b.pillAlignment) ?? .center
        menuIcon = MenuIcon(rawValue: b.menuIcon) ?? .waveform
        insertTarget = InsertTarget(rawValue: b.insertTarget) ?? .activeApp
        outputCase = OutputCase(rawValue: b.outputCase) ?? .asSpoken
        polishTone = PolishTone(rawValue: b.polishTone) ?? .clean
        localeID = b.localeID
        pillSize = PillSize(rawValue: b.pillSize) ?? .regular
        customPolishPrompt = b.customPolishPrompt
        soundsEnabled = b.sounds; tidyEnabled = b.tidy; polishEnabled = b.polish
        voiceCommandsEnabled = b.voiceCommands; typeInsteadOfPaste = b.typeInsert
        autoStopEnabled = b.autoStop; showTranscript = b.showTranscript
        showWordCount = b.showWordCount; glowEnabled = b.glow
        showMenuBarCount = b.menuBarCount; autoPunctuation = b.autoPunctuation
        dailyGoal = b.dailyGoal; totalWords = b.totalWords
        totalSessions = b.totalSessions; maxStreak = b.maxStreak
        replacements = b.replacements; history = b.history
        dailyWords = b.dailyWords; earned = b.earned
    }

    func resetToDefaults() {
        hotkey = .rightOption
        accentHue = AccentChoice.violet.hs.0; accentSat = AccentChoice.violet.hs.1
        pillPosition = .bottom; soundTheme = .soft; skin = .clean; waveStyle = .bars
        pillAlignment = .center; menuIcon = .waveform; insertTarget = .activeApp
        outputCase = .asSpoken; polishTone = .clean; localeID = "en-US"
        pillSize = .regular; customPolishPrompt = ""
        soundsEnabled = true; tidyEnabled = true; polishEnabled = false
        voiceCommandsEnabled = true; typeInsteadOfPaste = false; autoStopEnabled = true
        showTranscript = true; showWordCount = true; glowEnabled = true
        showMenuBarCount = false; autoPunctuation = true
        dailyGoal = 0; pillOpacity = 0.94; tapThreshold = 0.35; silenceSeconds = 3.0
        // Stats, history, dictionary, and achievements are intentionally kept.
    }

    static func dayKey(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: date)
    }

    /// Consecutive days with dictation, counting back from today
    /// (or yesterday, so an unstarted morning doesn't kill the streak).
    func streak() -> Int {
        let cal = Calendar.current
        var day = Date()
        var count = 0
        if (dailyWords[Self.dayKey(day)] ?? 0) == 0 {
            day = cal.date(byAdding: .day, value: -1, to: day) ?? day
        }
        while (dailyWords[Self.dayKey(day)] ?? 0) > 0 {
            count += 1
            day = cal.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return count
    }

    var todayWords: Int { dailyWords[Self.dayKey(Date())] ?? 0 }

    var activeDays: Int { dailyWords.values.filter { $0 > 0 }.count }
    var avgWordsPerActiveDay: Int { activeDays > 0 ? totalWords / activeDays : 0 }
    var wordsPerMinute: Int {
        totalSpeakSeconds > 10 ? Int(Double(totalWords) / (totalSpeakSeconds / 60.0)) : 0
    }
    var bestDayKey: String? {
        dailyWords.max { $0.value < $1.value }?.key
    }
    /// Words remaining and projected days to the next word-count badge.
    func nextMilestone() -> (name: String, remaining: Int, days: Int)? {
        let goals: [(String, Int)] = [("Century", 100), ("Wordsmith", 1_000), ("Novelist", 10_000)]
        guard let next = goals.first(where: { totalWords < $0.1 }) else { return nil }
        let remaining = next.1 - totalWords
        let rate = max(1, avgWordsPerActiveDay)
        return (next.0, remaining, Int(ceil(Double(remaining) / Double(rate))))
    }

    func resetStats() {
        totalWords = 0
        totalSessions = 0
        maxStreak = 0
        dailyWords = [:]
        totalSpeakSeconds = 0
    }

    /// Words per day for the trailing 30 days, oldest first.
    func monthActivity() -> [(count: Int, date: String)] {
        let cal = Calendar.current
        let full = DateFormatter()
        full.dateStyle = .medium
        return (0..<30).reversed().map { offset in
            let day = cal.date(byAdding: .day, value: -offset, to: Date()) ?? Date()
            return (dailyWords[Self.dayKey(day)] ?? 0, full.string(from: day))
        }
    }

    /// Sum of words over the 7 days ending `endingDaysAgo` days before today.
    func wordsInWeek(endingDaysAgo: Int) -> Int {
        let cal = Calendar.current
        return (endingDaysAgo..<(endingDaysAgo + 7)).reduce(0) { total, offset in
            let day = cal.date(byAdding: .day, value: -offset, to: Date()) ?? Date()
            return total + (dailyWords[Self.dayKey(day)] ?? 0)
        }
    }

    /// Words per day for the trailing week, oldest first.
    func weekActivity() -> [(label: String, count: Int, date: String)] {
        let cal = Calendar.current
        let letter = DateFormatter()
        letter.dateFormat = "EEEEE"
        let full = DateFormatter()
        full.dateStyle = .medium
        return (0..<7).reversed().map { offset in
            let day = cal.date(byAdding: .day, value: -offset, to: Date()) ?? Date()
            return (letter.string(from: day),
                    dailyWords[Self.dayKey(day)] ?? 0,
                    full.string(from: day))
        }
    }

    private init() {
        if let data = d.data(forKey: "hotkeyV2"),
           let k = try? JSONDecoder().decode(HotkeyKey.self, from: data) {
            hotkey = k
        } else {
            switch d.string(forKey: "hotkey") {
            case "rightCommand": hotkey = HotkeyKey(keyCode: 54, isModifier: true, name: "Right ⌘")
            case "rightControl": hotkey = HotkeyKey(keyCode: 62, isModifier: true, name: "Right ⌃")
            case "fn": hotkey = HotkeyKey(keyCode: 63, isModifier: true, name: "Fn 🌐")
            default: hotkey = .rightOption
            }
        }
        if d.object(forKey: "accentHue") != nil {
            accentHue = d.double(forKey: "accentHue")
            accentSat = d.double(forKey: "accentSat")
        } else {
            // Migrate the old preset choice (or default to violet).
            let old = AccentChoice(rawValue: d.string(forKey: "accent") ?? "") ?? .violet
            accentHue = old.hs.0
            accentSat = old.hs.1
        }
        pillPosition = PillPosition(rawValue: d.string(forKey: "pillPosition") ?? "") ?? .bottom
        soundsEnabled = d.object(forKey: "sounds") as? Bool ?? true
        tidyEnabled = d.object(forKey: "tidy") as? Bool ?? true
        polishEnabled = d.bool(forKey: "polish")
        totalWords = d.integer(forKey: "totalWords")
        if let data = d.data(forKey: "historyV2"),
           let items = try? JSONDecoder().decode([HistoryItem].self, from: data) {
            history = items
        } else {
            history = (d.stringArray(forKey: "history") ?? []).map { HistoryItem(text: $0, date: Date()) }
        }
        voiceCommandsEnabled = d.object(forKey: "voiceCommands") as? Bool ?? true
        polishTone = PolishTone(rawValue: d.string(forKey: "polishTone") ?? "") ?? .clean
        polishBackend = PolishBackend(rawValue: d.string(forKey: "polishBackend") ?? "") ?? .cli
        localeID = d.string(forKey: "localeID") ?? "en-US"
        typeInsteadOfPaste = d.bool(forKey: "typeInsert")
        dailyWords = d.dictionary(forKey: "dailyWords") as? [String: Int] ?? [:]
        autoStopEnabled = d.object(forKey: "autoStop") as? Bool ?? true
        dailyGoal = d.integer(forKey: "dailyGoal")
        customPolishPrompt = d.string(forKey: "customPolish") ?? ""
        pillSize = PillSize(rawValue: d.string(forKey: "pillSize") ?? "") ?? .regular
        pillTheme = PillTheme(rawValue: d.string(forKey: "pillTheme") ?? "") ?? .dark
        waveStyle = WaveStyle(rawValue: d.string(forKey: "waveStyle") ?? "") ?? .bars
        pillOpacity = d.object(forKey: "pillOpacity") as? Double ?? 0.94
        showTranscript = d.object(forKey: "showTranscript") as? Bool ?? true
        showWordCount = d.object(forKey: "showWordCount") as? Bool ?? true
        glowEnabled = d.object(forKey: "glow") as? Bool ?? true
        pillAlignment = PillAlignment(rawValue: d.string(forKey: "pillAlign") ?? "") ?? .center
        menuIcon = MenuIcon(rawValue: d.string(forKey: "menuIcon") ?? "") ?? .waveform
        if let raw = d.string(forKey: "skin"), let s = AppSkin(rawValue: raw) {
            skin = s
        } else {
            skin = d.bool(forKey: "sketchMode") ? .sketch : .clean // migrate v1.6 flag
        }
        pillMatchesSkin = d.object(forKey: "pillMatchesSkin") as? Bool ?? true
        outputCase = OutputCase(rawValue: d.string(forKey: "outputCase") ?? "") ?? .asSpoken
        showMenuBarCount = d.bool(forKey: "menuBarCount")
        totalSessions = d.integer(forKey: "totalSessions")
        maxStreak = d.integer(forKey: "maxStreak")
        if let data = d.data(forKey: "achievements"),
           let e = try? JSONDecoder().decode([String: Date].self, from: data) {
            earned = e
        } else {
            earned = [:]
        }
        autoPunctuation = d.object(forKey: "autoPunct") as? Bool ?? true
        tapThreshold = d.object(forKey: "tapThreshold") as? Double ?? 0.35
        silenceSeconds = d.object(forKey: "silenceSeconds") as? Double ?? 3.0
        soundVolume = d.object(forKey: "soundVolume") as? Double ?? 0.8
        historyLimit = d.object(forKey: "historyLimit") as? Int ?? 50
        fillerWords = d.stringArray(forKey: "fillerWords") ?? ["um", "uh", "uhm", "erm", "er", "you know like"]
        if let data = d.data(forKey: "appRules"),
           let rules = try? JSONDecoder().decode([AppRule].self, from: data) {
            appRules = rules
        } else {
            appRules = []
        }
        capitalizeI = d.object(forKey: "capI") as? Bool ?? true
        smartPunctuation = d.bool(forKey: "smartPunct")
        trailingSpace = d.bool(forKey: "trailSpace")
        noTrailingPeriod = d.bool(forKey: "noPeriod")
        discardShortWords = d.integer(forKey: "discardShort")
        maxRecordSeconds = d.integer(forKey: "maxRecord")
        keepTranscriptOnClipboard = d.bool(forKey: "keepClip")
        longToClipboardWords = d.integer(forKey: "longClip")
        showMenuBarStreak = d.bool(forKey: "menuStreak")
        caseSensitiveReplacements = d.bool(forKey: "caseSensRepl")
        waveBarCount = d.object(forKey: "waveBars") as? Int ?? 28
        pillCorner = PillCorner(rawValue: d.string(forKey: "pillCorner") ?? "") ?? .capsule
        recordTintAccent = d.bool(forKey: "recTintAccent")
        pillBorderWidth = d.object(forKey: "pillBorder") as? Double ?? 1.2
        glowIntensity = d.object(forKey: "glowIntensity") as? Double ?? 1.0
        waveGain = d.object(forKey: "waveGain") as? Double ?? 1.0
        pillEdgeOffset = d.object(forKey: "pillOffset") as? Double ?? 24
        idleIndicator = d.bool(forKey: "idleDot")
        pillFont = PillFont(rawValue: d.string(forKey: "pillFont") ?? "") ?? .system
        reduceMotion = d.bool(forKey: "reduceMotion")
        historyMaxAgeDays = d.integer(forKey: "histMaxAge")
        totalSpeakSeconds = d.double(forKey: "speakSecs")
        soundTheme = SoundTheme(rawValue: d.string(forKey: "soundTheme") ?? "") ?? .soft
        insertTarget = InsertTarget(rawValue: d.string(forKey: "insertTarget") ?? "") ?? .activeApp
        if let data = d.data(forKey: "replacements"),
           let items = try? JSONDecoder().decode([Replacement].self, from: data) {
            replacements = items
        } else {
            replacements = [Replacement(phrase: "my email", replacement: "you@example.com")]
        }
    }
}

// MARK: - Settings window controller

final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
                             styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "Murmur Settings"
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            // Not movable-by-background: it would swallow drags meant for
            // controls like the color wheel. The (invisible) titlebar strip
            // at the top still drags the window.
            w.isMovableByWindowBackground = false
            w.isReleasedWhenClosed = false
            w.center()
            w.contentView = NSHostingView(rootView: SettingsRootView())
            window = w
        }
        WindowPolicyManager.shared.opened(window!)
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Root settings view (sidebar layout)

struct SettingsRootView: View {
    @ObservedObject var settings = AppSettings.shared
    @Environment(\.colorScheme) private var scheme
    @State private var tab = 0

    var body: some View {
        let p = Palette.of(scheme)
        HStack(spacing: 0) {
            sidebar
            p.border.frame(width: 1)
            Group {
                switch tab {
                case 0: GeneralPane(settings: settings)
                case 1: DictionaryPane(settings: settings)
                case 2: AppearancePane(settings: settings)
                case 3: StatsPane(settings: settings)
                default: HistoryPane(settings: settings)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                ZStack {
                    p.bg
                    SkinBackground(seed: 1)
                }
            }
        }
        .frame(width: 700, height: 500)
    }

    private var sidebar: some View {
        let p = Palette.of(scheme)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                    .resizable()
                    .frame(width: 26, height: 26)
                Text("Murmur")
                    .font(murmurFont(14, .semibold, sketch: settings.sketchMode, scheme: scheme))
                    .foregroundStyle(p.text)
            }
            .padding(.horizontal, 10)
            .padding(.top, 44)
            .padding(.bottom, 18)

            navItem(0, "slider.horizontal.3", "General")
            navItem(1, "character.book.closed", "Dictionary")
            navItem(2, "paintbrush", "Appearance")
            navItem(3, "chart.bar", "Stats")
            navItem(4, "clock.arrow.circlepath", "History")

            Spacer()

            if settings.totalWords > 0 {
                let words = settings.totalWords == 1 ? "word" : "words"
                VStack(alignment: .leading, spacing: 1) {
                    if settings.streak() >= 2 {
                        Text("🔥 \(settings.streak())-day streak")
                    }
                    Text("\(settings.totalWords.formatted()) \(words) dictated")
                    Text("~\(Int(settings.minutesSaved)) min saved vs. typing")
                }
                .font(.system(size: 10.5))
                .foregroundStyle(p.subtext)
                .padding(.horizontal, 10)
                .padding(.bottom, 14)
            }
        }
        .padding(.horizontal, 8)
        .frame(width: 176)
        .background {
            ZStack {
                p.sidebar
                SkinBackground(seed: 7)
            }
        }
    }

    private func navItem(_ index: Int, _ symbol: String, _ label: String) -> some View {
        let p = Palette.of(scheme)
        let selected = tab == index
        return Button {
            tab = index
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 16)
                Text(label)
                    .font(murmurFont(13, selected ? .semibold : .regular,
                                     sketch: settings.sketchMode, scheme: scheme))
                Spacer()
            }
            .foregroundStyle(selected ? settings.accentColor : p.subtext)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? settings.accentColor.opacity(0.13) : .clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

/// Shared scaffold for a content pane: header + scrolling sections.
struct Pane<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: title, subtitle: subtitle)
                    .padding(.bottom, 4)
                content
            }
            .padding(.horizontal, 28)
            .padding(.top, 44)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - General pane

struct GeneralPane: View {
    @ObservedObject var settings: AppSettings
    @Environment(\.colorScheme) private var scheme
    @State private var loginEnabled = LoginItem.isEnabled

    var body: some View {
        let p = Palette.of(scheme)
        Pane(title: "General",
             subtitle: "Hold \(settings.hotkey.name) and talk — Murmur types it anywhere.") {
            SectionLabel(text: "Hotkey")
            CardGroup {
                PRow(title: "Push-to-talk key",
                     subtitle: "Hold to talk · quick-tap for hands-free · Esc cancels") {
                    HStack(spacing: 6) {
                        KeyCaptureButton(settings: settings)
                        if settings.hotkey != .rightOption {
                            Button("Reset") { settings.hotkey = .rightOption }
                                .buttonStyle(.borderless)
                                .font(.system(size: 12))
                        }
                    }
                }
            }
            if let warning = hotkeyWarning {
                Text(warning)
                    .font(.system(size: 11))
                    .foregroundStyle(p.subtext)
                    .padding(.horizontal, 2)
                    .padding(.top, -10)
            }

            SectionLabel(text: "Transcript")
                .padding(.top, 6)
            CardGroup {
                PRow(title: "Remove filler words",
                     subtitle: "Strips “um”, “uh”, and friends") {
                    Toggle("", isOn: $settings.tidyEnabled)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "AI polish with Claude",
                     subtitle: "Fixes false starts and paragraphs — adds a few seconds") {
                    Toggle("", isOn: $settings.polishEnabled)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                if settings.polishEnabled {
                    RowDivider()
                    PRow(title: "Polish tone",
                         subtitle: "How Claude shapes the rewrite") {
                        Picker("", selection: $settings.polishTone) {
                            ForEach(PolishTone.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 240)
                    }
                    if settings.polishTone == .custom {
                        RowDivider()
                        PRow(title: "Custom instruction",
                             subtitle: "Applied on top of the cleanup pass") {
                            TextField("e.g. Translate to Spanish", text: $settings.customPolishPrompt)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12))
                                .frame(width: 230)
                        }
                    }
                    RowDivider()
                    PRow(title: "Polish engine",
                         subtitle: settings.polishBackend == .cli
                            ? "Uses the claude CLI installed on this Mac"
                            : "Uses your Anthropic API key from the macOS Keychain") {
                        Picker("", selection: $settings.polishBackend) {
                            ForEach(PolishBackend.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 170)
                    }
                    if settings.polishBackend == .api {
                        RowDivider()
                        PRow(title: "Anthropic API key",
                             subtitle: settings.hasAPIKey
                                ? "A key is saved in your Keychain — it never leaves this Mac"
                                : "Get one at console.anthropic.com — stored only in your Keychain") {
                            if settings.hasAPIKey {
                                Button("Remove Key") { settings.removeAPIKey() }
                                    .buttonStyle(.borderless)
                                    .font(.system(size: 12))
                            } else {
                                APIKeyField(settings: settings)
                            }
                        }
                    }
                }
                RowDivider()
                PRow(title: "Capitalize “i”",
                     subtitle: "i think → I think") {
                    Toggle("", isOn: $settings.capitalizeI)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Smart punctuation",
                     subtitle: "Curly quotes and em dashes") {
                    Toggle("", isOn: $settings.smartPunctuation)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Drop trailing period") {
                    Toggle("", isOn: $settings.noTrailingPeriod)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Discard accidental recordings",
                     subtitle: "Ignore dictations at or under this many words") {
                    Picker("", selection: $settings.discardShortWords) {
                        Text("Off").tag(0)
                        ForEach([1, 2, 3], id: \.self) { Text("≤ \($0)").tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 170)
                }
                RowDivider()
                PRow(title: "Max recording length",
                     subtitle: "Auto-finish after this long") {
                    Picker("", selection: $settings.maxRecordSeconds) {
                        Text("Off").tag(0)
                        Text("30s").tag(30)
                        Text("1m").tag(60)
                        Text("2m").tag(120)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 190)
                }
                RowDivider()
                PRow(title: "Output case",
                     subtitle: "Transform everything you dictate") {
                    Picker("", selection: $settings.outputCase) {
                        ForEach(OutputCase.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 250)
                }
                RowDivider()
                PRow(title: "End hands-free after silence") {
                    HStack(spacing: 8) {
                        if settings.autoStopEnabled {
                            Picker("", selection: $settings.silenceSeconds) {
                                Text("2s").tag(2.0)
                                Text("3s").tag(3.0)
                                Text("5s").tag(5.0)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 110)
                        }
                        Toggle("", isOn: $settings.autoStopEnabled)
                            .toggleStyle(.switch).labelsHidden().controlSize(.small)
                    }
                }
            }

            SectionLabel(text: "Recognition")
                .padding(.top, 6)
            CardGroup {
                PRow(title: "Language",
                     subtitle: "On-device when the language supports it") {
                    Picker("", selection: $settings.localeID) {
                        ForEach(Self.languages, id: \.0) { id, name in
                            Text(name).tag(id)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 170)
                }
                RowDivider()
                PRow(title: "Auto-punctuation",
                     subtitle: "Let the recognizer add commas and periods") {
                    Toggle("", isOn: $settings.autoPunctuation)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Tap vs. hold threshold",
                     subtitle: "Presses shorter than this count as a hands-free tap") {
                    HStack(spacing: 8) {
                        Slider(value: $settings.tapThreshold, in: 0.2...0.6)
                            .frame(width: 110)
                            .controlSize(.small)
                        Text(String(format: "%.2fs", settings.tapThreshold))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(p.subtext)
                            .frame(width: 42, alignment: .trailing)
                    }
                }
            }

            SectionLabel(text: "System")
                .padding(.top, 6)
            CardGroup {
                PRow(title: "Insert into",
                     subtitle: "Clipboard mode copies instead of typing it out") {
                    Picker("", selection: $settings.insertTarget) {
                        ForEach(InsertTarget.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 170)
                }
                RowDivider()
                PRow(title: "Insert by typing",
                     subtitle: "Slower, but works in apps that block ⌘V paste") {
                    Toggle("", isOn: $settings.typeInsteadOfPaste)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Add trailing space",
                     subtitle: "Ready for the next sentence") {
                    Toggle("", isOn: $settings.trailingSpace)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Keep transcript on clipboard",
                     subtitle: "Skip restoring the previous clipboard after inserting") {
                    Toggle("", isOn: $settings.keepTranscriptOnClipboard)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Long transcripts to clipboard",
                     subtitle: "Don't auto-insert walls of text") {
                    Picker("", selection: $settings.longToClipboardWords) {
                        Text("Off").tag(0)
                        Text("> 100w").tag(100)
                        Text("> 250w").tag(250)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 190)
                }
                RowDivider()
                PRow(title: "Show streak in menu bar") {
                    Toggle("", isOn: $settings.showMenuBarStreak)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Daily word goal",
                     subtitle: "Progress shows in the History activity card") {
                    Picker("", selection: $settings.dailyGoal) {
                        Text("Off").tag(0)
                        ForEach([250, 500, 1000, 2000], id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 90)
                }
                RowDivider()
                PRow(title: "Sound effects",
                     subtitle: "Soft cues on start, insert, and cancel") {
                    Toggle("", isOn: $settings.soundsEnabled)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                if settings.soundsEnabled {
                    RowDivider()
                    PRow(title: "Sound theme") {
                        Picker("", selection: $settings.soundTheme) {
                            ForEach(SoundTheme.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 170)
                    }
                    RowDivider()
                    PRow(title: "Volume") {
                        Slider(value: $settings.soundVolume, in: 0.1...1.0)
                            .frame(width: 130)
                            .controlSize(.small)
                    }
                }
                RowDivider()
                PRow(title: "Show today's words in menu bar") {
                    Toggle("", isOn: $settings.showMenuBarCount)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Launch at login") {
                    Toggle("", isOn: $loginEnabled)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                        .onChange(of: loginEnabled) { _, on in LoginItem.set(enabled: on) }
                }
            }

            SectionLabel(text: "Backup")
                .padding(.top, 6)
            CardGroup {
                PRow(title: "Settings & data",
                     subtitle: "Everything: settings, dictionary, history, stats, badges") {
                    HStack(spacing: 6) {
                        Button("Export…") { exportSettings() }
                        Button("Import…") { importSettings() }
                    }
                }
                RowDivider()
                PRow(title: "Reset settings to defaults",
                     subtitle: "Keeps your history, dictionary, stats, and badges") {
                    Button("Reset") { settings.resetToDefaults() }
                }
            }
        }
    }

    private func exportSettings() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Murmur Backup.json"
        panel.title = "Export Murmur Backup"
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? settings.exportBackup() else { return }
        try? data.write(to: url)
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Import Murmur Backup"
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url) else { return }
        try? settings.importBackup(data)
    }

    /// Speech locales offered in the picker — the common ones Apple supports,
    /// intersected with what this machine's recognizer actually offers.
    static let languages: [(String, String)] = {
        let wanted = ["en-US", "en-GB", "en-AU", "en-IN", "es-ES", "es-MX", "fr-FR",
                      "de-DE", "it-IT", "pt-BR", "nl-NL", "sv-SE", "ja-JP", "ko-KR",
                      "zh-CN", "hi-IN"]
        let supported = Set(SFSpeechRecognizer.supportedLocales().map(\.identifier))
        let display = Locale(identifier: "en-US")
        return wanted
            .filter { supported.contains($0) || supported.contains($0.replacingOccurrences(of: "-", with: "_")) }
            .map { ($0, display.localizedString(forIdentifier: $0) ?? $0) }
    }()

    private var hotkeyWarning: String? {
        if settings.hotkey.keyCode == 63 {
            return "Fn may conflict with the system emoji/dictation key — see System Settings ▸ Keyboard."
        }
        if !settings.hotkey.isModifier {
            return "Murmur reserves \(settings.hotkey.name) system-wide while it's running, so pick a key you don't otherwise use."
        }
        return nil
    }
}

/// Secure entry for the optional Anthropic API key (Keychain-backed).
struct APIKeyField: View {
    @ObservedObject var settings: AppSettings
    @State private var draft = ""

    var body: some View {
        HStack(spacing: 6) {
            SecureField("sk-ant-…", text: $draft)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
                .frame(width: 180)
            Button("Save") {
                settings.saveAPIKey(draft)
                draft = ""
            }
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
}

/// Button that captures the next key press as the new hotkey.
struct KeyCaptureButton: View {
    @ObservedObject var settings: AppSettings
    @State private var capturing = false
    @State private var monitor: Any?

    var body: some View {
        Button(capturing ? "Type a key…" : settings.hotkey.name) {
            capturing ? stopCapture() : startCapture()
        }
        .buttonStyle(.bordered)
        .tint(capturing ? .accentColor : nil)
        .onDisappear { stopCapture() }
    }

    private func startCapture() {
        capturing = true
        KeyCaptureState.active = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if event.type == .keyDown {
                if event.keyCode != 53 { // Esc = cancel, reserved for cancelling dictation
                    settings.hotkey = HotkeyKey(keyCode: event.keyCode, isModifier: false,
                                                name: HotkeyKey.displayName(for: event))
                }
                stopCapture()
                return nil
            }
            if let name = HotkeyKey.modifierName(for: event.keyCode) {
                let candidate = HotkeyKey(keyCode: event.keyCode, isModifier: true, name: name)
                if let flag = candidate.modifierFlag, event.modifierFlags.contains(flag) {
                    settings.hotkey = candidate
                    stopCapture()
                }
            }
            return nil
        }
    }

    private func stopCapture() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        capturing = false
        KeyCaptureState.active = false
    }
}

// MARK: - Dictionary pane

struct DictionaryPane: View {
    @ObservedObject var settings: AppSettings
    @Environment(\.colorScheme) private var scheme
    @State private var testInput = ""

    private func isDuplicate(_ phrase: String) -> Bool {
        !phrase.isEmpty &&
        settings.replacements.filter { $0.phrase.caseInsensitiveCompare(phrase) == .orderedSame }.count > 1
    }

    private func exportDictionary() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Murmur Dictionary.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let esc: (String) -> String = { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        let rows = settings.replacements.map { "\(esc($0.phrase)),\(esc($0.replacement))" }
        try? ("phrase,replacement\n" + rows.joined(separator: "\n") + "\n")
            .write(to: url, atomically: true, encoding: .utf8)
    }

    private func importDictionary() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        var added = 0
        for line in content.components(separatedBy: .newlines).dropFirst() {
            let cols = line.components(separatedBy: ",")
            guard cols.count >= 2 else { continue }
            let clean: (String) -> String = {
                $0.trimmingCharacters(in: .whitespaces)
                  .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                  .replacingOccurrences(of: "\"\"", with: "\"")
            }
            let phrase = clean(cols[0])
            let repl = clean(cols[1...].joined(separator: ","))
            guard !phrase.isEmpty, !repl.isEmpty,
                  !settings.replacements.contains(where: { $0.phrase == phrase }) else { continue }
            settings.replacements.append(Replacement(phrase: phrase, replacement: repl))
            added += 1
        }
        NSLog("Murmur: imported \(added) replacements")
    }

    var body: some View {
        let p = Palette.of(scheme)
        Pane(title: "Dictionary",
             subtitle: "Teach Murmur your words, names, and shortcuts.") {
            SectionLabel(text: "Voice commands")
            CardGroup {
                PRow(title: "“New line” and “new paragraph”",
                     subtitle: "Say them to insert line breaks while dictating") {
                    Toggle("", isOn: $settings.voiceCommandsEnabled)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
            }

            SectionLabel(text: "Replacements")
                .padding(.top, 6)
            CardGroup {
                if settings.replacements.isEmpty {
                    Text("No replacements yet — add a spoken phrase and what it should type.")
                        .font(.system(size: 12))
                        .foregroundStyle(p.subtext)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach($settings.replacements) { $item in
                        if item.id != settings.replacements.first?.id { RowDivider() }
                        HStack(spacing: 10) {
                            Toggle("", isOn: $item.enabled)
                                .toggleStyle(.checkbox)
                                .labelsHidden()
                            TextField("Spoken phrase", text: $item.phrase)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12.5))
                                .foregroundStyle(isDuplicate(item.phrase) ? .red : p.text)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(p.subtext)
                            TextField("Text to insert", text: $item.replacement)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12.5))
                                .foregroundStyle(p.text)
                            Button {
                                settings.replacements.removeAll { $0.id == item.id }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(p.subtext.opacity(0.7))
                            }
                            .buttonStyle(.borderless)
                            .help("Remove")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                }
                RowDivider()
                HStack(spacing: 14) {
                    Button {
                        settings.replacements.append(Replacement(phrase: "", replacement: ""))
                    } label: {
                        Label("Add Replacement", systemImage: "plus")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(settings.accentColor)
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                    Button("A→Z") {
                        settings.replacements.sort {
                            $0.phrase.localizedCaseInsensitiveCompare($1.phrase) == .orderedAscending
                        }
                    }
                    .buttonStyle(.borderless).font(.system(size: 11)).foregroundStyle(p.subtext)
                    Button("Export CSV") { exportDictionary() }
                        .buttonStyle(.borderless).font(.system(size: 11)).foregroundStyle(p.subtext)
                    Button("Import CSV") { importDictionary() }
                        .buttonStyle(.borderless).font(.system(size: 11)).foregroundStyle(p.subtext)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            CardGroup {
                PRow(title: "Case-sensitive matching",
                     subtitle: "Off = “My Email” matches “my email”") {
                    Toggle("", isOn: $settings.caseSensitiveReplacements)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
            }

            SectionLabel(text: "Try it")
                .padding(.top, 6)
            CardGroup {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Type a phrase to test commands + replacements…", text: $testInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                    if !testInput.isEmpty {
                        Text(TextCleaner.applyReplacements(
                                settings.voiceCommandsEnabled
                                    ? TextCleaner.applyCommands(testInput) : testInput,
                                settings.replacements))
                            .font(.system(size: 12))
                            .foregroundStyle(settings.accentColor)
                            .textSelection(.enabled)
                    }
                }
                .padding(14)
            }
            Text("Say the phrase while dictating and Murmur types the replacement. These phrases are also sent to the speech engine as vocabulary hints, so unusual names get recognized more reliably.")
                .font(.system(size: 11))
                .foregroundStyle(p.subtext)
                .padding(.horizontal, 2)
                .padding(.top, -8)

            SectionLabel(text: "Filler words")
                .padding(.top, 6)
            CardGroup {
                PRow(title: "Words to strip",
                     subtitle: "Comma-separated — removed when “Remove filler words” is on") {
                    TextField("um, uh, like…", text: Binding(
                        get: { settings.fillerWords.joined(separator: ", ") },
                        set: { settings.fillerWords = $0.components(separatedBy: ",")
                            .map { $0.trimmingCharacters(in: .whitespaces) } }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .frame(width: 240)
                }
            }

            SectionLabel(text: "App rules")
                .padding(.top, 6)
            CardGroup {
                if settings.appRules.isEmpty {
                    Text("No rules yet — pick a tone and case that apply automatically when dictating into a matching app (e.g. “Mail” → Email tone).")
                        .font(.system(size: 12))
                        .foregroundStyle(p.subtext)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach($settings.appRules) { $rule in
                        if rule.id != settings.appRules.first?.id { RowDivider() }
                        HStack(spacing: 10) {
                            TextField("App name (e.g. Mail)", text: $rule.appName)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12.5))
                                .foregroundStyle(p.text)
                                .frame(width: 130)
                            Picker("", selection: $rule.tone) {
                                ForEach(PolishTone.allCases) { Text($0.label).tag($0) }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(width: 90)
                            Picker("", selection: $rule.ocase) {
                                ForEach(OutputCase.allCases) { Text($0.label).tag($0) }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(width: 110)
                            Spacer()
                            Button {
                                settings.appRules.removeAll { $0.id == rule.id }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(p.subtext.opacity(0.7))
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                }
                RowDivider()
                Button {
                    settings.appRules.append(AppRule(appName: ""))
                } label: {
                    Label("Add App Rule", systemImage: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(settings.accentColor)
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
    }
}

// MARK: - Color wheel

/// Hue/saturation wheel: angle picks hue, distance from center picks
/// saturation (white at the center). Drag or click anywhere on it.
struct ColorWheel: View {
    @Binding var hue: Double
    @Binding var sat: Double
    var size: CGFloat = 150

    var body: some View {
        ZStack {
            Circle()
                .fill(AngularGradient(
                    gradient: Gradient(colors: (0...24).map {
                        Color(hue: Double($0) / 24.0, saturation: 1, brightness: 1)
                    }),
                    center: .center))
            Circle()
                .fill(RadialGradient(colors: [.white, .white.opacity(0)],
                                     center: .center, startRadius: 0, endRadius: size / 2))
            Circle()
                .strokeBorder(.black.opacity(0.12), lineWidth: 1)
            knob
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { update($0.location) }
        )
    }

    private var knob: some View {
        let radius = (size / 2 - 2) * sat
        let angle = hue * 2 * .pi
        return Circle()
            .fill(Color(hue: hue, saturation: sat, brightness: 1))
            .overlay(Circle().strokeBorder(.white, lineWidth: 2.5))
            .frame(width: 18, height: 18)
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            .offset(x: cos(angle) * radius, y: sin(angle) * radius)
    }

    private func update(_ location: CGPoint) {
        let dx = location.x - size / 2
        let dy = location.y - size / 2
        let r = min(1, sqrt(dx * dx + dy * dy) / (size / 2 - 2))
        var h = atan2(dy, dx) / (2 * .pi)
        if h < 0 { h += 1 }
        hue = h
        sat = r
    }
}

// MARK: - Appearance pane

struct AppearancePane: View {
    @ObservedObject var settings: AppSettings
    @Environment(\.colorScheme) private var scheme
    @StateObject private var previewState = AppearancePane.makePreviewState()
    private let timer = Timer.publish(every: 0.09, on: .main, in: .common).autoconnect()
    @State private var t: Double = 0

    var body: some View {
        let p = Palette.of(scheme)
        VStack(spacing: 0) {
        Pane(title: "Appearance",
             subtitle: "Make the dictation pill yours.") {
            SectionLabel(text: "Skin")
            CardGroup {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                          spacing: 8) {
                    ForEach(AppSkin.allCases) { s in
                        skinChip(s)
                    }
                }
                .padding(12)
            }

            SectionLabel(text: "Accent")
                .padding(.top, 6)
            CardGroup {
                HStack(alignment: .center, spacing: 24) {
                    ColorWheel(hue: $settings.accentHue, sat: $settings.accentSat, size: 148)
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Presets")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(p.subtext)
                            HStack(spacing: 8) {
                                ForEach(AccentChoice.allCases) { choice in
                                    accentSwatch(choice)
                                }
                            }
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Current")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(p.subtext)
                            HStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(settings.accentColor)
                                    .frame(width: 42, height: 26)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .strokeBorder(p.border, lineWidth: 1)
                                    )
                                Text(settings.accentHex)
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .foregroundStyle(p.subtext)
                            }
                        }
                    }
                    Spacer()
                }
                .padding(16)
            }

            SectionLabel(text: "Pill")
                .padding(.top, 6)
            CardGroup {
                PRow(title: "Match app skin",
                     subtitle: "Dress the pill in the selected skin — off keeps the classic pill") {
                    Toggle("", isOn: $settings.pillMatchesSkin)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Theme") {
                    Picker("", selection: $settings.pillTheme) {
                        ForEach(PillTheme.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 250)
                }
                RowDivider()
                PRow(title: "Waveform style") {
                    Picker("", selection: $settings.waveStyle) {
                        ForEach(WaveStyle.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 200)
                }
                RowDivider()
                PRow(title: "Background opacity") {
                    HStack(spacing: 8) {
                        Slider(value: $settings.pillOpacity, in: 0.7...1.0)
                            .frame(width: 130)
                            .controlSize(.small)
                        Text("\(Int(settings.pillOpacity * 100))%")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Palette.of(scheme).subtext)
                            .frame(width: 36, alignment: .trailing)
                    }
                }
                RowDivider()
                PRow(title: "Size") {
                    Picker("", selection: $settings.pillSize) {
                        ForEach(PillSize.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 200)
                }
                RowDivider()
                PRow(title: "Position on screen") {
                    Picker("", selection: $settings.pillPosition) {
                        ForEach(PillPosition.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 150)
                }
                RowDivider()
                PRow(title: "Horizontal alignment") {
                    Picker("", selection: $settings.pillAlignment) {
                        ForEach(PillAlignment.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 200)
                }
                RowDivider()
                PRow(title: "Corner style") {
                    Picker("", selection: $settings.pillCorner) {
                        ForEach(PillCorner.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 200)
                }
                RowDivider()
                PRow(title: "Text font") {
                    Picker("", selection: $settings.pillFont) {
                        ForEach(PillFont.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 230)
                }
                RowDivider()
                PRow(title: "Border width") {
                    Slider(value: $settings.pillBorderWidth, in: 0.5...3.0)
                        .frame(width: 130).controlSize(.small)
                }
                RowDivider()
                PRow(title: "Glow intensity") {
                    Slider(value: $settings.glowIntensity, in: 0.2...2.0)
                        .frame(width: 130).controlSize(.small)
                }
                RowDivider()
                PRow(title: "Waveform bars") {
                    Picker("", selection: $settings.waveBarCount) {
                        Text("16").tag(16)
                        Text("28").tag(28)
                        Text("40").tag(40)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 150)
                }
                RowDivider()
                PRow(title: "Waveform sensitivity") {
                    Slider(value: $settings.waveGain, in: 0.5...2.0)
                        .frame(width: 130).controlSize(.small)
                }
                RowDivider()
                PRow(title: "Distance from screen edge") {
                    Slider(value: $settings.pillEdgeOffset, in: 8...120)
                        .frame(width: 130).controlSize(.small)
                }
                RowDivider()
                PRow(title: "Idle indicator",
                     subtitle: "Tiny dot stays on screen between dictations") {
                    Toggle("", isOn: $settings.idleIndicator)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Reduce motion",
                     subtitle: "No springs, no waveform animation") {
                    Toggle("", isOn: $settings.reduceMotion)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Show live transcript",
                     subtitle: "Off = just the waveform, extra minimal") {
                    Toggle("", isOn: $settings.showTranscript)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Word counter") {
                    Toggle("", isOn: $settings.showWordCount)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Accent glow") {
                    Toggle("", isOn: $settings.glowEnabled)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
            }

            SectionLabel(text: "Menu bar")
                .padding(.top, 6)
            CardGroup {
                PRow(title: "Recording tint",
                     subtitle: "Menu icon color while recording") {
                    Picker("", selection: $settings.recordTintAccent) {
                        Text("Red").tag(false)
                        Text("Accent").tag(true)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 140)
                }
                RowDivider()
                PRow(title: "Icon") {
                    Picker("", selection: $settings.menuIcon) {
                        ForEach(MenuIcon.allCases) { icon in
                            Image(systemName: icon.symbol(recording: false)).tag(icon)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 150)
                }
            }

        }
        pinnedPreview(p)
        }
        .onReceive(timer) { _ in
            t += 0.35
            let level = Float(0.25 + 0.55 * abs(sin(t)) * Double.random(in: 0.55...1.0))
            previewState.pushLevel(level)
        }
    }

    /// Live pill preview pinned to the bottom of the pane so it stays visible
    /// the whole time while you scroll and tweak the settings above it.
    private func pinnedPreview(_ p: Palette) -> some View {
        VStack(spacing: 0) {
            p.border.frame(height: 1)
            VStack(spacing: 4) {
                HStack {
                    Text("Live preview")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(p.subtext)
                    Spacer()
                    Button("Show Real Pill") {
                        NotificationCenter.default.post(name: Notification.Name("MurmurTestPill"), object: nil)
                    }
                    .controlSize(.small)
                }
                PillBody(state: previewState, accent: settings.accentColor)
                    .scaleEffect(0.7)
                    .frame(height: 46)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity)
            .background(p.sidebar)
        }
    }

    private func accentSwatch(_ choice: AccentChoice) -> some View {
        let selected = abs(settings.accentHue - choice.hs.0) < 0.01
            && abs(settings.accentSat - choice.hs.1) < 0.01
        return Circle()
            .fill(choice.color)
            .frame(width: 18, height: 18)
            .overlay {
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .onTapGesture {
                settings.accentHue = choice.hs.0
                settings.accentSat = choice.hs.1
            }
            .accessibilityLabel(choice.label)
    }

    private func skinChip(_ s: AppSkin) -> some View {
        let p = Palette.of(scheme)
        let selected = settings.skin == s
        return Button {
            settings.skin = s
        } label: {
            HStack(spacing: 6) {
                Image(systemName: s.symbol)
                    .font(.system(size: 11, weight: .medium))
                Text(s.label)
                    .font(.system(size: 12, weight: .medium))
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(settings.accentColor)
                }
            }
            .foregroundStyle(selected ? p.text : p.subtext)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? p.bg : .clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(selected ? settings.accentColor.opacity(0.6) : p.border,
                                          lineWidth: 1)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    static func makePreviewState() -> PillState {
        let s = PillState()
        s.phase = .listening
        s.text = "This is what your dictation looks like"
        return s
    }
}

// MARK: - Stats pane

struct StatsPane: View {
    @ObservedObject var settings: AppSettings
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Palette.of(scheme)
        let bestDay = settings.dailyWords.values.max() ?? 0
        let avg = settings.totalSessions > 0 ? settings.totalWords / settings.totalSessions : 0
        let earnedCount = settings.earned.count
        Pane(title: "Stats",
             subtitle: "Your dictation life in numbers.") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
                      spacing: 10) {
                statTile("Words", settings.totalWords.formatted())
                statTile("Sessions", settings.totalSessions.formatted())
                statTile("Avg / session", "\(avg)")
                statTile("Best day", "\(bestDay)")
                statTile("Streak", "\(settings.streak())d")
                statTile("Longest streak", "\(settings.maxStreak)d")
                statTile("Min saved", String(format: "%.0f", settings.minutesSaved))
                statTile("Badges", "\(earnedCount)/\(Achievement.all.count)")
                statTile("This week", "\(settings.wordsInWeek(endingDaysAgo: 0))")
                statTile("Last week", "\(settings.wordsInWeek(endingDaysAgo: 7))")
                statTile("Active days", "\(settings.activeDays)")
                statTile("Avg / active day", "\(settings.avgWordsPerActiveDay)")
                statTile("Speaking WPM", settings.wordsPerMinute > 0 ? "\(settings.wordsPerMinute)" : "—")
                statTile("Time spoken", speakTimeLabel)
            }

            if let ms = settings.nextMilestone() {
                Text("Next badge: \(ms.name) — \(ms.remaining.formatted()) words to go (≈\(ms.days) active days at your pace)")
                    .font(.system(size: 11))
                    .foregroundStyle(p.subtext)
                    .padding(.horizontal, 2)
            }

            SectionLabel(text: "Last 30 days")
                .padding(.top, 6)
            CardGroup {
                HStack(alignment: .bottom, spacing: 4) {
                    let days = settings.monthActivity()
                    let maxC = max(days.map(\.count).max() ?? 1, 1)
                    ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(day.count > 0 ? settings.accentColor : p.border)
                            .frame(maxWidth: .infinity)
                            .frame(height: day.count > 0
                                   ? max(5, 52 * CGFloat(day.count) / CGFloat(maxC)) : 3)
                            .help("\(day.count) \(day.count == 1 ? "word" : "words") — \(day.date)")
                    }
                }
                .frame(height: 60, alignment: .bottom)
                .padding(14)
            }

            SectionLabel(text: "Achievements")
                .padding(.top, 10)
            let progress = Double(earnedCount) / Double(Achievement.all.count)
            Capsule().fill(p.border)
                .frame(height: 5)
                .overlay(alignment: .leading) {
                    GeometryReader { geo in
                        Capsule().fill(settings.accentColor)
                            .frame(width: max(progress > 0 ? 5 : 0, geo.size.width * progress))
                    }
                }
                .padding(.horizontal, 2)
            CardGroup {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4),
                          spacing: 14) {
                    ForEach(Achievement.all) { a in
                        badge(a)
                    }
                }
                .padding(14)
            }

            HStack {
                Button("Copy Summary") { copyStatsSummary() }
                    .buttonStyle(.borderless).font(.system(size: 12)).foregroundStyle(p.subtext)
                Spacer()
                Button("Reset Stats…") { confirmResetStats() }
                    .buttonStyle(.borderless).font(.system(size: 12)).foregroundStyle(.red.opacity(0.8))
            }
        }
    }

    private var speakTimeLabel: String {
        let secs = Int(settings.totalSpeakSeconds)
        if secs < 60 { return "\(secs)s" }
        return "\(secs / 60)m \(secs % 60)s"
    }

    private func copyStatsSummary() {
        let s = settings
        let text = """
        Murmur stats — \(Date().formatted(date: .abbreviated, time: .omitted))
        Words: \(s.totalWords.formatted()) · Sessions: \(s.totalSessions) · Streak: \(s.streak())d (best \(s.maxStreak)d)
        This week: \(s.wordsInWeek(endingDaysAgo: 0)) · Last week: \(s.wordsInWeek(endingDaysAgo: 7))
        Speaking pace: \(s.wordsPerMinute) WPM · Time saved vs typing: ~\(Int(s.minutesSaved)) min
        Badges: \(s.earned.count)/\(Achievement.all.count)
        """
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    private func confirmResetStats() {
        let alert = NSAlert()
        alert.messageText = "Reset all stats?"
        alert.informativeText = "Words, sessions, streaks, daily activity, and speaking time go back to zero. Badges and history are kept."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reset Stats")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { settings.resetStats() }
    }

    private func statTile(_ label: String, _ value: String) -> some View {
        let p = Palette.of(scheme)
        return CardGroup {
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(p.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(p.subtext)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func badge(_ a: Achievement) -> some View {
        let p = Palette.of(scheme)
        let date = settings.earned[a.id]
        let unlocked = date != nil
        var tip = a.desc
        if let date {
            tip += " — earned \(date.formatted(date: .abbreviated, time: .omitted))"
        }
        return VStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(unlocked
                          ? AnyShapeStyle(settings.accentColor.opacity(0.22))
                          : AnyShapeStyle(p.border.opacity(0.5)))
                    .frame(width: 40, height: 40)
                Image(systemName: unlocked ? a.symbol : "lock")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(unlocked ? settings.accentColor : p.subtext.opacity(0.6))
            }
            Text(a.name)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(unlocked ? p.text : p.subtext.opacity(0.7))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .opacity(unlocked ? 1 : 0.55)
        .help(tip)
    }
}

// MARK: - History pane

struct HistoryPane: View {
    @ObservedObject var settings: AppSettings
    @Environment(\.colorScheme) private var scheme
    @State private var query = ""
    @State private var filter = 0   // 0=all 1=pinned 2=today
    @State private var sort: HistorySort = .newest

    private var filtered: [HistoryItem] {
        var base = query.isEmpty
            ? settings.history
            : settings.history.filter { $0.text.localizedCaseInsensitiveContains(query) }
        if filter == 1 { base = base.filter(\.pinned) }
        if filter == 2 { base = base.filter { Calendar.current.isDateInToday($0.date) } }
        return base.sorted {
            if $0.pinned != $1.pinned { return $0.pinned }
            switch sort {
            case .newest: return $0.date > $1.date
            case .oldest: return $0.date < $1.date
            case .longest: return $0.text.count > $1.text.count
            }
        }
    }

    private var totalWordsShown: Int {
        filtered.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count }
    }

    var body: some View {
        let p = Palette.of(scheme)
        Pane(title: "History",
             subtitle: settings.history.isEmpty
                ? "Your recent transcripts will appear here."
                : "\(filtered.count) transcripts · \(totalWordsShown.formatted()) words") {
            if settings.totalWords > 0 {
                ActivityCard(settings: settings)
            }
            if !settings.history.isEmpty {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(p.subtext)
                    TextField("Search transcripts", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5))
                        .foregroundStyle(p.text)
                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(p.subtext)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(p.card)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(p.border, lineWidth: 1)
                )
                HStack(spacing: 8) {
                    Picker("", selection: $filter) {
                        Text("All").tag(0)
                        Text("Pinned").tag(1)
                        Text("Today").tag(2)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 190)
                    Spacer()
                    Picker("", selection: $sort) {
                        ForEach(HistorySort.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.menu).labelsHidden().fixedSize()
                }
            }
            if settings.history.isEmpty {
                CardGroup {
                    VStack(spacing: 6) {
                        Image(systemName: "text.quote")
                            .font(.system(size: 24))
                            .foregroundStyle(p.subtext.opacity(0.6))
                        Text("Nothing dictated yet")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(p.text)
                        Text("Hold \(settings.hotkey.name) and say something")
                            .font(.system(size: 11.5))
                            .foregroundStyle(p.subtext)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 36)
                }
            } else if filtered.isEmpty {
                CardGroup {
                    Text("No transcripts match “\(query)”")
                        .font(.system(size: 12))
                        .foregroundStyle(p.subtext)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                }
            } else {
                CardGroup {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { i, item in
                        if i > 0 { RowDivider() }
                        HistoryRow(item: item, settings: settings)
                    }
                }
                HStack(spacing: 12) {
                    Picker("Keep", selection: $settings.historyLimit) {
                        ForEach([25, 50, 100, 200], id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.menu).font(.system(size: 12)).fixedSize()
                    Picker("Auto-clear", selection: $settings.historyMaxAgeDays) {
                        Text("Never").tag(0)
                        Text("7 days").tag(7)
                        Text("30 days").tag(30)
                    }
                    .pickerStyle(.menu).font(.system(size: 12)).fixedSize()
                    Menu("Export") {
                        Button("Export All…") { exportHistory(pinnedOnly: false) }
                        Button("Export Pinned…") { exportHistory(pinnedOnly: true) }
                    }
                    .font(.system(size: 12)).fixedSize()
                    Button("Copy All") {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(filtered.map(\.text).joined(separator: "\n\n"), forType: .string)
                    }
                    .buttonStyle(.borderless).font(.system(size: 12)).foregroundStyle(p.subtext)
                    Spacer()
                    Button("Clear History") { settings.history = settings.history.filter(\.pinned) }
                        .buttonStyle(.borderless)
                        .font(.system(size: 12))
                        .foregroundStyle(p.subtext)
                }
            }
        }
    }

    private func exportHistory(pinnedOnly: Bool = false) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = pinnedOnly ? "Murmur Pinned Transcripts.md" : "Murmur Transcripts.md"
        panel.title = "Export Transcripts"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        let body = (pinnedOnly ? settings.history.filter(\.pinned) : settings.history)
            .map { "- **\(df.string(from: $0.date))** — \($0.text)" }
            .joined(separator: "\n")
        let md = "# Murmur Transcripts\n\n\(body)\n"
        try? md.write(to: url, atomically: true, encoding: .utf8)
    }
}

/// Words-per-day for the trailing week: hero total + thin baseline bars.
struct ActivityCard: View {
    @ObservedObject var settings: AppSettings
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Palette.of(scheme)
        let days = settings.weekActivity()
        let weekTotal = days.reduce(0) { $0 + $1.count }
        let maxCount = max(days.map(\.count).max() ?? 1, 1)
        CardGroup {
            HStack(alignment: .bottom, spacing: 24) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("THIS WEEK")
                        .font(.system(size: 9.5, weight: .semibold))
                        .kerning(0.4)
                        .foregroundStyle(p.subtext)
                    Text("\(weekTotal.formatted())")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(p.text)
                        .contentTransition(.numericText())
                    Text(weekTotal == 1 ? "word" : "words")
                        .font(.system(size: 11))
                        .foregroundStyle(p.subtext)
                    if settings.dailyGoal > 0 {
                        let today = settings.todayWords
                        let progress = min(1, Double(today) / Double(settings.dailyGoal))
                        VStack(alignment: .leading, spacing: 3) {
                            Capsule()
                                .fill(p.border)
                                .frame(width: 120, height: 5)
                                .overlay(alignment: .leading) {
                                    Capsule()
                                        .fill(settings.accentColor)
                                        .frame(width: max(progress > 0 ? 5 : 0, 120 * progress))
                                }
                            Text("\(today) / \(settings.dailyGoal) today")
                                .font(.system(size: 10))
                                .foregroundStyle(p.subtext)
                        }
                        .padding(.top, 6)
                    }
                }
                Spacer()
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(day.count > 0
                                      ? settings.accentColor
                                      : p.border)
                                .frame(width: 8,
                                       height: day.count > 0
                                           ? max(6, 44 * CGFloat(day.count) / CGFloat(maxCount))
                                           : 3)
                            Text(day.label)
                                .font(.system(size: 9))
                                .foregroundStyle(p.subtext)
                        }
                        .help("\(day.count) \(day.count == 1 ? "word" : "words") — \(day.date)")
                    }
                }
            }
            .padding(16)
        }
    }
}

struct HistoryRow: View {
    @Environment(\.colorScheme) private var scheme
    let item: HistoryItem
    @ObservedObject var settings: AppSettings
    @State private var copied = false
    @State private var hovering = false
    @State private var showDetail = false
    @State private var polishing = false

    var body: some View {
        let p = Palette.of(scheme)
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.text)
                    .font(.system(size: 12.5))
                    .foregroundStyle(p.text)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 4) {
                    Text(item.date, format: .dateTime.month().day().hour().minute())
                    Text("· \(item.text.split(whereSeparator: \.isWhitespace).count) words")
                }
                .font(.system(size: 10.5))
                .foregroundStyle(p.subtext)
            }
            Spacer(minLength: 8)
            Button {
                showDetail = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 11.5))
                    .foregroundStyle(p.subtext)
            }
            .buttonStyle(.borderless)
            .opacity(hovering ? 1 : 0.35)
            .help("Details")
            .popover(isPresented: $showDetail, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.text)
                        .font(.system(size: 12.5))
                        .textSelection(.enabled)
                        .frame(maxWidth: 340, alignment: .leading)
                    Text("\(item.date.formatted(date: .abbreviated, time: .shortened)) · \(item.text.split(whereSeparator: \.isWhitespace).count) words · \(item.text.count) characters")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                .padding(14)
            }
            Button {
                guard !polishing else { return }
                polishing = true
                TextCleaner.polish(item.text, tone: settings.polishTone,
                                   custom: settings.customPolishPrompt) { out in
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(out, forType: .string)
                    polishing = false
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                }
            } label: {
                if polishing {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 11.5))
                        .foregroundStyle(p.subtext)
                }
            }
            .buttonStyle(.borderless)
            .opacity(hovering || polishing ? 1 : 0.35)
            .help("Polish with Claude & copy")
            Button {
                settings.history.removeAll { $0.id == item.id }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(p.subtext)
            }
            .buttonStyle(.borderless)
            .opacity(hovering ? 1 : 0.35)
            .help("Delete")
            Button {
                NSApp.hide(nil) // hand focus back to the previous app first
                let text = item.text
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    Inserter.insert(text)
                }
            } label: {
                Image(systemName: "text.insert")
                    .font(.system(size: 11.5))
                    .foregroundStyle(p.subtext)
            }
            .buttonStyle(.borderless)
            .opacity(hovering ? 1 : 0.35)
            .help("Insert into the previous app")
            Button {
                if let i = settings.history.firstIndex(where: { $0.id == item.id }) {
                    settings.history[i].pinned.toggle()
                }
            } label: {
                Image(systemName: item.pinned ? "pin.fill" : "pin")
                    .font(.system(size: 11))
                    .foregroundStyle(item.pinned ? settings.accentColor : p.subtext)
            }
            .buttonStyle(.borderless)
            .opacity(hovering || item.pinned ? 1 : 0.35)
            .help(item.pinned ? "Unpin" : "Pin — survives trimming and Clear History")
            Button {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(item.text, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11.5))
                    .foregroundStyle(copied ? .green : p.subtext)
            }
            .buttonStyle(.borderless)
            .opacity(hovering || copied ? 1 : 0.35)
            .help("Copy")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .onHover { hovering = $0 }
    }
}

// MARK: - Launch at login helper

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static func set(enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Login item toggle failed: \(error)")
        }
    }
}
