import AppKit
import QuartzCore

/// Sönük yıldız alanı ve farklı uzunluklarda kayan yıldızlar. Katmanlar
/// yeniden kullanılır; parıltı ve hareket Core Animation tarafından çizilir.
final class ShootingStarView: NSView {
    static func toolbarItem(identifier: NSToolbarItem.Identifier) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        let effect = ShootingStarView(frame: NSRect(x: 0, y: 0, width: 240, height: 32))
        item.view = effect
        // Katman tabanlı boş görünümün esnek aralığını açıkça belirt:
        // otomatik ölçüm bu görünümü başlangıç genişliğinde sabit tutuyor.
        item.minSize = NSSize(width: 0, height: 32)
        item.maxSize = NSSize(width: 10000, height: 32)
        item.visibilityPriority = .low
        item.label = ""
        return item
    }

    private struct Star {
        let layer: CALayer
        let xJitter: CGFloat
        let y: CGFloat
        let brightness: Float
        let period: TimeInterval
        let phase: TimeInterval
    }

    private let sky = CALayer()
    private var stars: [Star] = []
    private var streaks: [CALayer] = []
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var accessibilityObserver: NSObjectProtocol?

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 32)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        setAccessibilityElement(false)
        setContentHuggingPriority(.init(1), for: .horizontal)
        setContentCompressionResistancePriority(.init(1), for: .horizontal)

        sky.name = "starfield"
        layer?.addSublayer(sky)
        for index in 0..<72 {
            let point = CALayer()
            let prominent = index % 11 == 0
            let diameter: CGFloat = prominent ? 1.6 : .random(in: 0.65...1.2)
            point.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
            point.cornerRadius = diameter / 2
            point.backgroundColor = NSColor.white.cgColor
            if prominent {
                point.shadowColor = NSColor.white.cgColor
                point.shadowOpacity = 0.5
                point.shadowRadius = 2
                point.shadowOffset = .zero
                let sparkle = CAShapeLayer()
                let path = CGMutablePath()
                path.move(to: CGPoint(x: 0, y: 2.5))
                path.addLine(to: CGPoint(x: 0.5, y: 0.5))
                path.addLine(to: CGPoint(x: 2.5, y: 0))
                path.addLine(to: CGPoint(x: 0.5, y: -0.5))
                path.addLine(to: CGPoint(x: 0, y: -2.5))
                path.addLine(to: CGPoint(x: -0.5, y: -0.5))
                path.addLine(to: CGPoint(x: -2.5, y: 0))
                path.addLine(to: CGPoint(x: -0.5, y: 0.5))
                path.closeSubpath()
                sparkle.path = path
                sparkle.fillColor = NSColor.white.withAlphaComponent(0.35).cgColor
                sparkle.position = CGPoint(x: diameter / 2, y: diameter / 2)
                point.addSublayer(sparkle)
            }
            let brightness: Float = prominent ? 0.42 : .random(in: 0.12...0.30)
            point.opacity = brightness
            stars.append(Star(layer: point, xJitter: .random(in: 0.1...0.9),
                              y: .random(in: 0...1), brightness: brightness,
                              period: .random(in: 2.0...4.5), phase: .random(in: 0...9)))
            sky.addSublayer(point)
        }
        for length: CGFloat in [32, 54, 76, 104] {
            let streak = Self.makeStreak(length: length)
            streaks.append(streak)
            layer?.addSublayer(streak)
        }
    }

    private static func makeStreak(length: CGFloat) -> CALayer {
        let streak = CALayer()
        streak.name = "meteor"
        streak.bounds = CGRect(x: 0, y: 0, width: length, height: 12)
        streak.anchorPoint = CGPoint(x: 1, y: 0.5)
        streak.opacity = 0
        let prominent = length > 100
        let colors = [NSColor.white.withAlphaComponent(0).cgColor,
                      NSColor.white.withAlphaComponent(0.08).cgColor,
                      NSColor.white.withAlphaComponent(0.6).cgColor,
                      NSColor(calibratedRed: 1, green: 0.97, blue: 0.92, alpha: 1).cgColor]
        for glow in [true, false] {
            let tail = CAGradientLayer()
            let height: CGFloat = glow ? 4 : (prominent ? 1.4 : 0.9)
            tail.frame = CGRect(x: 0, y: 6 - height / 2, width: length, height: height)
            tail.colors = colors
            tail.locations = [0, 0.35, 0.82, 1]
            tail.startPoint = CGPoint(x: 0, y: 0.5)
            tail.endPoint = CGPoint(x: 1, y: 0.5)
            tail.opacity = glow ? 0.14 : 1
            let taper = CAShapeLayer()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: height / 2))
            path.addLine(to: CGPoint(x: length, y: 0))
            path.addLine(to: CGPoint(x: length, y: height))
            path.closeSubpath()
            taper.path = path
            tail.mask = taper
            streak.addSublayer(tail)
        }
        let head = CALayer()
        let diameter: CGFloat = prominent ? 2.6 : 1.7
        head.frame = CGRect(x: length - diameter / 2, y: 6 - diameter / 2,
                            width: diameter, height: diameter)
        head.cornerRadius = diameter / 2
        head.backgroundColor = NSColor.white.cgColor
        head.shadowColor = NSColor.white.cgColor
        head.shadowOpacity = prominent ? 0.75 : 0.45
        head.shadowRadius = prominent ? 3.5 : 2
        head.shadowOffset = .zero
        streak.addSublayer(head)
        return streak
    }

    override func layout() {
        super.layout()
        layoutStars()
    }

    private func layoutStars() {
        let count = bounds.height >= 12 ? min(stars.count, max(0, Int(bounds.width / 12))) : 0
        let animate = canPlay
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sky.frame = bounds
        for (index, star) in stars.enumerated() {
            star.layer.isHidden = index >= count
            if index < count {
                star.layer.position = CGPoint(
                    x: 5 + (CGFloat(index) + star.xJitter) / CGFloat(count) * max(0, bounds.width - 10),
                    y: 4 + star.y * max(0, bounds.height - 8))
                star.layer.contentsScale = window?.backingScaleFactor ?? 2
            }
            if animate && index < count {
                twinkle(star)
            } else {
                star.layer.removeAllAnimations()
            }
        }
        CATransaction.commit()
    }

    private func twinkle(_ star: Star) {
        guard star.layer.animation(forKey: "twinkle") == nil else { return }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = star.brightness * 0.45
        animation.toValue = min(0.85, star.brightness * 2)
        animation.duration = star.period
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.beginTime = star.layer.convertTime(CACurrentMediaTime(), from: nil) - star.phase
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        star.layer.add(animation, forKey: "twinkle")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // Üst barın sürüklenmesini ve komşu düğmelerin tıklanmasını engellemez.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var mouseDownCanMoveWindow: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopObserving()
        guard let window else { return }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                     NSWindow.didChangeOcclusionStateNotification] {
            observers.append(NotificationCenter.default.addObserver(
                forName: name, object: window, queue: .main) { [weak self] _ in
                    self?.refreshPlayback()
                })
        }
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main) { [weak self] _ in self?.refreshPlayback() }
        refreshPlayback()
    }

    private var canPlay: Bool {
        guard let window else { return false }
        return window.isKeyWindow && window.occlusionState.contains(.visible)
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private func refreshPlayback() {
        layoutStars()
        if canPlay {
            if timer == nil { schedule(after: 0.3) }
        } else {
            timer?.invalidate()
            timer = nil
            streaks.forEach { $0.removeAllAnimations() }
        }
    }

    private func schedule(after delay: TimeInterval) {
        timer?.invalidate()
        let next = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.timer = nil
            guard self.canPlay else { return }
            self.shoot()
            self.schedule(after: .random(in: 0.65...1.4))
        }
        next.tolerance = 0.05
        timer = next
        RunLoop.main.add(next, forMode: .common)
    }

    private func shoot() {
        guard bounds.width >= 140, bounds.height >= 16 else { return }
        let available = streaks.filter { $0.animation(forKey: "shootingStar") == nil }
        let small = available.filter { $0.bounds.width <= 100 }
        let candidates = small.isEmpty || Int.random(in: 0..<8) == 0 ? available : small
        guard let streak = candidates.randomElement() else { return }
        let prominent = streak.bounds.width > 100
        let duration = prominent ? TimeInterval.random(in: 1.8...2.4) : .random(in: 0.9...1.8)
        let distance = min(CGFloat.random(in: 110...260), bounds.width - streak.bounds.width - 16)
        let x = CGFloat.random(in: (streak.bounds.width + 8)...(bounds.width - distance - 8))
        let reverse = Int.random(in: 0..<4) == 0
        let start = CGPoint(x: reverse ? bounds.width - x : x,
                            y: CGFloat.random(in: 4...(bounds.height - 4)))
        let end = CGPoint(x: start.x + (reverse ? -distance : distance),
                          y: start.y < bounds.midY ? bounds.height - 4 : 4)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        streak.setAffineTransform(CGAffineTransform(rotationAngle: atan2(end.y - start.y, end.x - start.x)))
        CATransaction.commit()

        let travel = CABasicAnimation(keyPath: "position")
        travel.fromValue = NSValue(point: start)
        travel.toValue = NSValue(point: end)
        travel.duration = duration
        travel.timingFunction = CAMediaTimingFunction(name: .easeOut)
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, prominent ? 0.95 : 0.7, prominent ? 0.65 : 0.4, 0]
        fade.keyTimes = [0, 0.10, 0.65, 1]
        fade.duration = duration
        let pass = CAAnimationGroup()
        pass.animations = [travel, fade]
        pass.duration = duration
        streak.add(pass, forKey: "shootingStar")
    }

    private func stopObserving() {
        timer?.invalidate()
        timer = nil
        streaks.forEach { $0.removeAllAnimations() }
        stars.forEach { $0.layer.removeAllAnimations() }
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        if let accessibilityObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver)
        }
        accessibilityObserver = nil
    }

    deinit {
        timer?.invalidate()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        if let accessibilityObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver)
        }
    }
}
