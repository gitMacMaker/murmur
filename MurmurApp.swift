import AppKit
import AVFoundation
import Combine
import Speech

// MARK: - App delegate / state machine

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    private enum Phase { case idle, recording, processing }
    private var phase: Phase = .idle

    private var statusItem: NSStatusItem!
    private var lastVoiceAt = Date()
    private var silenceTimer: Timer?
    private var iconWatcher: AnyCancellable?
    private let pill = PillPanel()
    private let transcriber = Transcriber()
    private let hotkeys = HotkeyManager()
    private let settings = AppSettings.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildStatusItem()
        requestPermissions()
        wireTranscriber()
        wireHotkeys()
        if !UserDefaults.standard.bool(forKey: "onboarded") {
            UserDefaults.standard.set(true, forKey: "onboarded")
            OnboardingWindowController.shared.show()
        } else if UserDefaults.standard.bool(forKey: "welcomeAfterRelaunch") {
            UserDefaults.standard.set(false, forKey: "welcomeAfterRelaunch")
            OnboardingWindowController.shared.show()
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(showTestPill),
            name: Notification.Name("MurmurTestPill"), object: nil)
    }

    // MARK: Permissions

    private func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { _ in }
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
        // Deliberately NO Accessibility prompt here — prompting on every
        // launch is obnoxious. The Welcome window guides the user instead,
        // and a silent check registers Murmur in the Accessibility list.
        AXIsProcessTrusted()
    }

    // MARK: Wiring

    private func wireTranscriber() {
        transcriber.onPartial = { [weak self] text in self?.pill.state.text = text }
        transcriber.onLevel = { [weak self] level in
            DispatchQueue.main.async {
                self?.pill.state.pushLevel(level)
                if level > 0.3 { self?.lastVoiceAt = Date() }
            }
        }
    }

    private func wireHotkeys() {
        hotkeys.isRecording = { [weak self] in self?.phase == .recording }
        hotkeys.onStart = { [weak self] in self?.startRecording() }
        hotkeys.onFinish = { [weak self] in self?.finishRecording() }
        hotkeys.onCancel = { [weak self] in self?.cancelRecording() }
        hotkeys.activate()
    }

    private func play(_ event: SoundEvent) {
        guard settings.soundsEnabled else { return }
        guard let sound = NSSound(named: settings.soundTheme.sound(for: event)) else { return }
        sound.volume = Float(settings.soundVolume)
        sound.play()
    }

    // MARK: Recording lifecycle

    private func startRecording() {
        guard phase == .idle else { return }
        do {
            try transcriber.start()
        } catch {
            pill.state.phase = .error
            pill.state.text = error.localizedDescription
            pill.show()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in self?.pill.hide() }
            return
        }
        phase = .recording
        lastVoiceAt = Date()
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkAutoStop()
        }
        pill.state.phase = .listening
        pill.state.text = ""
        pill.state.targetApp = NSWorkspace.shared.frontmostApplication?.localizedName
        pill.state.startedAt = Date()
        pill.show()
        play(.start)
        setIcon(recording: true)
        // If the press turns out to be a quick tap, reflect hands-free mode.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self, self.phase == .recording, self.hotkeys.handsFree else { return }
            if self.pill.state.phase == .listening { self.pill.state.phase = .handsFree }
        }
    }

    private func checkAutoStop() {
        guard settings.autoStopEnabled,
              phase == .recording,
              hotkeys.handsFree,
              !pill.state.text.isEmpty,
              Date().timeIntervalSince(lastVoiceAt) > settings.silenceSeconds else { return }
        hotkeys.handsFree = false
        finishRecording()
    }

    private func finishRecording() {
        guard phase == .recording else { return }
        silenceTimer?.invalidate()
        silenceTimer = nil
        phase = .processing
        pill.state.phase = .processing
        transcriber.stop { [weak self] raw in self?.handleTranscript(raw) }
    }

    private func cancelRecording() {
        guard phase == .recording else { return }
        silenceTimer?.invalidate()
        silenceTimer = nil
        transcriber.cancel()
        phase = .idle
        pill.hide()
        setIcon(recording: false)
        play(.cancel)
    }

    private func handleTranscript(_ raw: String) {
        var text = settings.tidyEnabled
            ? TextCleaner.tidy(raw)
            : raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var usedCommands = false
        if settings.voiceCommandsEnabled {
            let before = text
            text = TextCleaner.applyCommands(text)
            usedCommands = text != before
        }
        text = TextCleaner.applyReplacements(text, settings.replacements)
        guard !text.isEmpty else {
            phase = .idle
            pill.hide()
            setIcon(recording: false)
            return
        }
        // Per-app rules can override tone and case for this delivery.
        let rule = settings.appRules.first {
            !$0.appName.isEmpty &&
            (pill.state.targetApp ?? "").localizedCaseInsensitiveContains($0.appName)
        }
        let tone = rule?.tone ?? settings.polishTone
        let ocase = rule?.ocase ?? settings.outputCase
        if settings.polishEnabled {
            TextCleaner.polish(text, tone: tone,
                               custom: settings.customPolishPrompt) { [weak self] polished in
                self?.deliver(polished, usedCommands: usedCommands, ocase: ocase)
            }
        } else {
            deliver(text, usedCommands: usedCommands, ocase: ocase)
        }
    }

    private func deliver(_ rawText: String, usedCommands: Bool = false,
                         ocase: OutputCase? = nil) {
        let text = TextCleaner.applyCase(rawText, ocase ?? settings.outputCase)
        if settings.insertTarget == .clipboardOnly {
            Inserter.copyOnly(text)
        } else {
            Inserter.insert(text)
        }
        let unlocked = settings.record(text, usedPolish: settings.polishEnabled,
                                       usedCommands: usedCommands)
        rebuildMenu()
        pill.state.phase = .done
        pill.state.text = text
        play(.insert)
        setIcon(recording: false)
        phase = .idle
        let hideDelay: TimeInterval = unlocked.isEmpty ? 1.1 : 3.0
        if let first = unlocked.first {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self, self.phase == .idle else { return }
                self.pill.state.text = "🏆 Unlocked: \(first.name)!"
                self.play(.unlock)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + hideDelay) { [weak self] in
            guard let self, self.phase == .idle else { return }
            self.pill.hide()
        }
    }

    // MARK: Status item + menu

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setIcon(recording: false)
        rebuildMenu()
        iconWatcher = settings.$menuIcon.dropFirst()
            .combineLatest(settings.$showMenuBarCount.dropFirst().prepend(settings.showMenuBarCount))
            .sink { [weak self] _, _ in
                DispatchQueue.main.async { self?.setIcon(recording: self?.phase == .recording) }
            }
    }

    private func setIcon(recording: Bool) {
        let name = settings.menuIcon.symbol(recording: recording)
        let img = NSImage(systemSymbolName: name, accessibilityDescription: "Murmur")
        img?.isTemplate = true
        statusItem.button?.image = img
        statusItem.button?.contentTintColor = recording ? .systemRed : nil
        if settings.showMenuBarCount, settings.todayWords > 0 {
            statusItem.button?.title = " \(settings.todayWords)"
            statusItem.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            statusItem.button?.imagePosition = .imageLeading
        } else {
            statusItem.button?.title = ""
        }
        rebuildMenu() // keep the Start/Finish dictation item in sync
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let header = NSMenuItem(title: "Murmur — hold \(settings.hotkey.name) and talk",
                                action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let dictate = NSMenuItem(
            title: phase == .recording ? "Finish && Insert" : "Start Dictation (hands-free)",
            action: #selector(toggleDictation), keyEquivalent: "d")
        dictate.target = self
        menu.addItem(dictate)

        if let last = settings.history.max(by: { $0.date < $1.date }) {
            let insertLast = NSMenuItem(title: "Insert Last Transcript",
                                        action: #selector(insertLastTranscript), keyEquivalent: "")
            insertLast.target = self
            insertLast.toolTip = last.text
            menu.addItem(insertLast)

            let copyLast = NSMenuItem(title: "Copy Last Transcript",
                                      action: #selector(copyLastTranscript), keyEquivalent: "")
            copyLast.target = self
            menu.addItem(copyLast)
        }

        let snippets = settings.replacements.filter { !$0.phrase.isEmpty && !$0.replacement.isEmpty }
        if !snippets.isEmpty {
            let parent = NSMenuItem(title: "Insert Snippet", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for (i, r) in snippets.prefix(12).enumerated() {
                let title = r.phrase.count > 36 ? String(r.phrase.prefix(36)) + "…" : r.phrase
                let item = NSMenuItem(title: title, action: #selector(insertSnippet(_:)), keyEquivalent: "")
                item.target = self
                item.tag = i
                item.toolTip = r.replacement
                sub.addItem(item)
            }
            parent.submenu = sub
            menu.addItem(parent)
        }

        let prefs = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)

        let welcome = NSMenuItem(title: "Welcome & Permissions…", action: #selector(openWelcome), keyEquivalent: "")
        welcome.target = self
        menu.addItem(welcome)

        let about = NSMenuItem(title: "About Murmur", action: #selector(openAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        if !settings.history.isEmpty {
            let recent = NSMenuItem(title: "Recent Transcripts", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for (i, item) in settings.history.prefix(8).enumerated() {
                let title = item.text.count > 52 ? String(item.text.prefix(52)) + "…" : item.text
                let mi = NSMenuItem(title: title, action: #selector(copyHistoryItem(_:)), keyEquivalent: "")
                mi.target = self
                mi.tag = i
                sub.addItem(mi)
            }
            recent.submenu = sub
            menu.addItem(recent)
        }

        if settings.totalWords > 0 {
            let stats = NSMenuItem(
                title: String(format: "%d words dictated • ~%.0f min saved",
                              settings.totalWords, settings.minutesSaved),
                action: nil, keyEquivalent: "")
            stats.isEnabled = false
            menu.addItem(stats)
        }
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Murmur", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusItem.menu = menu
    }

    /// Appearance pane "Show real pill" button: flash the live overlay.
    @objc private func showTestPill() {
        guard phase == .idle else { return }
        pill.state.phase = .listening
        pill.state.text = "Testing, one two three…"
        pill.state.targetApp = nil
        pill.state.startedAt = nil
        pill.state.levels = (0..<28).map { _ in CGFloat.random(in: 0.1...0.9) }
        pill.show()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self, self.phase == .idle else { return }
            self.pill.hide()
        }
    }

    @objc private func toggleDictation() {
        if phase == .recording {
            hotkeys.handsFree = false
            finishRecording()
        } else if phase == .idle {
            hotkeys.handsFree = true
            startRecording()
        }
    }

    @objc private func insertSnippet(_ sender: NSMenuItem) {
        let snippets = settings.replacements.filter { !$0.phrase.isEmpty && !$0.replacement.isEmpty }
        guard sender.tag < snippets.count else { return }
        Inserter.insert(snippets[sender.tag].replacement)
    }

    @objc private func insertLastTranscript() {
        guard let last = settings.history.max(by: { $0.date < $1.date }) else { return }
        Inserter.insert(last.text)
    }

    @objc private func copyLastTranscript() {
        guard let last = settings.history.max(by: { $0.date < $1.date }) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(last.text, forType: .string)
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func openWelcome() {
        OnboardingWindowController.shared.show()
    }

    @objc private func openAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(
                string: "Hold a key. Talk. It types.\nOn-device dictation for the Mac.",
                attributes: [.font: NSFont.systemFont(ofSize: 11),
                             .foregroundColor: NSColor.secondaryLabelColor]),
        ])
    }

    @objc private func copyHistoryItem(_ sender: NSMenuItem) {
        guard sender.tag < settings.history.count else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(settings.history[sender.tag].text, forType: .string)
    }
}
