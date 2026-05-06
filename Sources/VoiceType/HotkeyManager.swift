import Quartz

final class HotkeyManager {
    private let onPress: () -> Void
    private let onRelease: () -> Void
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var fnIsDown = false
    private var retainedSelf: Unmanaged<HotkeyManager>?

    init(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) {
        self.onPress = onPress
        self.onRelease = onRelease
    }

    deinit {
        stop()
    }

    func start() {
        let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)

        // Retain self so ARC can't deallocate while tap is active
        let retained = Unmanaged.passRetained(self)
        retainedSelf = retained

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: HotkeyManager.eventCallback,
            userInfo: retained.toOpaque()
        ) else {
            NSLog("VoiceType: Failed to create event tap — grant Accessibility permission")
            retained.release()
            retainedSelf = nil
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        NSLog("VoiceType: Listening for Fn/Globe")
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil

        // Release the retained self
        retainedSelf?.release()
        retainedSelf = nil
    }

    // MARK: - C callback

    private static let eventCallback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else { return Unmanaged.passUnretained(event) }
        let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
        manager.handleEvent(type: type, event: event)
        return Unmanaged.passUnretained(event)
    }

    private func handleEvent(type: CGEventType, event: CGEvent) {
        // Re-enable tap if macOS disabled it
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
                NSLog("VoiceType: Event tap re-enabled after timeout")
            }
            // Check actual Fn state — events were missed while tap was disabled
            let actualFlags = NSEvent.modifierFlags
            let fnActuallyDown = actualFlags.contains(.function)
            if fnIsDown && !fnActuallyDown {
                fnIsDown = false
                NSLog("VoiceType: Forcing Fn release — key was released during tap disable")
                DispatchQueue.main.async { self.onRelease() }
            } else if !fnIsDown && fnActuallyDown {
                fnIsDown = true
                NSLog("VoiceType: Forcing Fn press — key was pressed during tap disable")
                DispatchQueue.main.async { self.onPress() }
            }
            return
        }

        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags.rawValue

        if type == .flagsChanged {
            let fnFlag: UInt64 = 0x800000
            let fnNowDown = (flags & fnFlag) != 0

            if fnNowDown && !fnIsDown {
                fnIsDown = true
                DispatchQueue.main.async { self.onPress() }
            } else if !fnNowDown && fnIsDown {
                fnIsDown = false
                DispatchQueue.main.async { self.onRelease() }
            }
        } else if keycode == 63 {
            if type == .keyDown && !fnIsDown {
                fnIsDown = true
                DispatchQueue.main.async { self.onPress() }
            } else if type == .keyUp && fnIsDown {
                fnIsDown = false
                DispatchQueue.main.async { self.onRelease() }
            }
        }
    }
}
