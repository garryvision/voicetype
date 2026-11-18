import AppKit

/// Still image of the recording capsule (red dot, voice bars): the app's own emblem,
/// drawn with the same geometry and colours as CapsuleView.
final class CapsuleMark: NSView {
    private let size = CapsuleView.activeSize
    private let dotSize: CGFloat = 7
    private let barWidth: CGFloat = 3
    private let barGap: CGFloat = 3
    private let barHeights: [CGFloat] = [6, 12, 18, 10, 14, 7, 11]

    override init(frame: NSRect) {
        super.init(frame: NSRect(origin: .zero, size: size))
        wantsLayer = true
        build()
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize { size }

    private func build() {
        guard let root = layer else { return }
        root.backgroundColor = NSColor.black.cgColor
        root.cornerRadius = size.height / 2
        root.borderWidth = 1
        root.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor

        let inset: CGFloat = 13
        let dot = CALayer()
        dot.frame = NSRect(x: inset, y: (size.height - dotSize) / 2, width: dotSize, height: dotSize)
        dot.cornerRadius = dotSize / 2
        dot.backgroundColor = NSColor.systemRed.cgColor
        root.addSublayer(dot)

        let barsWidth = CGFloat(barHeights.count) * (barWidth + barGap) - barGap
        var x = size.width - inset - barsWidth
        for height in barHeights {
            let bar = CALayer()
            bar.frame = NSRect(x: x, y: (size.height - height) / 2, width: barWidth, height: height)
            bar.cornerRadius = barWidth / 2
            bar.backgroundColor = NSColor.white.cgColor
            root.addSublayer(bar)
            x += barWidth + barGap
        }
    }
}
