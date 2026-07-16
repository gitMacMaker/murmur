import SwiftUI
import AppKit

// MARK: - Murmur visual language
// Warm, minimal, product-grade. Adapts to system light/dark.
// "Hand-drawn mode" (settings.sketchMode) reskins every component with
// wobbly ink outlines and marker/chalk lettering — pencil-on-paper in
// light mode, chalk-on-blackboard in dark.

struct Palette {
    let bg: Color          // window background
    let sidebar: Color     // sidebar background
    let card: Color        // card / row group background
    let border: Color      // hairline borders
    let text: Color        // primary text
    let subtext: Color     // secondary text

    static let light = Palette(
        bg: Color(red: 0.980, green: 0.976, blue: 0.965),
        sidebar: Color(red: 0.951, green: 0.945, blue: 0.929),
        card: .white,
        border: Color.black.opacity(0.08),
        text: Color(red: 0.11, green: 0.10, blue: 0.09),
        subtext: Color(red: 0.44, green: 0.42, blue: 0.39)
    )
    static let dark = Palette(
        bg: Color(red: 0.118, green: 0.114, blue: 0.106),
        sidebar: Color(red: 0.145, green: 0.141, blue: 0.133),
        card: Color(red: 0.176, green: 0.172, blue: 0.161),
        border: Color.white.opacity(0.09),
        text: Color(red: 0.94, green: 0.93, blue: 0.92),
        subtext: Color(red: 0.64, green: 0.62, blue: 0.59)
    )

    static let terminal = Palette(
        bg: Color(red: 0.024, green: 0.045, blue: 0.024),
        sidebar: Color(red: 0.04, green: 0.07, blue: 0.04),
        card: Color(red: 0.05, green: 0.09, blue: 0.05),
        border: Color(red: 0.3, green: 0.9, blue: 0.45).opacity(0.35),
        text: Color(red: 0.45, green: 0.95, blue: 0.55),
        subtext: Color(red: 0.35, green: 0.7, blue: 0.42)
    )
    static let blueprint = Palette(
        bg: Color(red: 0.05, green: 0.16, blue: 0.32),
        sidebar: Color(red: 0.04, green: 0.13, blue: 0.27),
        card: Color(red: 0.08, green: 0.20, blue: 0.38),
        border: Color.white.opacity(0.4),
        text: Color.white.opacity(0.95),
        subtext: Color(red: 0.70, green: 0.80, blue: 0.92)
    )
    static let retro = Palette(
        bg: Color(white: 0.92),
        sidebar: Color(white: 0.85),
        card: .white,
        border: Color.black.opacity(0.85),
        text: .black,
        subtext: Color(white: 0.35)
    )
    static let neon = Palette(
        bg: Color(red: 0.05, green: 0.02, blue: 0.09),
        sidebar: Color(red: 0.07, green: 0.03, blue: 0.12),
        card: Color(red: 0.10, green: 0.05, blue: 0.16),
        border: Color(red: 1.0, green: 0.3, blue: 0.7).opacity(0.5),
        text: Color(red: 1.0, green: 0.88, blue: 0.96),
        subtext: Color(red: 0.78, green: 0.58, blue: 0.82)
    )

    static func of(_ scheme: ColorScheme) -> Palette {
        switch AppSettings.shared.skin {
        case .clean, .sketch: return scheme == .dark ? .dark : .light
        case .terminal: return .terminal
        case .blueprint: return .blueprint
        case .retro: return .retro
        case .neon: return .neon
        }
    }

    /// Stroke color for skin decorations (sketch wobble, blueprint dashes…).
    static func ink(_ scheme: ColorScheme) -> Color {
        switch AppSettings.shared.skin {
        case .terminal: return Palette.terminal.text.opacity(0.8)
        case .blueprint: return .white.opacity(0.85)
        case .retro: return .black
        case .neon: return Color(red: 1.0, green: 0.35, blue: 0.72)
        case .clean, .sketch:
            return scheme == .dark ? Color.white.opacity(0.8) : Color(white: 0.22).opacity(0.85)
        }
    }
}

// MARK: - Sketch mode primitives

enum SketchStyle {
    /// Marker in light mode, chalk in dark mode.
    static func fontName(_ scheme: ColorScheme) -> String {
        scheme == .dark ? "Chalkboard" : "Marker Felt"
    }
}

/// App-wide font helper — each skin brings its own typeface.
func murmurFont(_ size: CGFloat, _ weight: Font.Weight, sketch: Bool, scheme: ColorScheme) -> Font {
    switch AppSettings.shared.skin {
    case .sketch: return .custom(SketchStyle.fontName(scheme), size: size + 1)
    case .terminal: return .custom("Menlo", size: size)
    case .blueprint: return .custom("Noteworthy", size: size + 1)
    case .retro: return .custom("Monaco", size: size)
    case .neon: return .system(size: size, weight: weight, design: .rounded)
    case .clean: return .system(size: size, weight: weight)
    }
}

/// A rounded rectangle traced with a wobbly, hand-drawn line.
/// Deterministic jitter (seeded) so it doesn't shimmer between renders.
struct SketchyRoundedRect: Shape {
    var cornerRadius: CGFloat
    var seed: Int = 0
    var jitter: CGFloat = 1.7

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard rect.width > 4, rect.height > 4 else { return path }
        let r = min(cornerRadius, min(rect.width, rect.height) / 2)
        let n = 40
        var pts: [CGPoint] = (0..<n).map { i in
            Self.perimeterPoint(rect: rect, radius: r, t: CGFloat(i) / CGFloat(n))
        }
        for i in pts.indices {
            pts[i].x += noise(i * 2) * jitter
            pts[i].y += noise(i * 2 + 1) * jitter
        }
        let firstMid = CGPoint(x: (pts[n - 1].x + pts[0].x) / 2,
                               y: (pts[n - 1].y + pts[0].y) / 2)
        path.move(to: firstMid)
        for i in 0..<n {
            let next = pts[(i + 1) % n]
            let mid = CGPoint(x: (pts[i].x + next.x) / 2, y: (pts[i].y + next.y) / 2)
            path.addQuadCurve(to: mid, control: pts[i])
        }
        path.closeSubpath()
        return path
    }

    private func noise(_ i: Int) -> CGFloat {
        let v = sin(Double(i) * 12.9898 + Double(seed) * 78.233) * 43758.5453
        return CGFloat(v - v.rounded(.down)) * 2 - 1
    }

    /// Point at parameter t (0…1) along the rounded-rect perimeter, clockwise
    /// from the start of the top edge.
    static func perimeterPoint(rect: CGRect, radius r: CGFloat, t: CGFloat) -> CGPoint {
        let w = rect.width - 2 * r
        let h = rect.height - 2 * r
        let arc = .pi * r / 2
        let lengths: [CGFloat] = [w, arc, h, arc, w, arc, h, arc]
        let total = lengths.reduce(0, +)
        var d = t * total
        for (i, len) in lengths.enumerated() {
            if d <= len || i == lengths.count - 1 {
                let f = len > 0 ? d / len : 0
                switch i {
                case 0: return CGPoint(x: rect.minX + r + w * f, y: rect.minY)
                case 1:
                    let a = -CGFloat.pi / 2 + f * .pi / 2
                    return CGPoint(x: rect.maxX - r + r * cos(a), y: rect.minY + r + r * sin(a))
                case 2: return CGPoint(x: rect.maxX, y: rect.minY + r + h * f)
                case 3:
                    let a = f * CGFloat.pi / 2
                    return CGPoint(x: rect.maxX - r + r * cos(a), y: rect.maxY - r + r * sin(a))
                case 4: return CGPoint(x: rect.maxX - r - w * f, y: rect.maxY)
                case 5:
                    let a = CGFloat.pi / 2 + f * .pi / 2
                    return CGPoint(x: rect.minX + r + r * cos(a), y: rect.maxY - r + r * sin(a))
                case 6: return CGPoint(x: rect.minX, y: rect.maxY - r - h * f)
                default:
                    let a = CGFloat.pi + f * .pi / 2
                    return CGPoint(x: rect.minX + r + r * cos(a), y: rect.minY + r + r * sin(a))
                }
            }
            d -= len
        }
        return CGPoint(x: rect.midX, y: rect.minY)
    }
}

/// A horizontal hand-drawn line, for dividers.
struct SketchyLine: Shape {
    var seed: Int = 0

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let n = 10
        let pts: [CGPoint] = (0...n).map { i in
            let x = rect.minX + rect.width * CGFloat(i) / CGFloat(n)
            let v = sin(Double(i * 3 + seed) * 12.9898) * 43758.5453
            let jitterY = CGFloat(v - v.rounded(.down)) * 2.4 - 1.2
            return CGPoint(x: x, y: rect.midY + jitterY)
        }
        path.move(to: pts[0])
        for i in 1...n {
            let mid = CGPoint(x: (pts[i - 1].x + pts[i].x) / 2,
                              y: (pts[i - 1].y + pts[i].y) / 2)
            path.addQuadCurve(to: mid, control: pts[i - 1])
        }
        path.addLine(to: pts[n])
        return path
    }
}

/// Faint scattered pencil scribbles — hatch clusters and loose loops —
/// used as the window texture in hand-drawn mode. Seeded, so it's stable.
struct ScribbleBackground: View {
    @Environment(\.colorScheme) private var scheme
    var seed: UInt64 = 1

    var body: some View {
        Canvas { ctx, size in
            var rng = SeededRNG(state: seed &* 0x9E3779B97F4A7C15 &+ 12345)
            let base = scheme == .dark ? Color.white : Color(white: 0.2)
            let ink = base.opacity(scheme == .dark ? 0.045 : 0.055)

            // Hatch clusters: little groups of 2–4 parallel wobbly strokes.
            let clusters = Int(size.width * size.height / 16000) + 10
            for _ in 0..<clusters {
                let cx = rng.next() * size.width
                let cy = rng.next() * size.height
                let angle = rng.next() * .pi
                let dx = cos(angle), dy = sin(angle)
                let strokes = 2 + Int(rng.next() * 2.99)
                for k in 0..<strokes {
                    let len = 12 + rng.next() * 20
                    let off = CGFloat(k) * (4 + rng.next() * 2)
                    let px = -dy * off, py = dx * off
                    var path = Path()
                    path.move(to: CGPoint(x: cx - dx * len / 2 + px,
                                          y: cy - dy * len / 2 + py))
                    path.addQuadCurve(
                        to: CGPoint(x: cx + dx * len / 2 + px,
                                    y: cy + dy * len / 2 + py),
                        control: CGPoint(x: cx + px + (rng.next() - 0.5) * 6,
                                         y: cy + py + (rng.next() - 0.5) * 6))
                    ctx.stroke(path, with: .color(ink), lineWidth: 1)
                }
            }

            // A few loose loop scrawls.
            for _ in 0..<max(4, clusters / 6) {
                let cx = rng.next() * size.width
                let cy = rng.next() * size.height
                let w = 16 + rng.next() * 26
                let h = w * (0.4 + rng.next() * 0.4)
                for pass in 0..<2 {
                    let tilt = (rng.next() - 0.5) * 0.9 + CGFloat(pass) * 0.25
                    let rect = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
                    let path = Path(ellipseIn: rect)
                        .applying(CGAffineTransform(rotationAngle: tilt))
                        .applying(CGAffineTransform(translationX: cx, y: cy))
                    ctx.stroke(path, with: .color(ink), lineWidth: 1)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct SeededRNG {
    var state: UInt64
    mutating func next() -> CGFloat {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat((state >> 33) % 10000) / 10000
    }
}

/// Per-skin window texture: scribbles for sketch, scanlines for terminal,
/// drafting grid for blueprint, nothing for the rest.
struct SkinBackground: View {
    @ObservedObject private var settings = AppSettings.shared
    var seed: UInt64 = 1

    var body: some View {
        switch settings.skin {
        case .sketch: ScribbleBackground(seed: seed)
        case .terminal: ScanlineBackground()
        case .blueprint: GridBackground()
        default: EmptyView()
        }
    }
}

/// Faint CRT scanlines.
struct ScanlineBackground: View {
    var body: some View {
        Canvas { ctx, size in
            var y: CGFloat = 0
            while y < size.height {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(path, with: .color(.black.opacity(0.28)), lineWidth: 1)
                y += 3
            }
        }
        .allowsHitTesting(false)
    }
}

/// Drafting-paper grid: fine lines with heavier lines every fifth.
struct GridBackground: View {
    var body: some View {
        Canvas { ctx, size in
            let minor: CGFloat = 22
            var i = 0
            var x: CGFloat = 0
            while x < size.width {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(path, with: .color(.white.opacity(i % 5 == 0 ? 0.10 : 0.045)), lineWidth: 1)
                x += minor; i += 1
            }
            i = 0
            var y: CGFloat = 0
            while y < size.height {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(path, with: .color(.white.opacity(i % 5 == 0 ? 0.10 : 0.045)), lineWidth: 1)
                y += minor; i += 1
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Components

/// A group of rows in a soft card with hairline dividers.
/// Sketch mode: wobbly double-stroked ink outline, slightly tilted.
struct CardGroup<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var settings = AppSettings.shared
    @ViewBuilder var content: Content

    var body: some View {
        let p = Palette.of(scheme)
        let skin = settings.skin
        let radius: CGFloat = {
            switch skin {
            case .terminal: return 4
            case .retro: return 2
            case .sketch: return 14
            default: return 12
            }
        }()
        VStack(alignment: .leading, spacing: 0) { content }
            .background(skin == .sketch ? p.card.opacity(scheme == .dark ? 0.45 : 0.75) : p.card)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                let ink = Palette.ink(scheme)
                switch skin {
                case .sketch:
                    ZStack {
                        SketchyRoundedRect(cornerRadius: 14, seed: 3)
                            .stroke(ink, lineWidth: 1.4)
                        SketchyRoundedRect(cornerRadius: 14, seed: 11, jitter: 2.6)
                            .stroke(ink.opacity(0.3), lineWidth: 1)
                    }
                case .terminal:
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(p.border, lineWidth: 1)
                case .blueprint:
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [7, 4]))
                        .foregroundStyle(ink.opacity(0.7))
                case .retro:
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(.black, lineWidth: 1.5)
                case .neon:
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(ink.opacity(0.6), lineWidth: 1.2)
                case .clean:
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(p.border, lineWidth: 1)
                }
            }
            .shadow(color: shadowColor, radius: skin == .retro || skin == .neon ? (skin == .retro ? 0 : 14) : 3,
                    x: skin == .retro ? 3 : 0, y: skin == .retro ? 3 : 1)
            .rotationEffect(.degrees(skin == .sketch ? -0.15 : 0))
    }

    private var shadowColor: Color {
        switch settings.skin {
        case .retro: return .black.opacity(0.8)
        case .neon: return Color(red: 1.0, green: 0.3, blue: 0.7).opacity(0.25)
        case .sketch: return .clear
        case .clean: return scheme == .dark ? .clear : .black.opacity(0.04)
        default: return .clear
        }
    }
}

/// Text-first settings row: title (+ optional caption) left, control right.
struct PRow<Trailing: View>: View {
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var settings = AppSettings.shared
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        let p = Palette.of(scheme)
        let sketch = settings.sketchMode
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(murmurFont(13, .medium, sketch: sketch, scheme: scheme))
                    .foregroundStyle(p.text)
                if let subtitle {
                    Text(subtitle)
                        .font(murmurFont(11.5, .regular, sketch: sketch, scheme: scheme))
                        .foregroundStyle(p.subtext)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 16)
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

/// Divider between rows in a CardGroup — a hand-drawn stroke in sketch mode.
struct RowDivider: View {
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        switch settings.skin {
        case .sketch:
            SketchyLine(seed: 5)
                .stroke(Palette.ink(scheme).opacity(0.35), lineWidth: 1)
                .frame(height: 3)
                .padding(.leading, 16)
                .padding(.trailing, 10)
        case .blueprint:
            Line()
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .foregroundStyle(Palette.ink(scheme).opacity(0.35))
                .frame(height: 1)
                .padding(.leading, 16)
        case .retro:
            Color.black.frame(height: 1).padding(.leading, 0)
        default:
            Palette.of(scheme).border
                .frame(height: 1)
                .padding(.leading, 16)
        }
    }
}

struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

/// Page header inside the content pane.
struct PageHeader: View {
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var settings = AppSettings.shared
    let title: String
    let subtitle: String

    var body: some View {
        let p = Palette.of(scheme)
        let sketch = settings.sketchMode
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(murmurFont(21, .semibold, sketch: sketch, scheme: scheme))
                .foregroundStyle(p.text)
                .rotationEffect(.degrees(sketch ? -0.6 : 0))
            Text(subtitle)
                .font(murmurFont(12.5, .regular, sketch: sketch, scheme: scheme))
                .foregroundStyle(p.subtext)
        }
    }
}

/// Small uppercase section label above a CardGroup.
struct SectionLabel: View {
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var settings = AppSettings.shared
    let text: String

    var body: some View {
        Text(settings.sketchMode ? text : text.uppercased())
            .font(murmurFont(10.5, .semibold, sketch: settings.sketchMode, scheme: scheme))
            .kerning(settings.sketchMode ? 0 : 0.4)
            .foregroundStyle(Palette.of(scheme).subtext)
            .padding(.leading, 2)
    }
}
