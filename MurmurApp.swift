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
    private var idleDotWatcher: AnyCancellable?
    private var menuModeWatcher: AnyCancellable?
    private var currentMenu: NSMenu?
    private let pill = PillPanel()
    private let transcriber = Transcriber()
    private var hotkeys = HotkeyManager()
    private var axPoll: Timer?
    private let settings = AppSettings.shared
    /// Last text inserted into the active app — enables "Undo Last Insert".
    private var lastInsertedText: String?
    /// When true the hotkey is ignored (menu ▸ Pause Murmur).
    private var paused = false
    /// Set by menu ▸ Dictate to Clipboard: the next delivery copies instead
    /// of inserting, then the flag clears.
    private var forceClipboardOnce = false
    /// Duration of the dictation being processed, for history metadata.
    private var lastSessionSeconds: Double?
    /// Updates the menu-bar timer while recording (when enabled).
    private var menuTimerTicker: Timer?

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
        // Reflect the idle-dot toggle AND size immediately — without this the
        // dot only (dis)appears after the NEXT dictation, which reads as a
        // dead setting. Size changes re-show so the dot is there to resize.
        idleDotWatcher = Publishers.Merge3(
            settings.$idleIndicator.dropFirst().map { _ in () },
            settings.$idleDotSize.dropFirst().map { _ in () },
            settings.$idleDotOpacity.dropFirst().map { _ in () }
        ).sink { [weak self] in
            guard let self, self.phase == .idle else { return }
            self.pill.hide(toIdleDot: self.settings.idleIndicator)
        }
        // And show it from launch if it's enabled — previously the dot stayed
        // hidden after a relaunch until the first dictation.
        if settings.idleIndicator { pill.hide(toIdleDot: true) }
        NotificationCenter.default.addObserver(
            self, selector: #selector(pillTapped),
            name: Notification.Name("MurmurPillTapped"), object: nil)
        // Don't keep the mic open behind a locked screen.
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(screenLocked),
            name: Notification.Name("com.apple.screenIsLocked"), object: nil)
        runWeeklyAutoBackupIfDue()
        checkForUpdateIfDue()
        // Global key monitors registered without Accessibility trust never
        // fire — and monitors registered BEFORE trust is granted stay dead.
        // Watch for the grant and rearm the hotkey the moment it lands.
        if !AXIsProcessTrusted() {
            OnboardingWindowController.shared.show()
            axPoll = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                guard let self, AXIsProcessTrusted() else { return }
                self.axPoll?.invalidate()
                self.axPoll = nil
                self.hotkeys = HotkeyManager()
                self.wireHotkeys()
                self.rebuildMenu()
                NSSound(named: "Glass")?.play()
            }
        }
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
        if settings.quietHours {
            let hour = Calendar.current.component(.hour, from: Date())
            if hour >= 22 || hour < 8 { return }
        }
        guard let sound = NSSound(named: settings.soundTheme.sound(for: event)) else { return }
        sound.volume = Float(settings.soundVolume)
        sound.play()
    }

    // MARK: Recording lifecycle

    private func startRecording() {
        guard phase == .idle, !paused else { return }
        do {
            try transcriber.start()
        } catch {
            pill.state.phase = .error
            pill.state.text = error.localizedDescription
            pill.show()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
                guard let self else { return }
                self.pill.hide(toIdleDot: self.settings.idleIndicator)
            }
            return
        }
        phase = .recording
        lastVoiceAt = Date()
        if settings.maxRecordSeconds > 0 {
            let cap = TimeInterval(settings.maxRecordSeconds)
            DispatchQueue.main.asyncAfter(deadline: .now() + cap) { [weak self] in
                guard let self, self.phase == .recording,
                      let started = self.pill.state.startedAt,
                      Date().timeIntervalSince(started) >= cap - 0.5 else { return }
                self.hotkeys.handsFree = false
                self.finishRecording()
            }
        }
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkAutoStop()
        }
        pill.state.phase = .listening
        pill.state.text = ""
        pill.state.targetApp = NSWorkspace.shared.frontmostApplication?.localizedName
        pill.state.targetIcon = settings.showTargetIcon
            ? NSWorkspace.shared.frontmostApplication?.icon : nil
        pill.state.startedAt = Date()
        pill.show()
        play(.start)
        if settings.hapticsEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
        setIcon(recording: true)
        if settings.showMenuTimer {
            menuTimerTicker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                guard let self, self.phase == .recording,
                      let started = self.pill.state.startedAt else { return }
                let secs = Int(Date().timeIntervalSince(started))
                self.statusItem.button?.title = String(format: " %d:%02d", secs / 60, secs % 60)
            }
        }
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
        if let started = pill.state.startedAt {
            let elapsed = Date().timeIntervalSince(started)
            settings.totalSpeakSeconds += elapsed
            lastSessionSeconds = elapsed
        }
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
        pill.hide(toIdleDot: settings.idleIndicator)
        setIcon(recording: false)
        play(.cancel)
    }

    private func handleTranscript(_ raw: String) {
        var text = settings.tidyEnabled
            ? TextCleaner.tidy(raw)
            : raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if settings.stripStarterWords { text = TextCleaner.stripStarterWords(text) }
        if settings.removeDoubledWords { text = TextCleaner.removeDoubledWords(text) }
        var usedCommands = false
        if settings.voiceCommandsEnabled {
            let before = text
            text = TextCleaner.applyScratchThat(text)
            text = TextCleaner.applyCommands(text, includeEmoji: settings.emojiCommands)
            usedCommands = text != before
        }
        if settings.spokenPunctuation { text = TextCleaner.applySpokenPunctuation(text) }
        if settings.replacementsEnabled {
            text = TextCleaner.applyReplacements(text, settings.replacements)
        }
        text = TextCleaner.expandVariables(text)
        if settings.numbersToDigits { text = TextCleaner.numbersToDigits(text) }
        if !settings.censorWords.isEmpty {
            text = TextCleaner.censor(text, words: settings.censorWords,
                                      style: settings.censorStyle)
        }
        if settings.capitalizeI { text = TextCleaner.capitalizeI(text) }
        if settings.smartPunctuation { text = TextCleaner.smartPunctuation(text) }
        if settings.autoCapSentences { text = TextCleaner.capitalizeSentences(text) }
        if settings.ensureEndPunctuation { text = TextCleaner.ensureEndPunctuation(text) }
        let wordCount = text.split(whereSeparator: \.isWhitespace).count
        if settings.discardShortWords > 0, wordCount <= settings.discardShortWords {
            text = ""
        }
        guard !text.isEmpty else {
            phase = .idle
            pill.hide(toIdleDot: settings.idleIndicator)
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
        let usePolish = rule?.polish ?? settings.polishEnabled
        if usePolish {
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
        var text = TextCleaner.applyCase(rawText, ocase ?? settings.outputCase)
        if settings.noTrailingPeriod, text.hasSuffix(".") { text = String(text.dropLast()) }
        let words = text.split(whereSeparator: \.isWhitespace).count
        let tooLong = settings.longToClipboardWords > 0 && words > settings.longToClipboardWords
        let oneShot = forceClipboardOnce
        forceClipboardOnce = false
        if settings.insertTarget == .clipboardOnly || tooLong || oneShot {
            Inserter.copyOnly(text)
            lastInsertedText = nil   // a clipboard copy isn't undoable
        } else {
            var out = text
            if settings.trailingNewline { out += "\n" }
            else if settings.trailingSpace { out += " " }
            Inserter.insert(out)
            lastInsertedText = out
        }
        let copiedOnly = settings.insertTarget == .clipboardOnly || tooLong || oneShot
        let wordsBeforeGoal = settings.todayWords
        let unlocked = settings.record(
            text, usedPolish: settings.polishEnabled, usedCommands: usedCommands,
            app: pill.state.targetApp, seconds: lastSessionSeconds,
            saveToHistory: !(copiedOnly && settings.excludeClipboardOnly))
        lastSessionSeconds = nil
        rebuildMenu()
        pill.state.phase = .done
        pill.state.text = text
        play(.insert)
        if settings.hapticsEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
        setIcon(recording: false)
        phase = .idle
        let hitGoal = settings.goalCelebration && settings.dailyGoal > 0
            && wordsBeforeGoal < settings.dailyGoal && settings.todayWords >= settings.dailyGoal
        let celebrating = !unlocked.isEmpty || hitGoal
        let hideDelay: TimeInterval = celebrating ? max(3.0, settings.doneLinger) : settings.doneLinger
        if let first = unlocked.first {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self, self.phase == .idle else { return }
                self.pill.state.text = "🏆 Unlocked: \(first.name)!"
                if self.settings.unlockSoundEnabled { self.play(.unlock) }
            }
        } else if hitGoal {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self, self.phase == .idle else { return }
                self.pill.state.text = "🎯 Daily goal hit — \(self.settings.dailyGoal.formatted()) words!"
                if self.settings.unlockSoundEnabled { self.play(.unlock) }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + hideDelay) { [weak self] in
            guard let self, self.phase == .idle else { return }
            self.pill.hide(toIdleDot: self.settings.idleIndicator)
            // Chain mode: roll straight into the next hands-free dictation.
            if self.settings.chainMode, !self.paused {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                    guard let self, self.phase == .idle else { return }
                    self.hotkeys.handsFree = true
                    self.startRecording()
                }
            }
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
        menuModeWatcher = Publishers.Merge(
            settings.$menuClickToTalk.dropFirst().map { _ in () },
            settings.$menuSymbolName.dropFirst().map { _ in () }
        ).sink { [weak self] in
            DispatchQueue.main.async { self?.setIcon(recording: self?.phase == .recording) }
        }
    }

    private func setIcon(recording: Bool) {
        if !recording {
            menuTimerTicker?.invalidate()
            menuTimerTicker = nil
        }
        // A custom SF Symbol name (Appearance ▸ Menu bar) wins when it's valid.
        let custom = settings.menuSymbolName.trimmingCharacters(in: .whitespaces)
        let name = (!custom.isEmpty && NSImage(systemSymbolName: custom, accessibilityDescription: nil) != nil && !recording)
            ? custom
            : settings.menuIcon.symbol(recording: recording)
        let img = NSImage(systemSymbolName: name, accessibilityDescription: "Murmur")
        img?.isTemplate = true
        statusItem.button?.image = img
        statusItem.button?.contentTintColor = recording ? .systemRed : nil
        var title = ""
        if settings.showMenuBarCount, settings.todayWords > 0 { title += " \(settings.todayWords)" }
        if settings.showMenuBarStreak, settings.streak() >= 2 { title += " 🔥\(settings.streak())" }
        if !title.isEmpty {
            statusItem.button?.title = title
            statusItem.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            statusItem.button?.imagePosition = .imageLeading
        } else {
            statusItem.button?.title = ""
        }
        if recording, settings.recordTintAccent {
            let c = NSColor(hue: settings.accentHue, saturation: settings.accentSat,
                            brightness: 1.0, alpha: 1)
            statusItem.button?.contentTintColor = c
        }
        statusItem.button?.appearsDisabled = paused && !recording
        rebuildMenu() // keep the Start/Finish dictation item in sync
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let header = NSMenuItem(title: "Murmur — hold \(settings.hotkey.name) and talk",
                                action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        if !AXIsProcessTrusted() {
            let warn = NSMenuItem(title: "⚠️ Grant Accessibility to enable the hotkey…",
                                  action: #selector(openWelcome), keyEquivalent: "")
            warn.target = self
            menu.addItem(warn)
        }
        if let update = settings.availableUpdate {
            let item = NSMenuItem(title: "Update available — \(update)…",
                                  action: #selector(checkForUpdates), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let dictate = NSMenuItem(
            title: phase == .recording ? "Finish && Insert" : "Start Dictation (hands-free)",
            action: #selector(toggleDictation), keyEquivalent: "d")
        dictate.target = self
        menu.addItem(dictate)

        if phase == .idle {
            let toClip = NSMenuItem(title: "Dictate to Clipboard",
                                    action: #selector(dictateToClipboard), keyEquivalent: "")
            toClip.target = self
            menu.addItem(toClip)
        }

        let pause = NSMenuItem(title: paused ? "Resume Murmur" : "Pause Murmur",
                               action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        menu.addItem(pause)

        if lastInsertedText != nil {
            let undo = NSMenuItem(title: "Undo Last Insert",
                                  action: #selector(undoLastInsert), keyEquivalent: "")
            undo.target = self
            menu.addItem(undo)
        }

        if let last = settings.history.max(by: { $0.date < $1.date }) {
            let insertLast = NSMenuItem(title: "Insert Last Transcript",
                                        action: #selector(insertLastTranscript), keyEquivalent: "l")
            insertLast.target = self
            insertLast.toolTip = last.text
            menu.addItem(insertLast)

            let copyLast = NSMenuItem(title: "Copy Last Transcript",
                                      action: #selector(copyLastTranscript), keyEquivalent: "c")
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

        let langParent = NSMenuItem(title: "Language", action: nil, keyEquivalent: "")
        let langMenu = NSMenu()
        for (id, name) in GeneralPane.languages {
            let item = NSMenuItem(title: name, action: #selector(switchLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = id
            item.state = settings.localeID == id ? .on : .off
            langMenu.addItem(item)
        }
        langParent.submenu = langMenu
        menu.addItem(langParent)

        let welcome = NSMenuItem(title: "Welcome & Permissions…", action: #selector(openWelcome), keyEquivalent: "")
        welcome.target = self
        menu.addItem(welcome)

        let about = NSMenuItem(title: "About Murmur", action: #selector(openAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        let updates = NSMenuItem(title: "Check for Updates…",
                                 action: #selector(checkForUpdates), keyEquivalent: "")
        updates.target = self
        menu.addItem(updates)

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

        currentMenu = menu
        if settings.menuClickToTalk {
            // Left-click toggles dictation; the menu moves to right-click.
            statusItem.menu = nil
            if let button = statusItem.button {
                button.target = self
                button.action = #selector(statusClicked)
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            }
        } else {
            statusItem.menu = menu
        }
    }

    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            guard let menu = currentMenu else { return }
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            DispatchQueue.main.async { self.statusItem.menu = nil }
        } else {
            toggleDictation()
        }
    }

    /// Appearance pane "Show real pill" button: flash the live overlay.
    @objc private func showTestPill() {
        guard phase == .idle else { return }
        pill.state.phase = .listening
        pill.state.text = "Testing, one two three…"
        pill.state.targetApp = nil
        pill.state.startedAt = nil
        pill.state.levels = (0..<settings.waveBarCount).map { _ in CGFloat.random(in: 0.1...0.9) }
        pill.show()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self, self.phase == .idle else { return }
            self.pill.hide(toIdleDot: self.settings.idleIndicator)
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

    /// "Tap the pill to finish" — a click on the recording pill acts like
    /// tapping the hotkey: finish and insert.
    @objc private func pillTapped() {
        guard settings.pillClickToFinish, phase == .recording else { return }
        hotkeys.handsFree = false
        finishRecording()
    }

    /// Writes a settings backup to Application Support at most once a week
    /// (when enabled), keeping the five most recent files.
    private func runWeeklyAutoBackupIfDue() {
        guard settings.autoBackupWeekly else { return }
        let d = UserDefaults.standard
        if let last = d.object(forKey: "lastAutoBackup") as? Date,
           Date().timeIntervalSince(last) < 7 * 24 * 3600 { return }
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return }
        let dir = base.appendingPathComponent("Murmur/Backups", isDirectory: true)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
            let url = dir.appendingPathComponent("Murmur-Backup-\(df.string(from: Date())).json")
            try settings.exportBackup().write(to: url)
            d.set(Date(), forKey: "lastAutoBackup")
            let backups = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.hasPrefix("Murmur-Backup-") }
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
            for old in backups.dropFirst(5) { try? fm.removeItem(at: old) }
        } catch {
            NSLog("Murmur: auto-backup failed — \(error.localizedDescription)")
        }
    }

    @objc private func dictateToClipboard() {
        guard phase == .idle else { return }
        forceClipboardOnce = true
        hotkeys.handsFree = true
        startRecording()
    }

    @objc private func checkForUpdates() {
        NSWorkspace.shared.open(URL(string: "https://github.com/gitMacMaker/murmur/releases")!)
    }

    @objc private func screenLocked() {
        guard settings.cancelOnScreenLock, phase == .recording else { return }
        hotkeys.handsFree = false
        cancelRecording()
    }

    /// Weekly, when enabled: asks GitHub for the latest release tag and
    /// surfaces an "Update available" menu item if it's newer than this build.
    private func checkForUpdateIfDue() {
        guard settings.updateCheckWeekly else { return }
        let d = UserDefaults.standard
        if let last = d.object(forKey: "lastUpdateCheck") as? Date,
           Date().timeIntervalSince(last) < 7 * 24 * 3600 { return }
        guard let url = URL(string: "https://api.github.com/repos/gitMacMaker/murmur/releases/latest")
        else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self, let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else { return }
            let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
            let remote = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            DispatchQueue.main.async {
                d.set(Date(), forKey: "lastUpdateCheck")
                if remote.compare(current, options: .numeric) == .orderedDescending {
                    self.settings.availableUpdate = tag
                    self.rebuildMenu()
                }
            }
        }.resume()
    }

    @objc private func togglePause() {
        paused.toggle()
        if paused, phase == .recording { cancelRecording() }
        setIcon(recording: phase == .recording)
    }

    /// Deletes the most recently inserted text by sending one backspace per
    /// character — assumes the cursor is still where the insert landed.
    @objc private func undoLastInsert() {
        guard let text = lastInsertedText, !text.isEmpty, AXIsProcessTrusted() else { return }
        let src = CGEventSource(stateID: .combinedSessionState)
        for _ in 0..<text.count {
            CGEvent(keyboardEventSource: src, virtualKey: 51, keyDown: true)?.post(tap: .cghidEventTap)
            CGEvent(keyboardEventSource: src, virtualKey: 51, keyDown: false)?.post(tap: .cghidEventTap)
        }
        lastInsertedText = nil
        rebuildMenu()
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

    @objc private func switchLanguage(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        settings.localeID = id
        rebuildMenu()
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
