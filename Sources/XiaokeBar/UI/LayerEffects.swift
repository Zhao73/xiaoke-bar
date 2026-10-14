import SwiftUI
import AppKit
import QuartzCore

// 一直在循环的装饰动画（流光、呼吸灯、背景极光）全部交给 Core Animation：
// 动画由系统的渲染进程逐帧合成，我们的主线程和 SwiftUI 视图图完全不参与，面板开着也几乎不占 CPU。
// 之前用 SwiftUI 的 repeatForever / TimelineView，会让整个面板按屏幕刷新率不停重算布局。

/// 进度条上扫过的一道白光
struct SweepShine: NSViewRepresentable {
    func makeNSView(context: Context) -> ShineView { ShineView() }
    func updateNSView(_ v: ShineView, context: Context) {}

    final class ShineView: NSView {
        private let shine = CAGradientLayer()

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.masksToBounds = true
            shine.colors = [NSColor.white.withAlphaComponent(0).cgColor, NSColor.white.withAlphaComponent(0.45).cgColor, NSColor.white.withAlphaComponent(0).cgColor]
            shine.startPoint = CGPoint(x: 0, y: 0.5)
            shine.endPoint = CGPoint(x: 1, y: 0.5)
            layer?.addSublayer(shine)
        }
        required init?(coder: NSCoder) { fatalError() }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func layout() {
            super.layout()
            CATransaction.begin(); CATransaction.setDisableActions(true)
            shine.frame = CGRect(x: -60, y: 0, width: 40, height: bounds.height)
            CATransaction.commit()
            let a = CABasicAnimation(keyPath: "position.x")
            a.fromValue = -40
            a.toValue = bounds.width + 40
            a.duration = 2.4
            a.beginTime = CACurrentMediaTime() + 1
            a.repeatCount = .infinity
            shine.add(a, forKey: "sweep")
        }
    }
}

/// 呼吸灯小圆点：表示还在跑
struct PulseDot: NSViewRepresentable {
    var color: NSColor = .systemGreen
    var size: CGFloat = 5

    func makeNSView(context: Context) -> NSView {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        v.wantsLayer = true
        let dot = CALayer()
        dot.frame = v.bounds
        dot.cornerRadius = size / 2
        dot.backgroundColor = color.cgColor
        v.layer?.addSublayer(dot)
        let o = CABasicAnimation(keyPath: "opacity"); o.fromValue = 1; o.toValue = 0.35
        let s = CABasicAnimation(keyPath: "transform.scale"); s.fromValue = 1; s.toValue = 0.7
        let g = CAAnimationGroup()
        g.animations = [o, s]
        g.duration = 0.9
        g.autoreverses = true
        g.repeatCount = .infinity
        g.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        dot.add(g, forKey: "pulse")
        return v
    }
    func updateNSView(_ v: NSView, context: Context) {}
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? { CGSize(width: size, height: size) }
}

/// 面板背景里慢慢漂移的三团彩色光晕（28 秒来回一趟）
struct AuroraLayer: NSViewRepresentable {
    var colors: [Color]

    func makeNSView(context: Context) -> AuroraView { AuroraView() }
    func updateNSView(_ v: AuroraView, context: Context) { v.setColors(colors.map { NSColor($0) }) }

    final class AuroraView: NSView {
        private var blobs: [CAGradientLayer] = []
        // 每团光的大小（相对宽度）、起点、终点（相对宽度）
        private let specs: [(CGFloat, CGPoint, CGPoint)] = [
            (1.1, CGPoint(x: -0.3, y: 0.1), CGPoint(x: 0.25, y: -0.2)),
            (0.9, CGPoint(x: 0.3, y: 0.25), CGPoint(x: -0.3, y: 0.5)),
            (0.7, CGPoint(x: -0.15, y: 1.15), CGPoint(x: 0.2, y: 0.95)),
        ]

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            for _ in specs {
                let l = CAGradientLayer()
                l.type = .radial
                l.startPoint = CGPoint(x: 0.5, y: 0.5)
                l.endPoint = CGPoint(x: 1, y: 1)
                layer?.addSublayer(l)
                blobs.append(l)
            }
        }
        required init?(coder: NSCoder) { fatalError() }

        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func setColors(_ cs: [NSColor]) {
            for (i, l) in blobs.enumerated() {
                let c = cs[i % cs.count]
                let new = [c.withAlphaComponent(0.24).cgColor, c.withAlphaComponent(0).cgColor]
                let fade = CABasicAnimation(keyPath: "colors")
                fade.fromValue = l.colors
                fade.toValue = new
                fade.duration = 1.2
                l.colors = new
                l.add(fade, forKey: "colors")
            }
        }

        override func layout() {
            super.layout()
            let w = bounds.width
            guard w > 0 else { return }
            CATransaction.begin(); CATransaction.setDisableActions(true)
            for (l, (size, from, to)) in zip(blobs, specs) {
                let d = w * size
                l.bounds = CGRect(x: 0, y: 0, width: d, height: d)
                // 原来的偏移是相对左上角放一个 d×d 的圆；换成圆心坐标
                let p0 = CGPoint(x: w * from.x + d / 2, y: w * from.y + d / 2)
                let p1 = CGPoint(x: w * to.x + d / 2, y: w * to.y + d / 2)
                l.position = p0
                let a = CABasicAnimation(keyPath: "position")
                a.fromValue = NSValue(point: p0)
                a.toValue = NSValue(point: p1)
                a.duration = 14
                a.autoreverses = true
                a.repeatCount = .infinity
                a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                l.add(a, forKey: "drift")
            }
            CATransaction.commit()
        }
    }
}
