import AppKit
import AVFoundation
import Carbon.HIToolbox
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
    /// Recent inserts, newest last — multi-level undo (menu ▸ Undo Last Insert).
    private var undoStack: [String] = []
    /// When true the hotkey is ignored (menu ▸ Pause Murmur).
    private var paused = false
    /// The current dictation is an AI command (edit selection), not an insert.
    private var commandMode = false
    /// Set by menu ▸ Dictate to Clipboard: the next delivery copies instead
    /// of inserting, then the flag clears.
    private var forceClipboardOnce = false
    /// Set by menu ▸ Dictate to Journal: the next delivery appends to the
    /// journal file instead of inserting.
    private var forceJournalOnce = false
    /// Duration of the dictation being processed, for history metadata.
    private var lastSessionSeconds: Double?
    /// Updates the menu-bar timer while recording (when enabled).
    private var menuTimerTicker: Timer?
    /// Soft privacy cue every 30s while recording (when enabled).
    private var reminderTimer: Timer?
    /// Keeps the Mac awake while recording (when enabled).
    private var caffeinateProc: Process?

    private func startCaffeinate() {
        guard caffeinateProc == nil else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        p.arguments = ["-di"]
        try? p.run()
        caffeinateProc = p
    }

    private func stopCaffeinate() {
        caffeinateProc?.terminate()
        caffeinateProc = nil
        reminderTimer?.invalidate()
        reminderTimer = nil
    }

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
        rotateSkinIfDue()
        autoExportTodayIfDue()
        if settings.openSettingsAtLaunch { SettingsWindowController.shared.show() }
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
        transcriber.onPartial = { [weak self] text in
            guard let self else { return }
            self.pill.state.text = text
            // Auto-finish once the live transcript hits the word cap.
            if self.settings.maxRecordWords > 0, self.phase == .recording,
               text.split(whereSeparator: \.isWhitespace).count >= self.settings.maxRecordWords {
                self.hotkeys.handsFree = false
                self.finishRecording()
            }
        }
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
        hotkeys.onCommandStart = { [weak self] in self?.startRecording(command: true) }
        hotkeys.onCommandFinish = { [weak self] in self?.finishRecording() }
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

    /// The app rule matching the frontmost app, if any.
    private func ruleForFrontmostApp() -> AppRule? {
        let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
        return settings.appRules.first {
            !$0.appName.isEmpty && front.localizedCaseInsensitiveContains($0.appName)
        }
    }

    private func startRecording(command: Bool = false) {
        guard phase == .idle, !paused else { return }
        commandMode = command
        let rule = ruleForFrontmostApp()
        if rule?.blocked == true { return } // Murmur is off in this app
        do {
            try transcriber.start(localeOverride: rule?.localeID ?? keyboardLocaleOverride())
        } catch {
            pill.state.phase = .error
            pill.state.text = error.localizedDescription
            if settings.errorSound { NSSound(named: "Basso")?.play() }
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
        pill.state.text = command ? "⌘ Command — say an edit for the selection" : ""
        pill.state.targetApp = NSWorkspace.shared.frontmostApplication?.localizedName
        pill.state.targetIcon = settings.showTargetIcon
            ? NSWorkspace.shared.frontmostApplication?.icon : nil
        pill.state.startedAt = Date()
        pill.show()
        play(.start)
        if settings.hapticsEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
        if settings.preventSleep { startCaffeinate() }
        if settings.recordingReminder {
            reminderTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                guard let self, self.phase == .recording else { return }
                self.play(.start)
            }
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
        stopCaffeinate()
        phase = .processing
        pill.state.phase = .processing
        let wasCommand = commandMode
        transcriber.stop { [weak self] raw in
            if wasCommand { self?.handleCommand(raw) } else { self?.handleTranscript(raw) }
        }
    }

    private func cancelRecording() {
        guard phase == .recording else { return }
        // Don't lose what was said: keep the partial transcript in History.
        let partial = pill.state.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if settings.keepCanceled, !partial.isEmpty, !commandMode {
            _ = settings.record(partial, app: "(canceled)", saveToHistory: true)
        }
        commandMode = false
        silenceTimer?.invalidate()
        silenceTimer = nil
        stopCaffeinate()
        transcriber.cancel()
        phase = .idle
        pill.hide(toIdleDot: settings.idleIndicator)
        setIcon(recording: false)
        play(.cancel)
    }

    /// AI Command Mode: the spoken text is an instruction. Grab the current
    /// selection (⌘C), ask Claude to apply the instruction, and paste the
    /// result back over the selection (or at the cursor if nothing selected).
    private func handleCommand(_ raw: String) {
        commandMode = false
        let instruction = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else {
            phase = .idle; pill.hide(toIdleDot: settings.idleIndicator); setIcon(recording: false); return
        }
        // Command Mode needs an AI backend (API key or the claude CLI).
        let hasAI = settings.polishBackend == .api ? APIKeyStore.exists : ClaudeCLI.found != false
        guard hasAI else {
            pill.state.phase = .error
            pill.state.text = "Command Mode needs AI polish — add an API key or the Claude CLI"
            if settings.errorSound { NSSound(named: "Basso")?.play() }
            phase = .idle
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { [weak self] in
                guard let self, self.phase == .idle else { return }
                self.pill.hide(toIdleDot: self.settings.idleIndicator)
            }
            setIcon(recording: false)
            return
        }
        // Capture the current selection via a clipboard round-trip.
        let pb = NSPasteboard.general
        let savedChange = pb.changeCount
        let savedString = pb.string(forType: .string)
        if AXIsProcessTrusted() {
            let src = CGEventSource(stateID: .combinedSessionState)
            let cDown = CGEvent(keyboardEventSource: src, virtualKey: 8, keyDown: true)
            let cUp = CGEvent(keyboardEventSource: src, virtualKey: 8, keyDown: false)
            cDown?.flags = .maskCommand; cUp?.flags = .maskCommand
            cDown?.post(tap: .cghidEventTap); cUp?.post(tap: .cghidEventTap)
        }
        // Give the copy a moment to land, then read the selection.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            guard let self else { return }
            let selection = (pb.changeCount != savedChange ? pb.string(forType: .string) : nil) ?? ""
            self.pill.state.phase = .processing
            self.pill.state.text = selection.isEmpty ? "Generating…" : "Editing selection…"
            TextCleaner.command(selection: selection, instruction: instruction) { [weak self] result in
                guard let self else { return }
                let out = result.trimmingCharacters(in: .whitespacesAndNewlines)
                // Restore the user's clipboard before pasting our result.
                if let s = savedString { pb.clearContents(); pb.setString(s, forType: .string) }
                guard !out.isEmpty else {
                    self.phase = .idle
                    self.pill.hide(toIdleDot: self.settings.idleIndicator)
                    self.setIcon(recording: false)
                    return
                }
                self.pill.state.copiedMode = false
                self.pill.state.phase = .done
                self.pill.state.text = out
                Inserter.insert(out)
                self.undoStack.append(out)
                self.play(.insert)
                self.setIcon(recording: false)
                self.phase = .idle
                DispatchQueue.main.asyncAfter(deadline: .now() + max(1.4, self.settings.doneLinger)) { [weak self] in
                    guard let self, self.phase == .idle else { return }
                    self.pill.hide(toIdleDot: self.settings.idleIndicator)
                }
            }
        }
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
        if settings.webShortcuts { text = TextCleaner.applyWebShortcuts(text) }
        var pressReturnAfter = false
        if settings.sendItCommand {
            let (stripped, send) = TextCleaner.extractSendIt(text)
            text = stripped
            pressReturnAfter = send
        }
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
        if !settings.properNouns.isEmpty { text = TextCleaner.capitalizeProperNouns(text, settings.properNouns) }
        if settings.smartPunctuation { text = TextCleaner.smartPunctuation(text) }
        if settings.autoCapSentences { text = TextCleaner.capitalizeSentences(text) }
        if settings.capitalizeAfterColon { text = TextCleaner.capitalizeAfterColon(text) }
        if settings.ensureSentenceSpacing { text = TextCleaner.ensureSentenceSpacing(text) }
        if settings.collapseBlankLines { text = TextCleaner.collapseBlankLines(text) }
        if settings.trimSurroundingQuotes { text = TextCleaner.trimSurroundingQuotes(text) }
        if settings.autoLowercaseFirst { text = TextCleaner.lowercaseFirst(text) }
        if settings.ensureEndPunctuation { text = TextCleaner.ensureEndPunctuation(text) }
        if settings.maxWordsPerInsert > 0 {
            let parts = text.split(whereSeparator: \.isWhitespace)
            if parts.count > settings.maxWordsPerInsert {
                text = parts.prefix(settings.maxWordsPerInsert).joined(separator: " ") + "…"
            }
        }
        settings.learnVocabulary(from: raw)
        if settings.trackReplacementUsage, settings.replacementsEnabled {
            for r in settings.replacements where r.enabled && !r.phrase.isEmpty {
                if raw.range(of: "\\b\(NSRegularExpression.escapedPattern(for: r.phrase))\\b",
                             options: [.regularExpression, .caseInsensitive]) != nil {
                    settings.replacementUsage[r.phrase, default: 0] += 1
                }
            }
        }
        let wordCount = text.split(whereSeparator: \.isWhitespace).count
        if settings.discardShortWords > 0, wordCount <= settings.discardShortWords {
            text = ""
        }
        if settings.discardShortSeconds > 0, let secs = lastSessionSeconds,
           secs < settings.discardShortSeconds {
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
        var tone = rule?.tone ?? settings.polishTone
        let ocase = rule?.ocase ?? settings.outputCase
        var usePolish = rule?.polish ?? settings.polishEnabled
        // Per-app polish voice: the rule's own instruction wins — Claude
        // writes however you told it to for this app.
        var customPrompt = settings.customPolishPrompt
        if let voice = rule?.customPrompt.trimmingCharacters(in: .whitespaces), !voice.isEmpty {
            tone = .custom
            customPrompt = voice
        }
        // Per-app grammar fix: force a polish pass that only corrects
        // grammar/spelling/punctuation — stacked onto the voice if one is set.
        if rule?.grammar == true {
            usePolish = true
            let grammarNote = "Fix any grammar, spelling, and punctuation mistakes; do not otherwise change the wording, meaning, or tone."
            if tone == .custom, !customPrompt.isEmpty {
                customPrompt += " " + grammarNote
            } else {
                tone = .custom
                customPrompt = grammarNote
            }
        }
        // Translate mode outranks voices and grammar: everything you dictate
        // comes out in the target language.
        if settings.translateEnabled, !settings.translateTo.isEmpty {
            usePolish = true
            tone = .custom
            customPrompt = "Translate the text into \(settings.translateTo). Output ONLY the translation, no notes."
        }
        if settings.polishMinWords > 0, wordCount < settings.polishMinWords {
            usePolish = false // too short to be worth the round-trip
        }
        let ruleEnter = rule?.pressEnter == true
        let sendAfter = pressReturnAfter || ruleEnter
        if usePolish {
            TextCleaner.polish(text, tone: tone,
                               custom: customPrompt) { [weak self] polished in
                self?.deliver(polished, usedCommands: usedCommands, ocase: ocase,
                              pressReturn: sendAfter)
            }
        } else {
            deliver(text, usedCommands: usedCommands, ocase: ocase, pressReturn: sendAfter)
        }
    }

    private func deliver(_ rawText: String, usedCommands: Bool = false,
                         ocase: OutputCase? = nil, pressReturn: Bool = false) {
        var text = TextCleaner.applyCase(rawText, ocase ?? settings.outputCase)
        if settings.noTrailingPeriod, text.hasSuffix(".") { text = String(text.dropLast()) }
        let words = text.split(whereSeparator: \.isWhitespace).count
        let tooLong = settings.longToClipboardWords > 0 && words > settings.longToClipboardWords
        let oneShot = forceClipboardOnce
        forceClipboardOnce = false
        // Apps on the exclusion list never get auto-inserts.
        let excluded = settings.excludedApps.contains { app in
            !app.isEmpty && (pill.state.targetApp ?? "").localizedCaseInsensitiveContains(app)
        }
        // Journal mode: append to the journal file, no insertion.
        if forceJournalOnce {
            forceJournalOnce = false
            appendToJournal(text)
            pill.state.copiedMode = false
            pill.state.phase = .done
            pill.state.text = "Saved to journal ✓"
            play(.insert)
            setIcon(recording: false)
            phase = .idle
            _ = settings.record(text, usedPolish: false, usedCommands: usedCommands,
                                app: "Journal", seconds: lastSessionSeconds)
            lastSessionSeconds = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + settings.doneLinger) { [weak self] in
                guard let self, self.phase == .idle else { return }
                self.pill.hide(toIdleDot: self.settings.idleIndicator)
            }
            return
        }
        // Per-app rule can force typing-style insertion (terminals).
        let ruleTyping = ruleForFrontmostApp()?.typeInsert == true
        let copyMode = settings.insertTarget == .clipboardOnly || tooLong || oneShot || excluded
        if copyMode {
            Inserter.copyOnly(text)
            lastInsertedText = nil   // a clipboard copy isn't undoable
        } else if ruleTyping, AXIsProcessTrusted() {
            var out = text
            if settings.trailingNewline { out += "\n" }
            else if settings.trailingSpace { out += " " }
            Inserter.type(out)
            lastInsertedText = out
            undoStack.append(out)
            if undoStack.count > max(1, settings.undoDepth) { undoStack.removeFirst() }
        } else {
            var out = text
            if settings.prefixEnabled, !settings.prefixText.isEmpty {
                out = TextCleaner.expandVariables(settings.prefixText) + out
            }
            if settings.timestampPrefix {
                let tf = DateFormatter(); tf.timeStyle = .short
                out = "[\(tf.string(from: Date()))] " + out
            }
            if settings.signatureEnabled, !settings.signatureText.isEmpty {
                out += TextCleaner.expandVariables(settings.signatureText)
            }
            if settings.leadingSpace { out = " " + out }
            if settings.trailingNewline { out += "\n" }
            else if settings.trailingSpace { out += " " }
            if settings.alwaysCopy { Inserter.copyOnly(text) }
            Inserter.insert(out)
            lastInsertedText = out
            undoStack.append(out)
            if undoStack.count > max(1, settings.undoDepth) { undoStack.removeFirst() }
        }
        let wordsBeforeGoal = settings.todayWords
        let unlocked = settings.record(
            text, usedPolish: settings.polishEnabled, usedCommands: usedCommands,
            app: pill.state.targetApp, seconds: lastSessionSeconds,
            saveToHistory: !(copyMode && settings.excludeClipboardOnly))
        lastSessionSeconds = nil
        rebuildMenu()
        pill.state.copiedMode = copyMode
        pill.state.phase = .done
        pill.state.text = text
        play(.insert)
        if settings.hapticsEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
        setIcon(recording: false)
        phase = .idle
        if pressReturn, !copyMode, AXIsProcessTrusted() {
            // Give the paste a moment to land, then hit Return ("send it").
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55 + settings.insertDelay) {
                let src = CGEventSource(stateID: .combinedSessionState)
                CGEvent(keyboardEventSource: src, virtualKey: 36, keyDown: true)?.post(tap: .cghidEventTap)
                CGEvent(keyboardEventSource: src, virtualKey: 36, keyDown: false)?.post(tap: .cghidEventTap)
            }
        }
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
        if paused { title += " ⏸" }
        if settings.showMenuBarCount, settings.todayWords > 0 { title += " \(settings.todayWords)" }
        if settings.showMenuBarChars, settings.totalChars > 0 { title += " \(settings.totalChars / 1000)k" }
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

            let toJournal = NSMenuItem(title: "Dictate to Journal",
                                       action: #selector(dictateToJournal), keyEquivalent: "j")
            toJournal.target = self
            toJournal.toolTip = "Appends a dated entry to your journal file"
            menu.addItem(toJournal)
        }

        let toneParent = NSMenuItem(title: "Polish Tone", action: nil, keyEquivalent: "")
        let toneMenu = NSMenu()
        let polishToggle = NSMenuItem(title: settings.polishEnabled ? "✓ AI Polish On" : "AI Polish Off",
                                      action: #selector(togglePolish), keyEquivalent: "")
        polishToggle.target = self
        toneMenu.addItem(polishToggle)
        toneMenu.addItem(.separator())
        for tone in PolishTone.allCases {
            let item = NSMenuItem(title: tone.label, action: #selector(switchTone(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = tone.rawValue
            item.state = settings.polishTone == tone ? .on : .off
            toneMenu.addItem(item)
        }
        toneParent.submenu = toneMenu
        menu.addItem(toneParent)

        let cheat = NSMenuItem(title: "Cheat Sheet", action: #selector(openCheatSheet), keyEquivalent: "/")
        cheat.target = self
        menu.addItem(cheat)

        let pause = NSMenuItem(title: paused ? "Resume Murmur" : "Pause Murmur",
                               action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        menu.addItem(pause)

        let mute = NSMenuItem(title: settings.soundsEnabled ? "Mute Sounds" : "Unmute Sounds",
                              action: #selector(toggleMute), keyEquivalent: "")
        mute.target = self
        menu.addItem(mute)

        if settings.todayWords > 0 {
            let today = NSMenuItem(
                title: "Today: \(settings.todayWords.formatted()) words · \(settings.dailySessions[AppSettings.dayKey(Date())] ?? 0) sessions",
                action: nil, keyEquivalent: "")
            today.isEnabled = false
            menu.addItem(today)
        }

        if lastInsertedText != nil {
            let undo = NSMenuItem(title: "Undo Last Insert",
                                  action: #selector(undoLastInsert), keyEquivalent: "u")
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
            let title = GeneralPane.onDeviceLocales.contains(id) ? name : "\(name)  ☁︎"
            let item = NSMenuItem(title: title, action: #selector(switchLanguage(_:)), keyEquivalent: "")
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
        let dir = settings.backupFolderPath.isEmpty
            ? base.appendingPathComponent("Murmur/Backups", isDirectory: true)
            : URL(fileURLWithPath: (settings.backupFolderPath as NSString).expandingTildeInPath)
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

    /// Picks a skin based on the day of the year (when auto-rotate is on),
    /// once per calendar day.
    private func rotateSkinIfDue() {
        guard settings.skinAutoRotate else { return }
        let d = UserDefaults.standard
        let today = AppSettings.dayKey(Date())
        guard d.string(forKey: "lastSkinRotate") != today else { return }
        d.set(today, forKey: "lastSkinRotate")
        let choices = AppSkin.allCases.filter { $0 != .custom }
        let doy = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        settings.skin = choices[doy % choices.count]
    }

    /// Writes the day's transcripts to Application Support once per day.
    private func autoExportTodayIfDue() {
        guard settings.autoExportDaily else { return }
        let d = UserDefaults.standard
        let today = AppSettings.dayKey(Date())
        guard d.string(forKey: "lastDailyExport") != today else { return }
        // Export *yesterday's* transcripts (today's aren't done yet).
        let cal = Calendar.current
        let items = settings.history.filter {
            cal.isDateInYesterday($0.date)
        }
        guard !items.isEmpty else { d.set(today, forKey: "lastDailyExport"); return }
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let dir = base.appendingPathComponent("Murmur/Transcripts", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let yKey = AppSettings.dayKey(cal.date(byAdding: .day, value: -1, to: Date()) ?? Date())
        let body = items.map(\.text).joined(separator: "\n\n")
        try? body.write(to: dir.appendingPathComponent("\(yKey).txt"),
                        atomically: true, encoding: .utf8)
        d.set(today, forKey: "lastDailyExport")
    }

    /// Appends a dated entry to the journal file (creating it if needed).
    private func appendToJournal(_ text: String) {
        var path = settings.journalPath
        if path.isEmpty {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            path = docs.appendingPathComponent("Murmur Journal.md").path
            settings.journalPath = path
        }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        let tf = DateFormatter(); tf.dateStyle = .medium; tf.timeStyle = .short
        let entry = "\n\n## \(tf.string(from: Date()))\n\(text)"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(entry.utf8))
            try? handle.close()
        } else {
            try? ("# Murmur Journal" + entry).write(to: url, atomically: true, encoding: .utf8)
        }
    }

    @objc private func dictateToJournal() {
        guard phase == .idle else { return }
        forceJournalOnce = true
        hotkeys.handsFree = true
        startRecording()
    }

    /// The recognition locale implied by the current keyboard layout, when
    /// "Auto language by keyboard" is on and the layout's language is supported.
    private func keyboardLocaleOverride() -> String? {
        guard settings.autoLanguageByKeyboard,
              let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let langsPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages)
        else { return nil }
        let langs = Unmanaged<CFArray>.fromOpaque(langsPtr).takeUnretainedValue() as? [String] ?? []
        guard let lang = langs.first else { return nil }
        // Exact match first, then language-prefix match.
        let supported = GeneralPane.languages.map(\.0)
        if let exact = supported.first(where: { $0.lowercased() == lang.lowercased() }) { return exact }
        return supported.first { $0.lowercased().hasPrefix(lang.lowercased() + "-") }
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

    @objc private func togglePolish() {
        settings.polishEnabled.toggle()
        rebuildMenu()
    }

    @objc private func switchTone(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let tone = PolishTone(rawValue: raw) else { return }
        settings.polishTone = tone
        rebuildMenu()
    }

    @objc private func openCheatSheet() {
        CheatSheetWindowController.shared.show()
    }

    @objc private func togglePause() {
        paused.toggle()
        if paused, phase == .recording { cancelRecording() }
        setIcon(recording: phase == .recording)
    }

    @objc private func toggleMute() {
        settings.soundsEnabled.toggle()
        rebuildMenu()
    }

    /// While recording, optionally confirm before quitting (the mic is live).
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard phase == .recording, settings.confirmQuitWhileRecording else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Still recording — quit anyway?"
        alert.informativeText = "The current dictation will be discarded."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Keep Recording")
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

    /// Deletes the most recently inserted text by sending one backspace per
    /// character — assumes the cursor is still where the insert landed.
    @objc private func undoLastInsert() {
        // Pop the newest insert off the multi-level stack.
        let text = undoStack.popLast() ?? lastInsertedText
        guard let text, !text.isEmpty, AXIsProcessTrusted() else { return }
        let src = CGEventSource(stateID: .combinedSessionState)
        for _ in 0..<text.count {
            CGEvent(keyboardEventSource: src, virtualKey: 51, keyDown: true)?.post(tap: .cghidEventTap)
            CGEvent(keyboardEventSource: src, virtualKey: 51, keyDown: false)?.post(tap: .cghidEventTap)
        }
        lastInsertedText = undoStack.last
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
