import AppKit
import Quartz

final class TextInjector {
    private let injectionQueue = DispatchQueue(label: "com.clement.voicetype.injection")

    /// Clipboard managers (Raycast, Maccy, Paste) skip items carrying this type.
    private let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    private let settleDelay: useconds_t = 100_000   // let the pasteboard settle before Cmd+V
    private let pasteDelay: useconds_t = 500_000    // Electron apps need 300 ms+ to read it

    /// Inject text via clipboard + Cmd+V. Calls completion on finish (any thread).
    func inject(text: String, completion: @escaping () -> Void) {
        guard !text.isEmpty else {
            completion()
            return
        }

        // All pasteboard ops on main thread
        DispatchQueue.main.async {
            let pasteboard = NSPasteboard.general
            let saved = self.snapshot(pasteboard)

            pasteboard.clearContents()
            pasteboard.setString(" " + text, forType: .string)
            pasteboard.setData(Data(), forType: self.transientType)
            let ownChangeCount = pasteboard.changeCount

            // Sleep + paste + restore off the main thread
            self.injectionQueue.async {
                usleep(self.settleDelay)
                self.simulatePaste()
                usleep(self.pasteDelay)

                DispatchQueue.main.async {
                    // Something else was copied meanwhile: keep it, don't restore over it
                    if pasteboard.changeCount == ownChangeCount {
                        self.restore(saved, to: pasteboard)
                    }
                }
                completion()
            }
        }
    }

    // MARK: - Clipboard snapshot (every item and type: text, images, files, rich text)

    private func snapshot(_ pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            var types: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { types[type] = data }
            }
            return types
        }
    }

    private func restore(_ saved: [[NSPasteboard.PasteboardType: Data]], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let items = saved.map { types -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in types { item.setData(data, forType: type) }
            return item
        }
        if !items.isEmpty { pasteboard.writeObjects(items) }
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
