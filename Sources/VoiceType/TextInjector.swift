import AppKit
import Quartz

final class TextInjector {
    private let injectionQueue = DispatchQueue(label: "com.clement.voicetype.injection")

    /// Inject text via clipboard + Cmd+V. Calls completion on finish (any thread).
    func inject(text: String, completion: @escaping () -> Void) {
        guard !text.isEmpty else {
            completion()
            return
        }

        // All pasteboard ops on main thread
        DispatchQueue.main.async {
            let previous = NSPasteboard.general.string(forType: .string)

            let textToInject = " " + text
            NSPasteboard.general.clearContents()
            let success = NSPasteboard.general.setString(textToInject, forType: .string)
            NSLog("VoiceType: Pasteboard set: %@ (%d chars)", success ? "OK" : "FAILED", textToInject.count)

            // Sleep + paste + restore off the main thread
            self.injectionQueue.async {
                // Let pasteboard settle
                usleep(100_000)
                self.simulatePaste()
                NSLog("VoiceType: Paste simulated")

                // Wait for paste to complete (Electron apps need 300ms+)
                usleep(500_000)

                // Restore clipboard on main thread
                DispatchQueue.main.async {
                    NSPasteboard.general.clearContents()
                    if let previous {
                        NSPasteboard.general.setString(previous, forType: .string)
                    }
                }

                completion()
            }
        }
    }

    private func simulatePaste() {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        else { return }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
