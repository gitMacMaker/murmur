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
    let onDone: () -> Void
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var allGranted: Bool {
        PermState.mic == .granted && PermState.speech == .granted && PermState.accessibility == .granted
    }

    var body: some View {
        let p = Palette.of(scheme)
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                    .resizable()
                    .frame(width: 80, height: 80)
                Text("Welcome to Murmur")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(p.text)
                Text("Voice to text in any app — private, on-device, instant.")
                    .font(.system(size: 13))
                    .foregroundStyle(p.subtext)

                HStack(spacing: 8) {
                    Text(settings.hotkey.name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(p.text)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(p.card)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .strokeBorder(p.border, lineWidth: 1)
                                )
                        )
                    Text("hold to talk · tap for hands-free · Esc cancels")
                        .font(.system(size: 11.5))
                        .foregroundStyle(p.subtext)
                }
                .padding(.top, 6)
            }
            .padding(.top, 36)

            VStack(spacing: 0) {
                permissionRow(title: "Microphone",
                              detail: "Hear you while the key is held",
                              state: PermState.mic) {
                    if PermState.mic == .notDetermined {
                        AVCaptureDevice.requestAccess(for: .audio) { _ in }
                    } else {
                        openPrivacyPane("Privacy_Microphone")
                    }
                }
                RowDivider()
                permissionRow(title: "Speech Recognition",
                              detail: "Transcribe on-device — nothing leaves your Mac",
                              state: PermState.speech) {
                    if PermState.speech == .notDetermined {
                        SFSpeechRecognizer.requestAuthorization { _ in }
                    } else {
                        openPrivacyPane("Privacy_SpeechRecognition")
                    }
                }
                RowDivider()
                accessibilityRow
            }
            .background(p.card)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(p.border, lineWidth: 1)
            )
            .padding(.horizontal, 28)
            .padding(.top, 28)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $practiceText)
                    .font(.system(size: 12.5))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                if practiceText.isEmpty {
                    Text("Try it — click here, hold \(settings.hotkey.name), and talk…")
                        .font(.system(size: 12.5))
                        .foregroundStyle(p.subtext.opacity(0.8))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 62)
            .background(p.card)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(p.border, lineWidth: 1)
            )
            .padding(.horizontal, 28)
            .padding(.top, 14)

            aiPolishCard
                .padding(.horizontal, 28)
                .padding(.top, 10)

            Spacer()

            VStack(spacing: 10) {
                if allGranted {
                    Label("You're all set", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.green)
                }
                Button(action: onDone) {
                    Text(allGranted ? "Start Dictating" : "I'll finish this later")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(settings.accentContrastColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(settings.accentColor)
                        )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .padding(.horizontal, 28)
            }
            .padding(.bottom, 24)
        }
        .frame(width: 440, height: 700)
        .background {
            ZStack {
                Palette.of(scheme).bg
                SkinBackground(seed: 3)
            }
        }
        .onReceive(timer) { _ in tick += 1 } // re-checks permission states live
        .id(tick)
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
                    SecureField("API key (optional)", text: $apiKeyDraft)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 140)
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
