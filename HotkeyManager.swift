import AppKit

/// Set true while the Settings key-capture control is recording a new
/// hotkey, so pressing keys there doesn't start a dictation.
enum KeyCaptureState {
    static var active = false
}

/// Watches the user's chosen push-to-talk key globally — any modifier or
/// regular key. Hold = push-to-talk (release ends). Quick tap = toggle
/// hands-free mode. Esc while recording = cancel.
///
/// Modifier hotkeys use NSEvent flagsChanged monitors. Regular keys use a
/// CGEvent tap so the key is consumed system-wide (it won't also type);
/// if the tap can't be created we fall back to non-consuming monitors.
final class HotkeyManager {
    var onStart: (() -> Void)?
    var onFinish: (() -> Void)?
    var onCancel: (() -> Void)?
    /// Queried so a tap while already hands-free stops the recording.
    var isRecording: (() -> Bool)?
    /// Set true by the app while recording started from a quick tap.
    var handsFree = false

    private let escKeyCode: UInt16 = 53
    private var monitors: [Any] = []
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var keyDownAt: Date?
    private var startedThisPress = false

    func activate() {
        let flagsHandler: (NSEvent) -> Void = { [weak self] event in
            self?.handleFlagsChanged(event)
        }
        let escHandler: (NSEvent) -> Void = { [weak self] event in
            guard let self, event.keyCode == self.escKeyCode,
                  !KeyCaptureState.active,
                  AppSettings.shared.escCancels,
                  self.isRecording?() == true else { return }
            self.handsFree = false
            self.onCancel?()
        }
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: flagsHandler) as Any)
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: escHandler) as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            flagsHandler(event); return event
        } as Any)

        if !createEventTap() {
            NSLog("Murmur: event tap unavailable, falling back to NSEvent key monitors")
            monitors.append(NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] e in
                self?.handleKey(down: true, keyCode: e.keyCode, isRepeat: e.isARepeat)
            } as Any)
            monitors.append(NSEvent.addGlobalMonitorForEvents(matching: .keyUp) { [weak self] e in
                self?.handleKey(down: false, keyCode: e.keyCode, isRepeat: false)
            } as Any)
        }
    }

    deinit {
        monitors.forEach { NSEvent.removeMonitor($0) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
    }

    // MARK: Shared press/release logic

    private func handlePress() {
        keyDownAt = Date()
        if isRecording?() == true {
            // Tap while hands-free: finish and insert.
            startedThisPress = false
            handsFree = false
            onFinish?()
        } else {
            startedThisPress = true
            onStart?()
        }
    }

    private func handleRelease() {
        guard startedThisPress else { return }
        startedThisPress = false
        let heldFor = -(keyDownAt?.timeIntervalSinceNow ?? 0)
        if heldFor >= AppSettings.shared.tapThreshold || AppSettings.shared.holdOnlyMode {
            // Push-to-talk: release ends the recording. Hold-only mode treats
            // even quick taps as a (very short) hold instead of going
            // hands-free — for users who tap the key by accident.
            handsFree = false
            onFinish?()
        } else {
            // Quick tap: stay recording hands-free until the next tap.
            handsFree = true
        }
    }

    // MARK: Modifier hotkeys (flagsChanged)

    private func handleFlagsChanged(_ event: NSEvent) {
        guard !KeyCaptureState.active else { return }
        let hotkey = AppSettings.shared.hotkey
        guard hotkey.isModifier, event.keyCode == hotkey.keyCode,
              let flag = hotkey.modifierFlag else { return }
        if event.modifierFlags.contains(flag) { handlePress() } else { handleRelease() }
    }

    // MARK: Regular-key hotkeys

    private func handleKey(down: Bool, keyCode: UInt16, isRepeat: Bool) {
        guard !KeyCaptureState.active else { return }
        let hotkey = AppSettings.shared.hotkey
        guard !hotkey.isModifier, keyCode == hotkey.keyCode, !isRepeat else { return }
        if down { handlePress() } else { handleRelease() }
    }

    private func createEventTap() -> Bool {
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let mgr = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
            return mgr.handleTapEvent(type: type, event: event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: CGEventMask(mask),
                                          callback: callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            return false
        }
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handleTapEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard !KeyCaptureState.active else { return Unmanaged.passUnretained(event) }
        let hotkey = AppSettings.shared.hotkey
        guard !hotkey.isModifier else { return Unmanaged.passUnretained(event) }
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        guard keyCode == hotkey.keyCode else { return Unmanaged.passUnretained(event) }

        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let down = type == .keyDown
        DispatchQueue.main.async { [weak self] in
            guard let self, !isRepeat else { return }
            if down { self.handlePress() } else { self.handleRelease() }
        }
        return nil // consume: the hotkey shouldn't also type/trigger its normal role
    }
}
