import SwiftUI
import AppKit
import Combine
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
    /// App the transcript was inserted into, when known.
    var app: String?
    /// How long the dictation took, in seconds, when known.
    var seconds: Double?

    init(text: String, date: Date, pinned: Bool = false,
         app: String? = nil, seconds: Double? = nil) {
        self.text = text
        self.date = date
        self.pinned = pinned
        self.app = app
        self.seconds = seconds
    }

    // Manual decoding so items saved before newer fields existed still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try c.decode(String.self, forKey: .text)
        date = try c.decode(Date.self, forKey: .date)
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        app = try c.decodeIfPresent(String.self, forKey: .app)
        seconds = try c.decodeIfPresent(Double.self, forKey: .seconds)
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
    case bars, dots, wave, blocks
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

/// Recipe for spec-driven skins: one line of parameters instead of bespoke
/// styling everywhere. The original ten hand-built skins return nil.
struct SkinSpec {
    let palette: Palette
    let ink: Color
    let isDark: Bool
    let fontName: String?
    let fontDesign: Font.Design
    let pillFill: Color
    let pillBorder: Color
    let pillRadius: CGFloat
    let glow: Color

    func font(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        if let fontName { return .custom(fontName, size: size) }
        return .system(size: size, weight: weight, design: fontDesign)
    }

    static func dark(_ r: Double, _ g: Double, _ b: Double, ink: Color,
                     font: String? = nil, design: Font.Design = .default,
                     radius: CGFloat = 100) -> SkinSpec {
        SkinSpec(
            palette: Palette(
                bg: Color(red: r, green: g, blue: b),
                sidebar: Color(red: min(1, r + 0.018), green: min(1, g + 0.018), blue: min(1, b + 0.022)),
                card: Color(red: min(1, r + 0.045), green: min(1, g + 0.045), blue: min(1, b + 0.055)),
                border: ink.opacity(0.28),
                text: Color(white: 0.93),
                subtext: Color(white: 0.62)),
            ink: ink, isDark: true, fontName: font, fontDesign: design,
            pillFill: Color(red: min(1, r + 0.025), green: min(1, g + 0.025), blue: min(1, b + 0.03)),
            pillBorder: ink.opacity(0.6), pillRadius: radius, glow: ink)
    }

    static func light(_ r: Double, _ g: Double, _ b: Double, ink: Color,
                      font: String? = nil, design: Font.Design = .default,
                      radius: CGFloat = 100) -> SkinSpec {
        SkinSpec(
            palette: Palette(
                bg: Color(red: r, green: g, blue: b),
                sidebar: Color(red: max(0, r - 0.035), green: max(0, g - 0.035), blue: max(0, b - 0.03)),
                card: Color(red: 0.995, green: 0.995, blue: 0.995),
                border: ink.opacity(0.30),
                text: Color(red: 0.16, green: 0.14, blue: 0.15),
                subtext: Color(red: 0.45, green: 0.43, blue: 0.44)),
            ink: ink, isDark: false, fontName: font, fontDesign: design,
            pillFill: Color(red: 0.995, green: 0.995, blue: 0.995),
            pillBorder: ink.opacity(0.55), pillRadius: radius, glow: ink)
    }
}

/// Typeface choices for the user-built Custom skin.
enum CustomSkinFont: String, CaseIterable, Identifiable, Codable {
    case system, rounded, serif, mono, marker, avenir
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "System"
        case .rounded: return "Rounded"
        case .serif: return "Serif"
        case .mono: return "Mono"
        case .marker: return "Marker"
        case .avenir: return "Avenir"
        }
    }
    var fontName: String? {
        switch self {
        case .serif: return "Georgia"
        case .mono: return "Menlo"
        case .marker: return "Marker Felt"
        case .avenir: return "Avenir Next"
        case .system, .rounded: return nil
        }
    }
    var design: Font.Design { self == .rounded ? .rounded : .default }
}

enum AppSkin: String, CaseIterable, Identifiable {
    // Hand-built originals
    case clean, sketch, terminal, blueprint, retro, neon, paper, midnight, forest, candy
    // Spec-driven — dark
    case ocean, lava, slate, grape, coffee, cherry, gold, denim, olive, charcoal,
         cyber, storm, pumpkin
    // Spec-driven — light
    case ice, lavender, mint, sand, rose, linen, honey
    // v2.7 wave — dark
    case crimson, royal, emerald, copper, steel, plum, abyss, aurora, indigo, jade,
         carbon, wine, cocoa, navy, moss, graphite, amethyst, ember, teal, sapphire,
         onyx, bronze, cosmos, shadow
    // v2.7 wave — light
    case cloud, seafoam, blush, butter, lilac, peach, sage, sky, cream, pistachio,
         pearl, chambray, cotton, fog, matcha, orchid
    // v2.7 wave 2 — the road to 100
    case cobalt, scarlet, mustard, velvet, arctic, terracotta, eggplant, seaweed,
         noir, petrol, sienna, galaxy, hunter, merlot, gunmetal, blackberry, tangerine
    case vanilla, rosewater, glacier, meadow, sandstone, periwinkle, shell,
         porcelain, lemon, flamingo, dove, julep
    // User-built in the Skin Studio
    case custom
    var id: String { rawValue }

    /// The recipe for spec-driven skins; nil for the hand-built originals.
    var spec: SkinSpec? {
        switch self {
        case .custom:
            // Built live from the Skin Studio: per-color overrides, falling
            // back to a coherent set generated from the theme wheel.
            let s = AppSettings.shared
            let g = AppSettings.generatedCustomColors(hue: s.customSkinHue,
                                                      sat: s.customSkinSat,
                                                      dark: s.customSkinDark)
            let bg = AppSettings.parseHex(s.customBgHex) ?? g.bg
            let sidebar = AppSettings.parseHex(s.customSidebarHex) ?? g.sidebar
            let card = AppSettings.parseHex(s.customCardHex) ?? g.card
            let text = AppSettings.parseHex(s.customTextHex) ?? g.text
            let subtext = AppSettings.parseHex(s.customSubtextHex) ?? g.subtext
            let ink = AppSettings.parseHex(s.customInkHex) ?? g.ink
            let pillBg = AppSettings.parseHex(s.customPillBgHex) ?? g.pillBg
            return SkinSpec(
                palette: Palette(bg: bg, sidebar: sidebar, card: card,
                                 border: ink.opacity(0.32),
                                 text: text, subtext: subtext),
                ink: ink, isDark: s.customSkinDark,
                fontName: s.customSkinFont.fontName,
                fontDesign: s.customSkinFont.design,
                pillFill: pillBg,
                pillBorder: ink.opacity(0.6),
                pillRadius: s.customSkinShape.radius ?? 100,
                glow: ink)
        case .ocean: return .dark(0.016, 0.075, 0.11, ink: Color(red: 0.35, green: 0.78, blue: 0.90))
        case .lava: return .dark(0.09, 0.03, 0.02, ink: Color(red: 1.0, green: 0.45, blue: 0.25))
        case .slate: return .dark(0.09, 0.10, 0.12, ink: Color(red: 0.55, green: 0.65, blue: 0.78), radius: 14)
        case .grape: return .dark(0.08, 0.04, 0.12, ink: Color(red: 0.72, green: 0.52, blue: 0.95))
        case .coffee: return .dark(0.10, 0.07, 0.05, ink: Color(red: 0.78, green: 0.62, blue: 0.46), font: "Baskerville")
        case .cherry: return .dark(0.10, 0.03, 0.05, ink: Color(red: 0.95, green: 0.35, blue: 0.45))
        case .gold: return .dark(0.08, 0.075, 0.06, ink: Color(red: 0.87, green: 0.72, blue: 0.35), font: "Didot")
        case .denim: return .dark(0.07, 0.09, 0.14, ink: Color(red: 0.52, green: 0.68, blue: 0.92), radius: 16)
        case .olive: return .dark(0.08, 0.09, 0.05, ink: Color(red: 0.70, green: 0.75, blue: 0.40))
        case .charcoal: return .dark(0.10, 0.10, 0.10, ink: Color(white: 0.75), radius: 14)
        case .cyber: return .dark(0.05, 0.05, 0.04, ink: Color(red: 0.95, green: 0.90, blue: 0.15), font: "Menlo", radius: 6)
        case .storm: return .dark(0.07, 0.08, 0.10, ink: Color(red: 0.60, green: 0.70, blue: 0.80))
        case .pumpkin: return .dark(0.07, 0.045, 0.02, ink: Color(red: 0.98, green: 0.55, blue: 0.15))
        case .ice: return .light(0.93, 0.96, 0.985, ink: Color(red: 0.30, green: 0.52, blue: 0.72))
        case .lavender: return .light(0.955, 0.94, 0.985, ink: Color(red: 0.55, green: 0.42, blue: 0.80))
        case .mint: return .light(0.93, 0.975, 0.945, ink: Color(red: 0.22, green: 0.60, blue: 0.42))
        case .sand: return .light(0.965, 0.935, 0.875, ink: Color(red: 0.62, green: 0.44, blue: 0.24), font: "Avenir Next")
        case .rose: return .light(0.985, 0.94, 0.945, ink: Color(red: 0.80, green: 0.36, blue: 0.48))
        case .linen: return .light(0.955, 0.95, 0.94, ink: Color(red: 0.45, green: 0.42, blue: 0.40), radius: 14)
        case .honey: return .light(0.99, 0.96, 0.87, ink: Color(red: 0.80, green: 0.58, blue: 0.15))
        // v2.7 darks
        case .crimson: return .dark(0.12, 0.02, 0.03, ink: Color(red: 0.98, green: 0.35, blue: 0.35))
        case .royal: return .dark(0.04, 0.06, 0.16, ink: Color(red: 0.85, green: 0.70, blue: 0.30))
        case .emerald: return .dark(0.02, 0.10, 0.07, ink: Color(red: 0.30, green: 0.90, blue: 0.60))
        case .copper: return .dark(0.10, 0.06, 0.04, ink: Color(red: 0.85, green: 0.55, blue: 0.35))
        case .steel: return .dark(0.10, 0.11, 0.13, ink: Color(red: 0.75, green: 0.80, blue: 0.88), radius: 12)
        case .plum: return .dark(0.10, 0.04, 0.09, ink: Color(red: 0.90, green: 0.50, blue: 0.80))
        case .abyss: return .dark(0.015, 0.015, 0.025, ink: Color(red: 0.50, green: 0.55, blue: 0.60))
        case .aurora: return .dark(0.03, 0.08, 0.10, ink: Color(red: 0.40, green: 0.95, blue: 0.75))
        case .indigo: return .dark(0.05, 0.04, 0.14, ink: Color(red: 0.55, green: 0.50, blue: 0.95))
        case .jade: return .dark(0.03, 0.09, 0.08, ink: Color(red: 0.35, green: 0.85, blue: 0.70))
        case .carbon: return .dark(0.07, 0.07, 0.07, ink: Color(white: 0.88), font: "Menlo", radius: 8)
        case .wine: return .dark(0.10, 0.03, 0.06, ink: Color(red: 0.90, green: 0.45, blue: 0.60))
        case .cocoa: return .dark(0.08, 0.055, 0.045, ink: Color(red: 0.80, green: 0.65, blue: 0.55))
        case .navy: return .dark(0.03, 0.05, 0.10, ink: Color(red: 0.50, green: 0.70, blue: 0.95))
        case .moss: return .dark(0.06, 0.08, 0.04, ink: Color(red: 0.65, green: 0.80, blue: 0.45))
        case .graphite: return .dark(0.08, 0.08, 0.09, ink: Color(red: 0.62, green: 0.64, blue: 0.68), radius: 14)
        case .amethyst: return .dark(0.07, 0.04, 0.11, ink: Color(red: 0.75, green: 0.60, blue: 0.98))
        case .ember: return .dark(0.09, 0.05, 0.02, ink: Color(red: 0.95, green: 0.60, blue: 0.20))
        case .teal: return .dark(0.02, 0.08, 0.09, ink: Color(red: 0.30, green: 0.85, blue: 0.85))
        case .sapphire: return .dark(0.03, 0.05, 0.12, ink: Color(red: 0.40, green: 0.60, blue: 1.0))
        case .onyx: return .dark(0.04, 0.04, 0.05, ink: Color(red: 0.80, green: 0.75, blue: 0.90))
        case .bronze: return .dark(0.09, 0.07, 0.04, ink: Color(red: 0.80, green: 0.62, blue: 0.30))
        case .cosmos: return .dark(0.05, 0.03, 0.10, ink: Color(red: 0.85, green: 0.55, blue: 0.95))
        case .shadow: return .dark(0.06, 0.06, 0.08, ink: Color(red: 0.55, green: 0.60, blue: 0.75))
        // v2.7 lights
        case .cloud: return .light(0.96, 0.97, 0.98, ink: Color(red: 0.45, green: 0.55, blue: 0.68))
        case .seafoam: return .light(0.92, 0.975, 0.96, ink: Color(red: 0.20, green: 0.60, blue: 0.55))
        case .blush: return .light(0.99, 0.95, 0.94, ink: Color(red: 0.85, green: 0.45, blue: 0.40))
        case .butter: return .light(0.995, 0.975, 0.90, ink: Color(red: 0.75, green: 0.60, blue: 0.10))
        case .lilac: return .light(0.965, 0.95, 0.99, ink: Color(red: 0.60, green: 0.45, blue: 0.85))
        case .peach: return .light(0.995, 0.955, 0.92, ink: Color(red: 0.90, green: 0.50, blue: 0.30))
        case .sage: return .light(0.945, 0.96, 0.93, ink: Color(red: 0.45, green: 0.58, blue: 0.40))
        case .sky: return .light(0.94, 0.965, 0.99, ink: Color(red: 0.35, green: 0.60, blue: 0.90))
        case .cream: return .light(0.98, 0.965, 0.94, ink: Color(red: 0.60, green: 0.50, blue: 0.35), font: "Georgia")
        case .pistachio: return .light(0.955, 0.975, 0.92, ink: Color(red: 0.50, green: 0.65, blue: 0.30))
        case .pearl: return .light(0.97, 0.965, 0.96, ink: Color(red: 0.55, green: 0.50, blue: 0.55))
        case .chambray: return .light(0.945, 0.955, 0.975, ink: Color(red: 0.40, green: 0.50, blue: 0.70))
        case .cotton: return .light(0.985, 0.975, 0.985, ink: Color(red: 0.70, green: 0.50, blue: 0.75))
        case .fog: return .light(0.955, 0.955, 0.955, ink: Color(red: 0.50, green: 0.50, blue: 0.52), radius: 14)
        case .matcha: return .light(0.94, 0.955, 0.90, ink: Color(red: 0.45, green: 0.55, blue: 0.25))
        case .orchid: return .light(0.98, 0.945, 0.975, ink: Color(red: 0.75, green: 0.40, blue: 0.70))
        // Wave 2 — darks
        case .cobalt: return .dark(0.02, 0.06, 0.14, ink: Color(red: 0.35, green: 0.55, blue: 0.98))
        case .scarlet: return .dark(0.11, 0.03, 0.02, ink: Color(red: 1.0, green: 0.40, blue: 0.25))
        case .mustard: return .dark(0.09, 0.08, 0.03, ink: Color(red: 0.90, green: 0.75, blue: 0.25))
        case .velvet: return .dark(0.08, 0.03, 0.07, ink: Color(red: 0.85, green: 0.45, blue: 0.75))
        case .arctic: return .dark(0.05, 0.07, 0.09, ink: Color(red: 0.80, green: 0.90, blue: 0.98))
        case .terracotta: return .dark(0.10, 0.055, 0.04, ink: Color(red: 0.88, green: 0.55, blue: 0.40))
        case .eggplant: return .dark(0.07, 0.04, 0.08, ink: Color(red: 0.70, green: 0.50, blue: 0.85))
        case .seaweed: return .dark(0.03, 0.07, 0.06, ink: Color(red: 0.45, green: 0.75, blue: 0.60))
        case .noir: return .dark(0.05, 0.045, 0.05, ink: Color(red: 0.85, green: 0.70, blue: 0.75), font: "Georgia")
        case .petrol: return .dark(0.02, 0.07, 0.08, ink: Color(red: 0.35, green: 0.75, blue: 0.80))
        case .sienna: return .dark(0.09, 0.05, 0.035, ink: Color(red: 0.85, green: 0.50, blue: 0.30))
        case .galaxy: return .dark(0.04, 0.03, 0.09, ink: Color(red: 0.60, green: 0.55, blue: 1.0))
        case .hunter: return .dark(0.03, 0.07, 0.04, ink: Color(red: 0.40, green: 0.80, blue: 0.50))
        case .merlot: return .dark(0.09, 0.02, 0.04, ink: Color(red: 0.95, green: 0.40, blue: 0.50))
        case .gunmetal: return .dark(0.075, 0.08, 0.085, ink: Color(red: 0.70, green: 0.75, blue: 0.80), radius: 10)
        case .blackberry: return .dark(0.06, 0.03, 0.08, ink: Color(red: 0.80, green: 0.55, blue: 0.90))
        case .tangerine: return .dark(0.10, 0.06, 0.02, ink: Color(red: 1.0, green: 0.65, blue: 0.25))
        // Wave 2 — lights
        case .vanilla: return .light(0.995, 0.985, 0.955, ink: Color(red: 0.65, green: 0.55, blue: 0.35))
        case .rosewater: return .light(0.99, 0.955, 0.96, ink: Color(red: 0.80, green: 0.50, blue: 0.55))
        case .glacier: return .light(0.94, 0.97, 0.985, ink: Color(red: 0.30, green: 0.55, blue: 0.75))
        case .meadow: return .light(0.94, 0.975, 0.925, ink: Color(red: 0.40, green: 0.65, blue: 0.35))
        case .sandstone: return .light(0.97, 0.945, 0.90, ink: Color(red: 0.65, green: 0.50, blue: 0.30))
        case .periwinkle: return .light(0.955, 0.955, 0.995, ink: Color(red: 0.50, green: 0.50, blue: 0.90))
        case .shell: return .light(0.99, 0.965, 0.95, ink: Color(red: 0.75, green: 0.55, blue: 0.45))
        case .porcelain: return .light(0.975, 0.975, 0.97, ink: Color(red: 0.50, green: 0.55, blue: 0.60))
        case .lemon: return .light(0.995, 0.99, 0.92, ink: Color(red: 0.72, green: 0.66, blue: 0.12))
        case .flamingo: return .light(0.995, 0.94, 0.95, ink: Color(red: 0.92, green: 0.42, blue: 0.55))
        case .dove: return .light(0.96, 0.96, 0.965, ink: Color(red: 0.55, green: 0.55, blue: 0.60))
        case .julep: return .light(0.945, 0.985, 0.955, ink: Color(red: 0.30, green: 0.65, blue: 0.50))
        default: return nil
        }
    }

    /// Fixed-palette skins force the window appearance so native controls
    /// (buttons, toggles, pickers) match — nil follows the system.
    var forcedAppearance: NSAppearance? {
        if let spec { return NSAppearance(named: spec.isDark ? .darkAqua : .aqua) }
        switch self {
        case .clean, .sketch: return nil
        case .retro, .paper, .candy: return NSAppearance(named: .aqua)
        default: return NSAppearance(named: .darkAqua)
        }
    }
    var label: String {
        switch self {
        case .clean: return "Clean"
        case .sketch: return "Sketch"
        case .terminal: return "Terminal"
        case .blueprint: return "Blueprint"
        case .retro: return "Retro Mac"
        case .neon: return "Neon"
        default: return rawValue.capitalized
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
        case .paper: return "book.closed"
        case .midnight: return "moon.stars"
        case .forest: return "leaf"
        case .candy: return "heart"
        case .ocean: return "water.waves"
        case .lava: return "flame"
        case .slate: return "rectangle.stack"
        case .grape: return "circle.hexagongrid"
        case .coffee: return "cup.and.saucer"
        case .cherry: return "drop"
        case .gold: return "crown"
        case .denim: return "tshirt"
        case .olive: return "laurel.leading"
        case .charcoal: return "circle.fill"
        case .cyber: return "bolt"
        case .storm: return "cloud.bolt"
        case .pumpkin: return "moon.haze"
        case .ice: return "snowflake"
        case .lavender: return "sparkle"
        case .mint: return "wind"
        case .sand: return "sun.max"
        case .rose: return "camera.macro"
        case .linen: return "newspaper"
        case .honey: return "hexagon"
        case .custom: return "paintpalette"
        default: return "circle.lefthalf.filled"
        }
    }
}

enum OutputCase: String, CaseIterable, Identifiable, Codable {
    case asSpoken, lowercase, uppercase, titleCase
    var id: String { rawValue }
    var label: String {
        switch self {
        case .asSpoken: return "As Spoken"
        case .lowercase: return "lower"
        case .uppercase: return "UPPER"
        case .titleCase: return "Title"
        }
    }
}

enum PillScreen: String, CaseIterable, Identifiable, Codable {
    case mainScreen = "main", mouse
    var id: String { rawValue }
    var label: String { self == .mainScreen ? "Active Screen" : "Mouse Screen" }
}

enum IdleDotSize: String, CaseIterable, Identifiable, Codable {
    case small, medium, large
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var diameter: CGFloat {
        switch self {
        case .small: return 6
        case .medium: return 9
        case .large: return 13
        }
    }
}

enum CensorStyle: String, CaseIterable, Identifiable, Codable {
    case asterisks, bullets, redacted
    var id: String { rawValue }
    var label: String {
        switch self {
        case .asterisks: return "d***"
        case .bullets: return "••••"
        case .redacted: return "[redacted]"
        }
    }
}

enum DateStyleChoice: String, CaseIterable, Identifiable, Codable {
    case short, medium, long, iso
    var id: String { rawValue }
    var label: String {
        switch self {
        case .short: return "7/16/26"
        case .medium: return "Jul 16, 2026"
        case .long: return "July 16, 2026"
        case .iso: return "2026-07-16"
        }
    }
    func format(_ date: Date) -> String {
        let df = DateFormatter()
        switch self {
        case .short: df.dateStyle = .short
        case .medium: df.dateStyle = .medium
        case .long: df.dateStyle = .long
        case .iso: df.dateFormat = "yyyy-MM-dd"
        }
        return df.string(from: date)
    }
}

enum PillTextColor: String, CaseIterable, Identifiable, Codable {
    case auto, white, black
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum StatusDotStyle: String, CaseIterable, Identifiable, Codable {
    case dot, mic, none
    var id: String { rawValue }
    var label: String {
        switch self {
        case .dot: return "Dot"
        case .mic: return "Mic"
        case .none: return "None"
        }
    }
}

enum TimerFormat: String, CaseIterable, Identifiable, Codable {
    case mmss, seconds
    var id: String { rawValue }
    var label: String { self == .mmss ? "0:42" : "42s" }
}

enum EntranceAnim: String, CaseIterable, Identifiable, Codable {
    case spring, fade, none
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum IdleDotColor: String, CaseIterable, Identifiable, Codable {
    case accent, gray
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum PillFontWeight: String, CaseIterable, Identifiable, Codable {
    case regular, medium, semibold
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var weight: Font.Weight {
        switch self {
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
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
    case newest, oldest, longest, shortest
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

/// Per-app override: when dictating into a matching app, use this tone/case.
struct AppRule: Codable, Identifiable, Equatable {
    var id = UUID()
    var appName: String
    var tone: PolishTone = .clean
    var ocase: OutputCase = .asSpoken
    /// nil = inherit the global AI-polish setting.
    var polish: Bool?
    /// Custom instruction for how AI polish should write in this app —
    /// its own voice per app ("casual with emojis", "formal French").
    var customPrompt: String = ""
    /// Recognition language override for this app (nil = global setting).
    var localeID: String?
    /// True = Murmur's hotkey is ignored while this app is frontmost.
    var blocked: Bool = false
    /// True = force an AI grammar/spelling fix pass in this app (even when
    /// polish is globally off), without changing wording or tone.
    var grammar: Bool?

    init(appName: String, tone: PolishTone = .clean, ocase: OutputCase = .asSpoken,
         polish: Bool? = nil, customPrompt: String = "", localeID: String? = nil,
         blocked: Bool = false, grammar: Bool? = nil) {
        self.appName = appName
        self.tone = tone
        self.ocase = ocase
        self.polish = polish
        self.customPrompt = customPrompt
        self.localeID = localeID
        self.blocked = blocked
        self.grammar = grammar
    }

    // Manual decoding so rules saved before newer fields existed still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        appName = try c.decode(String.self, forKey: .appName)
        tone = try c.decodeIfPresent(PolishTone.self, forKey: .tone) ?? .clean
        ocase = try c.decodeIfPresent(OutputCase.self, forKey: .ocase) ?? .asSpoken
        polish = try c.decodeIfPresent(Bool.self, forKey: .polish)
        customPrompt = try c.decodeIfPresent(String.self, forKey: .customPrompt) ?? ""
        localeID = try c.decodeIfPresent(String.self, forKey: .localeID)
        blocked = try c.decodeIfPresent(Bool.self, forKey: .blocked) ?? false
        grammar = try c.decodeIfPresent(Bool.self, forKey: .grammar)
    }
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
    /// AI Command Mode — hold this key, speak an instruction, and Murmur
    /// rewrites the current selection (or generates text at the cursor).
    @Published var commandHotkey: HotkeyKey {
        didSet { d.set((try? JSONEncoder().encode(commandHotkey)) ?? Data(), forKey: "cmdHotkeyV2") }
    }
    @Published var commandModeEnabled: Bool { didSet { d.set(commandModeEnabled, forKey: "cmdModeOn") } }
    @Published var autoLearnVocab: Bool { didSet { d.set(autoLearnVocab, forKey: "autoLearnVocab") } }
    @Published var accentHue: Double { didSet { d.set(accentHue, forKey: "accentHue") } }
    @Published var accentSat: Double { didSet { d.set(accentSat, forKey: "accentSat") } }
    var accentColor: Color {
        useSystemAccent ? Color(nsColor: .controlAccentColor)
                        : Color(hue: accentHue, saturation: accentSat, brightness: 1.0)
    }
    /// Legible text color on top of the accent — dark ink on light accents,
    /// white on dark ones.
    var accentContrastColor: Color {
        let base = useSystemAccent
            ? (NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? .controlAccentColor)
            : NSColor(hue: accentHue, saturation: accentSat, brightness: 1.0, alpha: 1)
        let luminance = 0.299 * base.redComponent + 0.587 * base.greenComponent + 0.114 * base.blueComponent
        return luminance > 0.66 ? Color(white: 0.12) : .white
    }

    /// Secondary accent (for gradient waveforms / accent bars).
    var accentColor2: Color {
        accentGradient ? Color(hue: accentHue2, saturation: accentSat, brightness: 1.0)
                       : accentColor
    }

    /// Custom pill background color parsed from pillBgHex ("" = default look).
    var pillBgColor: Color? { Self.parseHex(pillBgHex) }

    static func parseHex(_ s: String) -> Color? {
        var hex = s.trimmingCharacters(in: .whitespaces)
        guard !hex.isEmpty else { return nil }
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let v = UInt32(hex, radix: 16) else { return nil }
        return Color(red: Double((v >> 16) & 0xFF) / 255,
                     green: Double((v >> 8) & 0xFF) / 255,
                     blue: Double(v & 0xFF) / 255)
    }

    static func hexString(_ color: Color) -> String {
        let n = NSColor(color).usingColorSpace(.sRGB) ?? .black
        return String(format: "#%02X%02X%02X",
                      Int(round(n.redComponent * 255)),
                      Int(round(n.greenComponent * 255)),
                      Int(round(n.blueComponent * 255)))
    }

    /// A coherent 7-color skin generated from one theme color — the Skin
    /// Studio's starting point, which the per-color editors then override.
    static func generatedCustomColors(hue: Double, sat: Double, dark: Bool)
        -> (bg: Color, sidebar: Color, card: Color, text: Color, subtext: Color,
            ink: Color, pillBg: Color) {
        if dark {
            let bg = Color(hue: hue, saturation: sat * 0.55, brightness: 0.085)
            return (bg: bg,
                    sidebar: Color(hue: hue, saturation: sat * 0.52, brightness: 0.11),
                    card: Color(hue: hue, saturation: sat * 0.45, brightness: 0.145),
                    text: Color(white: 0.97),
                    subtext: Color(white: 0.74),
                    ink: Color(hue: hue, saturation: min(1, sat + 0.15), brightness: 0.85),
                    pillBg: Color(hue: hue, saturation: sat * 0.5, brightness: 0.12))
        } else {
            return (bg: Color(hue: hue, saturation: sat * 0.16, brightness: 0.975),
                    sidebar: Color(hue: hue, saturation: sat * 0.20, brightness: 0.94),
                    card: Color(white: 0.995),
                    text: Color(white: 0.13),
                    subtext: Color(hue: hue, saturation: sat * 0.25, brightness: 0.42),
                    ink: Color(hue: hue, saturation: min(1, sat + 0.15), brightness: 0.58),
                    pillBg: Color(white: 0.995))
        }
    }

    /// Regenerates all Skin Studio colors from the theme wheel + base.
    func generateCustomSkin() {
        let g = Self.generatedCustomColors(hue: customSkinHue, sat: customSkinSat,
                                           dark: customSkinDark)
        customBgHex = Self.hexString(g.bg)
        customSidebarHex = Self.hexString(g.sidebar)
        customCardHex = Self.hexString(g.card)
        customTextHex = Self.hexString(g.text)
        customSubtextHex = Self.hexString(g.subtext)
        customInkHex = Self.hexString(g.ink)
        customPillBgHex = Self.hexString(g.pillBg)
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
    @Published var autoCapSentences: Bool { didSet { d.set(autoCapSentences, forKey: "autoCapSent") } }
    @Published var trailingNewline: Bool { didSet { d.set(trailingNewline, forKey: "trailNewline") } }
    @Published var showPillTimer: Bool { didSet { d.set(showPillTimer, forKey: "showPillTimer") } }
    @Published var waveMonochrome: Bool { didSet { d.set(waveMonochrome, forKey: "waveMono") } }
    @Published var idleDotSize: IdleDotSize { didSet { d.set(idleDotSize.rawValue, forKey: "idleDotSize") } }
    @Published var idleDotOpacity: Double { didSet { d.set(idleDotOpacity, forKey: "idleDotOpacity") } }
    @Published var spokenPunctuation: Bool { didSet { d.set(spokenPunctuation, forKey: "spokenPunct") } }
    @Published var censorWords: [String] { didSet { d.set(censorWords, forKey: "censorWords") } }
    @Published var replacementsEnabled: Bool { didSet { d.set(replacementsEnabled, forKey: "replOn") } }
    @Published var pillClickToFinish: Bool { didSet { d.set(pillClickToFinish, forKey: "pillTap") } }
    @Published var showPillWhileRecording: Bool { didSet { d.set(showPillWhileRecording, forKey: "showPill") } }
    @Published var pillScreen: PillScreen { didSet { d.set(pillScreen.rawValue, forKey: "pillScreen") } }
    @Published var autoBackupWeekly: Bool { didSet { d.set(autoBackupWeekly, forKey: "autoBackup") } }
    @Published var pillTextSize: Double { didSet { d.set(pillTextSize, forKey: "pillTextSize") } }
    @Published var transcriptWidth: Double { didSet { d.set(transcriptWidth, forKey: "transcriptWidth") } }
    @Published var showTargetIcon: Bool { didSet { d.set(showTargetIcon, forKey: "showTargetIcon") } }

    // General v2.5
    @Published var numbersToDigits: Bool { didSet { d.set(numbersToDigits, forKey: "numToDigits") } }
    @Published var removeDoubledWords: Bool { didSet { d.set(removeDoubledWords, forKey: "deDouble") } }
    @Published var ensureEndPunctuation: Bool { didSet { d.set(ensureEndPunctuation, forKey: "endPunct") } }
    @Published var stripStarterWords: Bool { didSet { d.set(stripStarterWords, forKey: "stripStarters") } }
    @Published var holdOnlyMode: Bool { didSet { d.set(holdOnlyMode, forKey: "holdOnly") } }
    @Published var hapticsEnabled: Bool { didSet { d.set(hapticsEnabled, forKey: "haptics") } }
    @Published var menuClickToTalk: Bool { didSet { d.set(menuClickToTalk, forKey: "menuClickTalk") } }
    @Published var insertDelay: Double { didSet { d.set(insertDelay, forKey: "insertDelay") } }
    @Published var restoreDelay: Double { didSet { d.set(restoreDelay, forKey: "restoreDelay") } }
    @Published var unlockSoundEnabled: Bool { didSet { d.set(unlockSoundEnabled, forKey: "unlockSound") } }
    @Published var goalCelebration: Bool { didSet { d.set(goalCelebration, forKey: "goalCeleb") } }
    @Published var updateCheckWeekly: Bool { didSet { d.set(updateCheckWeekly, forKey: "updateCheck") } }
    @Published var quietHours: Bool { didSet { d.set(quietHours, forKey: "quietHours") } }
    @Published var showMenuTimer: Bool { didSet { d.set(showMenuTimer, forKey: "menuTimer") } }
    @Published var chainMode: Bool { didSet { d.set(chainMode, forKey: "chainMode") } }
    @Published var cancelOnScreenLock: Bool { didSet { d.set(cancelOnScreenLock, forKey: "lockCancel") } }
    @Published var pasteMatchStyle: Bool { didSet { d.set(pasteMatchStyle, forKey: "pasteMatch") } }
    /// Set when a newer release tag was found on GitHub (not persisted).
    @Published var availableUpdate: String?

    // Dictionary v2.5
    @Published var preserveCaseReplacements: Bool { didSet { d.set(preserveCaseReplacements, forKey: "preserveCase") } }
    @Published var matchInsideWords: Bool { didSet { d.set(matchInsideWords, forKey: "matchInside") } }
    @Published var importReplaces: Bool { didSet { d.set(importReplaces, forKey: "importReplaces") } }
    @Published var autoSortReplacements: Bool { didSet { d.set(autoSortReplacements, forKey: "autoSortRepl") } }
    @Published var emojiCommands: Bool { didSet { d.set(emojiCommands, forKey: "emojiCmds") } }
    @Published var censorStyle: CensorStyle { didSet { d.set(censorStyle.rawValue, forKey: "censorStyle") } }
    @Published var dateStyleChoice: DateStyleChoice { didSet { d.set(dateStyleChoice.rawValue, forKey: "dateStyle") } }
    @Published var vocabWords: [String] { didSet { d.set(vocabWords, forKey: "vocabWords") } }

    // Appearance v2.5
    @Published var barWidth: Double { didSet { d.set(barWidth, forKey: "barWidth") } }
    @Published var barSpacing: Double { didSet { d.set(barSpacing, forKey: "barSpacing") } }
    @Published var squareBars: Bool { didSet { d.set(squareBars, forKey: "squareBars") } }
    @Published var shadowStrength: Double { didSet { d.set(shadowStrength, forKey: "shadowStrength") } }
    @Published var pillNudge: Double { didSet { d.set(pillNudge, forKey: "pillNudge") } }
    @Published var pillBgHex: String { didSet { d.set(pillBgHex, forKey: "pillBgHex") } }
    @Published var pillTextColor: PillTextColor { didSet { d.set(pillTextColor.rawValue, forKey: "pillTextColor") } }
    @Published var statusDotStyle: StatusDotStyle { didSet { d.set(statusDotStyle.rawValue, forKey: "statusDotStyle") } }
    @Published var timerFormat: TimerFormat { didSet { d.set(timerFormat.rawValue, forKey: "timerFormat") } }
    @Published var entranceAnim: EntranceAnim { didSet { d.set(entranceAnim.rawValue, forKey: "entranceAnim") } }
    @Published var doneLinger: Double { didSet { d.set(doneLinger, forKey: "doneLinger") } }
    @Published var idleDotColor: IdleDotColor { didSet { d.set(idleDotColor.rawValue, forKey: "idleDotColor") } }
    @Published var idleDotAlignment: PillAlignment { didSet { d.set(idleDotAlignment.rawValue, forKey: "idleDotAlign") } }
    @Published var menuSymbolName: String { didSet { d.set(menuSymbolName, forKey: "menuSymbol") } }
    @Published var useSystemAccent: Bool { didSet { d.set(useSystemAccent, forKey: "sysAccent") } }
    @Published var pillFontWeight: PillFontWeight { didSet { d.set(pillFontWeight.rawValue, forKey: "pillWeight") } }
    @Published var uppercasePill: Bool { didSet { d.set(uppercasePill, forKey: "upperPill") } }
    @Published var sidebarFilledIcons: Bool { didSet { d.set(sidebarFilledIcons, forKey: "sidebarFill") } }
    @Published var showLivePreviewBar: Bool { didSet { d.set(showLivePreviewBar, forKey: "livePreview") } }
    @Published var previewSampleText: String { didSet { d.set(previewSampleText, forKey: "previewText") } }

    // Stats v2.5 (data counters + options)
    @Published var totalChars: Int { didSet { d.set(totalChars, forKey: "totalChars") } }
    @Published var maxSessionWords: Int { didSet { d.set(maxSessionWords, forKey: "maxSessWords") } }
    @Published var commandsUsed: Int { didSet { d.set(commandsUsed, forKey: "commandsUsed") } }
    @Published var polishedCount: Int { didSet { d.set(polishedCount, forKey: "polishedCount") } }
    @Published var hourCounts: [String: Int] { didSet { d.set(hourCounts, forKey: "hourCounts") } }
    @Published var appWords: [String: Int] { didSet { d.set(appWords, forKey: "appWords") } }
    @Published var dailySessions: [String: Int] { didSet { d.set(dailySessions, forKey: "dailySessions") } }
    @Published var weeklyGoal: Int { didSet { d.set(weeklyGoal, forKey: "weeklyGoal") } }

    // Skin Studio (Custom skin)
    @Published var customSkinDark: Bool { didSet { d.set(customSkinDark, forKey: "customSkinDark") } }
    @Published var customSkinHue: Double { didSet { d.set(customSkinHue, forKey: "customSkinHue") } }
    @Published var customSkinSat: Double { didSet { d.set(customSkinSat, forKey: "customSkinSat") } }
    @Published var customSkinFont: CustomSkinFont { didSet { d.set(customSkinFont.rawValue, forKey: "customSkinFont") } }
    @Published var customSkinShape: PillCorner { didSet { d.set(customSkinShape.rawValue, forKey: "customSkinShape") } }
    // Per-color overrides ("" = generated from the theme wheel).
    @Published var customBgHex: String { didSet { d.set(customBgHex, forKey: "customBgHex") } }
    @Published var customSidebarHex: String { didSet { d.set(customSidebarHex, forKey: "customSidebarHex") } }
    @Published var customCardHex: String { didSet { d.set(customCardHex, forKey: "customCardHex") } }
    @Published var customTextHex: String { didSet { d.set(customTextHex, forKey: "customTextHex") } }
    @Published var customSubtextHex: String { didSet { d.set(customSubtextHex, forKey: "customSubtextHex") } }
    @Published var customInkHex: String { didSet { d.set(customInkHex, forKey: "customInkHex") } }
    @Published var customPillBgHex: String { didSet { d.set(customPillBgHex, forKey: "customPillBgHex") } }

    // History v2.5
    @Published var pinnedFirst: Bool { didSet { d.set(pinnedFirst, forKey: "pinnedFirst") } }
    @Published var historyPaused: Bool { didSet { d.set(historyPaused, forKey: "histPaused") } }
    @Published var excludeClipboardOnly: Bool { didSet { d.set(excludeClipboardOnly, forKey: "histNoClip") } }
    /// Items removed by the last "Clear History", for Undo (not persisted).
    @Published var lastCleared: [HistoryItem] = []

    // v2.6 — General
    @Published var polishTimeout: Int { didSet { d.set(polishTimeout, forKey: "polishTimeout") } }
    @Published var apiModel: String { didSet { d.set(apiModel, forKey: "apiModel") } }
    @Published var polishMinWords: Int { didSet { d.set(polishMinWords, forKey: "polishMinWords") } }
    @Published var leadingSpace: Bool { didSet { d.set(leadingSpace, forKey: "leadSpace") } }
    @Published var openSettingsAtLaunch: Bool { didSet { d.set(openSettingsAtLaunch, forKey: "openSettings") } }
    @Published var discardShortSeconds: Double { didSet { d.set(discardShortSeconds, forKey: "discardShortSecs") } }
    @Published var recordingReminder: Bool { didSet { d.set(recordingReminder, forKey: "recReminder") } }
    @Published var countdownTimer: Bool { didSet { d.set(countdownTimer, forKey: "countdown") } }
    @Published var typeChunkDelay: Double { didSet { d.set(typeChunkDelay, forKey: "typeDelay") } }
    @Published var alwaysCopy: Bool { didSet { d.set(alwaysCopy, forKey: "alwaysCopy") } }
    @Published var preventSleep: Bool { didSet { d.set(preventSleep, forKey: "noSleep") } }
    @Published var escCancels: Bool { didSet { d.set(escCancels, forKey: "escCancels") } }
    @Published var excludedApps: [String] { didSet { d.set(excludedApps, forKey: "excludedApps") } }
    @Published var confirmQuitWhileRecording: Bool { didSet { d.set(confirmQuitWhileRecording, forKey: "quitConfirm") } }
    // v2.6 — Dictionary
    @Published var regexReplacements: Bool { didSet { d.set(regexReplacements, forKey: "regexRepl") } }
    @Published var censorInsideWords: Bool { didSet { d.set(censorInsideWords, forKey: "censorInside") } }
    @Published var starterWords: [String] { didSet { d.set(starterWords, forKey: "starterWords") } }
    @Published var doubledWhitelist: [String] { didSet { d.set(doubledWhitelist, forKey: "doubledWhitelist") } }
    // v2.6 — Appearance
    @Published var waveHeight: Double { didSet { d.set(waveHeight, forKey: "waveHeight") } }
    @Published var statusSymbolName: String { didSet { d.set(statusSymbolName, forKey: "statusSymbol") } }
    @Published var pillPadding: Double { didSet { d.set(pillPadding, forKey: "pillPadding") } }
    @Published var glowColorHex: String { didSet { d.set(glowColorHex, forKey: "glowColorHex") } }
    @Published var borderGradient: Bool { didSet { d.set(borderGradient, forKey: "borderGrad") } }
    @Published var doneAccent: Bool { didSet { d.set(doneAccent, forKey: "doneAccent") } }
    @Published var pillItalic: Bool { didSet { d.set(pillItalic, forKey: "pillItalic") } }
    @Published var transcriptCentered: Bool { didSet { d.set(transcriptCentered, forKey: "transcriptCenter") } }
    @Published var idleDotPulse: Bool { didSet { d.set(idleDotPulse, forKey: "idlePulse") } }
    @Published var sidebarCompact: Bool { didSet { d.set(sidebarCompact, forKey: "sidebarCompact") } }
    @Published var settingsAlwaysOnTop: Bool { didSet { d.set(settingsAlwaysOnTop, forKey: "alwaysOnTop") } }
    @Published var hideSidebarStats: Bool { didSet { d.set(hideSidebarStats, forKey: "hideSideStats") } }
    @Published var previewUsesHistory: Bool { didSet { d.set(previewUsesHistory, forKey: "previewHistory") } }
    @Published var showWaveform: Bool { didSet { d.set(showWaveform, forKey: "showWave") } }
    @Published var pillCursor: Bool { didSet { d.set(pillCursor, forKey: "pillCursor") } }
    @Published var accentTintControls: Bool { didSet { d.set(accentTintControls, forKey: "accentTint") } }
    // v2.6 — Stats
    @Published var customMilestone: Int { didSet { d.set(customMilestone, forKey: "customMilestone") } }
    @Published var earnedFirst: Bool { didSet { d.set(earnedFirst, forKey: "earnedFirst") } }
    // v2.6 — History
    @Published var autoPinWords: Int { didSet { d.set(autoPinWords, forKey: "autoPinWords") } }
    @Published var historyRedactNumbers: Bool { didSet { d.set(historyRedactNumbers, forKey: "histRedact") } }
    @Published var skipDuplicateHistory: Bool { didSet { d.set(skipDuplicateHistory, forKey: "histSkipDupes") } }
    @Published var historyCompactRows: Bool { didSet { d.set(historyCompactRows, forKey: "histCompact") } }
    @Published var historyDefaultFilter: Int { didSet { d.set(historyDefaultFilter, forKey: "histDefaultFilter") } }
    @Published var exportMetadata: Bool { didSet { d.set(exportMetadata, forKey: "exportMeta") } }

    // v2.7 — General
    @Published var signatureEnabled: Bool { didSet { d.set(signatureEnabled, forKey: "sigOn") } }
    @Published var signatureText: String { didSet { d.set(signatureText, forKey: "sigText") } }
    @Published var prefixEnabled: Bool { didSet { d.set(prefixEnabled, forKey: "prefixOn") } }
    @Published var prefixText: String { didSet { d.set(prefixText, forKey: "prefixText") } }
    @Published var stripMarkdownOutput: Bool { didSet { d.set(stripMarkdownOutput, forKey: "stripMd") } }
    @Published var collapseBlankLines: Bool { didSet { d.set(collapseBlankLines, forKey: "collapseBlank") } }
    @Published var properNouns: [String] { didSet { d.set(properNouns, forKey: "properNouns") } }
    @Published var doubleTapHandsFree: Bool { didSet { d.set(doubleTapHandsFree, forKey: "dblTap") } }
    @Published var polishRetry: Bool { didSet { d.set(polishRetry, forKey: "polishRetry") } }
    @Published var errorSound: Bool { didSet { d.set(errorSound, forKey: "errSound") } }
    @Published var autoLowercaseFirst: Bool { didSet { d.set(autoLowercaseFirst, forKey: "lcFirst") } }
    @Published var maxWordsPerInsert: Int { didSet { d.set(maxWordsPerInsert, forKey: "maxWords") } }
    @Published var maxRecordWords: Int { didSet { d.set(maxRecordWords, forKey: "maxRecWords") } }
    @Published var showMenuBarChars: Bool { didSet { d.set(showMenuBarChars, forKey: "menuChars") } }
    @Published var ensureSentenceSpacing: Bool { didSet { d.set(ensureSentenceSpacing, forKey: "sentSpace") } }
    @Published var undoDepth: Int { didSet { d.set(undoDepth, forKey: "undoDepth") } }
    @Published var timestampPrefix: Bool { didSet { d.set(timestampPrefix, forKey: "tsPrefix") } }
    @Published var capitalizeAfterColon: Bool { didSet { d.set(capitalizeAfterColon, forKey: "capColon") } }
    @Published var trimSurroundingQuotes: Bool { didSet { d.set(trimSurroundingQuotes, forKey: "trimQuotes") } }
    @Published var greetingStyle: Int { didSet { d.set(greetingStyle, forKey: "greetStyle") } }
    // v2.7 — Dictionary
    @Published var replacementUsage: [String: Int] { didSet { d.set(replacementUsage, forKey: "replUsage") } }
    @Published var trackReplacementUsage: Bool { didSet { d.set(trackReplacementUsage, forKey: "trackRepl") } }
    @Published var showSnippetIndex: Bool { didSet { d.set(showSnippetIndex, forKey: "snipIndex") } }
    @Published var commandWord: String { didSet { d.set(commandWord, forKey: "cmdWord") } }
    // v2.7 — Appearance
    @Published var pillMinWidth: Double { didSet { d.set(pillMinWidth, forKey: "pillMinW") } }
    @Published var pillOffsetY: Double { didSet { d.set(pillOffsetY, forKey: "pillOffY") } }
    @Published var waveMirror: Bool { didSet { d.set(waveMirror, forKey: "waveMirror") } }
    @Published var pillAppearScale: Double { didSet { d.set(pillAppearScale, forKey: "appearScale") } }
    @Published var dimWhenIdle: Bool { didSet { d.set(dimWhenIdle, forKey: "dimIdle") } }
    @Published var accentGradient: Bool { didSet { d.set(accentGradient, forKey: "accentGrad") } }
    @Published var accentHue2: Double { didSet { d.set(accentHue2, forKey: "accentHue2") } }
    @Published var pillBlur: Bool { didSet { d.set(pillBlur, forKey: "pillBlur") } }
    @Published var processingLabel: String { didSet { d.set(processingLabel, forKey: "procLabel") } }
    @Published var doneLabel: String { didSet { d.set(doneLabel, forKey: "doneLabel") } }
    @Published var listeningLabel: String { didSet { d.set(listeningLabel, forKey: "listenLabel") } }
    @Published var wordCountBadge: Bool { didSet { d.set(wordCountBadge, forKey: "wcBadge") } }
    @Published var monospaceTranscript: Bool { didSet { d.set(monospaceTranscript, forKey: "monoTranscript") } }
    @Published var sidebarAccentBar: Bool { didSet { d.set(sidebarAccentBar, forKey: "sideAccentBar") } }
    @Published var animatedGradientBg: Bool { didSet { d.set(animatedGradientBg, forKey: "animBg") } }
    @Published var skinAutoRotate: Bool { didSet { d.set(skinAutoRotate, forKey: "skinRotate") } }
    // v2.7 — Stats
    @Published var statsGoalRing: Bool { didSet { d.set(statsGoalRing, forKey: "goalRing") } }
    @Published var statsWeekStart: Int { didSet { d.set(statsWeekStart, forKey: "weekStart") } }
    @Published var lifetimeSince: Double { didSet { d.set(lifetimeSince, forKey: "lifeSince") } }
    @Published var wpmGoal: Int { didSet { d.set(wpmGoal, forKey: "wpmGoal") } }
    // v2.7 — History
    @Published var historyFontSize: Double { didSet { d.set(historyFontSize, forKey: "histFont") } }
    @Published var historyShowSeconds: Bool { didSet { d.set(historyShowSeconds, forKey: "histSecs") } }
    @Published var historyMarkFavorites: [String] { didSet { d.set(historyMarkFavorites, forKey: "histFavs") } }
    @Published var autoExportDaily: Bool { didSet { d.set(autoExportDaily, forKey: "autoExport") } }
    @Published var historyGroupByApp: Bool { didSet { d.set(historyGroupByApp, forKey: "histGroupApp") } }

    var minutesSaved: Double { Double(totalWords) * (1.0 / 40.0 - 1.0 / 150.0) }

    /// Records a delivered dictation and returns any newly unlocked achievements.
    @discardableResult
    func record(_ text: String, usedPolish: Bool = false, usedCommands: Bool = false,
                app: String? = nil, seconds: Double? = nil,
                saveToHistory: Bool = true) -> [Achievement] {
        let duplicate = skipDuplicateHistory && history.first { !$0.pinned }?.text == text
        if saveToHistory, !historyPaused, !duplicate {
            var stored = text
            if historyRedactNumbers {
                stored = stored.replacingOccurrences(of: "[0-9]", with: "#",
                                                     options: .regularExpression)
            }
            let words = text.split(whereSeparator: \.isWhitespace).count
            let pin = autoPinWords > 0 && words >= autoPinWords
            // Pinned items always survive trimming.
            let pinnedItems = history.filter(\.pinned)
            let newItem = HistoryItem(text: stored, date: Date(), pinned: pin,
                                      app: app, seconds: seconds)
            if pin {
                history = [newItem] + history
            } else {
                let unpinned = [newItem] + history.filter { !$0.pinned }
                history = pinnedItems + Array(unpinned.prefix(max(10, historyLimit - pinnedItems.count)))
            }
        }
        let words = text.split(whereSeparator: \.isWhitespace).count
        totalWords += words
        totalSessions += 1
        totalChars += text.count
        maxSessionWords = max(maxSessionWords, words)
        if usedCommands { commandsUsed += 1 }
        if usedPolish { polishedCount += 1 }
        hourCounts["\(Calendar.current.component(.hour, from: Date()))", default: 0] += 1
        if let app, !app.isEmpty { appWords[app, default: 0] += words }
        dailySessions[Self.dayKey(Date()), default: 0] += 1
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
        /// Everything added after the original backup format. Optional so
        /// backups written by older versions still import (missing → keep
        /// current value); every field inside is optional for the same reason.
        var extra: Extra?

        struct Extra: Codable {
            var polishBackend, pillTheme, pillCorner, pillFont: String?
            var pillMatchesSkin, capitalizeI, smartPunctuation, trailingSpace,
                noTrailingPeriod, keepTranscriptOnClipboard, showMenuBarStreak,
                caseSensitiveReplacements, recordTintAccent, idleIndicator, reduceMotion,
                autoCapSentences, trailingNewline, showPillTimer, waveMonochrome,
                spokenPunctuation, replacementsEnabled, pillClickToFinish,
                showPillWhileRecording, autoBackupWeekly, showTargetIcon: Bool?
            var idleDotSize, pillScreen: String?
            var idleDotOpacity, pillTextSize, transcriptWidth: Double?
            var censorWords: [String]?
            var soundVolume, pillBorderWidth, glowIntensity, waveGain,
                pillEdgeOffset, totalSpeakSeconds: Double?
            var historyLimit, discardShortWords, maxRecordSeconds,
                longToClipboardWords, waveBarCount, historyMaxAgeDays: Int?
            var fillerWords: [String]?
            var appRules: [AppRule]?
        }

        /// v2.5 additions — same optional/back-compat pattern as Extra.
        var extra2: Extra2?

        struct Extra2: Codable {
            var numbersToDigits, removeDoubledWords, ensureEndPunctuation, stripStarterWords,
                holdOnlyMode, hapticsEnabled, menuClickToTalk, unlockSoundEnabled,
                goalCelebration, updateCheckWeekly, quietHours, showMenuTimer, chainMode,
                cancelOnScreenLock, pasteMatchStyle, preserveCaseReplacements, matchInsideWords,
                importReplaces, autoSortReplacements, emojiCommands, squareBars, useSystemAccent,
                uppercasePill, sidebarFilledIcons, showLivePreviewBar, pinnedFirst,
                historyPaused, excludeClipboardOnly: Bool?
            var insertDelay, restoreDelay, barWidth, barSpacing, shadowStrength, pillNudge,
                doneLinger: Double?
            var censorStyle, dateStyleChoice, pillBgHex, pillTextColor, statusDotStyle,
                timerFormat, entranceAnim, idleDotColor, idleDotAlignment, menuSymbolName,
                pillFontWeight, previewSampleText: String?
            var totalChars, maxSessionWords, commandsUsed, polishedCount, weeklyGoal: Int?
            var vocabWords: [String]?
            var hourCounts, appWords, dailySessions: [String: Int]?
            var customSkinDark: Bool?
            var customSkinHue, customSkinSat: Double?
            var customSkinFont, customSkinShape: String?
            var customBgHex, customSidebarHex, customCardHex, customTextHex,
                customSubtextHex, customInkHex, customPillBgHex: String?
        }

        /// v2.6 additions — same optional/back-compat pattern.
        var extra3: Extra3?

        struct Extra3: Codable {
            var leadingSpace, openSettingsAtLaunch, recordingReminder, countdownTimer,
                alwaysCopy, preventSleep, escCancels, confirmQuitWhileRecording,
                regexReplacements, censorInsideWords, borderGradient, doneAccent,
                pillItalic, transcriptCentered, idleDotPulse, sidebarCompact,
                settingsAlwaysOnTop, hideSidebarStats, previewUsesHistory, showWaveform,
                pillCursor, accentTintControls, earnedFirst, historyRedactNumbers,
                skipDuplicateHistory, historyCompactRows, exportMetadata: Bool?
            var discardShortSeconds, typeChunkDelay, waveHeight, pillPadding: Double?
            var polishTimeout, polishMinWords, customMilestone, autoPinWords,
                historyDefaultFilter: Int?
            var apiModel, statusSymbolName, glowColorHex: String?
            var excludedApps, starterWords, doubledWhitelist: [String]?
        }

        /// v2.7 additions.
        var extra4: Extra4?

        struct Extra4: Codable {
            var signatureEnabled, prefixEnabled, stripMarkdownOutput, collapseBlankLines,
                doubleTapHandsFree, polishRetry, errorSound, autoLowercaseFirst,
                showMenuBarChars, ensureSentenceSpacing, timestampPrefix, capitalizeAfterColon,
                trimSurroundingQuotes, trackReplacementUsage, showSnippetIndex, waveMirror,
                dimWhenIdle, accentGradient, pillBlur, wordCountBadge, monospaceTranscript,
                sidebarAccentBar, animatedGradientBg, skinAutoRotate, statsGoalRing,
                historyShowSeconds, autoExportDaily, historyGroupByApp: Bool?
            var pillMinWidth, pillOffsetY, pillAppearScale, accentHue2, lifetimeSince,
                historyFontSize: Double?
            var maxWordsPerInsert, maxRecordWords, undoDepth, greetingStyle, statsWeekStart,
                wpmGoal: Int?
            var signatureText, prefixText, commandWord, processingLabel, doneLabel,
                listeningLabel: String?
            var properNouns, historyMarkFavorites: [String]?
            var commandModeEnabled, autoLearnVocab: Bool?
            var commandHotkey: HotkeyKey?
        }
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
            dailyWords: dailyWords, earned: earned,
            extra: Backup.Extra(
                polishBackend: polishBackend.rawValue, pillTheme: pillTheme.rawValue,
                pillCorner: pillCorner.rawValue, pillFont: pillFont.rawValue,
                pillMatchesSkin: pillMatchesSkin, capitalizeI: capitalizeI,
                smartPunctuation: smartPunctuation, trailingSpace: trailingSpace,
                noTrailingPeriod: noTrailingPeriod,
                keepTranscriptOnClipboard: keepTranscriptOnClipboard,
                showMenuBarStreak: showMenuBarStreak,
                caseSensitiveReplacements: caseSensitiveReplacements,
                recordTintAccent: recordTintAccent, idleIndicator: idleIndicator,
                reduceMotion: reduceMotion, autoCapSentences: autoCapSentences,
                trailingNewline: trailingNewline, showPillTimer: showPillTimer,
                waveMonochrome: waveMonochrome, spokenPunctuation: spokenPunctuation,
                replacementsEnabled: replacementsEnabled, pillClickToFinish: pillClickToFinish,
                showPillWhileRecording: showPillWhileRecording, autoBackupWeekly: autoBackupWeekly,
                showTargetIcon: showTargetIcon,
                idleDotSize: idleDotSize.rawValue, pillScreen: pillScreen.rawValue,
                idleDotOpacity: idleDotOpacity, pillTextSize: pillTextSize,
                transcriptWidth: transcriptWidth, censorWords: censorWords,
                soundVolume: soundVolume,
                pillBorderWidth: pillBorderWidth, glowIntensity: glowIntensity,
                waveGain: waveGain, pillEdgeOffset: pillEdgeOffset,
                totalSpeakSeconds: totalSpeakSeconds, historyLimit: historyLimit,
                discardShortWords: discardShortWords, maxRecordSeconds: maxRecordSeconds,
                longToClipboardWords: longToClipboardWords, waveBarCount: waveBarCount,
                historyMaxAgeDays: historyMaxAgeDays, fillerWords: fillerWords,
                appRules: appRules),
            extra2: Backup.Extra2(
                numbersToDigits: numbersToDigits, removeDoubledWords: removeDoubledWords,
                ensureEndPunctuation: ensureEndPunctuation, stripStarterWords: stripStarterWords,
                holdOnlyMode: holdOnlyMode, hapticsEnabled: hapticsEnabled,
                menuClickToTalk: menuClickToTalk, unlockSoundEnabled: unlockSoundEnabled,
                goalCelebration: goalCelebration, updateCheckWeekly: updateCheckWeekly,
                quietHours: quietHours, showMenuTimer: showMenuTimer, chainMode: chainMode,
                cancelOnScreenLock: cancelOnScreenLock, pasteMatchStyle: pasteMatchStyle,
                preserveCaseReplacements: preserveCaseReplacements,
                matchInsideWords: matchInsideWords, importReplaces: importReplaces,
                autoSortReplacements: autoSortReplacements, emojiCommands: emojiCommands,
                squareBars: squareBars, useSystemAccent: useSystemAccent,
                uppercasePill: uppercasePill, sidebarFilledIcons: sidebarFilledIcons,
                showLivePreviewBar: showLivePreviewBar, pinnedFirst: pinnedFirst,
                historyPaused: historyPaused, excludeClipboardOnly: excludeClipboardOnly,
                insertDelay: insertDelay, restoreDelay: restoreDelay,
                barWidth: barWidth, barSpacing: barSpacing, shadowStrength: shadowStrength,
                pillNudge: pillNudge, doneLinger: doneLinger,
                censorStyle: censorStyle.rawValue, dateStyleChoice: dateStyleChoice.rawValue,
                pillBgHex: pillBgHex, pillTextColor: pillTextColor.rawValue,
                statusDotStyle: statusDotStyle.rawValue, timerFormat: timerFormat.rawValue,
                entranceAnim: entranceAnim.rawValue, idleDotColor: idleDotColor.rawValue,
                idleDotAlignment: idleDotAlignment.rawValue, menuSymbolName: menuSymbolName,
                pillFontWeight: pillFontWeight.rawValue, previewSampleText: previewSampleText,
                totalChars: totalChars, maxSessionWords: maxSessionWords,
                commandsUsed: commandsUsed, polishedCount: polishedCount,
                weeklyGoal: weeklyGoal, vocabWords: vocabWords,
                hourCounts: hourCounts, appWords: appWords, dailySessions: dailySessions,
                customSkinDark: customSkinDark, customSkinHue: customSkinHue,
                customSkinSat: customSkinSat, customSkinFont: customSkinFont.rawValue,
                customSkinShape: customSkinShape.rawValue,
                customBgHex: customBgHex, customSidebarHex: customSidebarHex,
                customCardHex: customCardHex, customTextHex: customTextHex,
                customSubtextHex: customSubtextHex, customInkHex: customInkHex,
                customPillBgHex: customPillBgHex),
            extra3: Backup.Extra3(
                leadingSpace: leadingSpace, openSettingsAtLaunch: openSettingsAtLaunch,
                recordingReminder: recordingReminder, countdownTimer: countdownTimer,
                alwaysCopy: alwaysCopy, preventSleep: preventSleep, escCancels: escCancels,
                confirmQuitWhileRecording: confirmQuitWhileRecording,
                regexReplacements: regexReplacements, censorInsideWords: censorInsideWords,
                borderGradient: borderGradient, doneAccent: doneAccent,
                pillItalic: pillItalic, transcriptCentered: transcriptCentered,
                idleDotPulse: idleDotPulse, sidebarCompact: sidebarCompact,
                settingsAlwaysOnTop: settingsAlwaysOnTop, hideSidebarStats: hideSidebarStats,
                previewUsesHistory: previewUsesHistory, showWaveform: showWaveform,
                pillCursor: pillCursor, accentTintControls: accentTintControls,
                earnedFirst: earnedFirst, historyRedactNumbers: historyRedactNumbers,
                skipDuplicateHistory: skipDuplicateHistory,
                historyCompactRows: historyCompactRows, exportMetadata: exportMetadata,
                discardShortSeconds: discardShortSeconds, typeChunkDelay: typeChunkDelay,
                waveHeight: waveHeight, pillPadding: pillPadding,
                polishTimeout: polishTimeout, polishMinWords: polishMinWords,
                customMilestone: customMilestone, autoPinWords: autoPinWords,
                historyDefaultFilter: historyDefaultFilter,
                apiModel: apiModel, statusSymbolName: statusSymbolName,
                glowColorHex: glowColorHex, excludedApps: excludedApps,
                starterWords: starterWords, doubledWhitelist: doubledWhitelist),
            extra4: Backup.Extra4(
                signatureEnabled: signatureEnabled, prefixEnabled: prefixEnabled,
                stripMarkdownOutput: stripMarkdownOutput, collapseBlankLines: collapseBlankLines,
                doubleTapHandsFree: doubleTapHandsFree, polishRetry: polishRetry,
                errorSound: errorSound, autoLowercaseFirst: autoLowercaseFirst,
                showMenuBarChars: showMenuBarChars, ensureSentenceSpacing: ensureSentenceSpacing,
                timestampPrefix: timestampPrefix, capitalizeAfterColon: capitalizeAfterColon,
                trimSurroundingQuotes: trimSurroundingQuotes,
                trackReplacementUsage: trackReplacementUsage, showSnippetIndex: showSnippetIndex,
                waveMirror: waveMirror, dimWhenIdle: dimWhenIdle, accentGradient: accentGradient,
                pillBlur: pillBlur, wordCountBadge: wordCountBadge,
                monospaceTranscript: monospaceTranscript, sidebarAccentBar: sidebarAccentBar,
                animatedGradientBg: animatedGradientBg, skinAutoRotate: skinAutoRotate,
                statsGoalRing: statsGoalRing, historyShowSeconds: historyShowSeconds,
                autoExportDaily: autoExportDaily, historyGroupByApp: historyGroupByApp,
                pillMinWidth: pillMinWidth, pillOffsetY: pillOffsetY,
                pillAppearScale: pillAppearScale, accentHue2: accentHue2,
                lifetimeSince: lifetimeSince, historyFontSize: historyFontSize,
                maxWordsPerInsert: maxWordsPerInsert, maxRecordWords: maxRecordWords,
                undoDepth: undoDepth, greetingStyle: greetingStyle,
                statsWeekStart: statsWeekStart, wpmGoal: wpmGoal,
                signatureText: signatureText, prefixText: prefixText, commandWord: commandWord,
                processingLabel: processingLabel, doneLabel: doneLabel,
                listeningLabel: listeningLabel, properNouns: properNouns,
                historyMarkFavorites: historyMarkFavorites,
                commandModeEnabled: commandModeEnabled, autoLearnVocab: autoLearnVocab,
                commandHotkey: commandHotkey))
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
        if let e = b.extra {
            if let v = e.polishBackend { polishBackend = PolishBackend(rawValue: v) ?? polishBackend }
            if let v = e.pillTheme { pillTheme = PillTheme(rawValue: v) ?? pillTheme }
            if let v = e.pillCorner { pillCorner = PillCorner(rawValue: v) ?? pillCorner }
            if let v = e.pillFont { pillFont = PillFont(rawValue: v) ?? pillFont }
            if let v = e.pillMatchesSkin { pillMatchesSkin = v }
            if let v = e.capitalizeI { capitalizeI = v }
            if let v = e.smartPunctuation { smartPunctuation = v }
            if let v = e.trailingSpace { trailingSpace = v }
            if let v = e.noTrailingPeriod { noTrailingPeriod = v }
            if let v = e.keepTranscriptOnClipboard { keepTranscriptOnClipboard = v }
            if let v = e.showMenuBarStreak { showMenuBarStreak = v }
            if let v = e.caseSensitiveReplacements { caseSensitiveReplacements = v }
            if let v = e.recordTintAccent { recordTintAccent = v }
            if let v = e.idleIndicator { idleIndicator = v }
            if let v = e.reduceMotion { reduceMotion = v }
            if let v = e.soundVolume { soundVolume = v }
            if let v = e.pillBorderWidth { pillBorderWidth = v }
            if let v = e.glowIntensity { glowIntensity = v }
            if let v = e.waveGain { waveGain = v }
            if let v = e.pillEdgeOffset { pillEdgeOffset = v }
            if let v = e.totalSpeakSeconds { totalSpeakSeconds = v }
            if let v = e.historyLimit { historyLimit = v }
            if let v = e.discardShortWords { discardShortWords = v }
            if let v = e.maxRecordSeconds { maxRecordSeconds = v }
            if let v = e.longToClipboardWords { longToClipboardWords = v }
            if let v = e.waveBarCount { waveBarCount = v }
            if let v = e.historyMaxAgeDays { historyMaxAgeDays = v }
            if let v = e.autoCapSentences { autoCapSentences = v }
            if let v = e.trailingNewline { trailingNewline = v }
            if let v = e.showPillTimer { showPillTimer = v }
            if let v = e.waveMonochrome { waveMonochrome = v }
            if let v = e.spokenPunctuation { spokenPunctuation = v }
            if let v = e.replacementsEnabled { replacementsEnabled = v }
            if let v = e.pillClickToFinish { pillClickToFinish = v }
            if let v = e.showPillWhileRecording { showPillWhileRecording = v }
            if let v = e.autoBackupWeekly { autoBackupWeekly = v }
            if let v = e.showTargetIcon { showTargetIcon = v }
            if let v = e.pillScreen { pillScreen = PillScreen(rawValue: v) ?? pillScreen }
            if let v = e.idleDotOpacity { idleDotOpacity = v }
            if let v = e.pillTextSize { pillTextSize = v }
            if let v = e.transcriptWidth { transcriptWidth = v }
            if let v = e.censorWords { censorWords = v }
            if let v = e.idleDotSize { idleDotSize = IdleDotSize(rawValue: v) ?? idleDotSize }
            if let v = e.fillerWords { fillerWords = v }
            if let v = e.appRules { appRules = v }
        }
        if let e = b.extra2 {
            if let v = e.numbersToDigits { numbersToDigits = v }
            if let v = e.removeDoubledWords { removeDoubledWords = v }
            if let v = e.ensureEndPunctuation { ensureEndPunctuation = v }
            if let v = e.stripStarterWords { stripStarterWords = v }
            if let v = e.holdOnlyMode { holdOnlyMode = v }
            if let v = e.hapticsEnabled { hapticsEnabled = v }
            if let v = e.menuClickToTalk { menuClickToTalk = v }
            if let v = e.unlockSoundEnabled { unlockSoundEnabled = v }
            if let v = e.goalCelebration { goalCelebration = v }
            if let v = e.updateCheckWeekly { updateCheckWeekly = v }
            if let v = e.quietHours { quietHours = v }
            if let v = e.showMenuTimer { showMenuTimer = v }
            if let v = e.chainMode { chainMode = v }
            if let v = e.cancelOnScreenLock { cancelOnScreenLock = v }
            if let v = e.pasteMatchStyle { pasteMatchStyle = v }
            if let v = e.preserveCaseReplacements { preserveCaseReplacements = v }
            if let v = e.matchInsideWords { matchInsideWords = v }
            if let v = e.importReplaces { importReplaces = v }
            if let v = e.autoSortReplacements { autoSortReplacements = v }
            if let v = e.emojiCommands { emojiCommands = v }
            if let v = e.squareBars { squareBars = v }
            if let v = e.useSystemAccent { useSystemAccent = v }
            if let v = e.uppercasePill { uppercasePill = v }
            if let v = e.sidebarFilledIcons { sidebarFilledIcons = v }
            if let v = e.showLivePreviewBar { showLivePreviewBar = v }
            if let v = e.pinnedFirst { pinnedFirst = v }
            if let v = e.historyPaused { historyPaused = v }
            if let v = e.excludeClipboardOnly { excludeClipboardOnly = v }
            if let v = e.insertDelay { insertDelay = v }
            if let v = e.restoreDelay { restoreDelay = v }
            if let v = e.barWidth { barWidth = v }
            if let v = e.barSpacing { barSpacing = v }
            if let v = e.shadowStrength { shadowStrength = v }
            if let v = e.pillNudge { pillNudge = v }
            if let v = e.doneLinger { doneLinger = v }
            if let v = e.censorStyle { censorStyle = CensorStyle(rawValue: v) ?? censorStyle }
            if let v = e.dateStyleChoice { dateStyleChoice = DateStyleChoice(rawValue: v) ?? dateStyleChoice }
            if let v = e.pillBgHex { pillBgHex = v }
            if let v = e.pillTextColor { pillTextColor = PillTextColor(rawValue: v) ?? pillTextColor }
            if let v = e.statusDotStyle { statusDotStyle = StatusDotStyle(rawValue: v) ?? statusDotStyle }
            if let v = e.timerFormat { timerFormat = TimerFormat(rawValue: v) ?? timerFormat }
            if let v = e.entranceAnim { entranceAnim = EntranceAnim(rawValue: v) ?? entranceAnim }
            if let v = e.idleDotColor { idleDotColor = IdleDotColor(rawValue: v) ?? idleDotColor }
            if let v = e.idleDotAlignment { idleDotAlignment = PillAlignment(rawValue: v) ?? idleDotAlignment }
            if let v = e.menuSymbolName { menuSymbolName = v }
            if let v = e.pillFontWeight { pillFontWeight = PillFontWeight(rawValue: v) ?? pillFontWeight }
            if let v = e.previewSampleText { previewSampleText = v }
            if let v = e.totalChars { totalChars = v }
            if let v = e.maxSessionWords { maxSessionWords = v }
            if let v = e.commandsUsed { commandsUsed = v }
            if let v = e.polishedCount { polishedCount = v }
            if let v = e.weeklyGoal { weeklyGoal = v }
            if let v = e.vocabWords { vocabWords = v }
            if let v = e.hourCounts { hourCounts = v }
            if let v = e.appWords { appWords = v }
            if let v = e.dailySessions { dailySessions = v }
            if let v = e.customSkinDark { customSkinDark = v }
            if let v = e.customSkinHue { customSkinHue = v }
            if let v = e.customSkinSat { customSkinSat = v }
            if let v = e.customSkinFont { customSkinFont = CustomSkinFont(rawValue: v) ?? customSkinFont }
            if let v = e.customSkinShape { customSkinShape = PillCorner(rawValue: v) ?? customSkinShape }
            if let v = e.customBgHex { customBgHex = v }
            if let v = e.customSidebarHex { customSidebarHex = v }
            if let v = e.customCardHex { customCardHex = v }
            if let v = e.customTextHex { customTextHex = v }
            if let v = e.customSubtextHex { customSubtextHex = v }
            if let v = e.customInkHex { customInkHex = v }
            if let v = e.customPillBgHex { customPillBgHex = v }
        }
        if let e = b.extra3 {
            if let v = e.leadingSpace { leadingSpace = v }
            if let v = e.openSettingsAtLaunch { openSettingsAtLaunch = v }
            if let v = e.recordingReminder { recordingReminder = v }
            if let v = e.countdownTimer { countdownTimer = v }
            if let v = e.alwaysCopy { alwaysCopy = v }
            if let v = e.preventSleep { preventSleep = v }
            if let v = e.escCancels { escCancels = v }
            if let v = e.confirmQuitWhileRecording { confirmQuitWhileRecording = v }
            if let v = e.regexReplacements { regexReplacements = v }
            if let v = e.censorInsideWords { censorInsideWords = v }
            if let v = e.borderGradient { borderGradient = v }
            if let v = e.doneAccent { doneAccent = v }
            if let v = e.pillItalic { pillItalic = v }
            if let v = e.transcriptCentered { transcriptCentered = v }
            if let v = e.idleDotPulse { idleDotPulse = v }
            if let v = e.sidebarCompact { sidebarCompact = v }
            if let v = e.settingsAlwaysOnTop { settingsAlwaysOnTop = v }
            if let v = e.hideSidebarStats { hideSidebarStats = v }
            if let v = e.previewUsesHistory { previewUsesHistory = v }
            if let v = e.showWaveform { showWaveform = v }
            if let v = e.pillCursor { pillCursor = v }
            if let v = e.accentTintControls { accentTintControls = v }
            if let v = e.earnedFirst { earnedFirst = v }
            if let v = e.historyRedactNumbers { historyRedactNumbers = v }
            if let v = e.skipDuplicateHistory { skipDuplicateHistory = v }
            if let v = e.historyCompactRows { historyCompactRows = v }
            if let v = e.exportMetadata { exportMetadata = v }
            if let v = e.discardShortSeconds { discardShortSeconds = v }
            if let v = e.typeChunkDelay { typeChunkDelay = v }
            if let v = e.waveHeight { waveHeight = v }
            if let v = e.pillPadding { pillPadding = v }
            if let v = e.polishTimeout { polishTimeout = v }
            if let v = e.polishMinWords { polishMinWords = v }
            if let v = e.customMilestone { customMilestone = v }
            if let v = e.autoPinWords { autoPinWords = v }
            if let v = e.historyDefaultFilter { historyDefaultFilter = v }
            if let v = e.apiModel { apiModel = v }
            if let v = e.statusSymbolName { statusSymbolName = v }
            if let v = e.glowColorHex { glowColorHex = v }
            if let v = e.excludedApps { excludedApps = v }
            if let v = e.starterWords { starterWords = v }
            if let v = e.doubledWhitelist { doubledWhitelist = v }
        }
        if let e = b.extra4 {
            if let v = e.signatureEnabled { signatureEnabled = v }
            if let v = e.prefixEnabled { prefixEnabled = v }
            if let v = e.stripMarkdownOutput { stripMarkdownOutput = v }
            if let v = e.collapseBlankLines { collapseBlankLines = v }
            if let v = e.doubleTapHandsFree { doubleTapHandsFree = v }
            if let v = e.polishRetry { polishRetry = v }
            if let v = e.errorSound { errorSound = v }
            if let v = e.autoLowercaseFirst { autoLowercaseFirst = v }
            if let v = e.showMenuBarChars { showMenuBarChars = v }
            if let v = e.ensureSentenceSpacing { ensureSentenceSpacing = v }
            if let v = e.timestampPrefix { timestampPrefix = v }
            if let v = e.capitalizeAfterColon { capitalizeAfterColon = v }
            if let v = e.trimSurroundingQuotes { trimSurroundingQuotes = v }
            if let v = e.trackReplacementUsage { trackReplacementUsage = v }
            if let v = e.showSnippetIndex { showSnippetIndex = v }
            if let v = e.waveMirror { waveMirror = v }
            if let v = e.dimWhenIdle { dimWhenIdle = v }
            if let v = e.accentGradient { accentGradient = v }
            if let v = e.pillBlur { pillBlur = v }
            if let v = e.wordCountBadge { wordCountBadge = v }
            if let v = e.monospaceTranscript { monospaceTranscript = v }
            if let v = e.sidebarAccentBar { sidebarAccentBar = v }
            if let v = e.animatedGradientBg { animatedGradientBg = v }
            if let v = e.skinAutoRotate { skinAutoRotate = v }
            if let v = e.statsGoalRing { statsGoalRing = v }
            if let v = e.historyShowSeconds { historyShowSeconds = v }
            if let v = e.autoExportDaily { autoExportDaily = v }
            if let v = e.historyGroupByApp { historyGroupByApp = v }
            if let v = e.pillMinWidth { pillMinWidth = v }
            if let v = e.pillOffsetY { pillOffsetY = v }
            if let v = e.pillAppearScale { pillAppearScale = v }
            if let v = e.accentHue2 { accentHue2 = v }
            if let v = e.lifetimeSince { lifetimeSince = v }
            if let v = e.historyFontSize { historyFontSize = v }
            if let v = e.maxWordsPerInsert { maxWordsPerInsert = v }
            if let v = e.maxRecordWords { maxRecordWords = v }
            if let v = e.undoDepth { undoDepth = v }
            if let v = e.greetingStyle { greetingStyle = v }
            if let v = e.statsWeekStart { statsWeekStart = v }
            if let v = e.wpmGoal { wpmGoal = v }
            if let v = e.signatureText { signatureText = v }
            if let v = e.prefixText { prefixText = v }
            if let v = e.commandWord { commandWord = v }
            if let v = e.processingLabel { processingLabel = v }
            if let v = e.doneLabel { doneLabel = v }
            if let v = e.listeningLabel { listeningLabel = v }
            if let v = e.properNouns { properNouns = v }
            if let v = e.historyMarkFavorites { historyMarkFavorites = v }
            if let v = e.commandModeEnabled { commandModeEnabled = v }
            if let v = e.autoLearnVocab { autoLearnVocab = v }
            if let v = e.commandHotkey { commandHotkey = v }
        }
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

    /// Auto-learns your vocabulary: mid-sentence capitalized words (likely
    /// names/jargon) that recur 3+ times get promoted into the recognizer
    /// hint list — Wispr-Flow-style "learns your unique words."
    func learnVocabulary(from text: String) {
        guard autoLearnVocab else { return }
        let known = Set((vocabWords + replacements.map(\.phrase)).map { $0.lowercased() })
        var counts = d.dictionary(forKey: "vocabCandidates") as? [String: Int] ?? [:]
        // Skip the first word of each sentence (its capital isn't a signal).
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
        for sentence in sentences {
            let words = sentence.split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
            for w in words.dropFirst() {
                let clean = w.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
                guard clean.count > 2, let f = clean.first, f.isUppercase,
                      !known.contains(clean.lowercased()) else { continue }
                counts[clean, default: 0] += 1
                if counts[clean]! >= 3, !vocabWords.contains(clean) {
                    vocabWords.append(clean)
                    counts[clean] = nil
                }
            }
        }
        if counts.count > 200 { counts = counts.filter { $0.value >= 2 } }
        d.set(counts, forKey: "vocabCandidates")
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
        totalChars = 0
        maxSessionWords = 0
        commandsUsed = 0
        polishedCount = 0
        hourCounts = [:]
        appWords = [:]
        dailySessions = [:]
    }

    /// Consecutive days (ending today or yesterday) that hit the daily goal.
    func goalStreak() -> Int {
        guard dailyGoal > 0 else { return 0 }
        let cal = Calendar.current
        var day = Date()
        var count = 0
        if (dailyWords[Self.dayKey(day)] ?? 0) < dailyGoal {
            day = cal.date(byAdding: .day, value: -1, to: day) ?? day
        }
        while (dailyWords[Self.dayKey(day)] ?? 0) >= dailyGoal {
            count += 1
            day = cal.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return count
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
        if let data = d.data(forKey: "cmdHotkeyV2"),
           let k = try? JSONDecoder().decode(HotkeyKey.self, from: data) {
            commandHotkey = k
        } else {
            commandHotkey = HotkeyKey(keyCode: 54, isModifier: true, name: "Right ⌘")
        }
        commandModeEnabled = d.object(forKey: "cmdModeOn") as? Bool ?? true
        autoLearnVocab = d.bool(forKey: "autoLearnVocab")
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
        autoCapSentences = d.object(forKey: "autoCapSent") as? Bool ?? true
        trailingNewline = d.bool(forKey: "trailNewline")
        showPillTimer = d.object(forKey: "showPillTimer") as? Bool ?? true
        waveMonochrome = d.bool(forKey: "waveMono")
        idleDotSize = IdleDotSize(rawValue: d.string(forKey: "idleDotSize") ?? "") ?? .medium
        idleDotOpacity = d.object(forKey: "idleDotOpacity") as? Double ?? 0.5
        spokenPunctuation = d.bool(forKey: "spokenPunct")
        censorWords = d.stringArray(forKey: "censorWords") ?? []
        replacementsEnabled = d.object(forKey: "replOn") as? Bool ?? true
        pillClickToFinish = d.bool(forKey: "pillTap")
        showPillWhileRecording = d.object(forKey: "showPill") as? Bool ?? true
        pillScreen = PillScreen(rawValue: d.string(forKey: "pillScreen") ?? "") ?? .mainScreen
        autoBackupWeekly = d.bool(forKey: "autoBackup")
        pillTextSize = d.object(forKey: "pillTextSize") as? Double ?? 14
        transcriptWidth = d.object(forKey: "transcriptWidth") as? Double ?? 270
        showTargetIcon = d.object(forKey: "showTargetIcon") as? Bool ?? true
        numbersToDigits = d.bool(forKey: "numToDigits")
        removeDoubledWords = d.bool(forKey: "deDouble")
        ensureEndPunctuation = d.bool(forKey: "endPunct")
        stripStarterWords = d.bool(forKey: "stripStarters")
        holdOnlyMode = d.bool(forKey: "holdOnly")
        hapticsEnabled = d.bool(forKey: "haptics")
        menuClickToTalk = d.bool(forKey: "menuClickTalk")
        insertDelay = d.object(forKey: "insertDelay") as? Double ?? 0
        restoreDelay = d.object(forKey: "restoreDelay") as? Double ?? 0.8
        unlockSoundEnabled = d.object(forKey: "unlockSound") as? Bool ?? true
        goalCelebration = d.object(forKey: "goalCeleb") as? Bool ?? true
        updateCheckWeekly = d.bool(forKey: "updateCheck")
        quietHours = d.bool(forKey: "quietHours")
        showMenuTimer = d.bool(forKey: "menuTimer")
        chainMode = d.bool(forKey: "chainMode")
        cancelOnScreenLock = d.object(forKey: "lockCancel") as? Bool ?? true
        pasteMatchStyle = d.bool(forKey: "pasteMatch")
        preserveCaseReplacements = d.bool(forKey: "preserveCase")
        matchInsideWords = d.bool(forKey: "matchInside")
        importReplaces = d.bool(forKey: "importReplaces")
        autoSortReplacements = d.bool(forKey: "autoSortRepl")
        emojiCommands = d.object(forKey: "emojiCmds") as? Bool ?? true
        censorStyle = CensorStyle(rawValue: d.string(forKey: "censorStyle") ?? "") ?? .asterisks
        dateStyleChoice = DateStyleChoice(rawValue: d.string(forKey: "dateStyle") ?? "") ?? .medium
        vocabWords = d.stringArray(forKey: "vocabWords") ?? []
        barWidth = d.object(forKey: "barWidth") as? Double ?? 3
        barSpacing = d.object(forKey: "barSpacing") as? Double ?? 2.5
        squareBars = d.bool(forKey: "squareBars")
        shadowStrength = d.object(forKey: "shadowStrength") as? Double ?? 1.0
        pillNudge = d.object(forKey: "pillNudge") as? Double ?? 0
        pillBgHex = d.string(forKey: "pillBgHex") ?? ""
        pillTextColor = PillTextColor(rawValue: d.string(forKey: "pillTextColor") ?? "") ?? .auto
        statusDotStyle = StatusDotStyle(rawValue: d.string(forKey: "statusDotStyle") ?? "") ?? .dot
        timerFormat = TimerFormat(rawValue: d.string(forKey: "timerFormat") ?? "") ?? .mmss
        entranceAnim = EntranceAnim(rawValue: d.string(forKey: "entranceAnim") ?? "") ?? .spring
        doneLinger = d.object(forKey: "doneLinger") as? Double ?? 1.1
        idleDotColor = IdleDotColor(rawValue: d.string(forKey: "idleDotColor") ?? "") ?? .accent
        idleDotAlignment = PillAlignment(rawValue: d.string(forKey: "idleDotAlign") ?? "") ?? .center
        menuSymbolName = d.string(forKey: "menuSymbol") ?? ""
        useSystemAccent = d.bool(forKey: "sysAccent")
        pillFontWeight = PillFontWeight(rawValue: d.string(forKey: "pillWeight") ?? "") ?? .medium
        uppercasePill = d.bool(forKey: "upperPill")
        sidebarFilledIcons = d.bool(forKey: "sidebarFill")
        showLivePreviewBar = d.object(forKey: "livePreview") as? Bool ?? true
        previewSampleText = d.string(forKey: "previewText") ?? ""
        totalChars = d.integer(forKey: "totalChars")
        maxSessionWords = d.integer(forKey: "maxSessWords")
        commandsUsed = d.integer(forKey: "commandsUsed")
        polishedCount = d.integer(forKey: "polishedCount")
        hourCounts = d.dictionary(forKey: "hourCounts") as? [String: Int] ?? [:]
        appWords = d.dictionary(forKey: "appWords") as? [String: Int] ?? [:]
        dailySessions = d.dictionary(forKey: "dailySessions") as? [String: Int] ?? [:]
        weeklyGoal = d.integer(forKey: "weeklyGoal")
        customSkinDark = d.object(forKey: "customSkinDark") as? Bool ?? true
        customSkinHue = d.object(forKey: "customSkinHue") as? Double ?? 0.60
        customSkinSat = d.object(forKey: "customSkinSat") as? Double ?? 0.55
        customSkinFont = CustomSkinFont(rawValue: d.string(forKey: "customSkinFont") ?? "") ?? .system
        customSkinShape = PillCorner(rawValue: d.string(forKey: "customSkinShape") ?? "") ?? .capsule
        customBgHex = d.string(forKey: "customBgHex") ?? ""
        customSidebarHex = d.string(forKey: "customSidebarHex") ?? ""
        customCardHex = d.string(forKey: "customCardHex") ?? ""
        customTextHex = d.string(forKey: "customTextHex") ?? ""
        customSubtextHex = d.string(forKey: "customSubtextHex") ?? ""
        customInkHex = d.string(forKey: "customInkHex") ?? ""
        customPillBgHex = d.string(forKey: "customPillBgHex") ?? ""
        polishTimeout = d.object(forKey: "polishTimeout") as? Int ?? 30
        apiModel = d.string(forKey: "apiModel") ?? "claude-opus-4-8"
        polishMinWords = d.integer(forKey: "polishMinWords")
        leadingSpace = d.bool(forKey: "leadSpace")
        openSettingsAtLaunch = d.bool(forKey: "openSettings")
        discardShortSeconds = d.double(forKey: "discardShortSecs")
        recordingReminder = d.bool(forKey: "recReminder")
        countdownTimer = d.bool(forKey: "countdown")
        typeChunkDelay = d.object(forKey: "typeDelay") as? Double ?? 9
        alwaysCopy = d.bool(forKey: "alwaysCopy")
        preventSleep = d.bool(forKey: "noSleep")
        escCancels = d.object(forKey: "escCancels") as? Bool ?? true
        excludedApps = d.stringArray(forKey: "excludedApps") ?? []
        confirmQuitWhileRecording = d.object(forKey: "quitConfirm") as? Bool ?? true
        regexReplacements = d.bool(forKey: "regexRepl")
        censorInsideWords = d.bool(forKey: "censorInside")
        starterWords = d.stringArray(forKey: "starterWords")
            ?? ["so", "well", "okay", "ok", "anyway", "alright", "basically", "like"]
        doubledWhitelist = d.stringArray(forKey: "doubledWhitelist") ?? ["very", "really"]
        waveHeight = d.object(forKey: "waveHeight") as? Double ?? 36
        statusSymbolName = d.string(forKey: "statusSymbol") ?? ""
        pillPadding = d.object(forKey: "pillPadding") as? Double ?? 22
        glowColorHex = d.string(forKey: "glowColorHex") ?? ""
        borderGradient = d.object(forKey: "borderGrad") as? Bool ?? true
        doneAccent = d.bool(forKey: "doneAccent")
        pillItalic = d.bool(forKey: "pillItalic")
        transcriptCentered = d.bool(forKey: "transcriptCenter")
        idleDotPulse = d.bool(forKey: "idlePulse")
        sidebarCompact = d.bool(forKey: "sidebarCompact")
        settingsAlwaysOnTop = d.bool(forKey: "alwaysOnTop")
        hideSidebarStats = d.bool(forKey: "hideSideStats")
        previewUsesHistory = d.bool(forKey: "previewHistory")
        showWaveform = d.object(forKey: "showWave") as? Bool ?? true
        pillCursor = d.bool(forKey: "pillCursor")
        accentTintControls = d.bool(forKey: "accentTint")
        customMilestone = d.integer(forKey: "customMilestone")
        earnedFirst = d.bool(forKey: "earnedFirst")
        autoPinWords = d.integer(forKey: "autoPinWords")
        historyRedactNumbers = d.bool(forKey: "histRedact")
        skipDuplicateHistory = d.bool(forKey: "histSkipDupes")
        historyCompactRows = d.bool(forKey: "histCompact")
        historyDefaultFilter = d.integer(forKey: "histDefaultFilter")
        exportMetadata = d.bool(forKey: "exportMeta")
        signatureEnabled = d.bool(forKey: "sigOn")
        signatureText = d.string(forKey: "sigText") ?? ""
        prefixEnabled = d.bool(forKey: "prefixOn")
        prefixText = d.string(forKey: "prefixText") ?? ""
        stripMarkdownOutput = d.bool(forKey: "stripMd")
        collapseBlankLines = d.object(forKey: "collapseBlank") as? Bool ?? true
        properNouns = d.stringArray(forKey: "properNouns") ?? []
        doubleTapHandsFree = d.object(forKey: "dblTap") as? Bool ?? true
        polishRetry = d.object(forKey: "polishRetry") as? Bool ?? true
        errorSound = d.object(forKey: "errSound") as? Bool ?? true
        autoLowercaseFirst = d.bool(forKey: "lcFirst")
        maxWordsPerInsert = d.integer(forKey: "maxWords")
        maxRecordWords = d.integer(forKey: "maxRecWords")
        showMenuBarChars = d.bool(forKey: "menuChars")
        ensureSentenceSpacing = d.bool(forKey: "sentSpace")
        undoDepth = d.object(forKey: "undoDepth") as? Int ?? 1
        timestampPrefix = d.bool(forKey: "tsPrefix")
        capitalizeAfterColon = d.bool(forKey: "capColon")
        trimSurroundingQuotes = d.bool(forKey: "trimQuotes")
        greetingStyle = d.integer(forKey: "greetStyle")
        replacementUsage = d.dictionary(forKey: "replUsage") as? [String: Int] ?? [:]
        trackReplacementUsage = d.object(forKey: "trackRepl") as? Bool ?? true
        showSnippetIndex = d.bool(forKey: "snipIndex")
        commandWord = d.string(forKey: "cmdWord") ?? ""
        pillMinWidth = d.object(forKey: "pillMinW") as? Double ?? 130
        pillOffsetY = d.double(forKey: "pillOffY")
        waveMirror = d.bool(forKey: "waveMirror")
        pillAppearScale = d.object(forKey: "appearScale") as? Double ?? 0.85
        dimWhenIdle = d.bool(forKey: "dimIdle")
        accentGradient = d.bool(forKey: "accentGrad")
        accentHue2 = d.object(forKey: "accentHue2") as? Double ?? 0.55
        pillBlur = d.object(forKey: "pillBlur") as? Bool ?? true
        processingLabel = d.string(forKey: "procLabel") ?? ""
        doneLabel = d.string(forKey: "doneLabel") ?? ""
        listeningLabel = d.string(forKey: "listenLabel") ?? ""
        wordCountBadge = d.object(forKey: "wcBadge") as? Bool ?? true
        monospaceTranscript = d.bool(forKey: "monoTranscript")
        sidebarAccentBar = d.object(forKey: "sideAccentBar") as? Bool ?? true
        animatedGradientBg = d.bool(forKey: "animBg")
        skinAutoRotate = d.bool(forKey: "skinRotate")
        statsGoalRing = d.object(forKey: "goalRing") as? Bool ?? true
        statsWeekStart = d.integer(forKey: "weekStart")
        lifetimeSince = d.double(forKey: "lifeSince")
        wpmGoal = d.integer(forKey: "wpmGoal")
        historyFontSize = d.object(forKey: "histFont") as? Double ?? 12.5
        historyShowSeconds = d.object(forKey: "histSecs") as? Bool ?? true
        historyMarkFavorites = d.stringArray(forKey: "histFavs") ?? []
        autoExportDaily = d.bool(forKey: "autoExport")
        historyGroupByApp = d.bool(forKey: "histGroupApp")
        pinnedFirst = d.object(forKey: "pinnedFirst") as? Bool ?? true
        historyPaused = d.bool(forKey: "histPaused")
        excludeClipboardOnly = d.bool(forKey: "histNoClip")
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
    private var skinWatcher: AnyCancellable?

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
            // Light skins (Paper, Candy, Retro) need light-styled native
            // controls even when the system is dark — and vice versa. The
            // Skin Studio's Dark/Light flip needs the same treatment.
            skinWatcher = Publishers.Merge(
                AppSettings.shared.$skin.map { _ in () },
                AppSettings.shared.$customSkinDark.map { _ in () }
            ).sink { [weak self] in
                self?.window?.appearance = AppSettings.shared.skin.forcedAppearance
            }
        }
        window?.appearance = AppSettings.shared.skin.forcedAppearance
        window?.level = AppSettings.shared.settingsAlwaysOnTop ? .floating : .normal
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
                case 2: AppsPane(settings: settings)
                case 3: AppearancePane(settings: settings)
                case 4: StatsPane(settings: settings)
                default: HistoryPane(settings: settings)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                ZStack {
                    p.bg
                    if settings.animatedGradientBg {
                        TimelineView(.animation) { context in
                            let t = context.date.timeIntervalSinceReferenceDate
                            RadialGradient(colors: [settings.accentColor.opacity(0.16), .clear],
                                           center: UnitPoint(x: 0.5 + 0.35 * cos(t * 0.25),
                                                             y: 0.35 + 0.25 * sin(t * 0.19)),
                                           startRadius: 5, endRadius: 420)
                        }
                    }
                    SkinBackground(seed: 1)
                }
            }
        }
        .frame(width: 700, height: 500)
        .tint(settings.accentTintControls ? settings.accentColor : nil)
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
            navItem(2, "macwindow", "Apps")
            navItem(3, "paintbrush", "Appearance")
            navItem(4, "chart.bar", "Stats")
            navItem(5, "clock.arrow.circlepath", "History")

            Spacer()

            if settings.totalWords > 0, !settings.hideSidebarStats {
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
        .frame(width: settings.sidebarCompact ? 132 : 176)
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
        // Filled variants where SF Symbols has them.
        let fillable = ["character.book.closed", "paintbrush", "chart.bar"]
        let name = settings.sidebarFilledIcons && fillable.contains(symbol)
            ? symbol + ".fill" : symbol
        return Button {
            tab = index
        } label: {
            HStack(spacing: 8) {
                Image(systemName: name)
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
            .overlay(alignment: .leading) {
                if selected, settings.sidebarAccentBar {
                    Capsule().fill(settings.accentColor)
                        .frame(width: 3, height: 16)
                        .offset(x: -6)
                }
            }
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
                RowDivider()
                PRow(title: "Hold-only mode",
                     subtitle: "Quick taps finish instead of going hands-free") {
                    Toggle("", isOn: $settings.holdOnlyMode)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Chain dictations",
                     subtitle: "Start the next hands-free dictation right after each insert") {
                    Toggle("", isOn: $settings.chainMode)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
            }

            SectionLabel(text: "Command mode")
                .padding(.top, 6)
            CardGroup {
                PRow(title: "AI command key",
                     subtitle: "Hold, speak an edit (“make this formal”, “fix grammar”), release — Claude rewrites your selected text in place") {
                    Toggle("", isOn: $settings.commandModeEnabled)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                if settings.commandModeEnabled {
                    RowDivider()
                    PRow(title: "Command key",
                         subtitle: "Different from your dictation key — needs AI polish (API key or Claude CLI)") {
                        HStack(spacing: 6) {
                            CommandKeyButton(settings: settings)
                            if settings.commandHotkey.keyCode != 54 {
                                Button("Reset") {
                                    settings.commandHotkey = HotkeyKey(keyCode: 54, isModifier: true, name: "Right ⌘")
                                }
                                .buttonStyle(.borderless).font(.system(size: 12))
                            }
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
                        RowDivider()
                        PRow(title: "Model",
                             subtitle: "Which Claude handles the polish") {
                            Picker("", selection: $settings.apiModel) {
                                Text("Opus 4.8").tag("claude-opus-4-8")
                                Text("Sonnet 5").tag("claude-sonnet-5")
                                Text("Haiku 4.5").tag("claude-haiku-4-5")
                            }
                            .pickerStyle(.segmented).labelsHidden().frame(width: 230)
                        }
                    }
                    RowDivider()
                    PRow(title: "Polish timeout",
                         subtitle: "Give up and insert the raw text after this long") {
                        Picker("", selection: $settings.polishTimeout) {
                            Text("10s").tag(10)
                            Text("30s").tag(30)
                            Text("60s").tag(60)
                        }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 150)
                    }
                    RowDivider()
                    PRow(title: "Skip polish on short dictations",
                         subtitle: "Not worth the round-trip under this many words") {
                        Picker("", selection: $settings.polishMinWords) {
                            Text("Off").tag(0)
                            Text("< 5w").tag(5)
                            Text("< 10w").tag(10)
                            Text("< 20w").tag(20)
                        }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 210)
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
                PRow(title: "Capitalize sentences",
                     subtitle: "Uppercase the first letter after . ! ? and new lines") {
                    Toggle("", isOn: $settings.autoCapSentences)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Numbers as digits",
                     subtitle: "“twenty five” → 25") {
                    Toggle("", isOn: $settings.numbersToDigits)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Remove doubled words",
                     subtitle: "“the the” → “the”") {
                    Toggle("", isOn: $settings.removeDoubledWords)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Strip starter words",
                     subtitle: "Drops a leading “So,” “Well,” “Okay,”") {
                    Toggle("", isOn: $settings.stripStarterWords)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Always end with punctuation",
                     subtitle: "Adds a period when the sentence ends bare") {
                    Toggle("", isOn: $settings.ensureEndPunctuation)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Space after sentences",
                     subtitle: "“a.Next” → “a. Next”") {
                    Toggle("", isOn: $settings.ensureSentenceSpacing)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Collapse blank lines",
                     subtitle: "Never more than one empty line in a row") {
                    Toggle("", isOn: $settings.collapseBlankLines)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Capitalize after colon") {
                    Toggle("", isOn: $settings.capitalizeAfterColon)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Trim surrounding quotes",
                     subtitle: "Drops a matching pair of quotes wrapping the whole thing") {
                    Toggle("", isOn: $settings.trimSurroundingQuotes)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Lowercase first letter",
                     subtitle: "For lowercase-chat style") {
                    Toggle("", isOn: $settings.autoLowercaseFirst)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Proper nouns",
                     subtitle: "Comma-separated — always capitalized wherever they appear") {
                    TextField("iPhone, GitHub, Anthropic…", text: Binding(
                        get: { settings.properNouns.joined(separator: ", ") },
                        set: { settings.properNouns = $0.components(separatedBy: ",")
                            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
                    ))
                    .textFieldStyle(.roundedBorder).font(.system(size: 12)).frame(width: 220)
                }
                RowDivider()
                PRow(title: "Strip Markdown from polish",
                     subtitle: "Removes **bold**, # headings, and bullets the model adds") {
                    Toggle("", isOn: $settings.stripMarkdownOutput)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Retry polish on failure",
                     subtitle: "Try once more if the model returns nothing") {
                    Toggle("", isOn: $settings.polishRetry)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Cap words per insert",
                     subtitle: "Truncate anything longer (0 = off)") {
                    Picker("", selection: $settings.maxWordsPerInsert) {
                        Text("Off").tag(0)
                        Text("100").tag(100)
                        Text("300").tag(300)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 160)
                }
                RowDivider()
                PRow(title: "Auto-finish at word count",
                     subtitle: "Stop recording once the transcript hits this many words") {
                    Picker("", selection: $settings.maxRecordWords) {
                        Text("Off").tag(0)
                        Text("50").tag(50)
                        Text("100").tag(100)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 160)
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
                PRow(title: "Discard blips",
                     subtitle: "Ignore recordings shorter than this") {
                    Picker("", selection: $settings.discardShortSeconds) {
                        Text("Off").tag(0.0)
                        Text("0.5s").tag(0.5)
                        Text("1s").tag(1.0)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 150)
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
                     subtitle: "\(Self.languages.count) languages — ☁︎ ones use Apple's speech servers instead of staying on-device") {
                    Picker("", selection: $settings.localeID) {
                        ForEach(Self.languages, id: \.0) { id, name in
                            Text(Self.onDeviceLocales.contains(id) ? name : "\(name)  ☁︎").tag(id)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 190)
                }
                RowDivider()
                PRow(title: "Auto-punctuation",
                     subtitle: "Let the recognizer add commas and periods") {
                    Toggle("", isOn: $settings.autoPunctuation)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Spoken punctuation",
                     subtitle: "Say “period”, “comma”, “question mark” to type them") {
                    Toggle("", isOn: $settings.spokenPunctuation)
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
                if settings.typeInsteadOfPaste {
                    RowDivider()
                    PRow(title: "Typing speed",
                         subtitle: "Left = faster, right = gentler on slow apps") {
                        Slider(value: $settings.typeChunkDelay, in: 2...40)
                            .frame(width: 130).controlSize(.small)
                    }
                    RowDivider()
                    PRow(title: "Also copy to clipboard",
                         subtitle: "Typed inserts leave the text on the clipboard too") {
                        Toggle("", isOn: $settings.alwaysCopy)
                            .toggleStyle(.switch).labelsHidden().controlSize(.small)
                    }
                }
                RowDivider()
                PRow(title: "Add leading space",
                     subtitle: "For appending mid-sentence") {
                    Toggle("", isOn: $settings.leadingSpace)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Prefix text",
                     subtitle: "Prepended to every insert — supports {greeting}, {date}, {app}") {
                    HStack(spacing: 6) {
                        TextField("e.g. {greeting} ", text: $settings.prefixText)
                            .textFieldStyle(.roundedBorder).font(.system(size: 12)).frame(width: 180)
                        Toggle("", isOn: $settings.prefixEnabled)
                            .toggleStyle(.switch).labelsHidden().controlSize(.small)
                    }
                }
                RowDivider()
                PRow(title: "Signature",
                     subtitle: "Appended to every insert — supports variables") {
                    HStack(spacing: 6) {
                        TextField("e.g. \\n— sent via Murmur", text: $settings.signatureText)
                            .textFieldStyle(.roundedBorder).font(.system(size: 12)).frame(width: 180)
                        Toggle("", isOn: $settings.signatureEnabled)
                            .toggleStyle(.switch).labelsHidden().controlSize(.small)
                    }
                }
                RowDivider()
                PRow(title: "Timestamp prefix",
                     subtitle: "Prepends [3:42 PM] to each insert") {
                    Toggle("", isOn: $settings.timestampPrefix)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Double-tap for hands-free",
                     subtitle: "Two quick taps of the hotkey latch hands-free mode") {
                    Toggle("", isOn: $settings.doubleTapHandsFree)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Undo depth",
                     subtitle: "How many past inserts “Undo Last Insert” can walk back") {
                    Picker("", selection: $settings.undoDepth) {
                        Text("1").tag(1)
                        Text("5").tag(5)
                        Text("10").tag(10)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 150)
                }
                RowDivider()
                PRow(title: "Play sound on error") {
                    Toggle("", isOn: $settings.errorSound)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Characters in menu bar",
                     subtitle: "Lifetime character count (in thousands)") {
                    Toggle("", isOn: $settings.showMenuBarChars)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Never auto-insert into",
                     subtitle: "Comma-separated app names — goes to clipboard instead") {
                    TextField("1Password, Terminal…", text: Binding(
                        get: { settings.excludedApps.joined(separator: ", ") },
                        set: { settings.excludedApps = $0.components(separatedBy: ",")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty } }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .frame(width: 220)
                }
                RowDivider()
                PRow(title: "Esc cancels dictation") {
                    Toggle("", isOn: $settings.escCancels)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Keep Mac awake while recording") {
                    Toggle("", isOn: $settings.preventSleep)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Recording reminder",
                     subtitle: "Soft cue every 30s while the mic is live") {
                    Toggle("", isOn: $settings.recordingReminder)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Countdown timer",
                     subtitle: "Pill counts down to the max length instead of up") {
                    Toggle("", isOn: $settings.countdownTimer)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Confirm quit while recording") {
                    Toggle("", isOn: $settings.confirmQuitWhileRecording)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Open settings at launch") {
                    Toggle("", isOn: $settings.openSettingsAtLaunch)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Microphone input",
                     subtitle: "Pick or test your mic in System Settings") {
                    Button("Open Sound Settings…") {
                        NSWorkspace.shared.open(
                            URL(string: "x-apple.systempreferences:com.apple.preference.sound")!)
                    }
                    .controlSize(.small)
                }
                RowDivider()
                PRow(title: "Paste and match style",
                     subtitle: "⌥⇧⌘V — takes the destination's formatting") {
                    Toggle("", isOn: $settings.pasteMatchStyle)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Insert delay",
                     subtitle: "Pause before pasting, for slow apps") {
                    HStack(spacing: 8) {
                        Slider(value: $settings.insertDelay, in: 0...1)
                            .frame(width: 110).controlSize(.small)
                        Text(String(format: "%.1fs", settings.insertDelay))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(p.subtext)
                            .frame(width: 36, alignment: .trailing)
                    }
                }
                RowDivider()
                PRow(title: "Clipboard restore delay",
                     subtitle: "How long the transcript stays before the old clipboard returns") {
                    Slider(value: $settings.restoreDelay, in: 0.3...3)
                        .frame(width: 130).controlSize(.small)
                }
                RowDivider()
                PRow(title: "Haptic feedback",
                     subtitle: "Trackpad tick on start and insert") {
                    Toggle("", isOn: $settings.hapticsEnabled)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Left-click icon to dictate",
                     subtitle: "Menu moves to right-click") {
                    Toggle("", isOn: $settings.menuClickToTalk)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Recording timer in menu bar") {
                    Toggle("", isOn: $settings.showMenuTimer)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Cancel when screen locks",
                     subtitle: "Never leaves the mic open behind a locked screen") {
                    Toggle("", isOn: $settings.cancelOnScreenLock)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Check for updates weekly",
                     subtitle: "Shows a menu item when a newer release is out") {
                    Toggle("", isOn: $settings.updateCheckWeekly)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Add trailing space",
                     subtitle: "Ready for the next sentence") {
                    Toggle("", isOn: $settings.trailingSpace)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Add trailing newline",
                     subtitle: "End each dictation on a new line (takes priority over space)") {
                    Toggle("", isOn: $settings.trailingNewline)
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
                    PRow(title: "Quiet hours",
                         subtitle: "No sound cues between 10 pm and 8 am") {
                        Toggle("", isOn: $settings.quietHours)
                            .toggleStyle(.switch).labelsHidden().controlSize(.small)
                    }
                    RowDivider()
                    PRow(title: "Badge unlock sound") {
                        Toggle("", isOn: $settings.unlockSoundEnabled)
                            .toggleStyle(.switch).labelsHidden().controlSize(.small)
                    }
                    RowDivider()
                    PRow(title: "Celebrate daily goal",
                         subtitle: "Pill flashes 🎯 when you hit your word goal") {
                        Toggle("", isOn: $settings.goalCelebration)
                            .toggleStyle(.switch).labelsHidden().controlSize(.small)
                    }
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
                        HStack(spacing: 8) {
                            Slider(value: $settings.soundVolume, in: 0.1...1.0)
                                .frame(width: 130)
                                .controlSize(.small)
                            Button("Preview") { previewSounds() }
                                .controlSize(.small)
                        }
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
                PRow(title: "Via clipboard",
                     subtitle: "Copy the backup JSON, or import what's on the clipboard") {
                    HStack(spacing: 6) {
                        Button("Copy") {
                            if let data = try? settings.exportBackup(),
                               let json = String(data: data, encoding: .utf8) {
                                let pb = NSPasteboard.general
                                pb.clearContents()
                                pb.setString(json, forType: .string)
                            }
                        }
                        Button("Import") {
                            if let json = NSPasteboard.general.string(forType: .string) {
                                try? settings.importBackup(Data(json.utf8))
                            }
                        }
                    }
                    .controlSize(.small)
                }
                RowDivider()
                PRow(title: "Auto-backup weekly",
                     subtitle: "Saves a backup to Application Support ▸ Murmur ▸ Backups (keeps 5)") {
                    HStack(spacing: 6) {
                        Button("Back Up Now") { backUpNow() }
                            .controlSize(.small)
                        Toggle("", isOn: $settings.autoBackupWeekly)
                            .toggleStyle(.switch).labelsHidden().controlSize(.small)
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

    /// Writes a dated backup to Application Support ▸ Murmur ▸ Backups.
    private func backUpNow() {
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return }
        let dir = base.appendingPathComponent("Murmur/Backups", isDirectory: true)
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd-HHmm"
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? settings.exportBackup() {
            try? data.write(to: dir.appendingPathComponent("Murmur-Backup-\(df.string(from: Date())).json"))
        }
    }

    /// Plays the start cue, then the insert cue, at the chosen theme/volume.
    private func previewSounds() {
        func play(_ event: SoundEvent) {
            guard let s = NSSound(named: settings.soundTheme.sound(for: event)) else { return }
            s.volume = Float(settings.soundVolume)
            s.play()
        }
        play(.start)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { play(.insert) }
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

    /// Every speech locale this Mac's recognizer supports — no curation.
    /// (Apple ships 60+; the old hand-picked list of 16 was an artificial cap.)
    static let languages: [(String, String)] = {
        let display = Locale(identifier: "en-US")
        return SFSpeechRecognizer.supportedLocales()
            .map { loc -> (String, String) in
                let id = loc.identifier.replacingOccurrences(of: "_", with: "-")
                return (id, display.localizedString(forIdentifier: id) ?? id)
            }
            .sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
    }()

    /// Locales that transcribe fully on-device. The rest fall back to Apple's
    /// speech servers — worth knowing if you picked Murmur for privacy.
    static let onDeviceLocales: Set<String> = {
        Set(languages.compactMap { id, _ in
            SFSpeechRecognizer(locale: Locale(identifier: id))?
                .supportsOnDeviceRecognition == true ? id : nil
        })
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

/// Captures a modifier key for AI Command Mode (modifier-only, so it can be
/// held while speaking without also typing).
struct CommandKeyButton: View {
    @ObservedObject var settings: AppSettings
    @State private var capturing = false
    @State private var monitor: Any?

    var body: some View {
        Button(capturing ? "Hold a modifier…" : settings.commandHotkey.name) {
            capturing ? stopCapture() : startCapture()
        }
        .buttonStyle(.bordered)
        .tint(capturing ? .accentColor : nil)
        .onDisappear { stopCapture() }
    }

    private func startCapture() {
        capturing = true
        KeyCaptureState.active = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { event in
            if let name = HotkeyKey.modifierName(for: event.keyCode) {
                let candidate = HotkeyKey(keyCode: event.keyCode, isModifier: true, name: name)
                if let flag = candidate.modifierFlag, event.modifierFlags.contains(flag) {
                    settings.commandHotkey = candidate
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
    @State private var replSearch = ""
    @State private var fullPipelineTest = false

    private func isDuplicate(_ phrase: String) -> Bool {
        !phrase.isEmpty &&
        settings.replacements.filter { $0.phrase.caseInsensitiveCompare(phrase) == .orderedSame }.count > 1
    }

    private func exportDictionary(enabledOnly: Bool = false) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Murmur Dictionary.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let esc: (String) -> String = { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        let items = enabledOnly ? settings.replacements.filter(\.enabled) : settings.replacements
        let rows = items.map { "\(esc($0.phrase)),\(esc($0.replacement))" }
        try? ("phrase,replacement\n" + rows.joined(separator: "\n") + "\n")
            .write(to: url, atomically: true, encoding: .utf8)
    }

    private func exportDictionaryJSON() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Murmur Dictionary.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(settings.replacements).write(to: url)
    }

    private func sortReplacements() {
        settings.replacements.sort {
            $0.phrase.localizedCaseInsensitiveCompare($1.phrase) == .orderedAscending
        }
    }

    /// The Try-it box result — commands + replacements, or the whole
    /// pipeline when "Full pipeline" is on.
    private var testResult: String {
        var t = testInput
        if fullPipelineTest, settings.tidyEnabled { t = TextCleaner.tidy(t) }
        if fullPipelineTest, settings.stripStarterWords { t = TextCleaner.stripStarterWords(t) }
        if fullPipelineTest, settings.removeDoubledWords { t = TextCleaner.removeDoubledWords(t) }
        if settings.voiceCommandsEnabled {
            t = TextCleaner.applyScratchThat(t)
            t = TextCleaner.applyCommands(t, includeEmoji: settings.emojiCommands)
        }
        if fullPipelineTest, settings.spokenPunctuation { t = TextCleaner.applySpokenPunctuation(t) }
        if settings.replacementsEnabled { t = TextCleaner.applyReplacements(t, settings.replacements) }
        t = TextCleaner.expandVariables(t)
        if fullPipelineTest {
            if settings.numbersToDigits { t = TextCleaner.numbersToDigits(t) }
            if !settings.censorWords.isEmpty {
                t = TextCleaner.censor(t, words: settings.censorWords, style: settings.censorStyle)
            }
            if settings.capitalizeI { t = TextCleaner.capitalizeI(t) }
            if settings.smartPunctuation { t = TextCleaner.smartPunctuation(t) }
            if settings.autoCapSentences { t = TextCleaner.capitalizeSentences(t) }
            if settings.ensureEndPunctuation { t = TextCleaner.ensureEndPunctuation(t) }
        }
        return t
    }

    /// Replacement phrases that actually matched the test input.
    private var firedRules: [String] {
        settings.replacements
            .filter { $0.enabled && !$0.phrase.isEmpty }
            .filter { testInput.range(of: "\\b\(NSRegularExpression.escapedPattern(for: $0.phrase))\\b",
                                      options: [.regularExpression, .caseInsensitive]) != nil }
            .map(\.phrase)
    }

    static let commandReference = """
    new line · new paragraph · scratch that
    bullet point · em dash · open/close paren · open/close quote · tab key
    period · comma · question mark · exclamation point (Spoken punctuation)
    today's date · current time · degree sign · ellipsis · copyright symbol
    trademark symbol · right arrow · asterisk · hashtag · at sign
    percent sign · ampersand
    smiley face · winky face · heart emoji · fire emoji · thumbs up
    rocket emoji · check mark · shrug emoji
    """

    private var replacementsFooter: String {
        let total = settings.replacements.count
        let enabled = settings.replacements.filter(\.enabled).count
        let shown = replSearch.isEmpty ? total : settings.replacements.filter {
            $0.phrase.localizedCaseInsensitiveContains(replSearch)
                || $0.replacement.localizedCaseInsensitiveContains(replSearch)
        }.count
        var s = "\(shown) of \(total) shown · \(enabled) enabled"
        s += " · \(settings.vocabWords.count) vocab · \(settings.censorWords.count) censored"
        let dupes = Dictionary(grouping: settings.replacements.map { $0.phrase.lowercased() }) { $0 }
            .filter { !$0.key.isEmpty && $0.value.count > 1 }.count
        if dupes > 0 { s += " · ⚠️ \(dupes) duplicate phrase\(dupes == 1 ? "" : "s")" }
        if total + settings.vocabWords.count > 100 {
            s += " · recognizer hints cap at 100"
        }
        return s
    }

    private func importDictionary() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        importDictionaryText(content)
    }

    private func importDictionaryText(_ content: String) {
        guard !content.isEmpty else { return }
        if settings.importReplaces { settings.replacements.removeAll() }
        var added = 0
        for cols in Self.parseCSV(content) {
            guard cols.count >= 2 else { continue }
            let phrase = cols[0].trimmingCharacters(in: .whitespaces)
            let repl = cols[1].trimmingCharacters(in: .whitespaces)
            // Skip the header row and blanks.
            if phrase.caseInsensitiveCompare("phrase") == .orderedSame,
               repl.caseInsensitiveCompare("replacement") == .orderedSame { continue }
            guard !phrase.isEmpty, !repl.isEmpty,
                  !settings.replacements.contains(where: { $0.phrase == phrase }) else { continue }
            settings.replacements.append(Replacement(phrase: phrase, replacement: repl))
            added += 1
        }
        NSLog("Murmur: imported \(added) replacements")
    }

    /// Minimal RFC-4180 CSV parser: honors quoted fields, escaped quotes
    /// (`""`), and commas or newlines inside quotes, so anything Export CSV
    /// writes reads back intact.
    static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        let chars = Array(text)
        var i = 0
        func endRow() { row.append(field); field = ""; rows.append(row); row = [] }
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" { field.append("\""); i += 1 }
                    else { inQuotes = false }
                } else { field.append(c) }
            } else {
                switch c {
                case "\"": inQuotes = true
                case ",": row.append(field); field = ""
                case "\n", "\r\n", "\r": endRow()
                default: field.append(c)
                }
            }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty { endRow() }
        return rows
    }

    var body: some View {
        let p = Palette.of(scheme)
        Pane(title: "Dictionary",
             subtitle: "Teach Murmur your words, names, and shortcuts.") {
            SectionLabel(text: "Voice commands")
            CardGroup {
                PRow(title: "“New line”, “new paragraph”, “scratch that”",
                     subtitle: "Line breaks, symbols, and emoji — “scratch that” restarts the sentence") {
                    Toggle("", isOn: $settings.voiceCommandsEnabled)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
            }

            SectionLabel(text: "Replacements")
                .padding(.top, 6)
            if settings.replacements.count > 5 {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(p.subtext)
                    TextField("Filter replacements", text: $replSearch)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5))
                        .foregroundStyle(p.text)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(p.card)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(p.border, lineWidth: 1))
            }
            CardGroup {
                if settings.replacements.isEmpty {
                    Text("No replacements yet — add a spoken phrase and what it should type.")
                        .font(.system(size: 12))
                        .foregroundStyle(p.subtext)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach($settings.replacements) { $item in
                        if replSearch.isEmpty
                            || item.phrase.localizedCaseInsensitiveContains(replSearch)
                            || item.replacement.localizedCaseInsensitiveContains(replSearch) {
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
                            if settings.showSnippetIndex,
                               let n = settings.replacementUsage[item.phrase], n > 0 {
                                Text("×\(n)")
                                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                    .foregroundStyle(p.subtext)
                            }
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
                }
                RowDivider()
                HStack(spacing: 14) {
                    Button {
                        settings.replacements.append(Replacement(phrase: "", replacement: ""))
                        if settings.autoSortReplacements { sortReplacements() }
                    } label: {
                        Label("Add Replacement", systemImage: "plus")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(settings.accentColor)
                    }
                    .buttonStyle(.borderless)
                    Button {
                        let clip = NSPasteboard.general.string(forType: .string) ?? ""
                        settings.replacements.append(Replacement(phrase: "", replacement: clip))
                    } label: {
                        Label("From Clipboard", systemImage: "doc.on.clipboard")
                            .font(.system(size: 11))
                            .foregroundStyle(p.subtext)
                    }
                    .buttonStyle(.borderless)
                    .help("New replacement with the clipboard as its text")
                    Spacer()
                    Menu("Sort") {
                        Button("A → Z") { sortReplacements() }
                        Button("Longest phrase first") {
                            settings.replacements.sort { $0.phrase.count > $1.phrase.count }
                        }
                        Button("Reverse order") { settings.replacements.reverse() }
                    }
                    .menuStyle(.borderlessButton).font(.system(size: 11)).fixedSize()
                    Menu("Enable") {
                        Button("Enable All") {
                            for i in settings.replacements.indices { settings.replacements[i].enabled = true }
                        }
                        Button("Disable All") {
                            for i in settings.replacements.indices { settings.replacements[i].enabled = false }
                        }
                        Divider()
                        Button("Remove Disabled") {
                            settings.replacements.removeAll { !$0.enabled }
                        }
                    }
                    .menuStyle(.borderlessButton).font(.system(size: 11)).fixedSize()
                    Menu("Export") {
                        Button("CSV…") { exportDictionary() }
                        Button("CSV (enabled only)…") { exportDictionary(enabledOnly: true) }
                        Button("JSON…") { exportDictionaryJSON() }
                        Button("Copy CSV to Clipboard") {
                            let esc: (String) -> String = { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
                            let rows = settings.replacements.map { "\(esc($0.phrase)),\(esc($0.replacement))" }
                            let pb = NSPasteboard.general
                            pb.clearContents()
                            pb.setString("phrase,replacement\n" + rows.joined(separator: "\n"), forType: .string)
                        }
                    }
                    .menuStyle(.borderlessButton).font(.system(size: 11)).fixedSize()
                    Menu("Import") {
                        Button("CSV File…") { importDictionary() }
                        Button("From Clipboard") { importDictionaryText(NSPasteboard.general.string(forType: .string) ?? "") }
                    }
                    .menuStyle(.borderlessButton).font(.system(size: 11)).fixedSize()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                RowDivider()
                Text(replacementsFooter)
                    .font(.system(size: 10.5))
                    .foregroundStyle(p.subtext)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            CardGroup {
                PRow(title: "Apply replacements",
                     subtitle: "Master switch — off leaves your list intact but unused") {
                    Toggle("", isOn: $settings.replacementsEnabled)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Case-sensitive matching",
                     subtitle: "Off = “My Email” matches “my email”") {
                    Toggle("", isOn: $settings.caseSensitiveReplacements)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Preserve spoken capitalization",
                     subtitle: "Spoken “My email” capitalizes the replacement too") {
                    Toggle("", isOn: $settings.preserveCaseReplacements)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Match inside words",
                     subtitle: "Off requires whole-word matches (recommended)") {
                    Toggle("", isOn: $settings.matchInsideWords)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Import replaces existing",
                     subtitle: "On = CSV import wipes the list first; off merges") {
                    Toggle("", isOn: $settings.importReplaces)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Regex phrases",
                     subtitle: "Phrases wrapped in /slashes/ match as regular expressions ($1 groups work)") {
                    Toggle("", isOn: $settings.regexReplacements)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Censor inside words",
                     subtitle: "Also masks the word when embedded in longer words") {
                    Toggle("", isOn: $settings.censorInsideWords)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Track replacement usage",
                     subtitle: "Count how often each phrase fires") {
                    Toggle("", isOn: $settings.trackReplacementUsage)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Show usage counts",
                     subtitle: "A ×N badge next to each replacement") {
                    Toggle("", isOn: $settings.showSnippetIndex)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Reset usage counts") {
                    Button("Reset") { settings.replacementUsage = [:] }
                        .controlSize(.small)
                }
                RowDivider()
                PRow(title: "Keep list alphabetized",
                     subtitle: "Re-sorts automatically as you add") {
                    Toggle("", isOn: $settings.autoSortReplacements)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                        .onChange(of: settings.autoSortReplacements) { _, on in
                            if on { sortReplacements() }
                        }
                }
                RowDivider()
                PRow(title: "Emoji voice commands",
                     subtitle: "“fire emoji”, “thumbs up”, “smiley face”…") {
                    Toggle("", isOn: $settings.emojiCommands)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Censor style") {
                    Picker("", selection: $settings.censorStyle) {
                        ForEach(CensorStyle.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 220)
                }
                RowDivider()
                PRow(title: "{date} format",
                     subtitle: "Also used for the “today's date” voice command") {
                    Picker("", selection: $settings.dateStyleChoice) {
                        ForEach(DateStyleChoice.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.menu).labelsHidden().fixedSize()
                }
            }

            SectionLabel(text: "Vocabulary")
                .padding(.top, 6)
            CardGroup {
                PRow(title: "Recognition hints",
                     subtitle: "Comma-separated names and jargon — no replacement, just better recognition") {
                    HStack(spacing: 6) {
                        TextField("Anthropic, Fable, Souza…", text: Binding(
                            get: { settings.vocabWords.joined(separator: ", ") },
                            set: { settings.vocabWords = $0.components(separatedBy: ",")
                                .map { $0.trimmingCharacters(in: .whitespaces) }
                                .filter { !$0.isEmpty } }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .frame(width: 220)
                        Button("Import .txt…") {
                            let panel = NSOpenPanel()
                            panel.allowsMultipleSelection = false
                            guard panel.runModal() == .OK, let url = panel.url,
                                  let content = try? String(contentsOf: url, encoding: .utf8) else { return }
                            let words = content.components(separatedBy: .newlines)
                                .map { $0.trimmingCharacters(in: .whitespaces) }
                                .filter { !$0.isEmpty }
                            settings.vocabWords = Array(Set(settings.vocabWords + words)).sorted()
                        }
                        .controlSize(.small)
                    }
                }
                RowDivider()
                PRow(title: "Auto-learn vocabulary",
                     subtitle: "Recurring names & jargon you dictate get added here automatically") {
                    Toggle("", isOn: $settings.autoLearnVocab)
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
                    HStack {
                        Toggle("Full pipeline", isOn: $fullPipelineTest)
                            .font(.system(size: 11))
                            .foregroundStyle(p.subtext)
                            .controlSize(.small)
                            .help("Also runs fillers, capitalization, punctuation, numbers, and censoring")
                        Spacer()
                        if !testInput.isEmpty {
                            Button("Copy Result") {
                                let pb = NSPasteboard.general
                                pb.clearContents()
                                pb.setString(testResult, forType: .string)
                            }
                            .controlSize(.small)
                        }
                    }
                    if !testInput.isEmpty {
                        Text(testResult)
                            .font(.system(size: 12))
                            .foregroundStyle(settings.accentColor)
                            .textSelection(.enabled)
                        if !firedRules.isEmpty {
                            Text("Matched: \(firedRules.joined(separator: ", "))")
                                .font(.system(size: 10.5))
                                .foregroundStyle(p.subtext)
                        }
                    }
                }
                .padding(14)
            }

            CardGroup {
                DisclosureGroup {
                    Text(Self.commandReference)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(p.subtext)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                } label: {
                    Text("All voice commands")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(p.text)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
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
                    HStack(spacing: 6) {
                        TextField("um, uh, like…", text: Binding(
                            get: { settings.fillerWords.joined(separator: ", ") },
                            set: { settings.fillerWords = $0.components(separatedBy: ",")
                                .map { $0.trimmingCharacters(in: .whitespaces) } }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .frame(width: 240)
                        Menu("Presets") {
                            Button("Minimal (um, uh)") {
                                settings.fillerWords = ["um", "uh"]
                            }
                            Button("Standard") {
                                settings.fillerWords = ["um", "uh", "uhm", "erm", "er", "you know like"]
                            }
                            Button("Aggressive") {
                                settings.fillerWords = ["um", "uh", "uhm", "erm", "er", "like",
                                                        "you know", "sort of", "kind of", "I mean"]
                            }
                        }
                        .menuStyle(.borderlessButton).fixedSize().controlSize(.small)
                    }
                }
                RowDivider()
                PRow(title: "Starter words",
                     subtitle: "Stripped from the beginning when the toggle is on") {
                    TextField("so, well, okay…", text: Binding(
                        get: { settings.starterWords.joined(separator: ", ") },
                        set: { settings.starterWords = $0.components(separatedBy: ",")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty } }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .frame(width: 240)
                }
                RowDivider()
                PRow(title: "Doubled-word exceptions",
                     subtitle: "Words allowed to repeat (“very very”)") {
                    TextField("very, really", text: Binding(
                        get: { settings.doubledWhitelist.joined(separator: ", ") },
                        set: { settings.doubledWhitelist = $0.components(separatedBy: ",")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty } }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .frame(width: 240)
                }
                RowDivider()
                PRow(title: "Censor words",
                     subtitle: "Comma-separated — typed as d*** instead of the word") {
                    TextField("none", text: Binding(
                        get: { settings.censorWords.joined(separator: ", ") },
                        set: { settings.censorWords = $0.components(separatedBy: ",")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty } }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .frame(width: 240)
                }
            }

            Text("Per-app behavior — tones, grammar fixes, polish voices, and languages — lives in the Apps tab.")
                .font(.system(size: 11))
                .foregroundStyle(p.subtext)
                .padding(.horizontal, 2)
                .padding(.top, 6)
        }
    }
}

// MARK: - Apps pane

/// Per-app behavior: each rule is a card — grammar fixing, a polish voice,
/// tone, case, language, and blocking, applied whenever you dictate into a
/// matching app.
struct AppsPane: View {
    @ObservedObject var settings: AppSettings
    @Environment(\.colorScheme) private var scheme

    /// Names of regular running apps, for one-click rule creation.
    private var runningAppNames: [String] {
        let existing = Set(settings.appRules.map { $0.appName.lowercased() })
        return Array(Set(
            NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular }
                .compactMap(\.localizedName)
        ))
        .filter { $0 != "Murmur" && !existing.contains($0.lowercased()) }
        .sorted()
    }

    var body: some View {
        let p = Palette.of(scheme)
        Pane(title: "Apps",
             subtitle: "Murmur can talk differently in every app.") {
            if settings.appRules.isEmpty {
                CardGroup {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No app rules yet")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(p.text)
                        Text("Add an app below and Murmur will adapt whenever you dictate into it — fix grammar in Mail, go casual with emojis in Slack, switch language in WhatsApp, or block dictation entirely in your password manager.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(p.subtext)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            ForEach($settings.appRules) { $rule in
                SectionLabel(text: rule.appName.isEmpty ? "New rule" : rule.appName)
                    .padding(.top, 6)
                CardGroup {
                    PRow(title: "App",
                         subtitle: "Matches when the frontmost app's name contains this") {
                        HStack(spacing: 8) {
                            TextField("e.g. Mail", text: $rule.appName)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12))
                                .frame(width: 150)
                            Button {
                                settings.appRules.removeAll { $0.id == rule.id }
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 11))
                                    .foregroundStyle(p.subtext)
                            }
                            .buttonStyle(.borderless)
                            .help("Remove this rule")
                        }
                    }
                    RowDivider()
                    PRow(title: "Fix grammar",
                         subtitle: "AI corrects grammar, spelling, and punctuation here — wording stays yours") {
                        Toggle("", isOn: Binding(
                            get: { rule.grammar ?? false },
                            set: { rule.grammar = $0 }
                        ))
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                    }
                    RowDivider()
                    PRow(title: "Polish voice",
                         subtitle: "How Claude writes in this app — overrides the tone") {
                        TextField("e.g. Casual with emojis", text: $rule.customPrompt)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                            .frame(width: 220)
                    }
                    RowDivider()
                    PRow(title: "Tone") {
                        Picker("", selection: $rule.tone) {
                            ForEach(PolishTone.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 250)
                    }
                    RowDivider()
                    PRow(title: "AI polish") {
                        Picker("", selection: $rule.polish) {
                            Text("Auto").tag(Bool?.none)
                            Text("On").tag(Bool?.some(true))
                            Text("Off").tag(Bool?.some(false))
                        }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 180)
                    }
                    RowDivider()
                    PRow(title: "Output case") {
                        Picker("", selection: $rule.ocase) {
                            ForEach(OutputCase.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 250)
                    }
                    RowDivider()
                    PRow(title: "Language",
                         subtitle: "Recognition language just for this app") {
                        Picker("", selection: $rule.localeID) {
                            Text("Auto").tag(String?.none)
                            ForEach(GeneralPane.languages, id: \.0) { id, name in
                                Text(GeneralPane.onDeviceLocales.contains(id) ? name : "\(name)  ☁︎")
                                    .tag(String?.some(id))
                            }
                        }
                        .pickerStyle(.menu).labelsHidden().frame(width: 130)
                    }
                    RowDivider()
                    PRow(title: "Block Murmur here",
                         subtitle: "The hotkey does nothing while this app is frontmost") {
                        Toggle("", isOn: $rule.blocked)
                            .toggleStyle(.switch).labelsHidden().controlSize(.small)
                    }
                    if let stats = settings.appWords.first(where: {
                        !rule.appName.isEmpty
                            && $0.key.localizedCaseInsensitiveContains(rule.appName)
                    }) {
                        RowDivider()
                        Text("\(stats.value.formatted()) words dictated into \(stats.key)")
                            .font(.system(size: 10.5))
                            .foregroundStyle(p.subtext)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    }
                }
            }

            HStack(spacing: 12) {
                Button {
                    settings.appRules.append(AppRule(appName: ""))
                } label: {
                    Label("Add App Rule", systemImage: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(settings.accentColor)
                }
                .buttonStyle(.borderless)
                if !runningAppNames.isEmpty {
                    Menu("Add Running App") {
                        ForEach(runningAppNames, id: \.self) { name in
                            Button(name) {
                                settings.appRules.append(AppRule(appName: name))
                            }
                        }
                    }
                    .menuStyle(.borderlessButton).font(.system(size: 12)).fixedSize()
                }
                Spacer()
            }
            .padding(.top, 6)
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
    @State private var suppressRegen = false
    @State private var subTab = 0   // 0 = Skins, 1 = Pill & Window
    @StateObject private var previewState = AppearancePane.makePreviewState()
    private let timer = Timer.publish(every: 0.09, on: .main, in: .common).autoconnect()
    @State private var t: Double = 0

    var body: some View {
        let p = Palette.of(scheme)
        VStack(spacing: 0) {
        Pane(title: "Appearance",
             subtitle: "Make the dictation pill yours.") {
            Picker("", selection: $subTab) {
                Text("Skins (\(AppSkin.allCases.count))").tag(0)
                Text("Pill & Window").tag(1)
            }
            .pickerStyle(.segmented).labelsHidden()

            if subTab == 0 {
            SectionLabel(text: "Skin")
                .padding(.top, 6)
            CardGroup {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                          spacing: 8) {
                    ForEach(AppSkin.allCases) { s in
                        skinChip(s)
                    }
                }
                .padding(12)
            }

            if settings.skin == .custom {
                skinStudio(p)
            }

            SectionLabel(text: "Accent")
                .padding(.top, 6)
            CardGroup {
                PRow(title: "Use system accent",
                     subtitle: "Follow the accent from System Settings ▸ Appearance") {
                    Toggle("", isOn: $settings.useSystemAccent)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                if !settings.useSystemAccent {
                RowDivider()
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
            }
            } else {

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
                PRow(title: "Monochrome waveform",
                     subtitle: "Ink-colored bars instead of the accent gradient") {
                    Toggle("", isOn: $settings.waveMonochrome)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Bar width") {
                    Slider(value: $settings.barWidth, in: 2...5)
                        .frame(width: 130).controlSize(.small)
                }
                RowDivider()
                PRow(title: "Bar spacing") {
                    Slider(value: $settings.barSpacing, in: 1.5...5)
                        .frame(width: 130).controlSize(.small)
                }
                RowDivider()
                PRow(title: "Square bars",
                     subtitle: "Hard-edged waveform bars") {
                    Toggle("", isOn: $settings.squareBars)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Waveform height") {
                    Slider(value: $settings.waveHeight, in: 24...52)
                        .frame(width: 130).controlSize(.small)
                }
                RowDivider()
                PRow(title: "Show waveform",
                     subtitle: "Off = text-only pill") {
                    Toggle("", isOn: $settings.showWaveform)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Status indicator",
                     subtitle: "What shows while listening") {
                    Picker("", selection: $settings.statusDotStyle) {
                        ForEach(StatusDotStyle.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 180)
                }
                RowDivider()
                PRow(title: "Custom status symbol",
                     subtitle: "SF Symbol name — overrides the indicator above") {
                    TextField("waveform.circle", text: $settings.statusSymbolName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 140)
                }
                RowDivider()
                PRow(title: "Done checkmark color") {
                    Picker("", selection: $settings.doneAccent) {
                        Text("Green").tag(false)
                        Text("Accent").tag(true)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 150)
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
                PRow(title: "Idle dot size") {
                    Picker("", selection: $settings.idleDotSize) {
                        ForEach(IdleDotSize.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 200)
                }
                RowDivider()
                PRow(title: "Idle dot opacity") {
                    Slider(value: $settings.idleDotOpacity, in: 0.2...1.0)
                        .frame(width: 130).controlSize(.small)
                }
                RowDivider()
                PRow(title: "Idle dot color") {
                    Picker("", selection: $settings.idleDotColor) {
                        ForEach(IdleDotColor.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 140)
                }
                RowDivider()
                PRow(title: "Idle dot position",
                     subtitle: "Own alignment, separate from the pill") {
                    Picker("", selection: $settings.idleDotAlignment) {
                        ForEach(PillAlignment.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 200)
                }
                RowDivider()
                PRow(title: "Idle dot breathing",
                     subtitle: "Gentle pulse so you know Murmur's alive") {
                    Toggle("", isOn: $settings.idleDotPulse)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Show elapsed timer",
                     subtitle: "Running mm:ss while you dictate") {
                    Toggle("", isOn: $settings.showPillTimer)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Text size") {
                    HStack(spacing: 8) {
                        Slider(value: $settings.pillTextSize, in: 12...18, step: 1)
                            .frame(width: 130).controlSize(.small)
                        Text("\(Int(settings.pillTextSize))pt")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(p.subtext)
                            .frame(width: 32, alignment: .trailing)
                    }
                }
                RowDivider()
                PRow(title: "Text weight") {
                    Picker("", selection: $settings.pillFontWeight) {
                        ForEach(PillFontWeight.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 230)
                }
                RowDivider()
                PRow(title: "Text color",
                     subtitle: "Auto follows the pill theme") {
                    Picker("", selection: $settings.pillTextColor) {
                        ForEach(PillTextColor.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 180)
                }
                RowDivider()
                PRow(title: "UPPERCASE display",
                     subtitle: "Pill text only — what's typed is untouched") {
                    Toggle("", isOn: $settings.uppercasePill)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Italic text") {
                    Toggle("", isOn: $settings.pillItalic)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Center transcript") {
                    Toggle("", isOn: $settings.transcriptCentered)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Typing cursor",
                     subtitle: "A ▎ marker at the end of the live transcript") {
                    Toggle("", isOn: $settings.pillCursor)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Pill padding") {
                    Slider(value: $settings.pillPadding, in: 14...34)
                        .frame(width: 130).controlSize(.small)
                }
                RowDivider()
                PRow(title: "Minimum text width") {
                    Slider(value: $settings.pillMinWidth, in: 60...220)
                        .frame(width: 130).controlSize(.small)
                }
                RowDivider()
                PRow(title: "Vertical offset",
                     subtitle: "Nudge the pill up from the screen edge") {
                    Slider(value: $settings.pillOffsetY, in: 0...200)
                        .frame(width: 130).controlSize(.small)
                }
                RowDivider()
                PRow(title: "Entrance scale",
                     subtitle: "How small the pill starts before it springs in") {
                    Slider(value: $settings.pillAppearScale, in: 0.5...1.0)
                        .frame(width: 130).controlSize(.small)
                }
                RowDivider()
                PRow(title: "Mirror waveform",
                     subtitle: "Bars grow from the centerline both ways") {
                    Toggle("", isOn: $settings.waveMirror)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Monospace transcript") {
                    Toggle("", isOn: $settings.monospaceTranscript)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Word-count badge",
                     subtitle: "The little “7w” pill while dictating") {
                    Toggle("", isOn: $settings.wordCountBadge)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Dim idle dot",
                     subtitle: "Extra-faint resting dot") {
                    Toggle("", isOn: $settings.dimWhenIdle)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Gradient waveform",
                     subtitle: "Blend the accent into a second hue") {
                    Toggle("", isOn: $settings.accentGradient)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                if settings.accentGradient {
                    RowDivider()
                    PRow(title: "Second hue") {
                        Slider(value: $settings.accentHue2, in: 0...1)
                            .frame(width: 130).controlSize(.small)
                    }
                }
                RowDivider()
                PRow(title: "Listening label",
                     subtitle: "Custom placeholder text (empty = default)") {
                    TextField("Listening…", text: $settings.listeningLabel)
                        .textFieldStyle(.roundedBorder).font(.system(size: 12)).frame(width: 180)
                }
                RowDivider()
                PRow(title: "Processing label") {
                    TextField("Polishing…", text: $settings.processingLabel)
                        .textFieldStyle(.roundedBorder).font(.system(size: 12)).frame(width: 180)
                }
                RowDivider()
                PRow(title: "Done label") {
                    TextField("Inserted ✓", text: $settings.doneLabel)
                        .textFieldStyle(.roundedBorder).font(.system(size: 12)).frame(width: 180)
                }
                RowDivider()
                PRow(title: "Solid border",
                     subtitle: "Even accent border instead of the gradient sweep") {
                    Toggle("", isOn: Binding(get: { !settings.borderGradient },
                                             set: { settings.borderGradient = !$0 }))
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Glow color",
                     subtitle: "Hex override — empty follows the accent") {
                    TextField("#FF9500", text: $settings.glowColorHex)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 100)
                }
                RowDivider()
                PRow(title: "Timer format") {
                    Picker("", selection: $settings.timerFormat) {
                        ForEach(TimerFormat.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 140)
                }
                RowDivider()
                PRow(title: "Custom background",
                     subtitle: "Hex color for the classic pill — empty = default") {
                    TextField("#1A1A2E", text: $settings.pillBgHex)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 100)
                }
                RowDivider()
                PRow(title: "Shadow strength") {
                    Slider(value: $settings.shadowStrength, in: 0...2)
                        .frame(width: 130).controlSize(.small)
                }
                RowDivider()
                PRow(title: "Horizontal nudge",
                     subtitle: "Shift the pill left or right of its alignment") {
                    Slider(value: $settings.pillNudge, in: -200...200)
                        .frame(width: 130).controlSize(.small)
                }
                RowDivider()
                PRow(title: "Entrance animation") {
                    Picker("", selection: $settings.entranceAnim) {
                        ForEach(EntranceAnim.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 190)
                }
                RowDivider()
                PRow(title: "Linger after insert",
                     subtitle: "How long “Inserted ✓” stays up") {
                    HStack(spacing: 8) {
                        Slider(value: $settings.doneLinger, in: 0.5...3)
                            .frame(width: 110).controlSize(.small)
                        Text(String(format: "%.1fs", settings.doneLinger))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(p.subtext)
                            .frame(width: 36, alignment: .trailing)
                    }
                }
                RowDivider()
                PRow(title: "Transcript width",
                     subtitle: "How much text shows before it scrolls") {
                    Slider(value: $settings.transcriptWidth, in: 200...400)
                        .frame(width: 130).controlSize(.small)
                }
                RowDivider()
                PRow(title: "Show target app icon",
                     subtitle: "The app you're dictating into, next to the waveform") {
                    Toggle("", isOn: $settings.showTargetIcon)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Tap pill to finish",
                     subtitle: "Click the pill to insert — like tapping the hotkey") {
                    Toggle("", isOn: $settings.pillClickToFinish)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Show pill while dictating",
                     subtitle: "Off = invisible dictation, sound cues only") {
                    Toggle("", isOn: $settings.showPillWhileRecording)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Display",
                     subtitle: "Which screen the pill appears on") {
                    Picker("", selection: $settings.pillScreen) {
                        ForEach(PillScreen.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 210)
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
                RowDivider()
                PRow(title: "Custom SF Symbol",
                     subtitle: "Any symbol name overrides the icon — empty = picker above") {
                    TextField("waveform.circle", text: $settings.menuSymbolName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 150)
                }
            }

            SectionLabel(text: "App window")
                .padding(.top, 6)
            CardGroup {
                PRow(title: "Filled sidebar icons") {
                    Toggle("", isOn: $settings.sidebarFilledIcons)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Compact sidebar") {
                    Toggle("", isOn: $settings.sidebarCompact)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Accent bar on selected tab",
                     subtitle: "A colored rail beside the active sidebar item") {
                    Toggle("", isOn: $settings.sidebarAccentBar)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Hide sidebar stats") {
                    Toggle("", isOn: $settings.hideSidebarStats)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Keep settings on top",
                     subtitle: "Window floats above other apps") {
                    Toggle("", isOn: $settings.settingsAlwaysOnTop)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                        .onChange(of: settings.settingsAlwaysOnTop) { _, _ in
                            SettingsWindowController.shared.show()
                        }
                }
                RowDivider()
                PRow(title: "Tint controls with accent",
                     subtitle: "Toggles and pickers wear your accent color") {
                    Toggle("", isOn: $settings.accentTintControls)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Live preview bar",
                     subtitle: "The pill preview pinned below this pane") {
                    Toggle("", isOn: $settings.showLivePreviewBar)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Preview shows last transcript",
                     subtitle: "Instead of the sample sentence") {
                    Toggle("", isOn: $settings.previewUsesHistory)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Preview sentence",
                     subtitle: "Custom text for the preview pill") {
                    TextField("This is what your dictation looks like", text: $settings.previewSampleText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .frame(width: 240)
                }
                RowDivider()
                PRow(title: "Animated background",
                     subtitle: "A slow drifting accent glow behind the settings") {
                    Toggle("", isOn: $settings.animatedGradientBg)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Rotate skin daily",
                     subtitle: "A different skin each day at launch") {
                    Toggle("", isOn: $settings.skinAutoRotate)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Frosted pill",
                     subtitle: "Blur whatever's behind the classic pill") {
                    Toggle("", isOn: $settings.pillBlur)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                RowDivider()
                PRow(title: "Feeling lucky") {
                    Button("Surprise Me 🎲") {
                        settings.skin = AppSkin.allCases.filter { $0 != settings.skin && $0 != .custom }
                            .randomElement() ?? .clean
                    }
                    .controlSize(.small)
                }
            }
            }

        }
        if settings.showLivePreviewBar { pinnedPreview(p) }
        }
        .onReceive(timer) { _ in
            t += 0.35
            let level = Float(0.25 + 0.55 * abs(sin(t)) * Double.random(in: 0.55...1.0))
            previewState.pushLevel(level)
            let sample = settings.previewSampleText.trimmingCharacters(in: .whitespaces)
            var wanted = sample.isEmpty ? "This is what your dictation looks like" : sample
            if settings.previewUsesHistory, let last = settings.history.first?.text, !last.isEmpty {
                wanted = last
            }
            if previewState.text != wanted { previewState.text = wanted }
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

    /// The Skin Studio: theme-wheel generator up top, then every color
    /// individually editable. The wheel (or a Base flip) regenerates the
    /// whole set; the pickers fine-tune from there.
    @ViewBuilder
    private func skinStudio(_ p: Palette) -> some View {
        let g = AppSettings.generatedCustomColors(hue: settings.customSkinHue,
                                                  sat: settings.customSkinSat,
                                                  dark: settings.customSkinDark)
        SectionLabel(text: "Skin studio")
            .padding(.top, 6)
        CardGroup {
            PRow(title: "Base",
                 subtitle: "Switching regenerates the colors below") {
                Picker("", selection: $settings.customSkinDark) {
                    Text("Dark").tag(true)
                    Text("Light").tag(false)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 140)
            }
            RowDivider()
            HStack(alignment: .center, spacing: 24) {
                ColorWheel(hue: $settings.customSkinHue,
                           sat: $settings.customSkinSat, size: 120)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Theme color")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(p.subtext)
                    Text("Drag to generate a matching set of colors below, then fine-tune any of them individually.")
                        .font(.system(size: 11))
                        .foregroundStyle(p.subtext)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(16)
            RowDivider()
            studioColorRow("Background", \.customBgHex, fallback: g.bg)
            RowDivider()
            studioColorRow("Sidebar", \.customSidebarHex, fallback: g.sidebar)
            RowDivider()
            studioColorRow("Cards", \.customCardHex, fallback: g.card)
            RowDivider()
            studioColorRow("Text", \.customTextHex, fallback: g.text)
            RowDivider()
            studioColorRow("Secondary text", \.customSubtextHex, fallback: g.subtext)
            RowDivider()
            studioColorRow("Accent ink", \.customInkHex, fallback: g.ink,
                           subtitle: "Borders, pill outline, and glow")
            RowDivider()
            studioColorRow("Pill background", \.customPillBgHex, fallback: g.pillBg)
            RowDivider()
            PRow(title: "Typeface") {
                Picker("", selection: $settings.customSkinFont) {
                    ForEach(CustomSkinFont.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu).labelsHidden().frame(width: 110)
            }
            RowDivider()
            PRow(title: "Pill shape") {
                Picker("", selection: $settings.customSkinShape) {
                    ForEach(PillCorner.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 200)
            }
            RowDivider()
            HStack {
                Button("Regenerate from Theme Color") { settings.generateCustomSkin() }
                    .controlSize(.small)
                Spacer()
                Button("Copy Skin Code") {
                    let s = settings
                    let code = "murmur-skin:1:\(s.customSkinDark ? "d" : "l"):"
                        + [s.customBgHex, s.customSidebarHex, s.customCardHex, s.customTextHex,
                           s.customSubtextHex, s.customInkHex, s.customPillBgHex,
                           s.customSkinFont.rawValue, s.customSkinShape.rawValue]
                            .joined(separator: ":")
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(code, forType: .string)
                }
                .controlSize(.small)
                .help("Share your skin — friends paste it with Import")
                Button("Import from Clipboard") {
                    guard let code = NSPasteboard.general.string(forType: .string) else { return }
                    let parts = code.components(separatedBy: ":")
                    guard parts.count >= 12, parts[0] == "murmur-skin", parts[1] == "1" else { return }
                    suppressRegen = true // don't let the Base flip wipe the imported colors
                    settings.customSkinDark = parts[2] == "d"
                    settings.customBgHex = parts[3]
                    settings.customSidebarHex = parts[4]
                    settings.customCardHex = parts[5]
                    settings.customTextHex = parts[6]
                    settings.customSubtextHex = parts[7]
                    settings.customInkHex = parts[8]
                    settings.customPillBgHex = parts[9]
                    settings.customSkinFont = CustomSkinFont(rawValue: parts[10]) ?? .system
                    settings.customSkinShape = PillCorner(rawValue: parts[11]) ?? .capsule
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .onChange(of: settings.customSkinHue) { _, _ in settings.generateCustomSkin() }
        .onChange(of: settings.customSkinSat) { _, _ in settings.generateCustomSkin() }
        .onChange(of: settings.customSkinDark) { _, _ in
            if suppressRegen { suppressRegen = false } else { settings.generateCustomSkin() }
        }
    }

    private func studioColorRow(_ title: String,
                                _ keyPath: ReferenceWritableKeyPath<AppSettings, String>,
                                fallback: Color, subtitle: String? = nil) -> some View {
        PRow(title: title, subtitle: subtitle) {
            HStack(spacing: 8) {
                ColorPicker("", selection: Binding(
                    get: { AppSettings.parseHex(settings[keyPath: keyPath]) ?? fallback },
                    set: { settings[keyPath: keyPath] = AppSettings.hexString($0) }
                ), supportsOpacity: false)
                .labelsHidden()
                Text(settings[keyPath: keyPath].isEmpty
                     ? AppSettings.hexString(fallback)
                     : settings[keyPath: keyPath])
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Palette.of(scheme).subtext)
                    .frame(width: 62, alignment: .trailing)
            }
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
                } else if s != .clean, s != .sketch {
                    // Mini palette preview: background, card, and ink dots.
                    let sp = Palette.of(scheme, skin: s)
                    let inkDot: Color = s.spec?.ink ?? sp.text
                    HStack(spacing: 2.5) {
                        ForEach(Array([sp.bg, sp.card, inkDot].enumerated()), id: \.offset) { _, c in
                            Circle()
                                .fill(c)
                                .frame(width: 7, height: 7)
                                .overlay(Circle().strokeBorder(p.border, lineWidth: 0.5))
                        }
                    }
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
    @State private var period = 0   // 0=all time 1=30 days 2=7 days
    @State private var selectedBadge: Achievement?

    /// Days in the selected period, or nil for all-time.
    private var periodDays: Int? { period == 1 ? 30 : (period == 2 ? 7 : nil) }

    private func wordsInPeriod() -> Int {
        guard let days = periodDays else { return settings.totalWords }
        let cal = Calendar.current
        return (0..<days).reduce(0) { total, offset in
            let day = cal.date(byAdding: .day, value: -offset, to: Date()) ?? Date()
            return total + (settings.dailyWords[AppSettings.dayKey(day)] ?? 0)
        }
    }

    private func periodDayCounts() -> [Int] {
        let cal = Calendar.current
        let days = periodDays ?? settings.dailyWords.count
        guard periodDays != nil else { return settings.dailyWords.values.map { $0 } }
        return (0..<days).map { offset in
            let day = cal.date(byAdding: .day, value: -offset, to: Date()) ?? Date()
            return settings.dailyWords[AppSettings.dayKey(day)] ?? 0
        }
    }

    var body: some View {
        let p = Palette.of(scheme)
        Pane(title: "Stats",
             subtitle: settings.todayWords > 0
                ? "Your dictation life in numbers · \(settings.todayWords.formatted()) words today."
                : "Your dictation life in numbers.") {
            Picker("", selection: $period) {
                Text("All Time").tag(0)
                Text("30 Days").tag(1)
                Text("7 Days").tag(2)
            }
            .pickerStyle(.segmented).labelsHidden()

            tilesGrid

            if let ms = settings.nextMilestone() {
                Text("Next badge: \(ms.name) — \(ms.remaining.formatted()) words to go (≈\(ms.days) active days at your pace)")
                    .font(.system(size: 11))
                    .foregroundStyle(p.subtext)
                    .padding(.horizontal, 2)
            }

            goalsSection(p)
            chartSection(p)
            heatmapSection(p)
            hourSection(p)
            appsSection(p)
            badgesSection(p)

            HStack(spacing: 10) {
                Menu("Copy") {
                    Button("Summary") { copyStatsSummary() }
                    Button("Markdown Table") { copyStatsMarkdown() }
                    Button("Badge List") {
                        let text = Achievement.all.map { a in
                            let mark = settings.earned[a.id] != nil ? "🏆" : "🔒"
                            return "\(mark) \(a.name) — \(a.desc)"
                        }.joined(separator: "\n")
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(text, forType: .string)
                    }
                }
                .menuStyle(.borderlessButton).font(.system(size: 12)).fixedSize()
                Button("Save Summary…") { saveStatsSummary() }
                    .buttonStyle(.borderless).font(.system(size: 12)).foregroundStyle(p.subtext)
                Menu("Export CSV") {
                    Button("Activity (30 days)…") { exportActivityCSV() }
                    Button("Activity (all time)…") { exportActivityCSV(allTime: true) }
                    Button("Achievements…") { exportAchievementsCSV() }
                }
                .menuStyle(.borderlessButton).font(.system(size: 12)).fixedSize()
                Spacer()
                Button("Reset Charts…") { confirmResetCharts() }
                    .buttonStyle(.borderless).font(.system(size: 12)).foregroundStyle(p.subtext)
                Button("Reset Badges…") { confirmResetBadges() }
                    .buttonStyle(.borderless).font(.system(size: 12)).foregroundStyle(p.subtext)
                Button("Reset Stats…") { confirmResetStats() }
                    .buttonStyle(.borderless).font(.system(size: 12)).foregroundStyle(.red.opacity(0.8))
            }
        }
    }

    private var tilesGrid: some View {
        let counts = periodDayCounts()
        let active = counts.filter { $0 > 0 }.count
        let words = wordsInPeriod()
        let avgActive = active > 0 ? words / active : 0
        let best = counts.max() ?? 0
        let avgSess = settings.totalSessions > 0 ? settings.totalWords / settings.totalSessions : 0
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
                         spacing: 10) {
            statTile("Words", words.formatted())
            statTile("Sessions", settings.totalSessions.formatted())
            statTile("Avg / session", "\(avgSess)")
            statTile("Best day", "\(best)")
            statTile("Best day was", bestDayDateLabel)
            statTile("Streak", "\(settings.streak())d")
            statTile("Longest streak", "\(settings.maxStreak)d")
            statTile("Goal streak", settings.dailyGoal > 0 ? "\(settings.goalStreak())d" : "—")
            statTile("Min saved", String(format: "%.0f", settings.minutesSaved),
                     help: "Assumes ~40 wpm typing vs ~150 wpm speaking")
            statTile("Badges", "\(settings.earned.count)/\(Achievement.all.count)")
            statTile("This week", "\(settings.wordsInWeek(endingDaysAgo: 0))")
            statTile("Last week", "\(settings.wordsInWeek(endingDaysAgo: 7))")
            statTile("Active days", "\(active)")
            statTile("Avg / active day", "\(avgActive)")
            statTile("Speaking WPM", settings.wordsPerMinute > 0 ? "\(settings.wordsPerMinute)" : "—")
            statTile("Time spoken", speakTimeLabel)
            statTile("Characters", settings.totalChars.formatted())
            statTile("Longest session", settings.maxSessionWords > 0 ? "\(settings.maxSessionWords)w" : "—")
            statTile("Sessions today", "\(settings.dailySessions[AppSettings.dayKey(Date())] ?? 0)")
            statTile("Commands used", "\(settings.commandsUsed)")
            statTile("Polished", "\(settings.polishedCount)")
            statTile("Polish rate", settings.totalSessions > 0
                     ? "\(settings.polishedCount * 100 / settings.totalSessions)%" : "—")
            statTile("Avg session", avgSessionLabel)
            statTile("Best hour", bestHourLabel)
            statTile("Trend", trendLabel, help: "This week vs last week")
            statTile("Median session", medianSessionLabel)
            statTile("Sessions / day", sessionsPerDayLabel)
            statTile("Saved this week",
                     String(format: "%.0fm", Double(settings.wordsInWeek(endingDaysAgo: 0)) * (1.0 / 40.0 - 1.0 / 150.0)))
            statTile("Longest transcript", longestTranscriptLabel)
            statTile("Apps used", "\(settings.appWords.count)")
        }
    }

    private var bestHourLabel: String {
        guard let best = settings.hourCounts.max(by: { $0.value < $1.value }),
              best.value > 0, let h = Int(best.key) else { return "—" }
        let ampm = h == 0 ? "12a" : h < 12 ? "\(h)a" : h == 12 ? "12p" : "\(h - 12)p"
        return ampm
    }

    private var trendLabel: String {
        let this = settings.wordsInWeek(endingDaysAgo: 0)
        let last = settings.wordsInWeek(endingDaysAgo: 7)
        guard last > 0 else { return this > 0 ? "↑ new" : "—" }
        let pct = (this - last) * 100 / last
        return pct >= 0 ? "↑ \(pct)%" : "↓ \(-pct)%"
    }

    private var medianSessionLabel: String {
        let counts = settings.history.map { $0.text.split(whereSeparator: \.isWhitespace).count }.sorted()
        guard !counts.isEmpty else { return "—" }
        return "\(counts[counts.count / 2])w"
    }

    private var sessionsPerDayLabel: String {
        let days = settings.dailySessions.values.filter { $0 > 0 }
        guard !days.isEmpty else { return "—" }
        return String(format: "%.1f", Double(days.reduce(0, +)) / Double(days.count))
    }

    private var longestTranscriptLabel: String {
        let most = settings.history.map { $0.text.split(whereSeparator: \.isWhitespace).count }.max() ?? 0
        return most > 0 ? "\(most)w" : "—"
    }

    private var bestDayDateLabel: String {
        guard let key = settings.bestDayKey, (settings.dailyWords[key] ?? 0) > 0 else { return "—" }
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        guard let date = df.date(from: key) else { return "—" }
        let out = DateFormatter(); out.dateFormat = "MMM d"
        return out.string(from: date)
    }

    @ViewBuilder
    private func goalsSection(_ p: Palette) -> some View {
        SectionLabel(text: "Goals")
            .padding(.top, 6)
        CardGroup {
            PRow(title: "Weekly word goal",
                 subtitle: "Separate from the daily goal") {
                Picker("", selection: $settings.weeklyGoal) {
                    Text("Off").tag(0)
                    ForEach([1000, 2500, 5000, 10000], id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.menu).labelsHidden().frame(width: 90)
            }
            RowDivider()
            PRow(title: "Speaking-pace goal",
                 subtitle: "Target words per minute — shown against your actual pace") {
                Picker("", selection: $settings.wpmGoal) {
                    Text("Off").tag(0)
                    ForEach([100, 130, 150, 180], id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.menu).labelsHidden().frame(width: 90)
            }
            if settings.wpmGoal > 0, settings.wordsPerMinute > 0 {
                RowDivider()
                let diff = settings.wordsPerMinute - settings.wpmGoal
                Text(diff >= 0
                     ? "You're \(diff) WPM above your \(settings.wpmGoal) goal 🏎"
                     : "\(-diff) WPM to reach your \(settings.wpmGoal) goal")
                    .font(.system(size: 11)).foregroundStyle(p.subtext)
                    .padding(.horizontal, 16).padding(.vertical, 10)
            }
            if settings.weeklyGoal > 0 {
                RowDivider()
                let done = settings.wordsInWeek(endingDaysAgo: 0)
                let frac = min(1, Double(done) / Double(settings.weeklyGoal))
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(done.formatted()) / \(settings.weeklyGoal.formatted()) words this week")
                        .font(.system(size: 11))
                        .foregroundStyle(p.subtext)
                    Capsule().fill(p.border).frame(height: 5)
                        .overlay(alignment: .leading) {
                            GeometryReader { geo in
                                Capsule().fill(settings.accentColor)
                                    .frame(width: max(frac > 0 ? 5 : 0, geo.size.width * frac))
                            }
                        }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            if settings.maxStreak > 0, settings.streak() < settings.maxStreak {
                RowDivider()
                Text("🔥 \(settings.streak())d streak — \(settings.maxStreak - settings.streak()) more to tie your record")
                    .font(.system(size: 11))
                    .foregroundStyle(p.subtext)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
            if settings.dailyGoal > 0 {
                RowDivider()
                let goalDays = (0..<7).filter { offset in
                    let day = Calendar.current.date(byAdding: .day, value: -offset, to: Date()) ?? Date()
                    return (settings.dailyWords[AppSettings.dayKey(day)] ?? 0) >= settings.dailyGoal
                }.count
                Text("🎯 Goal hit \(goalDays)/7 days this week\(goalDays == 7 ? " — perfect week!" : "")")
                    .font(.system(size: 11))
                    .foregroundStyle(p.subtext)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
            RowDivider()
            PRow(title: "Custom milestone",
                 subtitle: "Your own target — progress shows below") {
                Picker("", selection: $settings.customMilestone) {
                    Text("Off").tag(0)
                    ForEach([5000, 25000, 50000, 100_000], id: \.self) { Text($0.formatted()).tag($0) }
                }
                .pickerStyle(.menu).labelsHidden().frame(width: 100)
            }
            if settings.customMilestone > 0 {
                let frac = min(1, Double(settings.totalWords) / Double(settings.customMilestone))
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(settings.totalWords.formatted()) / \(settings.customMilestone.formatted()) words (\(Int(frac * 100))%)")
                        .font(.system(size: 11))
                        .foregroundStyle(p.subtext)
                    Capsule().fill(p.border).frame(height: 5)
                        .overlay(alignment: .leading) {
                            GeometryReader { geo in
                                Capsule().fill(settings.accentColor)
                                    .frame(width: max(frac > 0 ? 5 : 0, geo.size.width * frac))
                            }
                        }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            RowDivider()
            // Last 14 days at a glance: ● dictated, ○ quiet.
            HStack(spacing: 5) {
                Text("Last 14 days")
                    .font(.system(size: 11))
                    .foregroundStyle(p.subtext)
                Spacer()
                ForEach((0..<14).reversed(), id: \.self) { offset in
                    let day = Calendar.current.date(byAdding: .day, value: -offset, to: Date()) ?? Date()
                    let active = (settings.dailyWords[AppSettings.dayKey(day)] ?? 0) > 0
                    Circle()
                        .fill(active ? settings.accentColor : p.border)
                        .frame(width: 7, height: 7)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private func chartSection(_ p: Palette) -> some View {
        SectionLabel(text: "Last 30 days")
            .padding(.top, 6)
        CardGroup {
            let days = settings.monthActivity()
            let maxC = max(days.map(\.count).max() ?? 1, 1)
            let nonzero = days.map(\.count).filter { $0 > 0 }
            let avg = nonzero.isEmpty ? 0 : nonzero.reduce(0, +) / nonzero.count
            ZStack(alignment: .bottom) {
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(day.count > 0 ? settings.accentColor : p.border)
                            .frame(maxWidth: .infinity)
                            .frame(height: day.count > 0
                                   ? max(5, 52 * CGFloat(day.count) / CGFloat(maxC)) : 3)
                            .help("\(day.count) \(day.count == 1 ? "word" : "words") — \(day.date)")
                    }
                }
                if avg > 0 {
                    Rectangle()
                        .fill(p.subtext.opacity(0.55))
                        .frame(height: 1)
                        .offset(y: -max(5, 52 * CGFloat(avg) / CGFloat(maxC)))
                        .help("Average active day: \(avg) words")
                }
            }
            .frame(height: 60, alignment: .bottom)
            .padding(14)
        }
    }

    @ViewBuilder
    private func heatmapSection(_ p: Palette) -> some View {
        SectionLabel(text: "Heatmap")
            .padding(.top, 6)
        CardGroup {
            let days = settings.monthActivity()
            let maxC = max(days.map(\.count).max() ?? 1, 1)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 10),
                      spacing: 4) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(day.count > 0
                              ? settings.accentColor.opacity(0.25 + 0.75 * Double(day.count) / Double(maxC))
                              : p.border.opacity(0.6))
                        .frame(height: 16)
                        .help("\(day.count) \(day.count == 1 ? "word" : "words") — \(day.date)")
                }
            }
            .padding(14)
        }
    }

    @ViewBuilder
    private func hourSection(_ p: Palette) -> some View {
        SectionLabel(text: "When you dictate")
            .padding(.top, 6)
        CardGroup {
            let maxC = max(settings.hourCounts.values.max() ?? 1, 1)
            VStack(spacing: 4) {
                let nowHour = Calendar.current.component(.hour, from: Date())
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(0..<24, id: \.self) { hour in
                        let c = settings.hourCounts["\(hour)"] ?? 0
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(c > 0 ? settings.accentColor : p.border)
                            .frame(maxWidth: .infinity)
                            .frame(height: c > 0 ? max(4, 40 * CGFloat(c) / CGFloat(maxC)) : 2)
                            .overlay(alignment: .bottom) {
                                if hour == nowHour {
                                    RoundedRectangle(cornerRadius: 1.5)
                                        .strokeBorder(p.text.opacity(0.6), lineWidth: 1)
                                        .frame(height: max(4, c > 0 ? max(4, 40 * CGFloat(c) / CGFloat(maxC)) : 4))
                                }
                            }
                            .help("\(c) session\(c == 1 ? "" : "s") at \(hour):00\(hour == nowHour ? " (now)" : "")")
                    }
                }
                .frame(height: 46, alignment: .bottom)
                HStack {
                    Text("12a").font(.system(size: 9)).foregroundStyle(p.subtext)
                    Spacer()
                    Text("noon").font(.system(size: 9)).foregroundStyle(p.subtext)
                    Spacer()
                    Text("11p").font(.system(size: 9)).foregroundStyle(p.subtext)
                }
            }
            .padding(14)
        }
        SectionLabel(text: "By weekday")
            .padding(.top, 6)
        CardGroup {
            // Aggregate all recorded days by weekday (1=Sun…7=Sat).
            let cal = Calendar.current
            let df: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f }()
            var byWeekday = [Int](repeating: 0, count: 8)
            let _ = settings.dailyWords.forEach { key, words in
                if let date = df.date(from: key) {
                    byWeekday[cal.component(.weekday, from: date)] += words
                }
            }
            let labels = ["", "S", "M", "T", "W", "T", "F", "S"]
            let maxW = max(byWeekday.max() ?? 1, 1)
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(1..<8, id: \.self) { wd in
                    VStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(byWeekday[wd] > 0 ? settings.accentColor : p.border)
                            .frame(maxWidth: .infinity)
                            .frame(height: byWeekday[wd] > 0
                                   ? max(5, 40 * CGFloat(byWeekday[wd]) / CGFloat(maxW)) : 3)
                        Text(labels[wd])
                            .font(.system(size: 9))
                            .foregroundStyle(p.subtext)
                    }
                    .help("\(byWeekday[wd]) words")
                }
            }
            .frame(height: 56, alignment: .bottom)
            .padding(14)
        }
    }

    @ViewBuilder
    private func appsSection(_ p: Palette) -> some View {
        if !settings.appWords.isEmpty {
            SectionLabel(text: "Top apps")
                .padding(.top, 6)
            CardGroup {
                let top = settings.appWords.sorted { $0.value > $1.value }.prefix(5)
                let maxW = max(top.first?.value ?? 1, 1)
                let totalW = max(settings.appWords.values.reduce(0, +), 1)
                VStack(spacing: 8) {
                    ForEach(Array(top), id: \.key) { app, words in
                        HStack(spacing: 10) {
                            Text(app)
                                .font(.system(size: 11.5))
                                .foregroundStyle(p.text)
                                .frame(width: 110, alignment: .leading)
                                .lineLimit(1)
                            GeometryReader { geo in
                                Capsule().fill(settings.accentColor.opacity(0.75))
                                    .frame(width: max(4, geo.size.width * CGFloat(words) / CGFloat(maxW)))
                            }
                            .frame(height: 7)
                            Text("\(words * 100 / totalW)%")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(p.subtext)
                                .frame(width: 34, alignment: .trailing)
                            Text("\(words.formatted())w")
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(p.subtext)
                                .frame(width: 62, alignment: .trailing)
                        }
                    }
                }
                .padding(14)
            }
        }
    }

    @ViewBuilder
    private func badgesSection(_ p: Palette) -> some View {
        SectionLabel(text: "Achievements")
            .padding(.top, 10)
        let progress = Double(settings.earned.count) / Double(Achievement.all.count)
        Capsule().fill(p.border)
            .frame(height: 5)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Capsule().fill(settings.accentColor)
                        .frame(width: max(progress > 0 ? 5 : 0, geo.size.width * progress))
                }
            }
            .padding(.horizontal, 2)
        let locked = Achievement.all.filter { settings.earned[$0.id] == nil }.prefix(3)
        if !locked.isEmpty {
            Text("Within reach: " + locked.map { "\($0.name) (\($0.desc.lowercased()))" }
                .joined(separator: " · "))
                .font(.system(size: 11))
                .foregroundStyle(p.subtext)
                .padding(.horizontal, 2)
        }
        HStack {
            Toggle("Earned first", isOn: $settings.earnedFirst)
                .font(.system(size: 11))
                .foregroundStyle(p.subtext)
                .controlSize(.small)
            Spacer()
        }
        CardGroup {
            let ordered = settings.earnedFirst
                ? Achievement.all.sorted { (settings.earned[$0.id] != nil ? 0 : 1) < (settings.earned[$1.id] != nil ? 0 : 1) }
                : Achievement.all
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4),
                      spacing: 14) {
                ForEach(ordered) { a in
                    badge(a)
                        .onTapGesture { selectedBadge = a }
                }
            }
            .padding(14)
        }
        .popover(item: $selectedBadge) { a in
            VStack(alignment: .leading, spacing: 6) {
                Label(a.name, systemImage: a.symbol)
                    .font(.system(size: 13, weight: .semibold))
                Text(a.desc)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                if let date = settings.earned[a.id] {
                    Text("Earned \(date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Not earned yet")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .frame(width: 240, alignment: .leading)
        }
        if !settings.earned.isEmpty {
            CardGroup {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Achievement.all.filter { settings.earned[$0.id] != nil }) { a in
                            HStack {
                                Label(a.name, systemImage: a.symbol)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(p.text)
                                Spacer()
                                if let date = settings.earned[a.id] {
                                    Text(date.formatted(date: .abbreviated, time: .omitted))
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(p.subtext)
                                }
                            }
                        }
                    }
                    .padding(.top, 6)
                } label: {
                    Text("Earned badges (\(settings.earned.count)) — with dates")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(p.text)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
    }

    private var speakTimeLabel: String {
        let secs = Int(settings.totalSpeakSeconds)
        if secs < 60 { return "\(secs)s" }
        return "\(secs / 60)m \(secs % 60)s"
    }

    private var avgSessionLabel: String {
        guard settings.totalSessions > 0, settings.totalSpeakSeconds > 0 else { return "—" }
        return "\(Int(settings.totalSpeakSeconds) / settings.totalSessions)s"
    }

    private func copyStatsMarkdown() {
        let s = settings
        let text = """
        | Stat | Value |
        |---|---|
        | Words | \(s.totalWords.formatted()) |
        | Sessions | \(s.totalSessions) |
        | Characters | \(s.totalChars.formatted()) |
        | Streak | \(s.streak())d (best \(s.maxStreak)d) |
        | This week | \(s.wordsInWeek(endingDaysAgo: 0)) |
        | Last week | \(s.wordsInWeek(endingDaysAgo: 7)) |
        | Speaking WPM | \(s.wordsPerMinute) |
        | Longest session | \(s.maxSessionWords) words |
        | Time saved | ~\(Int(s.minutesSaved)) min |
        | Badges | \(s.earned.count)/\(Achievement.all.count) |
        """
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    private func exportAchievementsCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Murmur Achievements.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        let rows = Achievement.all.map { a -> String in
            let earned = settings.earned[a.id].map { df.string(from: $0) } ?? ""
            return "\"\(a.name)\",\"\(a.desc)\",\(earned)"
        }
        try? ("badge,description,earned\n" + rows.joined(separator: "\n") + "\n")
            .write(to: url, atomically: true, encoding: .utf8)
    }

    private func confirmResetBadges() {
        let alert = NSAlert()
        alert.messageText = "Reset all badges?"
        alert.informativeText = "All \(settings.earned.count) earned achievements go back to locked. Stats are kept."
        alert.addButton(withTitle: "Reset Badges")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { settings.earned = [:] }
    }

    /// Writes activity as date,words CSV — trailing 30 days, or every
    /// recorded day when `allTime`.
    private func exportActivityCSV(allTime: Bool = false) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Murmur Activity.csv"
        panel.title = "Export Activity"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let rows: [String]
        if allTime {
            rows = settings.dailyWords.sorted { $0.key < $1.key }
                .map { "\($0.key),\($0.value)" }
        } else {
            let cal = Calendar.current
            rows = (0..<30).reversed().map { offset -> String in
                let day = cal.date(byAdding: .day, value: -offset, to: Date()) ?? Date()
                let key = AppSettings.dayKey(day)
                return "\(key),\(settings.dailyWords[key] ?? 0)"
            }
        }
        try? ("date,words\n" + rows.joined(separator: "\n") + "\n")
            .write(to: url, atomically: true, encoding: .utf8)
    }

    private func confirmResetCharts() {
        let alert = NSAlert()
        alert.messageText = "Reset chart data?"
        alert.informativeText = "Clears the hour-of-day and top-apps data. Word totals and history are kept."
        alert.addButton(withTitle: "Reset Charts")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            settings.hourCounts = [:]
            settings.appWords = [:]
        }
    }

    private func statsSummary() -> String {
        let s = settings
        return """
        Murmur stats — \(Date().formatted(date: .abbreviated, time: .omitted))
        Words: \(s.totalWords.formatted()) · Sessions: \(s.totalSessions) · Streak: \(s.streak())d (best \(s.maxStreak)d)
        This week: \(s.wordsInWeek(endingDaysAgo: 0)) · Last week: \(s.wordsInWeek(endingDaysAgo: 7))
        Speaking pace: \(s.wordsPerMinute) WPM · Time saved vs typing: ~\(Int(s.minutesSaved)) min
        Badges: \(s.earned.count)/\(Achievement.all.count)
        """
    }

    private func copyStatsSummary() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(statsSummary(), forType: .string)
    }

    private func saveStatsSummary() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Murmur Stats.txt"
        panel.title = "Save Stats Summary"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? (statsSummary() + "\n").write(to: url, atomically: true, encoding: .utf8)
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

    private func statTile(_ label: String, _ value: String, help: String? = nil) -> some View {
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
        .help(help ?? "")
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
    @State private var filter = 0   // 0=all 1=pinned 2=today 3=yesterday 4=week 5=month
    @State private var lengthFilter = 0   // 0=any 1=<10w 2=10–50w 3=>50w
    @State private var appFilter: String?
    @State private var sort: HistorySort = .newest
    @State private var collapsedDays: Set<String> = []
    @State private var appliedDefaultFilter = false

    private var filtered: [HistoryItem] {
        let cal = Calendar.current
        var base = query.isEmpty
            ? settings.history
            : settings.history.filter {
                $0.text.localizedCaseInsensitiveContains(query)
                    || ($0.app?.localizedCaseInsensitiveContains(query) ?? false)
            }
        switch filter {
        case 1: base = base.filter(\.pinned)
        case 2: base = base.filter { cal.isDateInToday($0.date) }
        case 3: base = base.filter { cal.isDateInYesterday($0.date) }
        case 4:
            let cutoff = cal.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            base = base.filter { $0.date >= cutoff }
        case 5:
            let cutoff = cal.date(byAdding: .day, value: -30, to: Date()) ?? Date()
            base = base.filter { $0.date >= cutoff }
        default: break
        }
        switch lengthFilter {
        case 1: base = base.filter { $0.text.split(whereSeparator: \.isWhitespace).count < 10 }
        case 2: base = base.filter { (10...50).contains($0.text.split(whereSeparator: \.isWhitespace).count) }
        case 3: base = base.filter { $0.text.split(whereSeparator: \.isWhitespace).count > 50 }
        default: break
        }
        if let appFilter {
            base = base.filter { $0.app == appFilter }
        }
        return base.sorted {
            if settings.pinnedFirst, $0.pinned != $1.pinned { return $0.pinned }
            switch sort {
            case .newest: return $0.date > $1.date
            case .oldest: return $0.date < $1.date
            case .longest: return $0.text.count > $1.text.count
            case .shortest: return $0.text.count < $1.text.count
            }
        }
    }

    /// Distinct app names present in history, for the app filter menu.
    private var historyApps: [String] {
        Array(Set(settings.history.compactMap(\.app))).sorted()
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
                // Two rows so the controls never outgrow the pane and
                // stretch the window.
                Picker("", selection: $filter) {
                    Text("All").tag(0)
                    Text("Pinned").tag(1)
                    Text("Today").tag(2)
                    Text("Yesterday").tag(3)
                    Text("Week").tag(4)
                    Text("Month").tag(5)
                }
                .pickerStyle(.segmented).labelsHidden()
                HStack(spacing: 8) {
                    if filter != 0 || lengthFilter != 0 || appFilter != nil || !query.isEmpty {
                        Button("Reset") {
                            filter = 0; lengthFilter = 0; appFilter = nil; query = ""
                        }
                        .controlSize(.small)
                    }
                    Picker("", selection: $lengthFilter) {
                        Text("Any length").tag(0)
                        Text("< 10 words").tag(1)
                        Text("10–50 words").tag(2)
                        Text("> 50 words").tag(3)
                    }
                    .pickerStyle(.menu).labelsHidden().frame(maxWidth: 130)
                    if !historyApps.isEmpty {
                        Picker("", selection: $appFilter) {
                            Text("All apps").tag(String?.none)
                            ForEach(historyApps, id: \.self) { app in
                                Text(app).tag(String?.some(app))
                            }
                        }
                        .pickerStyle(.menu).labelsHidden().frame(maxWidth: 130)
                    }
                    Spacer()
                    Picker("", selection: $sort) {
                        ForEach(HistorySort.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.menu).labelsHidden().frame(maxWidth: 110)
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
                if sort == .newest || settings.historyGroupByApp {
                    // Grouped by day (or app) — headers show totals and
                    // click to collapse.
                    ForEach(groupedByDay, id: \.label) { group in
                        let words = group.items.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count }
                        Button {
                            if collapsedDays.contains(group.label) { collapsedDays.remove(group.label) }
                            else { collapsedDays.insert(group.label) }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: collapsedDays.contains(group.label) ? "chevron.right" : "chevron.down")
                                    .font(.system(size: 8, weight: .semibold))
                                SectionLabel(text: "\(group.label) · \(group.items.count) · \(words)w")
                            }
                        }
                        .buttonStyle(.plain)
                        if !collapsedDays.contains(group.label) {
                            CardGroup {
                                ForEach(Array(group.items.enumerated()), id: \.element.id) { i, item in
                                    if i > 0 { RowDivider() }
                                    HistoryRow(item: item, settings: settings)
                                }
                            }
                        }
                    }
                } else {
                    CardGroup {
                        ForEach(Array(filtered.enumerated()), id: \.element.id) { i, item in
                            if i > 0 { RowDivider() }
                            HistoryRow(item: item, settings: settings)
                        }
                    }
                }
                let totalSecs = filtered.compactMap(\.seconds).reduce(0, +)
                let storageKB = ((try? JSONEncoder().encode(settings.history))?.count ?? 0) / 1024
                Text(String(format: "Average %.0f words per transcript · %d:%02d spoken in view · %d KB stored",
                            filtered.isEmpty ? 0 : Double(totalWordsShown) / Double(filtered.count),
                            Int(totalSecs) / 60, Int(totalSecs) % 60, storageKB))
                    .font(.system(size: 10.5))
                    .foregroundStyle(p.subtext)
                    .padding(.horizontal, 2)
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
                        Button("Markdown (all)…") { exportHistory(pinnedOnly: false) }
                        Button("Markdown (pinned)…") { exportHistory(pinnedOnly: true) }
                        Button("Markdown (filtered view)…") { exportHistory(items: filtered) }
                        Button("Plain text…") { exportHistoryTXT() }
                        Button("JSON…") { exportHistoryJSON() }
                    }
                    .font(.system(size: 12)).fixedSize()
                    Menu("Copy") {
                        Button("As Paragraphs") {
                            copyToClipboard(filtered.map(\.text).joined(separator: "\n\n"))
                        }
                        Button("As Bullet List") {
                            copyToClipboard(filtered.map { "• \($0.text)" }.joined(separator: "\n"))
                        }
                        Button("Today's Transcripts") {
                            let today = settings.history.filter { Calendar.current.isDateInToday($0.date) }
                            copyToClipboard(today.map(\.text).joined(separator: "\n\n"))
                        }
                    }
                    .font(.system(size: 12)).fixedSize()
                    Spacer()
                    Menu("Clear") {
                        Button("All (keeps pinned)") { clearHistory { !$0.pinned } }
                        Button("Older than 7 days") { clearOlderThan(days: 7) }
                        Button("Older than 30 days") { clearOlderThan(days: 30) }
                        if !settings.lastCleared.isEmpty {
                            Divider()
                            Button("Undo Last Clear (\(settings.lastCleared.count))") {
                                settings.history = (settings.history + settings.lastCleared)
                                    .sorted { $0.date > $1.date }
                                settings.lastCleared = []
                            }
                        }
                    }
                    .font(.system(size: 12)).fixedSize()
                }
                CardGroup {
                    PRow(title: "Pause history",
                         subtitle: "Dictations aren't saved here — stats still count") {
                        Toggle("", isOn: $settings.historyPaused)
                            .toggleStyle(.switch).labelsHidden().controlSize(.small)
                    }
                    RowDivider()
                    PRow(title: "Skip clipboard-only dictations",
                         subtitle: "Don't save Dictate-to-Clipboard results") {
                        Toggle("", isOn: $settings.excludeClipboardOnly)
                            .toggleStyle(.switch).labelsHidden().controlSize(.small)
                    }
                    RowDivider()
                    PRow(title: "Pinned always on top") {
                        Toggle("", isOn: $settings.pinnedFirst)
                            .toggleStyle(.switch).labelsHidden().controlSize(.small)
                    }
                    RowDivider()
                    PRow(title: "Row text size") {
                        Slider(value: $settings.historyFontSize, in: 11...15)
                            .frame(width: 130).controlSize(.small)
                    }
                    RowDivider()
                    PRow(title: "Show seconds in timestamps") {
                        Toggle("", isOn: $settings.historyShowSeconds)
                            .toggleStyle(.switch).labelsHidden().controlSize(.small)
                    }
                    RowDivider()
                    PRow(title: "Group by app",
                         subtitle: "Section transcripts by the app they went to") {
                        Toggle("", isOn: $settings.historyGroupByApp)
                            .toggleStyle(.switch).labelsHidden().controlSize(.small)
                    }
                    RowDivider()
                    PRow(title: "Auto-export daily",
                         subtitle: "Write each day's transcripts to Application Support") {
                        Toggle("", isOn: $settings.autoExportDaily)
                            .toggleStyle(.switch).labelsHidden().controlSize(.small)
                    }
                    RowDivider()
                    PRow(title: "Compact rows",
                         subtitle: "One-line transcripts, tighter spacing") {
                        Toggle("", isOn: $settings.historyCompactRows)
                            .toggleStyle(.switch).labelsHidden().controlSize(.small)
                    }
                    RowDivider()
                    PRow(title: "Auto-pin long dictations") {
                        Picker("", selection: $settings.autoPinWords) {
                            Text("Off").tag(0)
                            Text("≥ 100w").tag(100)
                            Text("≥ 250w").tag(250)
                        }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 190)
                    }
                    RowDivider()
                    PRow(title: "Redact numbers",
                         subtitle: "Digits become # in saved transcripts (privacy)") {
                        Toggle("", isOn: $settings.historyRedactNumbers)
                            .toggleStyle(.switch).labelsHidden().controlSize(.small)
                    }
                    RowDivider()
                    PRow(title: "Skip exact duplicates",
                         subtitle: "Don't save a transcript identical to the last one") {
                        Toggle("", isOn: $settings.skipDuplicateHistory)
                            .toggleStyle(.switch).labelsHidden().controlSize(.small)
                    }
                    RowDivider()
                    PRow(title: "Exports include metadata",
                         subtitle: "App name and duration in Markdown exports") {
                        Toggle("", isOn: $settings.exportMetadata)
                            .toggleStyle(.switch).labelsHidden().controlSize(.small)
                    }
                    RowDivider()
                    PRow(title: "Open this pane on") {
                        Picker("", selection: $settings.historyDefaultFilter) {
                            Text("All").tag(0)
                            Text("Pinned").tag(1)
                            Text("Today").tag(2)
                        }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 190)
                    }
                }
            }
        }
        .onAppear {
            if !appliedDefaultFilter {
                appliedDefaultFilter = true
                filter = settings.historyDefaultFilter
            }
        }
    }

    /// Filtered items bucketed by calendar day (or by app, when the
    /// "Group by app" toggle is on), preserving the sorted order.
    private var groupedByDay: [(label: String, items: [HistoryItem])] {
        let cal = Calendar.current
        let df = DateFormatter()
        df.dateStyle = .medium
        var groups: [(label: String, items: [HistoryItem])] = []
        for item in filtered {
            let label: String
            if settings.historyGroupByApp {
                label = item.app?.isEmpty == false ? item.app! : "Other"
            } else {
                label = cal.isDateInToday(item.date) ? "Today"
                    : cal.isDateInYesterday(item.date) ? "Yesterday"
                    : df.string(from: item.date)
            }
            if let idx = groups.firstIndex(where: { $0.label == label }) {
                groups[idx].items.append(item)
            } else {
                groups.append((label, [item]))
            }
        }
        return groups
    }

    private func copyToClipboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    /// Removes matching unpinned items, remembering them for Undo.
    private func clearHistory(_ shouldRemove: (HistoryItem) -> Bool) {
        let removed = settings.history.filter { !$0.pinned && shouldRemove($0) }
        guard !removed.isEmpty else { return }
        settings.lastCleared = removed
        let removedIDs = Set(removed.map(\.id))
        settings.history.removeAll { removedIDs.contains($0.id) }
    }

    private func clearOlderThan(days: Int) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        clearHistory { $0.date < cutoff }
    }

    private func exportHistoryTXT() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Murmur Transcripts.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? (settings.history.map(\.text).joined(separator: "\n\n") + "\n")
            .write(to: url, atomically: true, encoding: .utf8)
    }

    private func exportHistoryJSON() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Murmur Transcripts.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        try? enc.encode(settings.history).write(to: url)
    }

    private func exportHistory(pinnedOnly: Bool = false, items: [HistoryItem]? = nil) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = pinnedOnly ? "Murmur Pinned Transcripts.md" : "Murmur Transcripts.md"
        panel.title = "Export Transcripts"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        let source = items ?? (pinnedOnly ? settings.history.filter(\.pinned) : settings.history)
        let body = source
            .map { item -> String in
                var meta = df.string(from: item.date)
                if settings.exportMetadata {
                    if let app = item.app, !app.isEmpty { meta += " · \(app)" }
                    if let secs = item.seconds, secs >= 1 {
                        meta += String(format: " · %d:%02d", Int(secs) / 60, Int(secs) % 60)
                    }
                }
                return "- **\(meta)** — \(item.text)"
            }
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
                ZStack(alignment: .bottom) {
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
                    // Daily-goal marker, when the goal is within the chart's scale.
                    if settings.dailyGoal > 0, settings.dailyGoal <= maxCount {
                        Line()
                            .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .foregroundStyle(p.subtext.opacity(0.7))
                            .frame(height: 1)
                            .offset(y: -(13 + max(6, 44 * CGFloat(settings.dailyGoal) / CGFloat(maxCount))))
                            .help("Daily goal: \(settings.dailyGoal) words")
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
                    .font(.system(size: settings.historyCompactRows ? 11.5 : CGFloat(settings.historyFontSize)))
                    .foregroundStyle(p.text)
                    .lineLimit(settings.historyCompactRows ? 1 : 3)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 4) {
                    let words = item.text.split(whereSeparator: \.isWhitespace).count
                    if settings.historyShowSeconds {
                        Text(item.date, format: .dateTime.month().day().hour().minute().second())
                    } else {
                        Text(item.date, format: .dateTime.month().day().hour().minute())
                    }
                    Text("· \(words) \(words == 1 ? "word" : "words")")
                    if let secs = item.seconds, secs >= 1 {
                        Text(String(format: "· %d:%02d", Int(secs) / 60, Int(secs) % 60))
                    }
                    if let app = item.app, !app.isEmpty {
                        Text("· → \(app)")
                            .lineLimit(1)
                    }
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
                    let words = item.text.split(whereSeparator: \.isWhitespace).count
                    Text("\(item.date.formatted(date: .abbreviated, time: .shortened)) · \(words) words · \(item.text.count) characters · ~\(max(1, words * 60 / 200))s read")
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
        .padding(.vertical, settings.historyCompactRows ? 6 : 10)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Copy") {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(item.text, forType: .string)
            }
            Button("Insert into Previous App") {
                NSApp.hide(nil)
                let text = item.text
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    Inserter.insert(text)
                }
            }
            Button(item.pinned ? "Unpin" : "Pin") {
                if let i = settings.history.firstIndex(where: { $0.id == item.id }) {
                    settings.history[i].pinned.toggle()
                }
            }
            Button("Copy as Quote") {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString("> " + item.text.replacingOccurrences(of: "\n", with: "\n> "),
                             forType: .string)
            }
            Button("Copy with Timestamp") {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString("[\(item.date.formatted(date: .abbreviated, time: .shortened))] \(item.text)",
                             forType: .string)
            }
            Button("Open in TextEdit") {
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("Murmur-Transcript.txt")
                try? item.text.write(to: url, atomically: true, encoding: .utf8)
                NSWorkspace.shared.open(url)
            }
            Menu("Polish as…") {
                ForEach(PolishTone.allCases.filter { $0 != .custom }) { tone in
                    Button(tone.label) {
                        TextCleaner.polish(item.text, tone: tone) { out in
                            let pb = NSPasteboard.general
                            pb.clearContents()
                            pb.setString(out, forType: .string)
                        }
                    }
                }
            }
            Button("Polish & Insert") {
                NSApp.hide(nil)
                TextCleaner.polish(item.text, tone: settings.polishTone,
                                   custom: settings.customPolishPrompt) { out in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        Inserter.insert(out)
                    }
                }
            }
            Divider()
            Button("Delete", role: .destructive) {
                settings.lastCleared = [item] // single-item undo via Clear menu
                settings.history.removeAll { $0.id == item.id }
            }
        }
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
