import AppKit

/// Flat button in the capsule's palette: white fill for the next step, quiet tint otherwise.
final class PermissionButton: NSButton {
    var isPrimary = false { didSet { restyle() } }
    private var hovering = false { didSet { restyle() } }
    private var pressed = false { didSet { restyle() } }

    private let height: CGFloat = 28
    private let padding: CGFloat = 14
    private let radius: CGFloat = 8
    private let labelFont = NSFont.systemFont(ofSize: 13, weight: .medium)

    init(title: String, target: AnyObject?, action: Selector) {
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = radius
        layer?.cornerCurve = .continuous
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        restyle()
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize {
        NSSize(width: ceil(attributedTitle.size().width + padding * 2), height: height)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func mouseDown(with event: NSEvent) {
        pressed = true
        super.mouseDown(with: event)  // runs the tracking loop until the mouse is released
        pressed = false
    }

    override var focusRingMaskBounds: NSRect { bounds }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
    }

    private func restyle() {
        let fill: NSColor
        if isPrimary {
            fill = NSColor.white.withAlphaComponent(pressed ? 0.72 : hovering ? 0.88 : 1)
        } else {
            fill = NSColor.white.withAlphaComponent(pressed ? 0.2 : hovering ? 0.14 : 0.08)
        }
        layer?.backgroundColor = fill.cgColor
        attributedTitle = NSAttributedString(string: title, attributes: [
            .font: labelFont,
            .foregroundColor: isPrimary ? NSColor.black : NSColor.white,
        ])
        invalidateIntrinsicContentSize()
    }
}
