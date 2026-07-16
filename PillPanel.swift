import AppKit
import SwiftUI

// MARK: - Observable state driving the pill UI

final class PillState: ObservableObject {
    enum Phase { case listening, handsFree, processing, done, error, idleDot }
    @Published var phase: Phase = .listening
    @Published var text: String = ""
    @Published var levels: [CGFloat] = Array(repeating: 0.05, count: 28)
    @Published var targetApp: String?
    @Published var startedAt: Date?

    func pushLevel(_ level: Float) {
        let gained = min(1.0, level * Float(AppSettings.shared.waveGain))
        levels.removeFirst()
        levels.append(max(0.05, CGFloat(gained)))
    }

    func resetLevels(count: Int) {
        levels = Array(repeating: 0.05, count: max(8, count))
    }
}

// MARK: - Floating, non-activating pill window

final class PillPanel {
    let state = PillState()
    private var panel: NSPanel?

    func show() {
        if panel == nil { build() }
        if state.levels.count != AppSettings.shared.waveBarCount {
            state.resetLevels(count: AppSettings.shared.waveBarCount)
        }
        position()
        panel?.orderFrontRegardless()
    }

    func hide(toIdleDot: Bool = false) {
        state.text = ""
        state.resetLevels(count: AppSettings.shared.waveBarCount)
        if toIdleDot {
            state.phase = .idleDot
            if panel == nil { build() }
            position()
            panel?.orderFrontRegardless()
        } else {
            panel?.orderOut(nil)
        }
    }

    private func build() {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 140),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let host = NSHostingView(rootView: PillView(state: state))
        host.frame = p.contentRect(forFrameRect: p.frame)
        p.contentView = host
        panel = p
    }

    private func position() {
        guard let p = panel,
              let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let f = screen.visibleFrame
        let s = AppSettings.shared
        let off = CGFloat(s.pillEdgeOffset)
        let y: CGFloat = s.pillPosition == .top
            ? f.maxY - p.frame.height - max(0, off - 18)
            : f.minY + off
        let x: CGFloat
        switch s.pillAlignment {
        case .leading: x = f.minX + 16
        case .center: x = f.midX - p.frame.width / 2
        case .trailing: x = f.maxX - p.frame.width - 16
        }
        p.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

// MARK: - SwiftUI pill

struct PillView: View {
    @ObservedObject var state: PillState
    @ObservedObject var settings = AppSettings.shared
    @State private var appeared = false

    var body: some View {
        VStack {
            if settings.pillPosition == .bottom { Spacer() }
            HStack {
                if settings.pillAlignment != .leading { Spacer(minLength: 0) }
                PillBody(state: state, accent: settings.accentColor)
                    .scaleEffect((appeared ? 1 : 0.85) * settings.pillSize.factor)
                    .opacity(appeared ? 1 : 0)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                if settings.pillAlignment != .trailing { Spacer(minLength: 0) }
            }
            if settings.pillPosition == .top { Spacer() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if settings.reduceMotion { appeared = true }
            else { withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) { appeared = true } }
        }
    }
}

/// The pill itself — shared by the live overlay and the settings preview.
/// Reads style options (theme, wave style, opacity, toggles) live from settings.
struct PillBody: View {
    @ObservedObject var state: PillState
    let accent: Color
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.colorScheme) private var colorScheme

    /// The skin the pill wears: the app skin when "Match app skin" is on,
    /// otherwise the classic clean pill.
    private var pillSkin: AppSkin {
        settings.pillMatchesSkin ? settings.skin : .clean
    }

    private var isDark: Bool {
        switch pillSkin {
        case .terminal, .blueprint, .neon: return true
        case .retro: return false
        case .clean, .sketch:
            switch settings.pillTheme {
            case .dark: return true
            case .light: return false
            case .system: return colorScheme == .dark
            }
        }
    }

    private var ink: Color {
        switch pillSkin {
        case .terminal: return Color(red: 0.45, green: 0.95, blue: 0.55)
        case .blueprint: return .white.opacity(0.95)
        case .retro: return .black
        case .neon: return Color(red: 1.0, green: 0.88, blue: 0.96)
        case .clean, .sketch: return isDark ? .white : Color(white: 0.13)
        }
    }

    var body: some View {
        if state.phase == .idleDot {
            let d = settings.idleDotSize.diameter
            Circle()
                .fill(accent.opacity(0.5))
                .frame(width: d, height: d)
                .padding(6)
        } else {
            mainPill
        }
    }

    private var mainPill: some View {
        HStack(spacing: 14) {
            statusDot
            waveform
            if settings.showTranscript { transcript }
            if settings.showWordCount, wordCount > 0,
               state.phase == .listening || state.phase == .handsFree {
                Text("\(wordCount)w")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(ink.opacity(0.5))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(ink.opacity(0.09)))
            }
            if settings.showPillTimer, let started = state.startedAt,
               state.phase == .listening || state.phase == .handsFree {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let secs = max(0, Int(context.date.timeIntervalSince(started)))
                    Text(String(format: "%d:%02d", secs / 60, secs % 60))
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(ink.opacity(0.4))
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 15)
        .background(background)
        .rotationEffect(.degrees(pillSkin == .sketch ? -0.5 : 0))
        .animation(settings.reduceMotion ? nil : .easeOut(duration: 0.18), value: state.text)
    }

    @ViewBuilder
    private var background: some View {
        let top: Color = isDark ? Color(white: 0.10) : Color(white: 1.0)
        let bottom: Color = isDark ? Color(white: 0.04) : Color(white: 0.93)
        let opacity = settings.pillOpacity
        switch pillSkin {
        case .terminal:
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(red: 0.03, green: 0.06, blue: 0.03).opacity(opacity))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(ink.opacity(0.6), lineWidth: 1.2)
                )
                .shadow(color: settings.glowEnabled ? ink.opacity(0.3) : .clear, radius: 16, y: 3)
                .shadow(color: .black.opacity(0.5), radius: 12, y: 5)
        case .blueprint:
            Capsule()
                .fill(Color(red: 0.06, green: 0.17, blue: 0.34).opacity(opacity))
                .overlay(
                    Capsule()
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.3, dash: [7, 4]))
                        .foregroundStyle(.white.opacity(0.8))
                )
                .shadow(color: .black.opacity(0.45), radius: 12, y: 5)
        case .retro:
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.white.opacity(max(0.92, opacity)))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(.black, lineWidth: 1.6)
                )
                .shadow(color: .black.opacity(0.85), radius: 0, x: 3, y: 3)
        case .neon:
            Capsule()
                .fill(Color(red: 0.08, green: 0.03, blue: 0.13).opacity(opacity))
                .overlay(
                    Capsule().strokeBorder(
                        LinearGradient(colors: [Color(red: 1, green: 0.3, blue: 0.7),
                                                Color(red: 0.3, green: 0.85, blue: 1)],
                                       startPoint: .leading, endPoint: .trailing),
                        lineWidth: 1.5)
                )
                .shadow(color: settings.glowEnabled
                        ? Color(red: 1, green: 0.3, blue: 0.7).opacity(0.5) : .clear,
                        radius: 20, y: 4)
                .shadow(color: .black.opacity(0.5), radius: 12, y: 5)
        case .clean, .sketch:
            classicBackground(top: top, bottom: bottom, opacity: opacity)
        }
    }

    private var cleanShape: some InsettableShape {
        let r: CGFloat = settings.pillCorner.radius ?? 100
        return RoundedRectangle(cornerRadius: r, style: .continuous)
    }

    @ViewBuilder
    private func classicBackground(top: Color, bottom: Color, opacity: Double) -> some View {
        if pillSkin == .sketch {
            // Hand-drawn: flat paper/board fill with a wobbly double ink outline.
            let paper: Color = isDark ? Color(white: 0.08) : Color(red: 0.99, green: 0.98, blue: 0.955)
            let sketchInk: Color = isDark ? .white.opacity(0.85) : Color(white: 0.2).opacity(0.9)
            Capsule()
                .fill(paper.opacity(opacity))
                .overlay(
                    ZStack {
                        SketchyRoundedRect(cornerRadius: 200, seed: 2)
                            .stroke(sketchInk, lineWidth: 1.6)
                        SketchyRoundedRect(cornerRadius: 200, seed: 9, jitter: 2.8)
                            .stroke(sketchInk.opacity(0.3), lineWidth: 1.1)
                    }
                )
                .shadow(color: .black.opacity(isDark ? 0.5 : 0.18), radius: 10, y: 5)
        } else {
            cleanShape
                .fill(
                    LinearGradient(colors: [top.opacity(opacity), bottom.opacity(opacity)],
                                   startPoint: .top, endPoint: .bottom)
                )
                .overlay(
                    cleanShape.strokeBorder(
                        LinearGradient(colors: [accent.opacity(0.65),
                                                ink.opacity(0.10),
                                                accent.opacity(0.25)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: settings.pillBorderWidth)
                )
                .shadow(color: settings.glowEnabled
                        ? accent.opacity((isDark ? 0.35 : 0.3) * settings.glowIntensity) : .clear,
                        radius: 22 * settings.glowIntensity, y: 4)
                .shadow(color: .black.opacity(isDark ? 0.5 : 0.22), radius: 14, y: 6)
        }
    }

    private var statusDot: some View {
        ZStack {
            switch state.phase {
            case .listening, .handsFree:
                Circle().fill(accent)
                    .frame(width: 10, height: 10)
                    .shadow(color: settings.glowEnabled ? accent.opacity(0.9) : .clear, radius: 6)
            case .processing:
                ProgressView().controlSize(.small).tint(ink)
            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green).font(.system(size: 15))
            case .error:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow).font(.system(size: 15))
            case .idleDot:
                EmptyView()
            }
        }
        .frame(width: 18, height: 18)
    }

    @ViewBuilder
    private var waveform: some View {
        switch settings.waveStyle {
        case .bars:
            HStack(spacing: 2.5) {
                ForEach(Array(state.levels.enumerated()), id: \.offset) { _, level in
                    Capsule()
                        .fill(LinearGradient(colors: markColors(level),
                                             startPoint: .bottom, endPoint: .top))
                        .frame(width: 3, height: 6 + level * 28)
                }
            }
            .frame(height: 36)
            .animation(settings.reduceMotion ? nil : .linear(duration: 0.08), value: state.levels)
        case .dots:
            HStack(spacing: 5) {
                ForEach(Array(state.levels.enumerated()), id: \.offset) { i, level in
                    if i.isMultiple(of: 2) {
                        Circle()
                            .fill(markColors(level).last ?? accent)
                            .frame(width: 4 + level * 9, height: 4 + level * 9)
                    }
                }
            }
            .frame(width: 152, height: 36)
            .animation(settings.reduceMotion ? nil : .linear(duration: 0.08), value: state.levels)
        case .wave:
            WaveShape(levels: state.levels)
                .stroke(
                    LinearGradient(colors: [accent, ink.opacity(0.9)],
                                   startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                )
                .frame(width: 152, height: 36)
                .animation(settings.reduceMotion ? nil : .linear(duration: 0.08), value: state.levels)
        }
    }

    private func markColors(_ level: CGFloat) -> [Color] {
        switch state.phase {
        case .processing: return [ink.opacity(0.25), ink.opacity(0.35)]
        case .done: return [.green.opacity(0.6), .green]
        default:
            return settings.waveMonochrome
                ? [ink.opacity(0.45), ink.opacity(0.95)]
                : [accent.opacity(0.75), ink.opacity(0.95)]
        }
    }

    private var transcript: some View {
        Text(displayText)
            .font(transcriptFont)
            .foregroundStyle(ink.opacity(state.text.isEmpty ? 0.55 : 0.95))
            .lineLimit(1)
            .truncationMode(.head)
            .frame(minWidth: 130, maxWidth: 270, alignment: .leading)
    }

    private var transcriptFont: Font {
        switch pillSkin {
        case .sketch: return .custom(SketchStyle.fontName(isDark ? .dark : .light), size: 15)
        case .terminal: return .custom("Menlo", size: 13)
        case .blueprint: return .custom("Noteworthy", size: 15)
        case .retro: return .custom("Monaco", size: 13)
        case .neon: return .system(size: 14, weight: .medium, design: .rounded)
        case .clean: return .system(size: 14, weight: .medium, design: settings.pillFont.design)
        }
    }

    private var wordCount: Int {
        state.text.split(whereSeparator: \.isWhitespace).count
    }

    private var displayText: String {
        if !state.text.isEmpty { return state.text }
        switch state.phase {
        case .listening:
            if let app = state.targetApp { return "Listening → \(app)" }
            return "Listening… release to insert"
        case .handsFree: return "Hands-free — tap to finish, Esc cancels"
        case .processing: return "Polishing…"
        case .done: return "Inserted ✓"
        case .error: return "Something went wrong"
        case .idleDot: return ""
        }
    }
}

/// Smooth line through the level history — a classic audio waveform look.
/// Amplitudes alternate sign so the line oscillates around the midline.
struct WaveShape: Shape {
    var levels: [CGFloat]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard levels.count > 1 else { return path }
        let step = rect.width / CGFloat(levels.count - 1)
        let points: [CGPoint] = levels.enumerated().map { i, level in
            let amp = level * rect.height * 0.44
            let y = rect.midY + (i.isMultiple(of: 2) ? -amp : amp)
            return CGPoint(x: CGFloat(i) * step, y: y)
        }
        path.move(to: points[0])
        for i in 1..<points.count {
            let mid = CGPoint(x: (points[i - 1].x + points[i].x) / 2,
                              y: (points[i - 1].y + points[i].y) / 2)
            path.addQuadCurve(to: mid, control: points[i - 1])
        }
        path.addLine(to: points[points.count - 1])
        return path
    }
}
