import SwiftUI
#if os(macOS)
import AppKit
#endif

/// 宠物的画法只依赖这几个绘图动作，于是同一套代码可以画到两种地方：
/// - SwiftUIPainter：SwiftUI 的 Canvas（截图、动作图鉴用）
/// - CGPainter：普通 NSView 的 Core Graphics（平时显示用）。每帧只重画这个小视图，
///   不触发 SwiftUI 的视图图更新和整窗重排，CPU 占用小得多
enum PetShade {
    case color(Color)
    case radialGradient([Color], center: CGPoint, startRadius: CGFloat, endRadius: CGFloat)
}

protocol PetPainter {
    var opacity: Double { get set }
    mutating func fill(_ path: Path, with: PetShade)
    mutating func stroke(_ path: Path, with: PetShade, lineWidth: CGFloat)
    mutating func stroke(_ path: Path, with: PetShade, style: StrokeStyle)
    mutating func translateBy(x: CGFloat, y: CGFloat)
    mutating func scaleBy(x: CGFloat, y: CGFloat)
    mutating func rotate(by: Angle)
    /// 以 at 为中心画一行字（音符、问号、「哈哈」）
    mutating func text(_ s: String, size: CGFloat, weight: Font.Weight, rounded: Bool, color: Color, at: CGPoint)
}

struct SwiftUIPainter: PetPainter {
    var g: GraphicsContext
    var opacity: Double { get { g.opacity } set { g.opacity = newValue } }
    mutating func fill(_ path: Path, with s: PetShade) {
        switch s {
        case .color(let c): g.fill(path, with: GraphicsContext.Shading.color(c))
        case .radialGradient(let cs, let c, let r0, let r1):
            g.fill(path, with: GraphicsContext.Shading.radialGradient(Gradient(colors: cs), center: c, startRadius: r0, endRadius: r1))
        }
    }
    mutating func rotate(by a: Angle) { g.rotate(by: a) }
    mutating func stroke(_ path: Path, with s: PetShade, lineWidth: CGFloat) {
        if case .color(let c) = s { g.stroke(path, with: GraphicsContext.Shading.color(c), lineWidth: lineWidth) }
    }
    mutating func stroke(_ path: Path, with s: PetShade, style: StrokeStyle) {
        if case .color(let c) = s { g.stroke(path, with: GraphicsContext.Shading.color(c), style: style) }
    }
    mutating func translateBy(x: CGFloat, y: CGFloat) { g.translateBy(x: x, y: y) }
    mutating func scaleBy(x: CGFloat, y: CGFloat) { g.scaleBy(x: x, y: y) }
    mutating func text(_ s: String, size: CGFloat, weight: Font.Weight, rounded: Bool, color: Color, at p: CGPoint) {
        g.draw(Text(s).font(.system(size: size, weight: weight, design: rounded ? .rounded : .default)).foregroundColor(color), at: p)
    }
}

#if os(macOS)
/// Core Graphics 版本。变换和透明度记在结构体里、每次画时才套上去，
/// 所以 `var body = g` 复制一份再翻转，不会影响原来那份（和 GraphicsContext 一样是值语义）
struct CGPainter: PetPainter {
    let ctx: CGContext
    var transform = CGAffineTransform.identity
    var opacity: Double = 1

    mutating func fill(_ path: Path, with s: PetShade) {
        ctx.saveGState(); defer { ctx.restoreGState() }
        ctx.concatenate(transform)
        ctx.setAlpha(opacity)
        ctx.addPath(path.cgPath)
        switch s {
        case .color(let c):
            ctx.setFillColor(Self.cg(c))
            ctx.fillPath()
        case .radialGradient(let cs, let c, let r0, let r1):
            ctx.clip()
            guard let gr = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: cs.map(Self.cg) as CFArray, locations: nil) else { return }
            ctx.drawRadialGradient(gr, startCenter: c, startRadius: r0, endCenter: c, endRadius: r1, options: [])
        }
    }
    mutating func rotate(by a: Angle) { transform = transform.rotated(by: a.radians) }

    mutating func stroke(_ path: Path, with s: PetShade, lineWidth: CGFloat) {
        stroke(path, with: s, style: StrokeStyle(lineWidth: lineWidth))
    }

    mutating func stroke(_ path: Path, with s: PetShade, style: StrokeStyle) {
        guard case .color(let c) = s else { return }
        ctx.saveGState(); defer { ctx.restoreGState() }
        ctx.concatenate(transform)
        ctx.setAlpha(opacity)
        ctx.setStrokeColor(Self.cg(c))
        ctx.setLineWidth(style.lineWidth)
        ctx.setLineCap(style.lineCap)
        ctx.addPath(path.cgPath)
        ctx.strokePath()
    }

    mutating func translateBy(x: CGFloat, y: CGFloat) { transform = transform.translatedBy(x: x, y: y) }
    mutating func scaleBy(x: CGFloat, y: CGFloat) { transform = transform.scaledBy(x: x, y: y) }

    mutating func text(_ s: String, size: CGFloat, weight: Font.Weight, rounded: Bool, color: Color, at p: CGPoint) {
        let str = NSAttributedString(string: s, attributes: [.font: Self.font(size: size, weight: weight, rounded: rounded),
                                                             .foregroundColor: NSColor(color)])
        let sz = str.size()
        ctx.saveGState(); defer { ctx.restoreGState() }
        ctx.concatenate(transform)
        ctx.setAlpha(opacity)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        str.draw(at: CGPoint(x: p.x - sz.width / 2, y: p.y - sz.height / 2))
        NSGraphicsContext.restoreGraphicsState()
    }

    // 颜色和字体转换有开销，一帧要画几百个格子，缓存起来
    nonisolated(unsafe) private static var colors: [Color: CGColor] = [:]
    nonisolated(unsafe) private static var fonts: [String: NSFont] = [:]

    private static func cg(_ c: Color) -> CGColor {
        if let v = colors[c] { return v }
        let v = NSColor(c).cgColor
        if colors.count > 512 { colors.removeAll() }
        colors[c] = v
        return v
    }

    private static func font(size: CGFloat, weight: Font.Weight, rounded: Bool) -> NSFont {
        let key = "\(Int(size * 10))-\(weight)-\(rounded)"
        if let f = fonts[key] { return f }
        let w: NSFont.Weight = weight == .heavy ? .heavy : (weight == .bold ? .bold : .regular)
        var f = NSFont.systemFont(ofSize: size, weight: w)
        if rounded, let d = f.fontDescriptor.withDesign(.rounded) { f = NSFont(descriptor: d, size: size) ?? f }
        fonts[key] = f
        return f
    }
}

/// 用 Core Graphics 画宠物的 NSView：自己的计时器按 6/8 帧刷新，窗口看不见时不画。
/// 不接鼠标事件（hitTest 返回 nil），点击、悬停、右键还是交给外面的 SwiftUI 处理。
final class PetCGNSView: NSView {
    var pet = PetView() { didSet { PetClock.shared.update(self) } }
    var wantsFast: Bool { pet.musicStart != nil }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { PetClock.shared.remove(self) } else { PetClock.shared.update(self) }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        var p = CGPainter(ctx: ctx)
        pet.render(&p, t: Date().timeIntervalSinceReferenceDate)
    }
}

/// 所有宠物共用一个时钟：同一时刻一起重画，系统一次提交就完事，比每只一个计时器省。
/// 有宠物在演奏时 8 帧（鼓点、换弓看得清），否则 6 帧；没有宠物在屏幕上时计时器停掉。
@MainActor
final class PetClock {
    static let shared = PetClock()
    private let views = NSHashTable<PetCGNSView>.weakObjects()
    private var timer: Timer?
    private var fps: Double = 0

    func update(_ v: PetCGNSView) {
        if v.window != nil { views.add(v) }
        retime()
    }

    func remove(_ v: PetCGNSView) {
        views.remove(v)
        retime()
    }

    private func retime() {
        let all = views.allObjects
        let want: Double = all.isEmpty ? 0 : (all.contains { $0.wantsFast } ? 8 : 6)
        guard want != fps else { return }
        fps = want
        timer?.invalidate(); timer = nil
        guard want > 0 else { return }
        let t = Timer(timeInterval: 1 / want, repeats: true) { _ in
            MainActor.assumeIsolated {
                for v in PetClock.shared.views.allObjects {
                    // 窗口被挡住、面板收起时不画
                    guard let w = v.window, w.isVisible, w.occlusionState.contains(.visible) else { continue }
                    v.needsDisplay = true
                }
            }
        }
        t.tolerance = 0.3 / want
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
}

struct PetCGView: NSViewRepresentable {
    var pet: PetView
    func makeNSView(context: Context) -> PetCGNSView {
        let v = PetCGNSView()
        v.pet = pet
        return v
    }
    func updateNSView(_ v: PetCGNSView, context: Context) {
        v.pet = pet
        v.needsDisplay = true
    }
}

#endif

/// 截图模式（离屏渲染）用 SwiftUI Canvas，平时用 Core Graphics
private struct PetUsesCanvasKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var petUsesCanvas: Bool {
        get { self[PetUsesCanvasKey.self] }
        set { self[PetUsesCanvasKey.self] = newValue }
    }
}
