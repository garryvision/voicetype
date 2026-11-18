import AppKit

/// Setup window in the capsule's world (black, white, one red dot): one row per permission,
/// live status, and a button straight to the right System Settings panel.
final class PermissionsWindow: NSObject, NSWindowDelegate {
    private enum Palette {
        static let background = NSColor(white: 0.075, alpha: 1)
        static let secondary = NSColor.white.withAlphaComponent(0.6)
        static let hairline = NSColor.white.withAlphaComponent(0.08)
    }

    private struct Row {
        let status: NSView
        let button: PermissionButton
    }

    private var window: NSWindow?
    private var rows: [Permission: Row] = [:]
    private var granted: [Permission: Bool] = [:]
    private let footer = NSTextField(wrappingLabelWithString: "")
    private var poll: Timer?
    private var wasComplete = false

    private let width: CGFloat = 460
    private let margin: CGFloat = 28
    private let pollInterval: TimeInterval = 1
    private let closeDelay: TimeInterval = 2
    private let fadeDuration: TimeInterval = 0.3
    private let trailingWidth: CGFloat = 96
    private let rowHeight: CGFloat = 64
    private var textWidth: CGFloat { width - margin * 2 }

    func show() {
        if window == nil { window = makeWindow() }
        wasComplete = Permission.allGranted
        granted = [:]
        refresh()
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        poll?.invalidate()
        poll = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func windowWillClose(_ notification: Notification) {
        poll?.invalidate()
    }

    @objc private func open(_ sender: NSButton) {
        Permission.allCases[sender.tag].request()
    }

    // MARK: - State

    private func refresh() {
        let next = Permission.allCases.first { !$0.isGranted }
        for permission in Permission.allCases {
            guard let row = rows[permission] else { continue }
            let isGranted = permission.isGranted
            row.button.isHidden = isGranted
            row.button.isPrimary = permission == next
            row.button.keyEquivalent = permission == next ? "\r" : ""
            if granted[permission] != isGranted { reveal(row.status, visible: isGranted, animated: granted[permission] != nil) }
            granted[permission] = isGranted
        }
        updateFooter(complete: next == nil)
    }

    /// The single moment of motion: the check fades in when macOS confirms a permission.
    private func reveal(_ status: NSView, visible: Bool, animated: Bool) {
        status.isHidden = !visible
        guard visible, animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            status.alphaValue = 1
            return
        }
        status.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = fadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            status.animator().alphaValue = 1
        }
    }

    private func updateFooter(complete: Bool) {
        footer.stringValue = complete
            ? "Tout est prêt. Maintiens Fn, parle, relâche."
            : "«\u{202F}Autoriser\u{202F}» ouvre le bon réglage\u{202F}: active VoiceType, puis reviens ici. "
              + "Absent de la liste\u{202F}? Bouton +, puis Applications\u{00A0}›\u{00A0}VoiceType."
        footer.textColor = complete ? .white : Palette.secondary
        guard complete, !wasComplete else { return }
        wasComplete = true
        Log.write("All permissions granted")
        DispatchQueue.main.asyncAfter(deadline: .now() + closeDelay) { [weak self] in self?.window?.close() }
    }

    // MARK: - Layout

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 10),
                              styleMask: [.titled, .closable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Autorisations de VoiceType"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Palette.background
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = makeContent()
        return window
    }

    private func makeContent() -> NSView {
        let list = NSStackView(views: Permission.allCases.flatMap { [hairline(), makeRow($0)] } + [hairline()])
        list.orientation = .vertical
        list.spacing = 0
        for view in list.arrangedSubviews {
            view.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true
        }

        footer.font = .systemFont(ofSize: 12)
        footer.preferredMaxLayoutWidth = textWidth
        let stack = NSStackView(views: [CapsuleMark(), makeHeader(), list, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 24
        stack.setCustomSpacing(20, after: stack.arrangedSubviews[0])
        stack.edgeInsets = NSEdgeInsets(top: 48, left: margin, bottom: margin, right: margin)
        stack.widthAnchor.constraint(equalToConstant: width).isActive = true
        for view in stack.arrangedSubviews.dropFirst() {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -margin * 2).isActive = true
        }
        return stack
    }

    private func makeHeader() -> NSView {
        let title = NSTextField(labelWithString: "Trois réglages, et tu parles")
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        title.textColor = .white
        let subtitle = NSTextField(wrappingLabelWithString:
            "macOS demande ton accord pour le micro, le collage et la touche Fn. "
            + "À refaire après chaque mise à jour de VoiceType.")
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = Palette.secondary
        subtitle.preferredMaxLayoutWidth = textWidth
        let header = NSStackView(views: [title, subtitle])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 6
        return header
    }

    private func makeRow(_ permission: Permission) -> NSView {
        let icon = NSImageView(image: symbol(permission.symbol, size: 15) ?? NSImage())
        icon.contentTintColor = .white
        icon.widthAnchor.constraint(equalToConstant: 22).isActive = true

        let title = NSTextField(labelWithString: permission.title)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .white
        let detail = NSTextField(wrappingLabelWithString: permission.detail)
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = Palette.secondary
        let texts = NSStackView(views: [title, detail])
        texts.orientation = .vertical
        texts.alignment = .leading
        texts.spacing = 2
        texts.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let button = PermissionButton(title: "Autoriser", target: self, action: #selector(open(_:)))
        button.tag = Permission.allCases.firstIndex(of: permission) ?? 0
        let status = makeStatus()
        rows[permission] = Row(status: status, button: button)

        let row = NSStackView(views: [icon, texts, trailingColumn(status, button)])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill  // the text column stretches, pushing the button to the edge
        row.spacing = 14
        icon.setContentHuggingPriority(.required, for: .horizontal)
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: rowHeight).isActive = true
        return row
    }

    /// Button and check share one right-aligned column, so states never shift the row.
    private func trailingColumn(_ views: NSView...) -> NSView {
        let column = NSView()
        column.translatesAutoresizingMaskIntoConstraints = false
        column.widthAnchor.constraint(equalToConstant: trailingWidth).isActive = true
        for view in views {
            view.translatesAutoresizingMaskIntoConstraints = false
            column.addSubview(view)
            view.trailingAnchor.constraint(equalTo: column.trailingAnchor).isActive = true
            view.centerYAnchor.constraint(equalTo: column.centerYAnchor).isActive = true
            view.heightAnchor.constraint(lessThanOrEqualTo: column.heightAnchor).isActive = true
        }
        column.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return column
    }

    private func makeStatus() -> NSView {
        let check = NSImageView(image: symbol("checkmark.circle.fill", size: 14) ?? NSImage())
        check.contentTintColor = .systemGreen
        let label = NSTextField(labelWithString: "Autorisé")
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .systemGreen
        let status = NSStackView(views: [check, label])
        status.spacing = 5
        status.isHidden = true
        return status
    }

    private func hairline() -> NSView {
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = Palette.hairline.cgColor
        line.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return line
    }

    private func symbol(_ name: String, size: CGFloat) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: size, weight: .medium))
    }
}
