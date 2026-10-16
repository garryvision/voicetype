import AppKit

/// Floating capsule at the bottom centre of the screen in use, above the Dock.
/// Non-activating panel: clicking it never steals focus from the app being dictated into.
final class StatusIndicator {
    private let panel: NSPanel
    private let view = CapsuleView()
    private var shrinkWork: DispatchWorkItem?
    private var dismissWork: DispatchWorkItem?

    /// Distance between the bottom of the usable screen area and the capsule centre.
    private let anchorHeight: CGFloat = 14 + CapsuleView.activeSize.height / 2
    private let messageDuration: TimeInterval = 2.2
    private let collapseDuration: TimeInterval = 0.5  // spring settling time before shrinking

    /// State shown when nothing happens: .idle or .paused.
    var resting: IndicatorState = .idle
    var menuProvider: (() -> NSMenu)?
    var state: IndicatorState { view.state }

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = view

        view.onClick = { [weak self] event in self?.showMenu(with: event) }
        place(on: Self.screenWithMouse(), size: view.windowSize(for: .idle))
        view.apply(.idle, animated: false)
        panel.orderFrontRegardless()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.place(on: self.panel.screen ?? Self.screenWithMouse(), size: self.panel.frame.size)
        }
    }

    // MARK: - Public API

    func show(_ newState: IndicatorState) {
        dismissWork?.cancel()
        shrinkWork?.cancel()

        // Follow the user: dictation starts on the screen where the pointer is
        let screen = newState == .recording ? Self.screenWithMouse() : (panel.screen ?? Self.screenWithMouse())
        let target = view.windowSize(for: newState)
        let current = panel.frame.size

        // Grow the window before the capsule expands; shrink it only once the collapse has settled
        let grown = NSSize(width: max(target.width, current.width), height: max(target.height, current.height))
        place(on: screen, size: grown)
        view.apply(newState, animated: true)

        if grown != target { scheduleShrink(to: target, for: newState) }
    }

    /// Short message (e.g. "Copié", "Micro indisponible"), then back to the resting state.
    func flash(_ message: String, isError: Bool) {
        show(.message(message, isError: isError))
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.show(self.resting)
        }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + messageDuration, execute: work)
    }

    func setLevel(_ level: Float) {
        view.pushLevel(level)
    }

    // MARK: - Placement

    private func scheduleShrink(to size: NSSize, for expected: IndicatorState) {
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.view.state == expected else { return }
            self.place(on: self.panel.screen ?? Self.screenWithMouse(), size: size)
        }
        shrinkWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + collapseDuration, execute: work)
    }

    /// The capsule centre stays at a fixed point, so resizing the window never moves it.
    private func place(on screen: NSScreen, size: NSSize) {
        let area = screen.visibleFrame
        let origin = NSPoint(x: (area.midX - size.width / 2).rounded(),
                             y: (area.minY + anchorHeight - size.height / 2).rounded())
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private static func screenWithMouse() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func showMenu(with event: NSEvent) {
        guard let menu = menuProvider?() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }
}
