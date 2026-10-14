import SwiftUI
import AppKit

/// 会动的宠物 + 道具。整块画布 26×16 格：身体在 (3, 5) 开始的 16×10 格，右边 7 列、上面 5 行放道具和特效。
/// 用 TimelineView 每秒 8 帧刷新：像素画本来就是低帧率风格，还省电。
/// 「这一帧演什么」在画的时候才决定（表演、摸头、欢呼都有时限），外面不用定时刷新。
struct PetView: View {
    var kind: Provider = .claude
    var action: PetAction = .idle
    var pixel: CGFloat = 4
    var walking = false
    var tapped: Date? = nil
    /// 每只宠物不同的种子：几只一起空闲时各玩各的
    var seed = 0
    /// 鼠标相对身体中心的水平距离（点），用来转眼睛；闭包每帧取一次，可以跟随全屏鼠标
    var gaze: (() -> CGFloat?)? = nil
    var petted: Date? = nil
    var trick: PetAction? = nil
    var trickUntil: Date? = nil
    var cheerUntil: Date? = nil
    var dragging = false
    var landed: Date? = nil
    /// 实时联动：AI 在说话（张嘴）、刚换了工具（蹦「!」）、子代理数量（小弟数量）、进程忙碌程度（冒汗）
    var talkUntil: Date? = nil
    var alertAt: Date? = nil
    var minions = 2
    var strain: Double = 0
    /// 乐队：曲子开始时间和速度，演奏动作跟着拍子走
    var musicStart: Date? = nil
    /// 主奏时传入曲子 id：按谱子里当前的音放手指、按换弓来回拉弓
    var songID: String? = nil
    var bpm: Double = 0
    /// 二泉映月：戴圆墨镜
    var glasses = false
    /// 心情 0–100：影响表情和空闲时做什么
    var happiness: Double = 60
    /// 刚出场的时间：从天上掉下来，落地扬灰
    var appearedAt: Date? = nil
    /// 养了狗 / 猫：空闲时会一起玩
    var hasDog = false
    var hasCat = false
    /// 空闲时在画布里左右溜达的距离（格）。在 Canvas 里画，不用外层每帧改位置，整页就不会跟着重新排版
    var wander: Double = 0

    static let cols: CGFloat = 26, rows: CGFloat = 16
    let ox = 3, oy = 5

    @Environment(\.petsPaused) private var paused
    @Environment(\.petUsesCanvas) private var usesCanvas

    var body: some View {
        Group {
            if usesCanvas {
                // 演奏时 8 帧（鼓点、换弓看得清），平时 6 帧就够像素画用；窗口被挡住时整个暂停
                TimelineView(.animation(minimumInterval: musicStart == nil ? 1.0 / 6.0 : 1.0 / 8.0, paused: paused)) { ctx in
                    let t = ctx.date.timeIntervalSinceReferenceDate
                    Canvas { g, _ in var p = SwiftUIPainter(g: g); render(&p, t: t) }
                }
            } else {
                PetCGView(pet: self)
            }
        }
        .frame(width: (Self.cols + wander * 2) * pixel, height: Self.rows * pixel)
        .accessibilityLabel("\(PetArt.name(kind)) · \(action.label)")
    }

    /// 道具上的主题色：小 G 本身是黑的，深色背景上要换成浅灰才看得见
    var accent: Color { kind == .grok ? Color(white: 0.82) : PetArt.limbColor(kind) }

    func cell(_ g: inout some PetPainter, _ x: Double, _ y: Double, _ c: Color, w: Double = 1, h: Double = 1) {
        g.fill(Path(CGRect(x: x * pixel, y: y * pixel, width: w * pixel + 0.3, height: h * pixel + 0.3)), with: .color(c))
    }

    /// 这一帧真正要演的动作：被拎着 > 双击表演 > 被摸头 > 别的会话做完一起欢呼 > 本职动作（空闲时自己找乐子）
    private func currentAction(_ t: Double, strolling: Bool) -> PetAction {
        if dragging { return .dangle }
        if let tr = trick, let u = trickUntil, u.timeIntervalSinceReferenceDate > t { return tr }
        if let p = petted, t - p.timeIntervalSinceReferenceDate < 1.8 { return .love }
        // 一起庆祝，但每只用不同的动作、错开一点开始，不整齐划一
        if let c = cheerUntil, c.timeIntervalSinceReferenceDate - 3 + Double(seed % 4) * 0.22 < t, c.timeIntervalSinceReferenceDate > t {
            return [.celebrate, .dance, .spin, .wave, .laugh][seed % 5]
        }
        if action == .idle && !walking && !strolling { return idleVariant(t) }
        return action
    }

    /// 吃饼干要从第一口按顺序演：用「这次表演开始了几秒」，而不是绝对时间（否则一出场饼干就是半块、还会长回来）
    func eatClock(_ tAbs: Double, fallback t: Double) -> Double {
        if let u = trickUntil?.timeIntervalSinceReferenceDate, u > tAbs { return max(0, Self.eatLength - (u - tAbs)) }
        return t.truncatingRemainder(dividingBy: Self.eatLength + 1.2)
    }

    /// 溜达：16 秒一圈，走一段、停一段。返回 (偏移格数, 是否在走, 是否朝左)
    private func stroll(_ t: Double) -> (Double, Bool, Bool) {
        guard wander > 0 else { return (0, false, false) }
        let c = (t + Double(seed) * 1.7).truncatingRemainder(dividingBy: 16) / 16
        if c < 0.3 { return (-wander + 2 * wander * (c / 0.3), true, false) }
        if c < 0.5 { return (wander, false, false) }
        if c < 0.8 { return (wander - 2 * wander * ((c - 0.5) / 0.3), true, true) }
        return (-wander, false, false)
    }

    /// 空闲时每 7 秒抽一次签：大多数时候发呆，偶尔挥手、伸懒腰、抛球、玩滑板、遛狗、陪猫；心情差时会闹情绪
    private func idleVariant(_ t: Double) -> PetAction {
        let slot = Int(t / 7)
        var h = UInt64(truncatingIfNeeded: slot &* 2_654_435_761 &+ seed &* 40_503)
        h ^= h >> 13; h = h &* 0x5bd1e995; h ^= h >> 15
        var options: [PetAction] = [.idle, .idle, .idle, .idle, .wave, .stretch, .juggle, .skate]
        if hasDog { options += [.walkDog, .fetch] }
        if hasCat { options += [.catNap] }
        if happiness > 78 { options += [.dance, .skate, .wave] }
        if happiness < 35 { options = [.idle, .sulk, .sulk] + (happiness < 18 ? [.angry, .angry] : []) }
        let pick = options[Int(h % UInt64(options.count))]
        // 遛狗、陪猫要演完整一段，给 6.5 秒；其他小把戏 4.6 秒
        let len = [.walkDog, .fetch, .catNap].contains(pick) ? 6.5 : 4.6
        guard t - Double(slot) * 7 < len else { return .idle }
        return pick
    }

    func render(_ g: inout some PetPainter, t tAbs: Double) {
        g.translateBy(x: wander * pixel, y: 0)
        // 每只宠物的动画相位错开，几只做同一件事时也不会整齐划一
        let t = tAbs + Double(seed) * 0.913
        var (sx, strolling, facingLeft) = stroll(tAbs)
        if action != .idle { (sx, strolling, facingLeft) = (0, false, false) }
        let act = currentAction(tAbs, strolling: strolling)
        if act != .idle { strolling = false; facingLeft = false }
        var pose = PetArt.Pose()
        var lift: Double = 0
        var dx: Double = act == .idle || act == .wave || act == .stretch || act == .juggle ? sx : 0
        var flip: Double = facingLeft ? -1 : 1        // 转圈 / 往左走时水平翻转
        pose.eyesClosed = t.truncatingRemainder(dividingBy: 3.7 + Double(seed % 3) * 0.4) < 0.14
        if walking || strolling { pose.legPhase = Int(t * 6) % 2 + 1 }
        let tapAge = tapped.map { tAbs - $0.timeIntervalSinceReferenceDate } ?? 99
        let beat = musicStart.map { max(0, (tAbs - $0.timeIntervalSinceReferenceDate) * bpm / 60) }
        let landAge = landed.map { tAbs - $0.timeIntervalSinceReferenceDate } ?? 99

        switch act {
        case .idle:
            lift = strolling ? 0 : (sin(t * 2.4 + Double(seed)) > 0.6 ? 1 : 0)
            pose.lookOffset = Int(t / 2.9) % 5 == 0 ? (Int(t / 5.8) % 2 == 0 ? -1 : 1) : 0
        case .thinking:
            lift = sin(t * 1.6) * 0.5 + 0.5
            pose.lookOffset = 1
        case .typing:
            pose.armWave = Int(t * 9) % 2 + 1
            pose.lookOffset = 1
        case .reading:
            pose.lookOffset = 1
            pose.eyesClosed = false
            lift = Int(t / 2.2) % 2 == 0 ? 0 : 0.5
        case .searching:
            pose.lookOffset = Int(t * 1.4) % 2 == 0 ? 1 : 0
            dx = sin(t * 1.4) * 0.6
        case .running:
            pose.armWave = Int(t * 4) % 3 == 0 ? 2 : 0
            pose.lookOffset = 1
        case .building:
            // 抡锤子：抬手 → 砸下去时身体一顿
            let hit = (t * 2.2).truncatingRemainder(dividingBy: 1)
            pose.armWave = hit < 0.55 ? 2 : 0
            pose.lookOffset = 1
            pose.squash = hit > 0.55 && hit < 0.65
        case .planning:
            pose.armWave = 2
            pose.lookOffset = 1
            lift = Int(t * 1.2) % 3 == 0 ? 0.5 : 0
        case .asking:
            pose.lookOffset = 0
            pose.armWave = Int(t * 1.5) % 2 == 0 ? 1 : 0
            lift = sin(t * 3) > 0.7 ? 0.5 : 0
        case .delegating:
            pose.armWave = 2
            pose.lookOffset = 1
        case .photo:
            // 举相机，按快门那一下缩一下
            let c = t.truncatingRemainder(dividingBy: 2.2) / 2.2
            pose.armWave = 2
            pose.lookOffset = 1
            pose.eyesClosed = c > 0.62 && c < 0.7
            pose.squash = c > 0.6 && c < 0.64
        case .git:
            pose.armWave = Int(t * 1.6) % 2 == 0 ? 2 : 0
            pose.lookOffset = 1
        case .network:
            pose.lookOffset = 1
            lift = sin(t * 2) > 0.5 ? 0.5 : 0
        case .deploy:
            // 火箭升空时举手欢呼
            let c = t.truncatingRemainder(dividingBy: 3.2) / 3.2
            pose.armsUp = c > 0.35 && c < 0.8
            pose.lookOffset = 1
            lift = c > 0.35 && c < 0.8 ? abs(sin(c * 18)) * 1 : 0
        case .install:
            let c = t.truncatingRemainder(dividingBy: 2.6) / 2.6
            pose.armWave = c < 0.5 ? 2 : 1
            pose.lookOffset = 1
            pose.eyesClosed = c > 0.8 && c < 0.86
        case .guitar:
            pose.armsHidden = true
            lift = Int(t * 3) % 2 == 0 ? 0.5 : 0
            pose.eyesClosed = Int(t * 0.8) % 3 == 0
        case .dance:
            let beat = Int(t * 4)
            pose.armWave = beat % 2 + 1
            pose.legPhase = beat % 2 + 1
            lift = beat % 2 == 0 ? 1.5 : 0
            dx = beat % 4 < 2 ? -0.5 : 0.5
        case .coffee:
            pose.armWave = Int(t / 2.5) % 2 == 0 ? 2 : 0
            pose.eyesClosed = Int(t / 2.5) % 2 == 0
        case .sleep:
            pose.eyesClosed = true
            lift = sin(t * 1.2) > 0 ? 0.5 : 0
        case .worried:
            pose.lookOffset = Int(t * 1.5) % 2 == 0 ? -1 : 1
        case .celebrate:
            let cyc = t.truncatingRemainder(dividingBy: 0.7) / 0.7
            lift = sin(cyc * .pi) * 3.5
            pose.armsUp = true
            pose.squash = cyc < 0.08
        case .wave:
            pose.armWave = Int(t * 5) % 2 == 0 ? 2 : 0
            pose.lookOffset = 0
        case .stretch:
            let cyc = t.truncatingRemainder(dividingBy: 2.4) / 2.4
            pose.armsUp = cyc < 0.7
            pose.eyesClosed = cyc < 0.7
            lift = cyc < 0.7 ? sin(cyc / 0.7 * .pi) * 0.8 : 0
            pose.squash = cyc > 0.72 && cyc < 0.82
        case .juggle:
            pose.armWave = Int(t * 5) % 2 + 1
            pose.lookOffset = 0
        case .skate:
            lift = 1
            dx += sin(t * 1.3 + Double(seed)) * 2.2
            pose.armWave = cos(t * 1.3) > 0 ? 1 : 2
            pose.lookOffset = cos(t * 1.3 + Double(seed)) > 0 ? 1 : -1
        case .spin:
            flip = cos(t * 11)
            lift = abs(sin(t * 5.5)) * 1.5
            pose.armsUp = true
        case .love:
            pose.eyesClosed = true
            pose.armWave = Int(t * 4) % 2 + 1
            lift = abs(sin(t * 5)) * 0.8
        case .dangle:
            pose.armsUp = true
            pose.legPhase = Int(t * 8) % 2 + 1
            pose.lookOffset = Int(t * 2) % 2 == 0 ? -1 : 1
            dx = sin(t * 5) * 0.5
            lift = 2.5
        default:
            extraPose(act, t: act == .eat ? eatClock(tAbs, fallback: t) : t, beat: beat, pose: &pose, lift: &lift, dx: &dx)
        }
        // 出场：从上面掉下来，落地压扁一下
        let enterAge = appearedAt.map { tAbs - $0.timeIntervalSinceReferenceDate } ?? 99
        if enterAge < 0.55 { lift = 14 * pow(1 - enterAge / 0.55, 2); pose.armsUp = true }
        else if enterAge < 0.72 { pose.squash = true; lift = 0 }
        if tapAge < 0.6 {
            lift = sin(tapAge / 0.6 * .pi) * 3.5
            pose.armsUp = true
        }
        if landAge < 0.18 { pose.squash = true; lift = 0 }
        let alertAge = alertAt.map { tAbs - $0.timeIntervalSinceReferenceDate } ?? 99
        if alertAge < 0.45 { lift = max(lift, sin(alertAge / 0.45 * .pi) * 1.5) }
        // 眼睛跟着鼠标：只在没专心干活时看你
        if [.idle, .wave, .asking, .juggle, .celebrate].contains(act), let gx = gaze?() {
            pose.lookOffset = gx > 28 ? 1 : (gx < -28 ? -1 : 0)
        }

        let bx = Double(ox) + dx, by = Double(oy) - lift
        // 影子（跳得越高越淡）
        let sw = 12 * (1 - lift / 8)
        g.fill(Path(ellipseIn: CGRect(x: (bx + 8 - sw / 2) * pixel, y: (Double(oy) + 9.6 + (act == .skate ? 1 : 0)) * pixel, width: sw * pixel, height: 0.8 * pixel)),
               with: .color(.black.opacity(max(0.04, 0.18 - lift / 40))))

        drawPropBehind(&g, act, t: t, beat: beat, bx: bx, by: by)
        var body = g
        if flip != 1 {
            let cx = (bx + 8) * pixel
            body.translateBy(x: cx, y: 0)
            body.scaleBy(x: abs(flip) < 0.15 ? 0.15 * (flip < 0 ? -1 : 1) : flip, y: 1)
            body.translateBy(x: -cx, y: 0)
        }
        for (x, y, c) in PetArt.pixels(kind, pose) { cell(&body, bx + Double(x), by + Double(y), c) }
        if act == .love { drawBlush(&body, bx: bx, by: by) }
        drawFace(&body, act, t: t, eyesClosed: pose.eyesClosed, look: pose.lookOffset, bx: bx, by: by + (pose.squash ? 1 : 0))
        if glasses { drawGlasses(&body, look: pose.lookOffset, bx: bx, by: by + (pose.squash ? 1 : 0)) }
        if let u = talkUntil, u.timeIntervalSinceReferenceDate > tAbs, !pose.eyesClosed || act != .sleep { drawMouth(&body, t: t, bx: bx, by: by + (pose.squash ? 1 : 0)) }
        drawPropFront(&g, act, t: act == .eat ? eatClock(tAbs, fallback: t) : t, beat: beat, bx: bx, by: by)
        if landAge < 0.5 { drawDust(&g, age: landAge) }
        if enterAge > 0.55 && enterAge < 1.05 { drawDust(&g, age: enterAge - 0.55) }
        if alertAge < 1.1 { drawAlert(&g, age: alertAge, bx: bx, by: by) }
        if strain > 0.6 { drawSweat(&g, t: t, bx: bx, by: by) }
    }

    /// 说话：嘴巴一张一合（节奏不规则一点，像在讲话）
    private func drawMouth(_ g: inout some PetPainter, t: Double, bx: Double, by: Double) {
        let open = sin(t * 13) + sin(t * 7.3) > 0.3
        switch kind {
        case .claude: cell(&g, bx + 7, by + 4.6, Color(red: 0.25, green: 0.1, blue: 0.08), w: 2, h: open ? 1.2 : 0.4)
        case .codex: cell(&g, bx + 7, by + (open ? 4.6 : 5), .white, w: 3, h: open ? 1.4 : 1)
        case .grok: cell(&g, bx + 7, by + 4.2, .white, w: 2, h: open ? 0.9 : 0.35)
        case .gemini: cell(&g, bx + 7, by + 5.4, Color(red: 0.1, green: 0.08, blue: 0.27), w: 2, h: open ? 0.9 : 0.35)
        }
    }

    /// 换工具时头上蹦一个黄色「!」
    private func drawAlert(_ g: inout some PetPainter, age: Double, bx: Double, by: Double) {
        let pop = min(1, age / 0.15)
        g.opacity = age > 0.8 ? 1 - (age - 0.8) / 0.3 : 1
        let x = bx + 7.4, y = by - 3.6 - pop * 0.6
        cell(&g, x, y, .yellow, w: 1.2, h: 2.2 * pop)
        cell(&g, x, y + 2.7, .yellow, w: 1.2, h: 1)
        g.opacity = 1
    }

    /// 进程很忙时冒汗，越忙汗越多
    private func drawSweat(_ g: inout some PetPainter, t: Double, bx: Double, by: Double) {
        let n = strain > 1.2 ? 3 : (strain > 0.9 ? 2 : 1)
        for i in 0..<n {
            let ph = (t * 1.1 + Double(i) / Double(n)).truncatingRemainder(dividingBy: 1)
            g.opacity = 1 - ph
            let x = i % 2 == 0 ? bx + 14 + ph : bx + 1 - ph
            g.fill(Path(ellipseIn: CGRect(x: x * pixel, y: (by + 0.5 + Double(i) + ph * 3) * pixel, width: pixel * 0.9, height: pixel * 1.3)),
                   with: .color(Color(red: 0.45, green: 0.75, blue: 1)))
            g.opacity = 1
        }
    }

    // MARK: 特效

    private func drawBlush(_ g: inout some PetPainter, bx: Double, by: Double) {
        let pink = Color(red: 1, green: 0.45, blue: 0.6).opacity(0.75)
        let spots: [(Double, Double)] = kind == .gemini ? [(5, 5), (10, 5)] : [(2.6, 4.2), (12.4, 4.2)]
        for (x, y) in spots { cell(&g, bx + x, by + y, pink, w: 1, h: 0.6) }
    }

    /// 像素小爱心（5×4）
    func pixelHeart(_ g: inout some PetPainter, x: Double, y: Double, c: Color, s: Double = 0.5) {
        let rows = [".x.x.", "xxxxx", ".xxx.", "..x.."]
        for (j, r) in rows.enumerated() { for (i, ch) in r.enumerated() where ch == "x" { cell(&g, x + Double(i) * s, y + Double(j) * s, c, w: s, h: s) } }
    }

    func drawDust(_ g: inout some PetPainter, age: Double) {
        let p = age / 0.5
        g.opacity = 1 - p
        for side in [-1.0, 1.0] {
            for i in 0..<3 {
                let x = 11 + side * (5 + p * 6 + Double(i) * 1.2)
                let y = Double(oy) + 9 - p * 1.5 - Double(i) * 0.4
                cell(&g, x, y, Color(white: 0.7), w: 0.8 - Double(i) * 0.2, h: 0.8 - Double(i) * 0.2)
            }
        }
        g.opacity = 1
    }

    // MARK: 道具

    private func drawPropBehind(_ g: inout some PetPainter, _ act: PetAction, t: Double, beat: Double?, bx: Double, by: Double) {
        let px = 19.0   // 道具起始列（身体右侧）
        switch act {
        case .typing:
            // 笔记本电脑：屏幕上一行行代码在冒出来
            cell(&g, px, 9, Color(white: 0.55), w: 6, h: 0.8)
            cell(&g, px + 0.5, 4.5, Color(white: 0.22), w: 5, h: 4.5)
            let colors: [Color] = [Provider.claude.tint, .green, Provider.codex.tint, .yellow]
            let shown = Int(t * 5) % 7
            for i in 0..<4 where i <= shown {
                let w = Double((i * 7 + 3) % 4 + 1)
                cell(&g, px + 1, 5.2 + Double(i), colors[i % 4], w: w, h: 0.5)
            }
        case .running:
            // 终端窗口：>_ 光标闪烁，输出一行行往上滚
            cell(&g, px, 3.5, Color(white: 0.08), w: 6.5, h: 6)
            cell(&g, px, 3.5, Color(white: 0.3), w: 6.5, h: 0.8)
            for i in 0..<3 {
                let w = Double((Int(t * 4) + i * 3) % 5 + 1)
                cell(&g, px + 0.6, 4.8 + Double(i) * 1.2, Color.green.opacity(0.75), w: w, h: 0.5)
            }
            cell(&g, px + 0.6, 8.4, .green, w: 0.6, h: 0.6)
            if Int(t * 2.5) % 2 == 0 { cell(&g, px + 1.6, 8.6, .green, w: 1, h: 0.4) }
        case .building:
            // 转动的齿轮 + 进度条
            let center = CGPoint(x: (px + 3.5) * pixel, y: 5.2 * pixel)
            var gear = Path()
            let teeth = 8
            for i in 0..<(teeth * 2) {
                let a = Double(i) / Double(teeth * 2) * 2 * .pi + t * 1.6
                let r = (i % 2 == 0 ? 2.3 : 1.7) * pixel
                let p = CGPoint(x: center.x + cos(a) * r, y: center.y + sin(a) * r)
                if i == 0 { gear.move(to: p) } else { gear.addLine(to: p) }
            }
            gear.closeSubpath()
            g.fill(gear, with: .color(Color(white: 0.6)))
            g.fill(Path(ellipseIn: CGRect(x: center.x - 0.7 * pixel, y: center.y - 0.7 * pixel, width: 1.4 * pixel, height: 1.4 * pixel)), with: .color(Color(white: 0.3)))
            let prog = (t * 0.25).truncatingRemainder(dividingBy: 1)
            cell(&g, px, 9, Color(white: 0.3), w: 6.5, h: 0.7)
            cell(&g, px, 9, .green, w: 6.5 * prog, h: 0.7)
        case .planning:
            // 写字板：清单一条条打勾
            cell(&g, px + 0.5, 3.5, Color(red: 0.6, green: 0.4, blue: 0.22), w: 5.5, h: 6.5)
            cell(&g, px + 1, 4.2, Color(white: 0.96), w: 4.5, h: 5.5)
            cell(&g, px + 2.3, 3.2, Color(white: 0.5), w: 2, h: 0.8)
            let done = Int(t * 1.2) % 5
            for i in 0..<4 {
                let y = 5 + Double(i) * 1.15
                cell(&g, px + 1.4, y, i < done ? .green : Color(white: 0.75), w: 0.7, h: 0.7)
                cell(&g, px + 2.4, y + 0.15, Color(white: 0.55), w: Double(2 + (i * 3) % 2), h: 0.4)
            }
        case .reading:
            // 摊开的书，偶尔翻页
            let flip = Int(t / 2.2) % 2 == 0
            cell(&g, px, 6, Color(white: 0.95), w: 3, h: 3.5)
            cell(&g, px + 3.2, 6, Color(white: 0.9), w: 3, h: 3.5)
            cell(&g, px + 2.9, 6, Color(red: 0.6, green: 0.35, blue: 0.2), w: 0.4, h: 3.8)
            for i in 0..<3 {
                cell(&g, px + 0.5, 6.7 + Double(i), Color(white: 0.6), w: 2, h: 0.35)
                cell(&g, px + 3.7, 6.7 + Double(i), Color(white: 0.6), w: flip ? 2 : 1.4, h: 0.35)
            }
        case .coffee:
            cell(&g, px + 1, 7, Color(white: 0.96), w: 3, h: 3)
            cell(&g, px + 4, 7.6, Color(white: 0.96), w: 0.8, h: 1.5)
            cell(&g, px + 1.4, 7.2, Color(red: 0.45, green: 0.28, blue: 0.16), w: 2.2, h: 0.6)
            for i in 0..<2 {
                let ph = (t * 0.8 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
                g.opacity = 1 - ph
                cell(&g, px + 1.8 + Double(i) + sin(ph * 6) * 0.4, 6 - ph * 3, Color(white: 0.8), w: 0.5, h: 0.8)
                g.opacity = 1
            }
        case .delegating:
            // 迷你小弟跑来跑去：有几个子代理在跑就有几只（最多 5 只）
            let count = max(1, min(5, minions))
            for i in 0..<count {
                let x = px - 1 + (sin(t * (2 + Double(i) * 0.3) + Double(i) * 2.1) + 1) * 3
                let y = 7.4 + Double(i % 3) * 0.8
                let c = accent
                cell(&g, x, y, c, w: 2, h: 1.2)
                cell(&g, x + (Int(t * 8) % 2 == 0 ? 0 : 1.4), y + 1.2, c, w: 0.5, h: 0.5)
                cell(&g, x + 0.4, y + 0.3, .black, w: 0.3, h: 0.3)
                cell(&g, x + 1.3, y + 0.3, .black, w: 0.3, h: 0.3)
            }
        case .photo:
            // 相机 + 闪光后吐出一张照片
            let c = t.truncatingRemainder(dividingBy: 2.2) / 2.2
            cell(&g, px + 0.5, 5, Color(white: 0.2), w: 5, h: 3.4)
            cell(&g, px + 1.2, 4.4, Color(white: 0.3), w: 1.6, h: 0.7)
            g.fill(Path(ellipseIn: CGRect(x: (px + 2) * pixel, y: 5.5 * pixel, width: 2.4 * pixel, height: 2.4 * pixel)), with: .color(Color(white: 0.55)))
            g.fill(Path(ellipseIn: CGRect(x: (px + 2.6) * pixel, y: 6.1 * pixel, width: 1.2 * pixel, height: 1.2 * pixel)), with: .color(Color(red: 0.3, green: 0.5, blue: 0.9)))
            cell(&g, px + 4.4, 5.4, c > 0.6 && c < 0.75 ? .yellow : Color(white: 0.75), w: 0.7, h: 0.6)
            if c > 0.66 {
                let out = min(1, (c - 0.66) / 0.25)
                cell(&g, px + 1, 8.4, Color(white: 0.96), w: 3.6, h: 0.4 + out * 2.2)
                cell(&g, px + 1.4, 8.7, Color(red: 0.95, green: 0.6, blue: 0.4).opacity(out), w: 2.8, h: out * 1.4)
            }
        case .git:
            // 分支树：主干上一个个提交点亮，旁边分出一条支线
            let main = Color(red: 0.95, green: 0.45, blue: 0.25), side = Color(red: 0.35, green: 0.8, blue: 0.45)
            cell(&g, px + 1.6, 3.5, main.opacity(0.6), w: 0.5, h: 6.5)
            cell(&g, px + 2, 6.2, side.opacity(0.6), w: 2.4, h: 0.4)
            cell(&g, px + 4.2, 3.8, side.opacity(0.6), w: 0.5, h: 2.6)
            let lit = Int(t * 1.5) % 6
            for i in 0..<4 {
                let y = 9 - Double(i) * 1.7
                cell(&g, px + 1.2, y, i <= lit ? main : Color(white: 0.4), w: 1.3, h: 1.3)
            }
            for i in 0..<2 { cell(&g, px + 3.8, 4.6 - Double(i) * 1.4 + 1.4, lit > 3 + i ? side : Color(white: 0.4), w: 1.3, h: 1.3) }
        case .network:
            // 转动的地球 + 信号波纹
            let c = CGPoint(x: (px + 3.2) * pixel, y: 6.6 * pixel), r = 2.5 * pixel
            g.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(Color(red: 0.3, green: 0.6, blue: 0.95)))
            for i in 0..<3 {
                let ph = (t * 0.35 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                let w = abs(cos(ph * .pi)) * r
                g.stroke(Path(ellipseIn: CGRect(x: c.x - w, y: c.y - r, width: w * 2, height: r * 2)), with: .color(Color(red: 0.6, green: 0.95, blue: 0.7).opacity(0.8)), lineWidth: pixel * 0.35)
            }
            g.stroke(Path(CGRect(x: c.x - r, y: c.y - 0.15 * pixel, width: r * 2, height: 0.3 * pixel)), with: .color(Color(red: 0.6, green: 0.95, blue: 0.7).opacity(0.8)), lineWidth: pixel * 0.3)
            for i in 0..<2 {
                let ph = (t * 0.9 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
                let rr = r + ph * 2.2 * pixel
                var arc = Path()
                arc.addArc(center: c, radius: rr, startAngle: .degrees(-70), endAngle: .degrees(-20), clockwise: false)
                g.opacity = 1 - ph
                g.stroke(arc, with: .color(.green), lineWidth: pixel * 0.4)
                g.opacity = 1
            }
        case .deploy:
            // 火箭：发射台上点火 → 升空 → 再来一枚
            let c = t.truncatingRemainder(dividingBy: 3.2) / 3.2
            let rise = c < 0.3 ? 0 : pow((c - 0.3) / 0.7, 2) * 12
            let rx = px + 2, ry = 5.2 - rise
            cell(&g, px + 0.6, 9.4, Color(white: 0.45), w: 5, h: 0.6)
            if ry > -4 {
                cell(&g, rx + 0.4, ry - 1, Color(red: 0.95, green: 0.35, blue: 0.3), w: 1.2, h: 1)
                cell(&g, rx, ry, Color(white: 0.95), w: 2, h: 3)
                g.fill(Path(ellipseIn: CGRect(x: (rx + 0.5) * pixel, y: (ry + 0.6) * pixel, width: pixel, height: pixel)), with: .color(Color(red: 0.3, green: 0.6, blue: 0.95)))
                cell(&g, rx - 0.6, ry + 2, Color(red: 0.95, green: 0.35, blue: 0.3), w: 0.6, h: 1)
                cell(&g, rx + 2, ry + 2, Color(red: 0.95, green: 0.35, blue: 0.3), w: 0.6, h: 1)
                let flame = c < 0.3 ? (Int(t * 10) % 2 == 0 ? 0.6 : 0.3) : 1.6 + Double(Int(t * 12) % 2) * 0.5
                cell(&g, rx + 0.4, ry + 3, .orange, w: 1.2, h: flame)
                cell(&g, rx + 0.7, ry + 3, .yellow, w: 0.6, h: flame * 0.7)
            }
            if c > 0.3 && c < 0.6 {
                g.opacity = 1 - (c - 0.3) / 0.3
                for i in 0..<4 { cell(&g, px + Double(i) * 1.5, 8.6 + Double(i % 2) * 0.4, Color(white: 0.8), w: 1.2, h: 1) }
                g.opacity = 1
            }
        case .install:
            // 拆包裹：盖子打开，小方块一个个蹦出来
            let c = t.truncatingRemainder(dividingBy: 2.6) / 2.6
            let box = Color(red: 0.8, green: 0.6, blue: 0.35), dark = Color(red: 0.6, green: 0.42, blue: 0.22)
            cell(&g, px + 0.8, 6.6, box, w: 4.6, h: 3.4)
            cell(&g, px + 2.8, 6.6, dark, w: 0.6, h: 3.4)
            let open = c > 0.25
            cell(&g, px + (open ? -0.2 : 0.6), open ? 5.6 : 6, dark, w: 2.4, h: 0.6)
            cell(&g, px + (open ? 3.8 : 3.2), open ? 5.6 : 6, dark, w: 2.4, h: 0.6)
            if open {
                let colors: [Color] = [Provider.codex.tint, .green, .yellow]
                for i in 0..<3 {
                    let ph = ((c - 0.25) / 0.75 * 1.6 - Double(i) * 0.3)
                    guard ph > 0 && ph < 1 else { continue }
                    cell(&g, px + 1.6 + Double(i) * 1.1, 6 - sin(ph * .pi) * 4, colors[i], w: 1, h: 1)
                }
            }
        case .skate:
            // 滑板跟着身体走
            let deck = Color(red: 0.95, green: 0.35, blue: 0.3)
            cell(&g, bx + 1, by + 10, deck, w: 14, h: 0.7)
            cell(&g, bx + 0.4, by + 9.6, deck, w: 0.8, h: 0.6)
            cell(&g, bx + 14.8, by + 9.6, deck, w: 0.8, h: 0.6)
            for wx in [3.0, 12.0] { cell(&g, bx + wx, by + 10.7, Color(white: 0.2), w: 1.2, h: 0.9) }
        default:
            extraBehind(&g, act, t: t, beat: beat, bx: bx, by: by)
        }
    }

    private func drawPropFront(_ g: inout some PetPainter, _ act: PetAction, t: Double, beat: Double?, bx: Double, by: Double) {
        switch act {
        case .searching:
            // 放大镜在右边来回扫
            let cx = 21.0 + sin(t * 1.4) * 1.5, cy = 6.0
            let ring = Path(ellipseIn: CGRect(x: (cx - 1.6) * pixel, y: (cy - 1.6) * pixel, width: 3.2 * pixel, height: 3.2 * pixel))
            g.fill(ring, with: .color(Color(red: 0.6, green: 0.85, blue: 1).opacity(0.35)))
            g.stroke(ring, with: .color(Color(white: 0.35)), lineWidth: pixel * 0.6)
            var handle = Path()
            handle.move(to: CGPoint(x: (cx - 1.1) * pixel, y: (cy + 1.1) * pixel))
            handle.addLine(to: CGPoint(x: (cx - 2.8) * pixel, y: (cy + 2.8) * pixel))
            g.stroke(handle, with: .color(Color(red: 0.55, green: 0.33, blue: 0.2)), lineWidth: pixel * 0.9)
        case .building:
            // 锤子从右手抡下来，砸中时冒火花
            let hit = (t * 2.2).truncatingRemainder(dividingBy: 1)
            let angle = hit < 0.55 ? -0.9 + hit / 0.55 * 0.4 : -0.5 + min(1, (hit - 0.55) / 0.1) * 1.3
            let pivot = CGPoint(x: (bx + 15.5) * pixel, y: (by + 3.5) * pixel)
            var h = g
            h.translateBy(x: pivot.x, y: pivot.y)
            h.rotate(by: .radians(angle))
            h.fill(Path(CGRect(x: 0, y: -0.35 * pixel, width: 4 * pixel, height: 0.7 * pixel)), with: .color(Color(red: 0.55, green: 0.33, blue: 0.2)))
            h.fill(Path(CGRect(x: 3.4 * pixel, y: -1.1 * pixel, width: 1.6 * pixel, height: 2.2 * pixel)), with: .color(Color(white: 0.45)))
            if hit > 0.6 && hit < 0.85 {
                let p = (hit - 0.6) / 0.25
                for i in 0..<4 {
                    let a = Double(i) * 0.8 - 2.6
                    cell(&g, 20 + cos(a) * (1 + p * 2.5), 8.6 + sin(a) * (1 + p * 2), [Color.yellow, .orange][i % 2], w: 0.5, h: 0.5)
                }
            }
        case .photo:
            let c = t.truncatingRemainder(dividingBy: 2.2) / 2.2
            if c > 0.6 && c < 0.72 {
                let k = 1 - (c - 0.6) / 0.12
                g.opacity = k * 0.85
                g.fill(Path(ellipseIn: CGRect(x: 18 * pixel, y: 1.5 * pixel, width: 8 * pixel, height: 8 * pixel)),
                       with: .radialGradient([.white, .white.opacity(0)], center: CGPoint(x: 22 * pixel, y: 5.5 * pixel), startRadius: 0, endRadius: 4 * pixel))
                g.opacity = 1
            }
        case .asking:
            // 头顶一个跳动的问号：在等你回答
            let bob = sin(t * 4) * 0.4
            g.opacity = Int(t * 2) % 4 == 3 ? 0.55 : 1
            g.text("?", size: pixel * 4.6, weight: .heavy, rounded: true, color: accent, at: CGPoint(x: (bx + 17) * pixel, y: (by - 0.5 + bob) * pixel))
            g.opacity = 1
        case .guitar:
            // 吉他斜挎在身前，音符往上飘
            let gx = bx + 6, gy = by + 5
            let wood = Color(red: 0.86, green: 0.55, blue: 0.24), dark = Color(red: 0.5, green: 0.27, blue: 0.12)
            cell(&g, gx, gy + 1, wood, w: 4, h: 3)
            cell(&g, gx + 0.6, gy + 0.4, wood, w: 2.8, h: 0.8)
            cell(&g, gx + 1.5, gy + 2, dark, w: 1, h: 1)
            for i in 0..<7 { cell(&g, gx + 4 + Double(i), gy + 1.6 - Double(i) * 0.75, dark, w: 1, h: 0.7) }
            cell(&g, gx + 10.5, gy - 4, Color(white: 0.2), w: 1.4, h: 1)
            // 一只手在音孔上扫弦（上下扫），一只手按在琴颈上换把位
            let strum = Int(t * 6) % 2 == 0 ? -0.7 : 0.6
            let fret = 4.5 + Double(Int(t * 0.8) % 3) * 0.9
            drawArms(&g, bx: bx, by: by, left: (gx + 2, gy + 2 + strum), right: (gx + 4 + fret, gy + 1.6 - fret * 0.75 + 0.2))
            for i in 0..<3 {
                let ph = (t * 0.7 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                g.opacity = 1 - ph
                g.text(i % 2 == 0 ? "♪" : "♫", size: pixel * 3.2, weight: .bold, rounded: false, color: i == 1 ? Provider.codex.tint : PetArt.clawd, at: CGPoint(x: (20 + Double(i) * 1.6 + sin(ph * 5) * 0.8) * pixel, y: (6 - ph * 5.5) * pixel))
                g.opacity = 1
            }
        case .juggle:
            // 三个球在头顶画抛物线
            let colors: [Color] = [PetArt.clawd, Provider.codex.tint, .yellow]
            for i in 0..<3 {
                let ph = (t * 1.1 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                let x = bx + 1.5 + ph * 12
                let y = by + 3 - sin(ph * .pi) * 6
                cell(&g, x, y, colors[i], w: 1.2, h: 1.2)
            }
        case .love:
            for i in 0..<3 {
                let ph = (t * 0.9 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                g.opacity = 1 - ph
                pixelHeart(&g, x: bx + 4 + Double(i) * 3.5 + sin(ph * 6) * 0.6, y: by - ph * 4.5, c: Color(red: 1, green: 0.4, blue: 0.55))
                g.opacity = 1
            }
        case .dangle:
            // 被拎着时冒汗
            let ph = t.truncatingRemainder(dividingBy: 0.9) / 0.9
            g.opacity = 1 - ph
            g.fill(Path(ellipseIn: CGRect(x: (bx + 14) * pixel, y: (by + 1 + ph * 3) * pixel, width: pixel, height: pixel * 1.4)),
                   with: .color(Color(red: 0.45, green: 0.75, blue: 1)))
            g.opacity = 1
        case .thinking:
            // 头顶冒思考泡泡
            for (i, r) in [0.6, 0.9, 1.3].enumerated() {
                let on = Int(t * 2.5) % 4 > i
                let c = CGRect(x: (bx + 15 + Double(i) * 1.5 - r) * pixel, y: (by - 0.5 - Double(i) * 1.4 - r) * pixel, width: r * 2 * pixel, height: r * 2 * pixel)
                g.fill(Path(ellipseIn: c), with: .color(Color.secondary.opacity(on ? 0.75 : 0.25)))
            }
        case .sleep:
            for i in 0..<2 {
                let ph = (t * 0.5 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
                g.opacity = 1 - ph
                g.text(i == 0 ? "z" : "Z", size: pixel * (2.4 + Double(i)), weight: .heavy, rounded: true, color: .secondary, at: CGPoint(x: (bx + 15 + ph * 3) * pixel, y: (by - ph * 4) * pixel))
                g.opacity = 1
            }
        case .worried:
            let ph = t.truncatingRemainder(dividingBy: 1.6) / 1.6
            g.opacity = 1 - ph
            g.fill(Path(ellipseIn: CGRect(x: (bx + 13) * pixel, y: (by + ph * 3) * pixel, width: pixel, height: pixel * 1.4)),
                   with: .color(Color(red: 0.45, green: 0.75, blue: 1)))
            g.opacity = 1
        case .celebrate, .dance, .spin:
            // 彩纸 / 迪厅光点
            let colors: [Color] = [PetArt.clawd, Provider.codex.tint, .yellow, .green, .pink]
            let disco = act != .celebrate
            for i in 0..<8 {
                let ph = (t * (disco ? 0.6 : 0.9) + Double(i) / 8).truncatingRemainder(dividingBy: 1)
                let x = Double((i * 37) % 24) + 1 + sin(ph * 6 + Double(i)) * 0.8
                let y = disco ? 1 + Double((i * 13) % 4) : ph * 8
                g.opacity = disco ? (Int(t * 4 + Double(i)) % 2 == 0 ? 0.9 : 0.25) : 1 - ph
                cell(&g, x, y, colors[i % colors.count], w: 0.7, h: 0.7)
                g.opacity = 1
            }
        default:
            extraFront(&g, act, t: t, beat: beat, bx: bx, by: by)
        }
    }
}

/// 能玩的宠物：眼睛跟着鼠标，单击跳一下冒爱心，双击随机表演，鼠标来回蹭就是摸头。
/// 顶栏、工作小队卡片、桌面宠物都用它。
struct InteractivePet: View {
    @Environment(AppModel.self) private var model
    var kind: Provider
    var action: PetAction
    var pixel: CGFloat = 3
    var seed = 0
    var walking = false
    var dragging = false
    var landed: Date? = nil
    /// 不传就只在鼠标停在宠物身上时转眼睛；桌面宠物传全屏鼠标位置
    var gaze: (() -> CGFloat?)? = nil
    var wander: Double = 0
    var talkUntil: Date? = nil
    var alertAt: Date? = nil
    var minions = 2
    var strain: Double = 0
    /// 这只宠物是谁（会话 id）；nil = 主宠物。手动指定的动作只给对应那只演
    var rowID: String? = nil
    var musicStart: Date? = nil
    var songID: String? = nil
    var bpm: Double = 0
    var glasses = false
    var appearedAt: Date? = nil
    var onTap: (() -> Void)? = nil

    @State private var tapped: Date?
    @State private var petted: Date?
    @State private var trick: PetAction?
    @State private var trickUntil: Date?
    @State private var hoverX: CGFloat?
    @State private var lastX: CGFloat?
    @State private var lastDir: CGFloat = 0
    @State private var strokes: [Date] = []

    static let tricks: [PetAction] = [.spin, .juggle, .dance, .wave, .skate]

    var body: some View {
        let hx = hoverX
        let localTrick = trickUntil.map { $0 > Date() } ?? false
        let global = model.petOverride.flatMap { o -> (action: PetAction, until: Date, target: String?)? in
            // 指定给我的，或者没指定且我是主宠物（顶栏那只 / 最显眼的会话）
            o.target == rowID || (o.target == nil && (rowID == nil || rowID == model.focusSession?.id)) ? o : nil
        }
        PetView(kind: kind, action: action, pixel: pixel, walking: walking, tapped: tapped, seed: seed,
                gaze: gaze ?? { hx }, petted: petted,
                trick: localTrick ? trick : global?.action, trickUntil: localTrick ? trickUntil : global?.until,
                cheerUntil: model.cheerUntil, dragging: dragging, landed: landed,
                talkUntil: talkUntil, alertAt: alertAt, minions: minions, strain: strain,
                musicStart: musicStart, songID: songID, bpm: bpm, glasses: glasses, happiness: model.happiness, appearedAt: appearedAt,
                hasDog: model.hasDog, hasCat: model.hasCat, wander: wander)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let p): hovered(p.x)
                case .ended: hoverX = nil; lastX = nil; lastDir = 0
                }
            }
            .onTapGesture {
                tapped = Date()
                model.cheer(1)
                Self.pop(model.petVolume, pitch: "Pop")
                onTap?()
            }
            .simultaneousGesture(TapGesture(count: 2).onEnded {
                trick = Self.tricks.randomElement()
                trickUntil = Date().addingTimeInterval(3.6)
            })
    }

    /// 鼠标在宠物身上左右来回 4 次（1.2 秒内）就算摸头
    private func hovered(_ x: CGFloat) {
        hoverX = x - (11 + wander) * pixel
        defer { lastX = x }
        guard let lx = lastX, abs(x - lx) > 2 else { return }
        let dir: CGFloat = x > lx ? 1 : -1
        let now = Date()
        if lastDir != 0 && dir != lastDir { strokes.append(now) }
        lastDir = dir
        strokes.removeAll { now.timeIntervalSince($0) > 1.2 }
        if strokes.count >= 4, petted.map({ now.timeIntervalSince($0) > 1.6 }) ?? true {
            petted = now
            strokes.removeAll()
            model.cheer(6)
            Self.pop(model.petVolume, pitch: "Purr")
        }
    }

    /// 轻轻的音效，音量跟吉他音量走；系统没有 Purr 就退回 Pop
    static func pop(_ volume: Double, pitch: String) {
        guard volume > 0.01 else { return }
        guard let s = (NSSound(named: NSSound.Name(pitch)) ?? NSSound(named: "Pop"))?.copy() as? NSSound else { return }
        s.volume = Float(volume * 0.35)
        s.play()
    }
}

/// 顶栏里的宠物：没事时左右溜达；点一下跳起来、说一句话
struct WanderingPet: View {
    var kind: Provider
    var action: PetAction
    var line: String
    var onTap: () -> Void
    @State private var bubble: String?
    private static let range = 3.4      // 左右各走 3.4 格（约 10pt）

    var body: some View {
        InteractivePet(kind: kind, action: action, pixel: 3, wander: Self.range, onTap: tapped)
            .overlay(alignment: .topLeading) {
                if let bubble {
                    Text(bubble)
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.regularMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(PetArt.limbColor(kind).opacity(0.35)))
                        .fixedSize()
                        .offset(x: 72, y: 4)
                        .transition(.scale(scale: 0.6, anchor: .leading).combined(with: .opacity))
                }
            }
            .frame(width: (PetView.cols + Self.range * 2) * 3, height: PetView.rows * 3)
            .help(L("点点%@，双击看表演，来回蹭蹭摸摸头", PetArt.name(kind)))
    }

    private func tapped() {
        onTap()
        withAnimation(.spring(duration: 0.35, bounce: 0.4)) { bubble = line }
        let shown = line
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
            if bubble == shown { withAnimation(.easeOut(duration: 0.25)) { bubble = nil } }
        }
    }
}

extension InteractivePet {
    /// 按运行中的会话填好实时联动参数
    init(session s: LiveSession, model: AppModel, pixel: CGFloat, seed: Int, dragging: Bool = false, landed: Date? = nil, gaze: (() -> CGFloat?)? = nil) {
        let said = model.saidAt[s.id]
        self.init(kind: s.provider, action: s.action, pixel: pixel, seed: seed, dragging: dragging, landed: landed, gaze: gaze,
                  talkUntil: said.map { $0.addingTimeInterval(min(6, 1.5 + Double(s.say?.count ?? 0) * 0.05)) },
                  alertAt: model.toolChangedAt[s.id], minions: s.subagents, strain: s.cpu / 100, rowID: s.id)
    }
}

/// 打字机效果：文字变了就从头一个字一个字冒出来
struct TypewriterText: View {
    var text: String
    @State private var shown = 0

    var body: some View {
        Text(String(text.prefix(shown)))
            .task(id: text) {
                let chars = text.count
                // 已经显示过的旧文字直接整句出，新文字才逐字打（每秒约 40 字）
                shown = 0
                for i in stride(from: 0, through: chars, by: 2) {
                    shown = i
                    try? await Task.sleep(for: .milliseconds(45))
                    if Task.isCancelled { return }
                }
                shown = chars
            }
    }
}

/// 宠物动画暂停开关：桌面宠物窗口完全被挡住（全屏 App、锁屏）时设为 true，省电
private struct PetsPausedKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var petsPaused: Bool {
        get { self[PetsPausedKey.self] }
        set { self[PetsPausedKey.self] = newValue }
    }
}
