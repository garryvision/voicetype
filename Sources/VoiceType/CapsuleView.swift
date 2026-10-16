import AppKit
import QuartzCore

enum IndicatorState: Equatable {
    case idle, paused, recording, transcribing
    case message(String, isError: Bool)
}

/// The capsule drawn with Core Animation. States differ by shape and motion, not colour alone.
final class CapsuleView: NSView {
    // MARK: - Design tokens

    static let idleSize = NSSize(width: 30, height: 7)
    static let hoverSize = NSSize(width: 40, height: 9)
    static let activeSize = NSSize(width: 112, height: 30)
    static let padding: CGFloat = 14  // room for the shadow and the shake

    private let fill = NSColor.black.withAlphaComponent(0.86).cgColor
    private let restingFill = NSColor(white: 0.5, alpha: 1).cgColor
    private let idleOpacity: Float = 0.6
    let barCount = 11
    private let barWidth: CGFloat = 3
    private let barStep: CGFloat = 6
    let barMinHeight: CGFloat = 3
    let barMaxHeight: CGFloat = 18
    private let dotSize: CGFloat = 8
    private let contentInset: CGFloat = 14
    private let font = NSFont.systemFont(ofSize: 12, weight: .medium)

    // MARK: - Layers

    let stage = CALayer()      // everything, so the error shake moves it as one
    let capsule = CALayer()
    let dot = CALayer()
    private let text = CATextLayer()
    var bars: [CALayer] = []
    var levels: [CGFloat] = []

    private(set) var state: IndicatorState = .idle
    private var isHovered = false
    var onClick: ((NSEvent) -> Void)?

    var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        setupLayers()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func setupLayers() {
        layer?.addSublayer(stage)
        capsule.backgroundColor = fill
        capsule.borderWidth = 0.5
        capsule.shadowColor = NSColor.black.cgColor
        capsule.shadowOpacity = 0.3
        capsule.shadowRadius = 8
        capsule.shadowOffset = CGSize(width: 0, height: -2)
        stage.addSublayer(capsule)

        dot.cornerRadius = dotSize / 2
        dot.bounds = CGRect(x: 0, y: 0, width: dotSize, height: dotSize)
        stage.addSublayer(dot)

        text.font = font
        text.fontSize = font.pointSize
        text.foregroundColor = NSColor.white.cgColor
        text.truncationMode = .end
        stage.addSublayer(text)

        levels = Array(repeating: 0, count: barCount)
        bars = (0..<barCount).map { _ in
            let bar = CALayer()
            bar.backgroundColor = NSColor.white.cgColor
            bar.cornerRadius = barWidth / 2
            bar.bounds = CGRect(x: 0, y: 0, width: barWidth, height: barMinHeight)
            stage.addSublayer(bar)
            return bar
        }
    }

    // MARK: - Sizing

    func capsuleSize(for state: IndicatorState) -> NSSize {
        switch state {
        case .idle, .paused: return isHovered ? Self.hoverSize : Self.idleSize
        case .recording, .transcribing: return Self.activeSize
        case .message(let message, _):
            let width = contentInset * 2 + dotSize + 8 + textWidth(message)
            return NSSize(width: ceil(width), height: Self.activeSize.height)
        }
    }

    /// The window always leaves room for the hover size, so hovering never resizes it.
    func windowSize(for state: IndicatorState) -> NSSize {
        let size = capsuleSize(for: state)
        let width = max(size.width, Self.hoverSize.width) + Self.padding * 2
        let height = max(size.height, Self.hoverSize.height) + Self.padding * 2
        return NSSize(width: width, height: height)
    }

    private func textWidth(_ string: String) -> CGFloat {
        (string as NSString).size(withAttributes: [.font: font]).width
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        stage.frame = bounds
        layoutContent(width: capsuleSize(for: state).width)
        CATransaction.commit()
    }

    private func layoutContent(width: CGFloat) {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        capsule.position = center
        dot.position = CGPoint(x: center.x - width / 2 + contentInset + dotSize / 2, y: center.y)

        // Bars fill the space right of the dot; centred when the dot is hidden (transcribing)
        let barsWidth = CGFloat(barCount - 1) * barStep + barWidth
        let regionStart = state == .transcribing
            ? center.x - width / 2 + contentInset : dot.position.x + dotSize / 2
        let regionEnd = center.x + width / 2 - contentInset
        let barsStart = regionStart + (regionEnd - regionStart - barsWidth) / 2
        for (index, bar) in bars.enumerated() {
            bar.position = CGPoint(x: barsStart + barWidth / 2 + CGFloat(index) * barStep, y: center.y)
        }

        let textX = dot.position.x + dotSize / 2 + 8
        let lineHeight = ceil(font.ascender - font.descender)
        text.frame = CGRect(x: textX, y: center.y - lineHeight / 2 - 1,
                            width: max(0, center.x + width / 2 - contentInset - textX), height: lineHeight)
    }

    // MARK: - Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self))
    }

    override func mouseEntered(with event: NSEvent) { setHovered(true) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }
    override func mouseDown(with event: NSEvent) { onClick?(event) }
    override func rightMouseDown(with event: NSEvent) { onClick?(event) }

    private func setHovered(_ hovered: Bool) {
        isHovered = hovered
        guard state == .idle || state == .paused else { return }
        apply(state, animated: true)
    }

    // MARK: - State rendering

    func apply(_ newState: IndicatorState, animated: Bool) {
        let previous = state
        state = newState
        text.contentsScale = window?.backingScaleFactor ?? 2
        dot.removeAllAnimations()
        bars.forEach { $0.removeAnimation(forKey: "wave") }

        let size = capsuleSize(for: newState)
        morph(to: size, animated: animated)
        CATransaction.begin()
        CATransaction.setAnimationDuration(animated ? 0.18 : 0)
        layoutContent(width: size.width)
        style(for: newState)
        CATransaction.commit()

        if case .message(_, true) = newState, animated, !reduceMotion { shake() }
        if newState == .recording, previous != .recording { resetLevels() }
    }

    private func style(for state: IndicatorState) {
        let resting = state == .idle || state == .paused
        // Resting: mid grey, readable on light and dark backgrounds. Paused: outline only.
        let hovered = resting && isHovered
        capsule.opacity = resting && !isHovered ? idleOpacity : 1
        capsule.backgroundColor = state == .paused ? NSColor.clear.cgColor
            : resting && !hovered ? restingFill : fill
        capsule.borderWidth = state == .paused ? 1.5 : 0.5
        capsule.borderColor = state == .paused ? restingFill : NSColor.white.withAlphaComponent(0.12).cgColor
        capsule.shadowOpacity = resting && !hovered ? 0 : 0.3

        switch state {
        case .idle, .paused:
            show(dot: false, bars: false, text: nil)
        case .recording:
            dot.backgroundColor = NSColor.systemRed.cgColor
            show(dot: true, bars: true, text: nil)
            pulseDot()
        case .transcribing:
            show(dot: false, bars: true, text: nil)
            startWave()
        case .message(let message, let isError):
            dot.backgroundColor = (isError ? NSColor.systemRed : NSColor.white).cgColor
            show(dot: true, bars: false, text: message)
        }
    }

    private func show(dot showDot: Bool, bars showBars: Bool, text message: String?) {
        dot.opacity = showDot ? 1 : 0
        bars.forEach { $0.opacity = showBars ? 1 : 0 }
        if let message { text.string = message }
        text.opacity = message == nil ? 0 : 1
    }
}
