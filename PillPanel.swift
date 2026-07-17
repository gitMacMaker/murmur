import AppKit
import SwiftUI

// MARK: - Observable state driving the pill UI

final class PillState: ObservableObject {
    enum Phase { case listening, handsFree, processing, done, error, idleDot }
    @Published var phase: Phase = .listening
    @Published var text: String = ""
    @Published var levels: [CGFloat] = Array(repeating: 0.05, count: 28)
    @Published var targetApp: String?
    @Published var targetIcon: NSImage?
    @Published var startedAt: Date?
    /// True when the last delivery went to the clipboard, not an insert.
    @Published var copiedMode = false

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
        guard AppSettings.shared.showPillWhileRecording else { return }
        if panel == nil { build() }
        if state.levels.count != AppSettings.shared.waveBarCount {
            state.resetLevels(count: AppSettings.shared.waveBarCount)
        }
        // Clickable only when "tap to finish" is on — otherwise clicks pass
        // straight through to whatever is behind the pill.
        panel?.ignoresMouseEvents = !AppSettings.shared.pillClickToFinish
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
        let preferred: NSScreen? = AppSettings.shared.pillScreen == .mouse
            ? NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            : NSScreen.main
        guard let p = panel,
              let screen = preferred ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let f = screen.visibleFrame
        let s = AppSettings.shared
        let off = CGFloat(s.pillEdgeOffset)
        let nudgeY = CGFloat(s.pillOffsetY)
        let y: CGFloat = s.pillPosition == .top
            ? f.maxY - p.frame.height - max(0, off - 18) - nudgeY
            : f.minY + off + nudgeY
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

    /// The idle dot can sit at its own alignment, separate from the pill's.
    private var alignment: PillAlignment {
        state.phase == .idleDot ? settings.idleDotAlignment : settings.pillAlignment
    }

    var body: some View {
        VStack {
            if settings.pillPosition == .bottom { Spacer() }
            HStack {
                if alignment != .leading { Spacer(minLength: 0) }
                PillBody(state: state, accent: settings.accentColor)
                    .scaleEffect((appeared ? 1 : entranceScale) * settings.pillSize.factor)
                    .opacity(appeared ? 1 : 0)
                    .offset(x: CGFloat(settings.pillNudge))
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                if alignment != .trailing { Spacer(minLength: 0) }
            }
            if settings.pillPosition == .top { Spacer() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if settings.reduceMotion { appeared = true; return }
            switch settings.entranceAnim {
            case .spring:
                withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) { appeared = true }
            case .fade:
                withAnimation(.easeOut(duration: 0.22)) { appeared = true }
            case .none:
                appeared = true
            }
        }
    }

    private var entranceScale: CGFloat {
        settings.entranceAnim == .spring ? CGFloat(settings.pillAppearScale) : 1.0
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
        if let spec = pillSkin.spec { return spec.isDark }
        switch pillSkin {
        case .terminal, .blueprint, .neon, .midnight, .forest: return true
        case .retro, .paper, .candy: return false
        default:
            switch settings.pillTheme {
            case .dark: return true
            case .light: return false
            case .system: return colorScheme == .dark
            }
        }
    }

    private var ink: Color {
        switch settings.pillTextColor {
        case .white: return .white
        case .black: return Color(white: 0.1)
        case .auto: break
        }
        if let spec = pillSkin.spec { return spec.palette.text }
        switch pillSkin {
        case .terminal: return Color(red: 0.45, green: 0.95, blue: 0.55)
        case .blueprint: return .white.opacity(0.95)
        case .retro: return .black
        case .neon: return Color(red: 1.0, green: 0.88, blue: 0.96)
        case .paper: return Color(red: 0.20, green: 0.16, blue: 0.11)
        case .midnight: return Color(red: 0.902, green: 0.918, blue: 0.969)
        case .forest: return Color(red: 0.875, green: 0.941, blue: 0.886)
        case .candy: return Color(red: 0.29, green: 0.125, blue: 0.22)
        default: return isDark ? .white : Color(white: 0.13)
        }
    }

    var body: some View {
        if state.phase == .idleDot {
            let d = settings.idleDotSize.diameter
            let baseDot = (settings.idleDotColor == .accent ? accent : Color(white: 0.55))
            let dotColor = settings.dimWhenIdle ? baseDot.opacity(0.5) : baseDot
            Group {
                if settings.idleDotPulse, !settings.reduceMotion {
                    TimelineView(.animation(minimumInterval: 1 / 20)) { context in
                        let t = context.date.timeIntervalSinceReferenceDate
                        let breathe = 0.72 + 0.28 * (sin(t * 1.6) + 1) / 2
                        Circle()
                            .fill(dotColor.opacity(settings.idleDotOpacity * breathe))
                            .frame(width: d, height: d)
                    }
                } else {
                    Circle()
                        .fill(dotColor.opacity(settings.idleDotOpacity))
                        .frame(width: d, height: d)
                }
            }
            .padding(6)
        } else {
            mainPill
                .contentShape(Capsule())
                .onTapGesture {
                    guard settings.pillClickToFinish else { return }
                    NotificationCenter.default.post(
                        name: Notification.Name("MurmurPillTapped"), object: nil)
                }
        }
    }

    private var mainPill: some View {
        HStack(spacing: 14) {
            statusDot
            if settings.showTargetIcon, let icon = state.targetIcon,
               state.phase == .listening || state.phase == .handsFree {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 17, height: 17)
            }
            if settings.showWaveform { waveform }
            if settings.showTranscript { transcript }
            if settings.showWordCount, settings.wordCountBadge, wordCount > 0,
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
                    let elapsed = max(0, Int(context.date.timeIntervalSince(started)))
                    // Count down to the auto-finish cap when one is set.
                    let secs = (settings.countdownTimer && settings.maxRecordSeconds > 0)
                        ? max(0, settings.maxRecordSeconds - elapsed) : elapsed
                    Text(settings.timerFormat == .mmss
                         ? String(format: "%d:%02d", secs / 60, secs % 60)
                         : "\(secs)s")
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(ink.opacity(0.4))
                }
            }
        }
        .padding(.horizontal, CGFloat(settings.pillPadding))
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
        let borderW = CGFloat(settings.pillBorderWidth)
        let glowI = settings.glowIntensity
        if let spec = pillSkin.spec {
            // Spec-driven skins share one parameterized pill.
            let shape = RoundedRectangle(cornerRadius: pillRadius(spec.pillRadius),
                                         style: .continuous)
            shape
                .fill(spec.pillFill.opacity(spec.isDark ? opacity : max(0.93, opacity)))
                .overlay(shape.strokeBorder(spec.pillBorder, lineWidth: borderW))
                .shadow(color: settings.glowEnabled ? spec.glow.opacity(0.35 * glowI) : .clear,
                        radius: 16 * glowI, y: 3)
                .shadow(color: .black.opacity((spec.isDark ? 0.5 : 0.2) * settings.shadowStrength),
                        radius: 12, y: 5)
        } else {
        switch pillSkin {
        case .terminal:
            let shape = RoundedRectangle(cornerRadius: pillRadius(10), style: .continuous)
            shape
                .fill(Color(red: 0.03, green: 0.06, blue: 0.03).opacity(opacity))
                .overlay(shape.strokeBorder(ink.opacity(0.6), lineWidth: borderW))
                .shadow(color: settings.glowEnabled ? ink.opacity(0.3 * glowI) : .clear,
                        radius: 16 * glowI, y: 3)
                .shadow(color: .black.opacity(0.5), radius: 12, y: 5)
        case .blueprint:
            let shape = RoundedRectangle(cornerRadius: pillRadius(100), style: .continuous)
            shape
                .fill(Color(red: 0.06, green: 0.17, blue: 0.34).opacity(opacity))
                .overlay(
                    shape.strokeBorder(style: StrokeStyle(lineWidth: borderW, dash: [7, 4]))
                        .foregroundStyle(.white.opacity(0.8))
                )
                .shadow(color: settings.glowEnabled ? .white.opacity(0.2 * glowI) : .clear,
                        radius: 14 * glowI, y: 3)
                .shadow(color: .black.opacity(0.45), radius: 12, y: 5)
        case .retro:
            let shape = RoundedRectangle(cornerRadius: pillRadius(5), style: .continuous)
            shape
                .fill(Color.white.opacity(max(0.92, opacity)))
                .overlay(shape.strokeBorder(.black, lineWidth: borderW + 0.4))
                .shadow(color: .black.opacity(0.85), radius: 0, x: 3, y: 3)
        case .neon:
            let shape = RoundedRectangle(cornerRadius: pillRadius(100), style: .continuous)
            shape
                .fill(Color(red: 0.08, green: 0.03, blue: 0.13).opacity(opacity))
                .overlay(
                    shape.strokeBorder(
                        LinearGradient(colors: [Color(red: 1, green: 0.3, blue: 0.7),
                                                Color(red: 0.3, green: 0.85, blue: 1)],
                                       startPoint: .leading, endPoint: .trailing),
                        lineWidth: borderW + 0.3)
                )
                .shadow(color: settings.glowEnabled
                        ? Color(red: 1, green: 0.3, blue: 0.7).opacity(0.5 * glowI) : .clear,
                        radius: 20 * glowI, y: 4)
                .shadow(color: .black.opacity(0.5), radius: 12, y: 5)
        case .paper:
            let shape = RoundedRectangle(cornerRadius: pillRadius(8), style: .continuous)
            shape
                .fill(Color(red: 0.995, green: 0.988, blue: 0.965).opacity(max(0.92, opacity)))
                .overlay(shape.strokeBorder(
                    Color(red: 0.45, green: 0.36, blue: 0.26).opacity(0.45),
                    lineWidth: borderW))
                .shadow(color: .black.opacity(0.18 * settings.shadowStrength), radius: 4, y: 3)
        case .midnight:
            let shape = RoundedRectangle(cornerRadius: pillRadius(100), style: .continuous)
            shape
                .fill(Color(red: 0.055, green: 0.075, blue: 0.157).opacity(opacity))
                .overlay(
                    shape.strokeBorder(
                        LinearGradient(colors: [Color(red: 0.49, green: 0.55, blue: 0.94),
                                                Color(red: 0.35, green: 0.80, blue: 0.95)],
                                       startPoint: .leading, endPoint: .trailing)
                            .opacity(0.7),
                        lineWidth: borderW)
                )
                .shadow(color: settings.glowEnabled
                        ? Color(red: 0.49, green: 0.55, blue: 0.94).opacity(0.4 * glowI) : .clear,
                        radius: 18 * glowI, y: 3)
                .shadow(color: .black.opacity(0.5 * settings.shadowStrength), radius: 12, y: 5)
        case .forest:
            let shape = RoundedRectangle(cornerRadius: pillRadius(16), style: .continuous)
            shape
                .fill(Color(red: 0.075, green: 0.129, blue: 0.090).opacity(opacity))
                .overlay(shape.strokeBorder(
                    Color(red: 0.44, green: 0.75, blue: 0.53).opacity(0.55),
                    lineWidth: borderW))
                .shadow(color: settings.glowEnabled
                        ? Color(red: 0.44, green: 0.75, blue: 0.53).opacity(0.3 * glowI) : .clear,
                        radius: 14 * glowI, y: 3)
                .shadow(color: .black.opacity(0.45 * settings.shadowStrength), radius: 10, y: 5)
        case .candy:
            let shape = RoundedRectangle(cornerRadius: pillRadius(100), style: .continuous)
            shape
                .fill(Color(red: 1.0, green: 0.918, blue: 0.953).opacity(max(0.94, opacity)))
                .overlay(shape.strokeBorder(.white, lineWidth: borderW + 1))
                .shadow(color: settings.glowEnabled
                        ? Color(red: 0.949, green: 0.420, blue: 0.659).opacity(0.4 * glowI) : .clear,
                        radius: 16 * glowI, y: 3)
                .shadow(color: Color(red: 0.6, green: 0.2, blue: 0.4)
                    .opacity(0.25 * settings.shadowStrength), radius: 10, y: 5)
        default:
            classicBackground(top: top, bottom: bottom, opacity: opacity)
        }
        }
    }

    /// Corner radius for the pill: the user's corner style, or the skin's
    /// natural radius when they left it on Capsule.
    private func pillRadius(_ capsuleDefault: CGFloat) -> CGFloat {
        settings.pillCorner.radius ?? capsuleDefault
    }

    private var cleanShape: some InsettableShape {
        RoundedRectangle(cornerRadius: pillRadius(100), style: .continuous)
    }

    @ViewBuilder
    private func classicBackground(top: Color, bottom: Color, opacity: Double) -> some View {
        if pillSkin == .sketch {
            // Hand-drawn: flat paper/board fill with a wobbly double ink outline.
            let paper: Color = isDark ? Color(white: 0.08) : Color(red: 0.99, green: 0.98, blue: 0.955)
            let sketchInk: Color = isDark ? .white.opacity(0.85) : Color(white: 0.2).opacity(0.9)
            let r = pillRadius(200)
            RoundedRectangle(cornerRadius: r, style: .continuous)
                .fill(paper.opacity(opacity))
                .overlay(
                    ZStack {
                        SketchyRoundedRect(cornerRadius: r, seed: 2)
                            .stroke(sketchInk, lineWidth: settings.pillBorderWidth + 0.4)
                        SketchyRoundedRect(cornerRadius: r, seed: 9, jitter: 2.8)
                            .stroke(sketchInk.opacity(0.3),
                                    lineWidth: max(0.8, settings.pillBorderWidth - 0.2))
                    }
                )
                .shadow(color: settings.glowEnabled
                        ? accent.opacity(0.3 * settings.glowIntensity) : .clear,
                        radius: 18 * settings.glowIntensity, y: 4)
                .shadow(color: .black.opacity((isDark ? 0.5 : 0.18) * settings.shadowStrength),
                        radius: 10, y: 5)
        } else {
            let customBg = settings.pillBgColor
            let glowColor = AppSettings.parseHex(settings.glowColorHex) ?? accent
            cleanShape
                .fill(
                    LinearGradient(colors: customBg.map { [$0.opacity(opacity), $0.opacity(opacity)] }
                                        ?? [top.opacity(opacity), bottom.opacity(opacity)],
                                   startPoint: .top, endPoint: .bottom)
                )
                .background(settings.pillBlur ? AnyView(cleanShape.fill(.ultraThinMaterial)) : AnyView(Color.clear))
                .overlay(
                    cleanShape.strokeBorder(
                        settings.borderGradient
                            ? LinearGradient(colors: [accent.opacity(0.65),
                                                      ink.opacity(0.10),
                                                      accent.opacity(0.25)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [accent.opacity(0.6), accent.opacity(0.6)],
                                             startPoint: .top, endPoint: .bottom),
                        lineWidth: settings.pillBorderWidth)
                )
                .shadow(color: settings.glowEnabled
                        ? glowColor.opacity((isDark ? 0.35 : 0.3) * settings.glowIntensity) : .clear,
                        radius: 22 * settings.glowIntensity, y: 4)
                .shadow(color: .black.opacity((isDark ? 0.5 : 0.22) * settings.shadowStrength),
                        radius: 14, y: 6)
        }
    }

    private var statusDot: some View {
        ZStack {
            switch state.phase {
            case .listening, .handsFree:
                if !settings.statusSymbolName.trimmingCharacters(in: .whitespaces).isEmpty,
                   NSImage(systemSymbolName: settings.statusSymbolName,
                           accessibilityDescription: nil) != nil {
                    Image(systemName: settings.statusSymbolName)
                        .font(.system(size: 12))
                        .foregroundStyle(accent)
                } else {
                    switch settings.statusDotStyle {
                    case .dot:
                        Circle().fill(accent)
                            .frame(width: 10, height: 10)
                            .shadow(color: settings.glowEnabled ? accent.opacity(0.9) : .clear, radius: 6)
                    case .mic:
                        Image(systemName: "mic.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(accent)
                    case .none:
                        EmptyView()
                    }
                }
            case .processing:
                ProgressView().controlSize(.small).tint(ink)
            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(settings.doneAccent ? accent : .green)
                    .font(.system(size: 15))
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
        let h = CGFloat(settings.waveHeight)
        switch settings.waveStyle {
        case .bars:
            HStack(spacing: CGFloat(settings.barSpacing)) {
                ForEach(Array(state.levels.enumerated()), id: \.offset) { _, level in
                    // Mirror mode grows bars from the centerline both ways.
                    RoundedRectangle(cornerRadius: settings.squareBars ? 0 : CGFloat(settings.barWidth) / 2,
                                     style: .continuous)
                        .fill(LinearGradient(colors: markColors(level),
                                             startPoint: .bottom, endPoint: .top))
                        .frame(width: CGFloat(settings.barWidth), height: 6 + level * (h - 8))
                        .frame(height: h, alignment: settings.waveMirror ? .center : .bottom)
                }
            }
            .frame(height: h)
            .animation(settings.reduceMotion ? nil : .linear(duration: 0.08), value: state.levels)
        case .blocks:
            // LED meter: each column is 5 segments lit from the bottom.
            HStack(spacing: CGFloat(settings.barSpacing)) {
                ForEach(Array(state.levels.enumerated()), id: \.offset) { _, level in
                    let lit = Int((level * 5).rounded())
                    VStack(spacing: 1.5) {
                        ForEach((0..<5).reversed(), id: \.self) { seg in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(seg < lit
                                      ? (markColors(level).last ?? accent)
                                      : ink.opacity(0.12))
                                .frame(width: CGFloat(settings.barWidth) + 1,
                                       height: (h - 12) / 5)
                        }
                    }
                }
            }
            .frame(height: h)
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
            if settings.waveMonochrome { return [ink.opacity(0.45), ink.opacity(0.95)] }
            if settings.accentGradient { return [accent, settings.accentColor2] }
            return [accent.opacity(0.75), ink.opacity(0.95)]
        }
    }

    private var transcript: some View {
        let live = state.phase == .listening || state.phase == .handsFree
        let shown = displayText + (settings.pillCursor && live ? "▎" : "")
        return Text(shown)
            .font(settings.monospaceTranscript
                  ? .system(size: CGFloat(settings.pillTextSize), design: .monospaced)
                  : transcriptFont)
            .italic(settings.pillItalic)
            .foregroundStyle(ink.opacity(state.text.isEmpty ? 0.55 : 0.95))
            .lineLimit(1)
            .truncationMode(.head)
            .frame(minWidth: CGFloat(settings.pillMinWidth),
                   maxWidth: CGFloat(settings.transcriptWidth),
                   alignment: settings.transcriptCentered ? .center : .leading)
    }

    private var transcriptFont: Font {
        let base = CGFloat(settings.pillTextSize)
        let weight = settings.pillFontWeight.weight
        if let spec = pillSkin.spec { return spec.font(base, weight) }
        switch pillSkin {
        case .sketch: return .custom(SketchStyle.fontName(isDark ? .dark : .light), size: base + 1)
        case .terminal: return .custom("Menlo", size: base - 1)
        case .blueprint: return .custom("Noteworthy", size: base + 1)
        case .retro: return .custom("Monaco", size: base - 1)
        case .neon: return .system(size: base, weight: weight, design: .rounded)
        case .paper: return .custom("Georgia", size: base)
        case .midnight: return .system(size: base, weight: weight)
        case .forest: return .custom("Avenir Next", size: base)
        case .candy: return .system(size: base, weight: weight, design: .rounded)
        default: return .system(size: base, weight: weight, design: settings.pillFont.design)
        }
    }

    private var wordCount: Int {
        state.text.split(whereSeparator: \.isWhitespace).count
    }

    private var displayText: String {
        settings.uppercasePill ? rawDisplayText.uppercased() : rawDisplayText
    }

    private var rawDisplayText: String {
        if !state.text.isEmpty { return state.text }
        switch state.phase {
        case .listening:
            let l = settings.listeningLabel.trimmingCharacters(in: .whitespaces)
            if !l.isEmpty { return l }
            if let app = state.targetApp { return "Listening → \(app)" }
            return "Listening… release to insert"
        case .handsFree: return "Hands-free — tap to finish, Esc cancels"
        case .processing:
            let l = settings.processingLabel.trimmingCharacters(in: .whitespaces)
            return l.isEmpty ? "Polishing…" : l
        case .done:
            let l = settings.doneLabel.trimmingCharacters(in: .whitespaces)
            if !l.isEmpty { return l }
            return state.copiedMode ? "Copied — ⌘V to paste" : "Inserted ✓"
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
