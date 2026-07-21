import SwiftUI
import AppKit
import AVFoundation
import Speech

// MARK: - Dock icon while windows are open

/// Murmur is a menu-bar app (LSUIElement), but while one of its windows is
/// open it should behave like a regular app: Dock icon, focusable, ⌘-tab.
final class WindowPolicyManager: NSObject {
    static let shared = WindowPolicyManager()
    private var windows = NSHashTable<NSWindow>.weakObjects()

    func opened(_ w: NSWindow) {
        windows.add(w)
        NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: w)
        NotificationCenter.default.addObserver(self, selector: #selector(closed(_:)),
                                               name: NSWindow.willCloseNotification, object: w)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func closed(_ n: Notification) {
        guard let w = n.object as? NSWindow else { return }
        windows.remove(w)
        DispatchQueue.main.async {
            if self.windows.allObjects.filter({ $0.isVisible }).isEmpty {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}

// MARK: - Onboarding window

final class OnboardingWindowController {
    static let shared = OnboardingWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 700),
                             styleMask: [.titled, .closable],
                             backing: .buffered, defer: false)
            w.title = "Welcome to Murmur"
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.center()
            w.contentView = NSHostingView(rootView: OnboardingView { [weak w] in w?.close() })
            window = w
        }
        WindowPolicyManager.shared.opened(window!)
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Permission plumbing

enum PermState {
    case granted, denied, notDetermined

    static var mic: PermState {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }
    static var speech: PermState {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }
    static var accessibility: PermState {
        AXIsProcessTrusted() ? .granted : .denied
    }
}

private func openPrivacyPane(_ anchor: String) {
    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
    NSWorkspace.shared.open(url)
}

/// Relaunches Murmur (used when a permission grant needs a fresh process
/// to take effect). The welcome window reopens after the relaunch.
enum AppRelauncher {
    static func relaunch() {
        UserDefaults.standard.set(true, forKey: "welcomeAfterRelaunch")
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = ["-c", "sleep 0.6; open \"\(path)\""]
        try? task.run()
        NSApp.terminate(nil)
    }
}

// MARK: - Onboarding view

struct OnboardingView: View {
    @ObservedObject var settings = AppSettings.shared
    @Environment(\.colorScheme) private var scheme
    @State private var tick = 0
    @State private var practiceText = ""
    @State private var apiKeyDraft = ""
    @State private var cliFound: Bool?
    @State private var step: Int
    let onDone: () -> Void
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(startStep: Int = 0, onDone: @escaping () -> Void) {
        _step = State(initialValue: startStep)
        self.onDone = onDone
    }

    private let lastStep = 4   // 0 welcome · 1 permissions · 2 try it · 3 superpowers · 4 polish

    private var allGranted: Bool {
        PermState.mic == .granted && PermState.speech == .granted && PermState.accessibility == .granted
    }

    var body: some View {
        let _ = tick  // read so the 1s timer re-runs body and re-checks permissions
        let p = Palette.of(scheme)
        VStack(spacing: 0) {
            // Content — VStack (not Group) so the frame applies to the whole
            // step, not each subview (a Group forwards modifiers to children).
            VStack(spacing: 0) {
                switch step {
                case 0: welcomeStep(p)
                case 1: permissionsStep(p)
                case 2: tryItStep(p)
                case 3: superpowersStep(p)
                default: polishStep(p)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            footer(p)
        }
        .frame(width: 440, height: 700)
        .background {
            ZStack {
                Palette.of(scheme).bg
                SkinBackground(seed: 3)
            }
        }
        // Bumping `tick` re-runs body (re-reading the live PermState values)
        // every second. Deliberately NOT `.id(tick)` — that would rebuild the
        // subtree and drop keyboard focus from the API-key / practice fields
        // mid-type.
        .onReceive(timer) { _ in tick += 1 }
    }

    // MARK: Steps

    private func stepHeader(_ icon: String, _ title: String, _ subtitle: String,
                            _ p: Palette) -> some View {
        VStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(settings.accentColor)
                .frame(height: 40)
            Text(title)
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(p.text)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(p.subtext)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 44)
        .padding(.horizontal, 32)
    }

    @ViewBuilder
    private func welcomeStep(_ p: Palette) -> some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                .resizable().frame(width: 84, height: 84)
                .padding(.top, 60)
            Text("Welcome to Murmur")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(p.text)
            Text("Voice to text in any app — private, on-device, and instant. Let's get you dictating in under a minute.")
                .font(.system(size: 13.5))
                .foregroundStyle(p.subtext)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 40)

            VStack(spacing: 10) {
                loopRow("1", "Hold \(settings.hotkey.name)", "and start talking", p)
                loopRow("2", "Release the key", "your words appear where you're typing", p)
                loopRow("3", "That's it", "quick-tap instead for hands-free · Esc cancels", p)
            }
            .padding(.horizontal, 34)
            .padding(.top, 8)
        }
    }

    private func loopRow(_ n: String, _ title: String, _ detail: String, _ p: Palette) -> some View {
        HStack(spacing: 12) {
            Text(n)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(settings.accentContrastColor)
                .frame(width: 26, height: 26)
                .background(Circle().fill(settings.accentColor))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(p.text)
                Text(detail).font(.system(size: 11.5)).foregroundStyle(p.subtext)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func permissionsStep(_ p: Palette) -> some View {
        stepHeader("lock.shield", "Three permissions",
                   "Murmur needs these to hear you and type for you. Nothing leaves your Mac.", p)
        VStack(spacing: 0) {
            permissionRow(title: "Microphone",
                          detail: "Hear you while the key is held",
                          state: PermState.mic) {
                if PermState.mic == .notDetermined {
                    AVCaptureDevice.requestAccess(for: .audio) { _ in }
                } else { openPrivacyPane("Privacy_Microphone") }
            }
            RowDivider()
            permissionRow(title: "Speech Recognition",
                          detail: "Transcribe on-device — nothing leaves your Mac",
                          state: PermState.speech) {
                if PermState.speech == .notDetermined {
                    SFSpeechRecognizer.requestAuthorization { _ in }
                } else { openPrivacyPane("Privacy_SpeechRecognition") }
            }
            RowDivider()
            accessibilityRow
        }
        .background(p.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(p.border, lineWidth: 1))
        .padding(.horizontal, 28)
        .padding(.top, 22)

        if allGranted {
            Label("All granted — you're ready", systemImage: "checkmark.circle.fill")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.green)
                .padding(.top, 14)
        }
    }

    @ViewBuilder
    private func tryItStep(_ p: Palette) -> some View {
        stepHeader("waveform", "Give it a go",
                   "Click the box, hold \(settings.hotkey.name), and say a sentence. Try “new line” or “fire emoji” too.", p)
        ZStack(alignment: .topLeading) {
            TextEditor(text: $practiceText)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(6)
            if practiceText.isEmpty {
                Text("Hold \(settings.hotkey.name) and talk…")
                    .font(.system(size: 13))
                    .foregroundStyle(p.subtext.opacity(0.8))
                    .padding(.horizontal, 11).padding(.vertical, 14)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: 120)
        .background(p.card)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(practiceText.isEmpty ? p.border : settings.accentColor.opacity(0.6), lineWidth: 1))
        .padding(.horizontal, 28)
        .padding(.top, 22)

        if !practiceText.isEmpty {
            Label("Nice — it works!", systemImage: "checkmark.circle.fill")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.green)
                .padding(.top, 14)
        } else if !allGranted {
            Text("Not typing anything? Finish granting permissions on the previous step.")
                .font(.system(size: 11.5))
                .foregroundStyle(p.subtext)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40).padding(.top, 12)
        }
    }

    @ViewBuilder
    private func superpowersStep(_ p: Palette) -> some View {
        stepHeader("wand.and.stars", "Murmur has depth",
                   "You'll never need most of it — but it's there when you do.", p)
        ScrollView {
            VStack(spacing: 0) {
                featureRow("text.badge.plus", "Voice commands",
                           "Say “new line”, “scratch that”, or “send it” and Murmur obeys.", p)
                RowDivider()
                featureRow("character.book.closed", "Your dictionary",
                           "Teach it your name, email, and jargon in Settings ▸ Dictionary.", p)
                RowDivider()
                featureRow("macwindow", "Rules per app",
                           "Fix grammar in Mail, go casual in Slack — Settings ▸ Apps.", p)
                RowDivider()
                featureRow("sparkles", "AI polish & commands",
                           "Let Claude tidy your text, or hold a key and speak an edit to your selection.", p)
                RowDivider()
                featureRow("globe", "63 languages, live translate",
                           "Dictate in any language, or have it come out translated.", p)
                RowDivider()
                featureRow("paintbrush", "100 skins",
                           "Make the app and pill yours in Settings ▸ Appearance.", p)
            }
            .background(p.card)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(p.border, lineWidth: 1))
            .padding(.horizontal, 28)
            .padding(.top, 18)
            .padding(.bottom, 10)
        }
    }

    private func featureRow(_ icon: String, _ title: String, _ detail: String, _ p: Palette) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(settings.accentColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(p.text)
                Text(detail).font(.system(size: 11.5)).foregroundStyle(p.subtext)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }

    @ViewBuilder
    private func polishStep(_ p: Palette) -> some View {
        stepHeader("checkmark.seal", "One last thing",
                   "AI polish is optional — it cleans up false starts and powers translate & Command Mode.", p)
        aiPolishCard
            .padding(.horizontal, 28)
            .padding(.top, 22)
        Text("Skip it and Murmur still works great — plain, fast, on-device dictation. You can add a key anytime in Settings.")
            .font(.system(size: 11.5))
            .foregroundStyle(p.subtext)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 36).padding(.top, 16)
    }

    // MARK: Footer / paging

    @ViewBuilder
    private func footer(_ p: Palette) -> some View {
        VStack(spacing: 12) {
            // Page dots
            HStack(spacing: 7) {
                ForEach(0...lastStep, id: \.self) { i in
                    Circle()
                        .fill(i == step ? settings.accentColor : p.subtext.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }
            HStack(spacing: 10) {
                if step > 0 {
                    Button("Back") { withAnimation { step -= 1 } }
                        .controlSize(.large)
                }
                Spacer()
                if step < lastStep {
                    Button(action: { withAnimation { step += 1 } }) {
                        Text(step == 1 && !allGranted ? "Skip for now" : "Next")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(settings.accentContrastColor)
                            .padding(.horizontal, 22).padding(.vertical, 9)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(settings.accentColor))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button(action: onDone) {
                        Text("Start Dictating")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(settings.accentContrastColor)
                            .padding(.horizontal, 22).padding(.vertical, 9)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(settings.accentColor))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
    }

    private func permissionRow(title: String, detail: String,
                               state: PermState, action: @escaping () -> Void) -> some View {
        let p = Palette.of(scheme)
        return HStack(spacing: 12) {
            statusDot(state)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(p.text)
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(p.subtext)
            }
            Spacer(minLength: 10)
            switch state {
            case .granted:
                EmptyView()
            case .notDetermined:
                Button("Grant", action: action).controlSize(.small)
            case .denied:
                Button("Open Settings…", action: action).controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    /// Accessibility gets special handling: a granted toggle can point at a
    /// stale entry from an older build, in which case the running app still
    /// reads "not trusted". Offer the remove-and-re-add hint plus a restart.
    @ViewBuilder
    private var accessibilityRow: some View {
        let p = Palette.of(scheme)
        let granted = PermState.accessibility == .granted
        HStack(spacing: 12) {
            statusDot(granted ? .granted : .denied)
            VStack(alignment: .leading, spacing: 1) {
                Text("Accessibility")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(p.text)
                Text(granted
                     ? "Type the result into the app you're using"
                     : "Toggled on but not detected? Remove Murmur from the list (−), re-add it, then Restart App.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(p.subtext)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 10)
            if !granted {
                VStack(spacing: 4) {
                    Button("Open Settings…") { openPrivacyPane("Privacy_Accessibility") }
                        .controlSize(.small)
                    Button("Restart App") { AppRelauncher.relaunch() }
                        .controlSize(.small)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    /// Optional AI-polish setup: shows CLI status, or lets a new user drop in
    /// their own Anthropic API key (stored in the Keychain).
    @ViewBuilder
    private var aiPolishCard: some View {
        let p = Palette.of(scheme)
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("AI polish (optional)")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(p.text)
                Text(polishStatusText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(p.subtext)
            }
            Spacer(minLength: 10)
            if settings.hasAPIKey || cliFound == true {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.green)
            } else {
                HStack(spacing: 5) {
                    SecureField("sk-ant-…", text: $apiKeyDraft)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 104)
                    Button("Save") {
                        settings.saveAPIKey(apiKeyDraft)
                        apiKeyDraft = ""
                    }
                    .controlSize(.small)
                    .disabled(apiKeyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(p.card)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(p.border, lineWidth: 1)
        )
        .onAppear {
            if cliFound == nil { ClaudeCLI.detect { cliFound = $0 } }
        }
    }

    private var polishStatusText: String {
        if settings.hasAPIKey { return "Your API key is saved in the Keychain" }
        switch cliFound {
        case true: return "Claude CLI detected — polish is ready to enable in Settings"
        case false: return "No Claude CLI found — add an Anthropic API key to enable polish"
        default: return "Cleans up false starts via Claude — bring your own key or CLI"
        }
    }

    private func statusDot(_ state: PermState) -> some View {
        Group {
            if state == .granted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.green)
            } else {
                Circle()
                    .strokeBorder(Palette.of(scheme).border, lineWidth: 1.5)
                    .frame(width: 15, height: 15)
            }
        }
        .frame(width: 18)
    }
}
