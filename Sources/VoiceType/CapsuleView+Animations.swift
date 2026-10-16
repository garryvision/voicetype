import AppKit
import QuartzCore

extension CapsuleView {
    // MARK: - Animations

    func morph(to size: NSSize, animated: Bool) {
        let from = capsule.presentation()?.bounds ?? capsule.bounds
        let to = CGRect(origin: .zero, size: size)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        capsule.bounds = to
        capsule.cornerRadius = size.height / 2
        CATransaction.commit()
        guard animated, from != to else { return }

        for (key, start, end) in [("bounds", NSValue(rect: from), NSValue(rect: to)),
                                  ("cornerRadius", from.height / 2 as NSNumber, size.height / 2 as NSNumber)] {
            let animation: CABasicAnimation = reduceMotion ? CABasicAnimation(keyPath: key) : {
                let spring = CASpringAnimation(keyPath: key)
                spring.damping = 22
                spring.stiffness = 320
                spring.duration = spring.settlingDuration
                return spring
            }()
            if reduceMotion { animation.duration = 0.15 }
            animation.fromValue = start
            animation.toValue = end
            capsule.add(animation, forKey: key)
        }
    }

    func pulseDot() {
        guard !reduceMotion else { return }
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1
        pulse.toValue = 0.35
        pulse.duration = 0.9
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        dot.add(pulse, forKey: "pulse")
    }

    /// Bars ripple left to right while whisper works.
    func startWave() {
        let now = CACurrentMediaTime()
        for (index, bar) in bars.enumerated() {
            bar.bounds.size.height = barMinHeight
            bar.opacity = 0.75
            guard !reduceMotion else { continue }
            let wave = CABasicAnimation(keyPath: "transform.scale.y")
            wave.fromValue = 1
            wave.toValue = 2.6
            wave.duration = 0.42
            wave.autoreverses = true
            wave.repeatCount = .infinity
            wave.beginTime = now + Double(index) * 0.055
            wave.fillMode = .backwards
            wave.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            bar.add(wave, forKey: "wave")
        }
    }

    func shake() {
        let shake = CAKeyframeAnimation(keyPath: "transform.translation.x")
        shake.values = [0, -7, 7, -5, 5, -2, 0]
        shake.duration = 0.4
        stage.add(shake, forKey: "shake")
    }

    // MARK: - Live waveform

    func resetLevels() {
        levels = Array(repeating: 0, count: barCount)
        updateBars()
    }

    /// Scrolling history: the newest level enters on the right.
    func pushLevel(_ level: Float) {
        guard state == .recording else { return }
        levels.removeFirst()
        levels.append(CGFloat(level))
        updateBars()
    }

    func updateBars() {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.08)
        for (bar, level) in zip(bars, levels) {
            bar.bounds.size.height = barMinHeight + (barMaxHeight - barMinHeight) * level
        }
        CATransaction.commit()
    }
}
