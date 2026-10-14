import SwiftUI

/// 乐队乐器、心情表情、互动小剧场（鞭子 / 零食 / 狗 / 猫）的画法。
/// 从 PetView 拆出来，免得一个文件太长；坐标系和 PetView 一样：画布 26×16 格，身体左上角在 (bx, by)。
private enum Mood { case happy, sad, angry, plain }

extension PetView {

    // MARK: 姿势

    /// 新动作的身体姿势。乐器动作跟着拍子（beat）走；没在放歌时按 120 拍/分钟自己打拍子
    func extraPose(_ act: PetAction, t: Double, beat: Double?, pose: inout PetArt.Pose, lift: inout Double, dx: inout Double) {
        let b = beat ?? t * 2
        let onBeat = b.truncatingRemainder(dividingBy: 1) < 0.18
        switch act {
        case .piano:
            pose.armsHidden = true
            pose.lookOffset = 1
            lift = onBeat ? 0.5 : 0
        case .bass:
            pose.armsHidden = true
            lift = onBeat ? 0.6 : 0
            pose.eyesClosed = Int(b / 4) % 3 == 2
        case .drums:
            pose.armsHidden = true
            lift = onBeat ? 0.8 : 0
        case .flute:
            pose.armsHidden = true
            dx = sin(b * .pi / 2) * 0.4
            pose.eyesClosed = Int(b / 2) % 3 == 1
        case .violin:
            pose.armsHidden = true
            dx = sin(b * .pi / 4) * 0.5
            pose.eyesClosed = Int(b / 2) % 2 == 1
        case .erhu:
            // 阿炳：闭着眼、跟着长弓慢慢摇
            pose.armsHidden = true
            dx = sin(b * .pi / 4) * 0.5
            pose.eyesClosed = true
        case .musicbox:
            pose.armsHidden = true
            pose.lookOffset = 1
        case .whipped:
            let c = t.truncatingRemainder(dividingBy: 1.6) / 1.6
            if c > 0.36 && c < 0.6 {
                lift = sin((c - 0.36) / 0.24 * .pi) * 2.5
                pose.armsUp = true
                pose.eyesClosed = true
            } else if c >= 0.6 {
                dx = sin(t * 30) * 0.3
                pose.lookOffset = 1
            } else {
                pose.lookOffset = 1
            }
        case .eat:
            // t 是这次吃东西开始后的秒数（PetView.eatClock），见 drawEating
            pose.armsHidden = true
            let e = Self.eatPhase(t)
            pose.eyesClosed = e.chewing || e.done
            lift = e.chewing ? abs(sin(t * 18)) * 0.35 : 0
        case .laugh:
            dx = sin(t * 25) * 0.3
            lift = abs(sin(t * 10)) * 0.6
            pose.eyesClosed = true
            pose.armWave = Int(t * 6) % 2 + 1
        case .sulk:
            pose.lookOffset = -1
        case .angry:
            pose.legPhase = Int(t * 6) % 2 + 1
            pose.armsUp = Int(t * 3) % 2 == 0
            dx = sin(t * 28) * 0.25
        case .walkDog:
            pose.legPhase = Int(t * 6) % 2 + 1
            pose.armWave = 2
            pose.lookOffset = 1
            lift = Int(t * 6) % 2 == 0 ? 0.3 : 0
        case .fetch:
            let c = t.truncatingRemainder(dividingBy: 3.2) / 3.2
            if c < 0.12 { pose.armWave = 2 }
            else if c < 0.2 { pose.armsUp = true }
            else if c > 0.85 { pose.armsUp = true; lift = abs(sin(c * 40)) * 1 }
            pose.lookOffset = 1
        case .catNap:
            let c = t.truncatingRemainder(dividingBy: 6.5) / 6.5
            if c < 0.45 {
                pose.lookOffset = Int(t * 1.2) % 2 == 0 ? -1 : 1
            } else {
                pose.eyesClosed = true
                lift = sin(t * 1.2) > 0 ? 0.3 : 0
            }
        default: break
        }
    }

    // MARK: 身后的道具

    func extraBehind(_ g: inout some PetPainter, _ act: PetAction, t: Double, beat: Double?, bx: Double, by: Double) {
        let b = beat ?? t * 2
        switch act {
        case .drums:
            // 鼓组在右边：底鼓 + 军鼓 + 镲，镲在每小节第一拍闪一下
            let shell = Color(red: 0.85, green: 0.22, blue: 0.3), head = Color(white: 0.94)
            let kickHit = b.truncatingRemainder(dividingBy: 1) < 0.15
            cell(&g, 19, 9.5 + (kickHit ? 0.2 : 0), shell, w: 6, h: 5)
            cell(&g, 20, 10.5 + (kickHit ? 0.2 : 0), head, w: 4, h: 3)
            cell(&g, 21.4, 11.5, accent.opacity(0.8), w: 1.2, h: 1)
            cell(&g, 15.5, by + 7, shell, w: 4, h: 1.6)
            cell(&g, 15.5, by + 6.6, head, w: 4, h: 0.5)
            let crash = b.truncatingRemainder(dividingBy: 4) < 0.25
            cell(&g, 21, 6.5 - (crash ? 0.3 : 0), Color(red: 0.95, green: 0.78, blue: 0.3), w: 4.5, h: 0.6)
            cell(&g, 23, 7, Color(white: 0.45), w: 0.4, h: 2.5)
            if crash {
                g.opacity = 0.7
                for (x, y) in [(20.2, 5.4), (25.6, 5.4), (23, 4.6)] { cell(&g, x, y, .yellow, w: 0.5, h: 0.5) }
                g.opacity = 1
            }
        case .sulk:
            // 头顶一朵小乌云在下雨
            let cloud = Color(white: 0.55)
            cell(&g, bx + 4, by - 4.5, cloud, w: 8, h: 1.6)
            cell(&g, bx + 5.5, by - 5.4, cloud, w: 4.5, h: 1)
            for i in 0..<4 {
                let ph = (t * 1.6 + Double(i) * 0.27).truncatingRemainder(dividingBy: 1)
                g.opacity = 1 - ph * 0.6
                cell(&g, bx + 4.8 + Double(i) * 1.9, by - 2.8 + ph * 2.6, Color(red: 0.45, green: 0.7, blue: 1), w: 0.4, h: 0.8)
                g.opacity = 1
            }
        default: break
        }
    }

    // MARK: 吃饼干

    static let eatLength = 6.0
    private static let bites = 4, biteStart = 0.3, biteCycle = 1.25

    /// 吃饼干演到哪了：第几口（已经咬掉几口）、这一口进行到 0…1 的哪里、是不是在嚼、是不是吃完了
    static func eatPhase(_ t: Double) -> (eaten: Int, c: Double, chewing: Bool, done: Bool) {
        let x = (t - biteStart) / biteCycle
        if x < 0 { return (0, 0, false, false) }
        let n = Int(x)
        if n >= bites { return (bites, 1, false, true) }
        let c = x - Double(n)
        return (c >= 0.45 ? n + 1 : n, c, c > 0.5, false)
    }

    /// 嘴在哪（身体格子坐标）
    private var mouthSpot: (Double, Double) {
        switch kind {
        case .claude: (8, 4.9); case .codex: (8.5, 5.2); case .grok: (8, 4.5); case .gemini: (8, 5.6)
        }
    }

    /// 每一口：拿饼干送到嘴边 → 张大嘴 → 咬（饼干缺一块、掉渣）→ 放低一点闭眼嚼；四口吃完舔舔嘴、摸摸肚子
    func drawEating(_ g: inout some PetPainter, t: Double, bx: Double, by: Double) {
        let e = Self.eatPhase(t)
        let ink = kind == .codex || kind == .grok ? Color.white : Color(red: 0.25, green: 0.1, blue: 0.08)
        let (mx, my) = (bx + mouthSpot.0, by + mouthSpot.1)
        // 这些是饼干中心的位置：到嘴边时饼干左缘盖住嘴，像真的咬上去
        let rest = (bx + 13.2, by + 6.4), atMouth = (mx + 0.9, my - 0.1), chew = (bx + 12, by + 5.6)
        func lerp(_ a: (Double, Double), _ b: (Double, Double), _ k: Double) -> (Double, Double) {
            let s = k * k * (3 - 2 * k)
            return (a.0 + (b.0 - a.0) * s, a.1 + (b.1 - a.1) * s)
        }
        // 饼干的位置；手在饼干右下角托着
        let center: (Double, Double)
        if t < Self.biteStart { center = lerp(rest, chew, t / Self.biteStart) }
        else if e.c < 0.35 { center = lerp(chew, atMouth, e.c / 0.35) }
        else if e.c < 0.5 { center = atMouth }
        else { center = lerp(atMouth, chew, min(1, (e.c - 0.5) / 0.2)) }
        let hand = e.done ? (bx + 9, by + 6.9) : (center.0 + 1.5, center.1 + 1)      // 吃完摸肚子
        drawArms(&g, bx: bx, by: by, left: (bx + 0.2, by + 6.4), right: hand)

        // 嘴：送到嘴边时张大，咬下去合上，嚼的时候一张一合，鼓腮帮子
        if !e.done {
            if e.c >= 0.25 && e.c < 0.45 {
                cell(&g, mx - 1.1, my - 0.4, ink, w: 2.2, h: 1.5)
                cell(&g, mx - 0.6, my + 0.6, Color(red: 0.95, green: 0.45, blue: 0.5), w: 1.2, h: 0.4)
            } else if e.chewing {
                let open = sin(t * 18) > 0
                cell(&g, mx - 0.8, my, ink, w: 1.6, h: open ? 0.8 : 0.4)
                let cheek = Color(red: 1, green: 0.5, blue: 0.55).opacity(0.7)
                cell(&g, bx + 2.4, by + 4.2, cheek, w: 1.4, h: 0.9)
                cell(&g, bx + 12.2, by + 4.2, cheek, w: 1.4, h: 0.9)
            }
        } else {
            // 吃完：笑着舔一下嘴，冒一颗小星星
            cell(&g, mx - 1.2, my, ink, w: 0.5, h: 0.5)
            cell(&g, mx - 0.7, my + 0.5, ink, w: 1.4, h: 0.5)
            cell(&g, mx + 0.7, my, ink, w: 0.5, h: 0.5)
            if sin(t * 6) > 0 { cell(&g, mx + 0.2, my + 1, Color(red: 0.95, green: 0.45, blue: 0.5), w: 0.7, h: 0.6) }
            let ph = ((t - Self.biteStart - Double(Self.bites) * Self.biteCycle) * 0.9).truncatingRemainder(dividingBy: 1)
            g.opacity = 1 - ph
            g.text("✦", size: pixel * 2.2, weight: .bold, rounded: false, color: .yellow, at: CGPoint(x: (bx + 15) * pixel, y: (by - 0.5 - ph * 2) * pixel))
            g.opacity = 1
        }

        // 饼干：半格一个点画圆，每咬一口从靠嘴那边挖掉一个圆缺口
        if !e.done {
            let cookie = Color(red: 0.86, green: 0.6, blue: 0.3), edge = Color(red: 0.72, green: 0.45, blue: 0.2)
            let chip = Color(red: 0.35, green: 0.2, blue: 0.1)
            let r = 1.8, (cx, cy) = center
            let bitesAt: [(Double, Double)] = [(-1.7, -0.4), (-1.3, 0.9), (-0.1, -1.3), (0.4, 0.5)]
            var y = -r
            while y < r {
                var x = -r
                while x < r {
                    let d = sqrt((x + 0.25) * (x + 0.25) + (y + 0.25) * (y + 0.25))
                    let bitten = bitesAt.prefix(e.eaten).contains { b in hypot(x + 0.25 - b.0, y + 0.25 - b.1) < 1.15 }
                    if d < r && !bitten {
                        let isChip = (abs(x - 0.5) < 0.1 && abs(y + 0.5) < 0.1) || (abs(x + 0.5) < 0.1 && abs(y - 0.5) < 0.1) || (abs(x - 1) < 0.1 && abs(y - 1) < 0.1)
                        cell(&g, cx + x, cy + y, isChip ? chip : (d > r - 0.55 ? edge : cookie), w: 0.5, h: 0.5)
                    }
                    x += 0.5
                }
                y += 0.5
            }
            // 咬下去那一刻掉渣，往下落
            if e.eaten > 0 && e.c >= 0.45 && e.c < 0.95 {
                let p = (e.c - 0.45) / 0.5
                g.opacity = 1 - p * 0.7
                for i in 0..<4 {
                    let sx = mx + 0.5 + Double(i) * 0.7 + sin(Double(i) * 2.1) * 0.4
                    cell(&g, sx + p * Double(i - 1) * 0.6, my + 1 + p * (3 + Double(i) * 0.6), cookie, w: 0.45, h: 0.45)
                }
                g.opacity = 1
            }
        }
    }

    // MARK: 演奏时的手臂

    /// 正在主奏的这一拍：谱子里的音和弓的位置（没在放歌 / 不是主奏时为 nil）
    func melodyNow(_ beat: Double?) -> (midi: Double?, bow: Double)? {
        guard let beat, let id = songID else { return nil }
        return MelodyTrack.of(id)?.at(beat)
    }

    /// midi → 从 C 开始数的白键序号（升号音算到下面那个白键）
    static func diatonic(_ midi: Double) -> Double {
        let m = Int(midi.rounded())
        let map = [0, 0, 1, 1, 2, 3, 3, 4, 4, 5, 5, 6]
        return Double((m / 12) * 7 + map[((m % 12) + 12) % 12])
    }

    /// 两边肩膀在哪（身体格子坐标 + 身体左上角）
    private func shoulders(bx: Double, by: Double) -> (l: (Double, Double), r: (Double, Double)) {
        switch kind {
        case .claude: return ((bx + 1, by + 4.5), (bx + 14.5, by + 4.5))
        case .codex: return ((bx + 0.3, by + 5), (bx + 15.4, by + 5))
        case .grok: return ((bx + 1.5, by + 3.8), (bx + 14, by + 3.8))
        case .gemini: return ((bx + 1, by + 4.5), (bx + 14.5, by + 4.5))
        }
    }

    /// 从两边肩膀各画一条手臂到手的位置，手画成一个小方块。手臂比身体深一点，横过身体时也看得清
    func drawArms(_ g: inout some PetPainter, bx: Double, by: Double, left: (Double, Double), right: (Double, Double)) {
        let (arm, hand): (Color, Color) = switch kind {
        case .claude: (Color(red: 0.68, green: 0.33, blue: 0.23), Color(red: 0.8, green: 0.42, blue: 0.3))
        case .codex: (Color(red: 0.3, green: 0.38, blue: 0.9), Color(red: 0.42, green: 0.5, blue: 1))
        case .grok: (Color(white: 0.42), Color(white: 0.55))
        case .gemini: (Color(red: 0.46, green: 0.36, blue: 0.8), Color(red: 0.58, green: 0.46, blue: 0.9))
        }
        let sh = shoulders(bx: bx, by: by)
        for (from, to) in [(sh.l, left), (sh.r, right)] {
            let dx = to.0 - from.0, dy = to.1 - from.1
            let n = max(1, Int((sqrt(dx * dx + dy * dy) / 0.55).rounded(.up)))
            for i in 0...n {
                let k = Double(i) / Double(n)
                cell(&g, from.0 + dx * k - 0.45, from.1 + dy * k - 0.45, arm, w: 0.9, h: 0.9)
            }
            cell(&g, to.0 - 0.7, to.1 - 0.7, hand, w: 1.4, h: 1.4)
        }
    }

    /// 细棍（鼓棒、摇把）
    func stickLine(_ g: inout some PetPainter, from: (Double, Double), to: (Double, Double), color: Color) {
        let dx = to.0 - from.0, dy = to.1 - from.1
        let n = max(1, Int((sqrt(dx * dx + dy * dy) / 0.4).rounded(.up)))
        for i in 0...n {
            let k = Double(i) / Double(n)
            cell(&g, from.0 + dx * k - 0.25, from.1 + dy * k - 0.25, color, w: 0.5, h: 0.5)
        }
    }

    // MARK: 身前的道具

    func extraFront(_ g: inout some PetPainter, _ act: PetAction, t: Double, beat: Double?, bx: Double, by: Double) {
        let b = beat ?? t * 2
        switch act {
        case .piano:
            // 小电子琴架在身前；右手弹旋律、左手弹低音，按下去的键会亮
            let frame = Color(white: 0.16)
            cell(&g, bx - 0.5, by + 6.2, frame, w: 17, h: 2.4)
            for i in 0..<14 { cell(&g, bx + 0.1 + Double(i) * 1.15, by + 6.6, .white, w: 0.95, h: 1.7) }
            for i in [0, 1, 3, 4, 5, 7, 8, 10, 11, 12] { cell(&g, bx + 0.85 + Double(i) * 1.15, by + 6.6, frame, w: 0.6, h: 1) }
            // 有谱子就按音高找白键（右半边 7–13），没有就随拍子换
            let right = melodyNow(beat).flatMap { $0.midi }.map { 7 + Int(Self.diatonic($0)) % 7 } ?? 7 + (Int(b * 2) * 3) % 7
            let left = [0, 4, 2, 4][Int(b) % 4]
            let downR = (b * 2).truncatingRemainder(dividingBy: 1) < 0.5, downL = b.truncatingRemainder(dividingBy: 1) < 0.4
            for (k, down) in [(right, downR), (left, downL)] where down { cell(&g, bx + 0.1 + Double(k) * 1.15, by + 7.4, accent, w: 0.95, h: 0.9) }
            cell(&g, bx + 1, by + 8.6, frame, w: 0.6, h: 1.4)
            cell(&g, bx + 14.4, by + 8.6, frame, w: 0.6, h: 1.4)
            drawArms(&g, bx: bx, by: by, left: (bx + 0.6 + Double(left) * 1.15, by + (downL ? 6.9 : 6.2)),
                     right: (bx + 0.6 + Double(right) * 1.15, by + (downR ? 6.9 : 6.2)))
            drawNotes(&g, t: t, x: 20, y: 6, colors: [accent, .yellow])
        case .bass:
            // 贝斯：比吉他长，红色琴身；一只手拨弦、一只手按琴颈
            let gx = bx + 5, gy = by + 5
            let red = Color(red: 0.82, green: 0.2, blue: 0.24), dark = Color(white: 0.15)
            cell(&g, gx, gy + 1, red, w: 4.5, h: 3)
            cell(&g, gx + 0.4, gy + 0.3, red, w: 2.6, h: 0.9)
            cell(&g, gx + 1.2, gy + 2, dark, w: 1.6, h: 0.6)
            for i in 0..<9 { cell(&g, gx + 4.5 + Double(i), gy + 1.6 - Double(i) * 0.72, dark, w: 1, h: 0.6) }
            cell(&g, gx + 13.2, gy - 5.2, dark, w: 1.4, h: 1)
            let pluck = b.truncatingRemainder(dividingBy: 1) < 0.3 ? 0.6 : -0.2
            let fret = 5.0 + Double(Int(b / 2) % 3)
            drawArms(&g, bx: bx, by: by, left: (gx + 2, gy + 2 + pluck), right: (gx + 4.5 + fret, gy + 1.8 - fret * 0.72))
            drawNotes(&g, t: t * 0.7, x: 20, y: 6, colors: [red, accent])
        case .drums:
            // 两手各握一根鼓棒：右手敲军鼓、左手敲左边的通鼓，轮流落下
            let stick = Color(red: 0.9, green: 0.75, blue: 0.5)
            let shell = Color(red: 0.85, green: 0.22, blue: 0.3), head = Color(white: 0.94)
            cell(&g, bx - 2.6, by + 6.8, shell, w: 3.2, h: 1.8)
            cell(&g, bx - 2.6, by + 6.5, head, w: 3.2, h: 0.5)
            cell(&g, bx - 1.4, by + 8.6, Color(white: 0.45), w: 0.4, h: 1.4)
            let rightDown = Int(b * 2) % 2 == 0
            let rh: (Double, Double) = rightDown ? (bx + 15.4, by + 5.4) : (bx + 15.8, by + 3.6)
            let lh: (Double, Double) = !rightDown ? (bx + 0.2, by + 5.4) : (bx - 0.2, by + 3.6)
            // 鼓棒从手里伸到鼓面（落下时）或斜着举起来
            stickLine(&g, from: rh, to: rightDown ? (bx + 14, by + 6.7) : (bx + 17.5, by + 1.8), color: stick)
            stickLine(&g, from: lh, to: !rightDown ? (bx - 1.2, by + 6.5) : (bx - 1.8, by + 1.8), color: stick)
            drawArms(&g, bx: bx, by: by, left: lh, right: rh)
        case .flute:
            // 长笛横在嘴边往右伸出去，两只手按在笛身上，手指轮流抬起
            let silver = Color(white: 0.85)
            let y = by + 4.6
            cell(&g, bx + 6, y, silver, w: 15, h: 0.7)
            for i in 0..<5 { cell(&g, bx + 12 + Double(i) * 1.6, y + 0.1, Color(white: 0.45), w: 0.5, h: 0.4) }
            let lift1 = Int(b * 2) % 2 == 0 ? -0.35 : 0, lift2 = Int(b * 2 + 1) % 2 == 0 ? -0.35 : 0
            drawArms(&g, bx: bx, by: by, left: (bx + 11.2, y + 0.5 + lift1), right: (bx + 16.6, y + 0.5 + lift2))
            drawNotes(&g, t: t * 0.8, x: 21, y: 3, colors: [Color(red: 0.6, green: 0.85, blue: 1), accent])
        case .violin:
            // 小提琴夹在右肩：右边的手按琴颈（按音高前后挪），左边的手握弓根，弓按换弓来回拉
            let wood = Color(red: 0.7, green: 0.32, blue: 0.12), dark = Color(red: 0.35, green: 0.15, blue: 0.06)
            cell(&g, bx + 12.5, by + 2.8, wood, w: 3.6, h: 3)
            cell(&g, bx + 13, by + 2.3, wood, w: 2.6, h: 0.6)
            cell(&g, bx + 13.8, by + 3.6, dark, w: 0.4, h: 1.4)
            for i in 0..<4 { cell(&g, bx + 16 + Double(i), by + 2.6 - Double(i) * 0.6, dark, w: 1, h: 0.5) }
            let mel = melodyNow(beat)
            let ph = mel?.bow ?? abs(sin(b * .pi / 2))
            let bowX = bx + 7.5 + ph * 4
            for i in 0..<10 { cell(&g, bowX + Double(i), by + 6.4 - Double(i) * 0.55, Color(white: 0.92), w: 1, h: 0.3) }
            cell(&g, bowX - 0.3, by + 6.2, dark, w: 0.9, h: 0.7)
            let pos = mel.flatMap { $0.midi }.map { min(3, max(0, ($0 - 67) / 6)) } ?? 1.5
            drawArms(&g, bx: bx, by: by, left: (bowX + 0.2, by + 6.5), right: (bx + 19.2 - pos, by + 1.1 + pos * 0.6))
            drawNotes(&g, t: t * 0.6, x: 21, y: 5, colors: [wood, accent])
        case .erhu:
            // 二胡：琴筒夹在腿边、琴杆竖着；左边的手握弓杆左右拉（按换弓来回），
            // 右边的手按在琴弦上，音越高手越往下（离琴筒越近），长音带揉弦的小抖动
            let wood = Color(red: 0.45, green: 0.2, blue: 0.1), snake = Color(white: 0.2)
            let px = bx + 15.5
            cell(&g, px, by - 3, wood, w: 0.6, h: 12)
            cell(&g, px - 0.6, by - 2.4, wood, w: 1.8, h: 0.4)
            cell(&g, px - 0.6, by - 1.2, wood, w: 1.8, h: 0.4)
            cell(&g, px - 1.2, by + 7, wood, w: 3, h: 2.2)
            cell(&g, px - 1, by + 7.3, snake, w: 2.6, h: 1.6)
            cell(&g, px + 0.4, by - 2.6, Color(white: 0.8).opacity(0.7), w: 0.15, h: 9.6)
            cell(&g, px - 0.4, by - 0.4, Color(white: 0.85), w: 1.4, h: 0.3)        // 千斤
            let mel = melodyNow(beat)
            let ph = mel?.bow ?? (sin(b * .pi / 4) + 1) / 2
            let bowL = bx + 4.5 + ph * 6
            cell(&g, bowL, by + 6.6, Color(red: 0.6, green: 0.35, blue: 0.15), w: 12, h: 0.35)
            cell(&g, bowL, by + 7, Color(white: 0.9), w: 12, h: 0.25)
            // 按弦位置：弦长按 2^(-半音/12) 缩短，千斤到琴筒之间约 7.4 格
            let semis = mel.flatMap { $0.midi }.map { max(0, $0 - 55) } ?? 4 + 3 * sin(b * .pi / 8)
            let vib = sin(t * 2 * .pi * 2.5) * 0.18
            let fy = by - 0.2 + 7.4 * (1 - pow(2, -semis / 12)) + vib
            drawArms(&g, bx: bx, by: by, left: (bowL + 1, by + 6.8), right: (px - 0.4, fy))
            drawNotes(&g, t: t * 0.45, x: 20, y: 4, colors: [Color(red: 0.55, green: 0.7, blue: 0.95), Color(white: 0.75)])
        case .musicbox:
            // 八音盒：木盒子 + 转动的摇把，手握着摇把一起转
            let wood = Color(red: 0.82, green: 0.6, blue: 0.36), lid = Color(red: 0.62, green: 0.38, blue: 0.2)
            cell(&g, 18.5, 11, wood, w: 5.5, h: 3.5)
            cell(&g, 18.3, 10.4, lid, w: 5.9, h: 0.8)
            cell(&g, 20, 12.2, Color(red: 1, green: 0.85, blue: 0.4), w: 2.4, h: 0.6)
            let a = t * 6
            let knob = (24 + cos(a) * 0.9, 12.4 + sin(a) * 0.9)
            cell(&g, 24, 12.6, Color(white: 0.5), w: 0.4, h: 0.4)
            stickLine(&g, from: (24.2, 12.8), to: knob, color: Color(white: 0.6))
            drawArms(&g, bx: bx, by: by, left: (bx + 3, by + 7.2), right: knob)
            drawNotes(&g, t: t * 0.5, x: 20, y: 6, colors: [.yellow, accent])
        case .whipped:
            drawWhip(&g, t: t, bx: bx, by: by)
        case .eat:
            drawEating(&g, t: t, bx: bx, by: by)
        case .laugh:
            let ph = (t * 0.8).truncatingRemainder(dividingBy: 1)
            g.opacity = 1 - ph
            g.text(L("哈哈"), size: pixel * 2.8, weight: .heavy, rounded: true, color: accent, at: CGPoint(x: (21.5 + sin(ph * 6) * 0.5) * pixel, y: (4 - ph * 3) * pixel))
            g.opacity = 1
        case .angry:
            // 头顶冒烟 + 「怒」字符号
            for i in 0..<3 {
                let ph = (t * 1.3 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                g.opacity = (1 - ph) * 0.8
                let s = 0.8 + ph * 1.2
                g.fill(Path(ellipseIn: CGRect(x: (bx + 3 + Double(i) * 4.5 + sin(ph * 4) * 0.6) * pixel, y: (by - 0.8 - ph * 3.5) * pixel, width: s * pixel, height: s * pixel)),
                       with: .color(Color(white: 0.72)))
                g.opacity = 1
            }
            let red = Color(red: 0.95, green: 0.2, blue: 0.2)
            let x = bx + 16, y = by - 1.5
            cell(&g, x, y, red, w: 0.6, h: 1.4); cell(&g, x + 1.6, y, red, w: 0.6, h: 1.4)
            cell(&g, x - 0.4, y + 0.4, red, w: 1.4, h: 0.6); cell(&g, x + 1.2, y + 0.4, red, w: 1.4, h: 0.6)
        case .walkDog:
            // 牵着狗在原地散步：狗在右边走，牵绳从手连到项圈
            let step = Int(t * 6) % 2
            let dogX = 18.5 + sin(t * 0.8) * 0.6
            drawDog(&g, x: dogX, y: 10.5, step: step, wag: Int(t * 8) % 2 == 0, facingLeft: false)
            leash(&g, from: CGPoint(x: bx + 15.5, y: by + 3.6), to: CGPoint(x: dogX + 6.5, y: 11.6))
        case .fetch:
            // 扔球 → 狗追出去 → 叼回来 → 小克跳起来
            let c = t.truncatingRemainder(dividingBy: 3.2) / 3.2
            let ball = Color(red: 0.95, green: 0.85, blue: 0.2)
            var dogX = 17.5
            var facingLeft = false
            if c >= 0.15 && c < 0.45 {
                let p = (c - 0.15) / 0.3
                cell(&g, bx + 15 + p * 10, by + 2 - sin(p * .pi) * 4 + p * 7, ball, w: 1, h: 1)
                dogX = 17.5 + p * 6
            } else if c >= 0.45 && c < 0.85 {
                let p = (c - 0.45) / 0.4
                dogX = 23.5 - p * 6
                facingLeft = true
            }
            let step = (c > 0.15 && c < 0.85) ? Int(t * 10) % 2 : 0
            drawDog(&g, x: dogX, y: 10.5, step: step, wag: Int(t * 8) % 2 == 0, facingLeft: facingLeft)
            if c >= 0.45 { cell(&g, facingLeft ? dogX - 0.6 : dogX + 8.4, 12, ball, w: 1, h: 1) }
            if c < 0.15 { cell(&g, bx + 15.5, by + 3, ball, w: 1, h: 1) }
        case .catNap:
            let c = t.truncatingRemainder(dividingBy: 6.5) / 6.5
            if c < 0.45 {
                // 猫蹲在小克头顶甩尾巴
                drawCatSitting(&g, x: bx + 5, y: by - 3.6, tailUp: Int(t * 2) % 2 == 0)
            } else {
                // 猫蜷在旁边一起睡，冒 Zz
                drawCatCurled(&g, x: 19, y: 12.2, breathe: sin(t * 1.2) > 0)
                for i in 0..<2 {
                    let ph = (t * 0.5 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
                    g.opacity = 1 - ph
                    g.text("z", size: pixel * (2 + Double(i) * 0.6), weight: .bold, rounded: true, color: .secondary, at: CGPoint(x: (22 + ph * 2 + Double(i)) * pixel, y: (10 - ph * 4) * pixel))
                    g.opacity = 1
                }
            }
        default: break
        }
    }

    // MARK: 表情

    /// 心情表情：开心时笑，难过时眉毛下垂偶尔掉眼泪，生气时眉毛竖起来
    func drawFace(_ g: inout some PetPainter, _ act: PetAction, t: Double, eyesClosed: Bool, look: Int, bx: Double, by: Double) {
        let happyActs: [PetAction] = [.laugh, .celebrate, .dance, .love, .fetch, .walkDog, .wave, .skate]
        let mood: Mood
        if act == .angry || act == .whipped { mood = .angry }
        else if act == .sulk { mood = .sad }
        else if happyActs.contains(act) { mood = .happy }
        else if [.idle, .juggle, .stretch].contains(act) {
            mood = happiness < 18 ? .angry : (happiness < 35 ? .sad : (happiness > 75 ? .happy : .plain))
        } else { mood = .plain }
        guard mood != .plain else { return }

        let lo = Double(look)
        let (eyes, ey, mx, my, ink): ([Double], Double, Double, Double, Color) = {
            switch kind {
            case .claude: return ([4, 11], 2, 8, 4.4, Color(red: 0.12, green: 0.10, blue: 0.09))
            case .codex: return ([4.5, 8], 3, 8, 5, .white)
            case .grok: return ([5, 10], 2, 8, 4.2, .white)
            case .gemini: return ([6, 9], 3, 8, 5.4, Color(red: 0.1, green: 0.08, blue: 0.27))
            }
        }()
        let x0 = bx + eyes[0] + lo, x1 = bx + eyes[1] + lo, y = by + ey
        let s = 0.5
        switch mood {
        case .happy:
            // 小 Co 的「_」本身就是嘴，开心时翘成笑
            if kind == .codex {
                cell(&g, bx + 6.5 + lo, by + my - 0.5, ink, w: s, h: s)
                cell(&g, bx + 10 + lo, by + my - 0.5, ink, w: s, h: s)
            } else {
                cell(&g, bx + mx - 1.4 + lo, by + my, ink, w: s, h: s)
                cell(&g, bx + mx - 0.9 + lo, by + my + s, ink, w: 1.8, h: s)
                cell(&g, bx + mx + 0.9 + lo, by + my, ink, w: s, h: s)
            }
        case .sad:
            // 眉毛内高外低
            cell(&g, x0 - 0.5, y - 0.7, ink, w: 0.8, h: s); cell(&g, x0 + 0.3, y - 1.1, ink, w: 0.8, h: s)
            cell(&g, x1 + 0.7, y - 0.7, ink, w: 0.8, h: s); cell(&g, x1 - 0.1, y - 1.1, ink, w: 0.8, h: s)
            if kind != .codex {
                cell(&g, bx + mx - 0.9 + lo, by + my, ink, w: 1.8, h: s)
                cell(&g, bx + mx - 1.4 + lo, by + my + s, ink, w: s, h: s)
                cell(&g, bx + mx + 0.9 + lo, by + my + s, ink, w: s, h: s)
            }
            // 每 2.5 秒滑下一滴眼泪
            let ph = t.truncatingRemainder(dividingBy: 2.5) / 2.5
            if ph < 0.6 {
                g.opacity = 1 - ph / 0.6
                g.fill(Path(ellipseIn: CGRect(x: (x0 + 0.1) * pixel, y: (y + 1.6 + ph * 3) * pixel, width: pixel * 0.7, height: pixel * 1)),
                       with: .color(Color(red: 0.45, green: 0.75, blue: 1)))
                g.opacity = 1
            }
        case .angry:
            // 眉毛外高内低，竖起来
            cell(&g, x0 - 0.6, y - 1.3, ink, w: 0.8, h: s); cell(&g, x0 + 0.2, y - 0.9, ink, w: 0.8, h: s)
            cell(&g, x1 + 0.8, y - 1.3, ink, w: 0.8, h: s); cell(&g, x1, y - 0.9, ink, w: 0.8, h: s)
            if kind != .codex { cell(&g, bx + mx - 0.9 + lo, by + my + 0.2, ink, w: 1.8, h: s) }
        case .plain: break
        }
    }

    /// 阿炳的圆墨镜
    func drawGlasses(_ g: inout some PetPainter, look: Int, bx: Double, by: Double) {
        let (eyes, ey): ([Double], Double) = {
            switch kind {
            case .claude: return ([4, 11], 2)
            case .codex: return ([4.5, 8.5], 3)
            case .grok: return ([5, 10], 2)
            case .gemini: return ([6, 9], 3)
            }
        }()
        let lens = Color(white: 0.06), rim = Color(white: 0.35)
        let r = kind == .gemini ? 1.9 : 2.4
        for ex in eyes {
            let x = bx + ex + 0.5 - r / 2, y = by + ey + 1 - r / 2
            let rect = CGRect(x: x * pixel, y: y * pixel, width: r * pixel, height: r * pixel)
            g.fill(Path(ellipseIn: rect.insetBy(dx: -0.6, dy: -0.6)), with: .color(rim))
            g.fill(Path(ellipseIn: rect), with: .color(lens))
            g.fill(Path(ellipseIn: CGRect(x: (x + 0.4) * pixel, y: (y + 0.4) * pixel, width: pixel * 0.55, height: pixel * 0.45)), with: .color(.white.opacity(0.55)))
        }
        cell(&g, bx + eyes[0] + 0.5 + r / 2, by + ey + 0.6, rim, w: eyes[1] - eyes[0] - r, h: 0.35)
    }

    // MARK: 小工具

    /// 往上飘的音符
    private func drawNotes(_ g: inout some PetPainter, t: Double, x: Double, y: Double, colors: [Color]) {
        for i in 0..<3 {
            let ph = (t * 0.7 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
            g.opacity = 1 - ph
            g.text(i % 2 == 0 ? "♪" : "♫", size: pixel * 3, weight: .bold, rounded: false, color: colors[i % colors.count], at: CGPoint(x: (x + Double(i) * 1.6 + sin(ph * 5) * 0.8) * pixel, y: (y - ph * 5) * pixel))
            g.opacity = 1
        }
    }

    /// 鞭子从右边甩过来：先收着、再抽到身上、啪一下冒星星
    private func drawWhip(_ g: inout some PetPainter, t: Double, bx: Double, by: Double) {
        let c = t.truncatingRemainder(dividingBy: 1.6) / 1.6
        let leather = Color(red: 0.45, green: 0.25, blue: 0.12)
        var path = Path()
        let hand = CGPoint(x: 25.4 * pixel, y: 1.5 * pixel)
        path.move(to: hand)
        if c < 0.3 {
            // 往后扬
            let p = c / 0.3
            path.addQuadCurve(to: CGPoint(x: (25 - p * 2) * pixel, y: (-1 + p) * pixel), control: CGPoint(x: 24 * pixel, y: 3 * pixel))
        } else if c < 0.5 {
            // 抽下来
            let tip = CGPoint(x: (bx + 14.5) * pixel, y: (by + 4.5) * pixel)
            path.addQuadCurve(to: tip, control: CGPoint(x: 22 * pixel, y: (by - 3) * pixel))
        } else {
            let p = min(1, (c - 0.5) / 0.3)
            path.addQuadCurve(to: CGPoint(x: (bx + 14.5 + p * 8) * pixel, y: (by + 4.5 + p * 4) * pixel), control: CGPoint(x: 23 * pixel, y: 4 * pixel))
        }
        g.stroke(path, with: .color(leather), style: StrokeStyle(lineWidth: max(1, pixel * 0.45), lineCap: .round))
        cell(&g, 25, 0, Color(white: 0.3), w: 0.8, h: 2)
        if c > 0.36 && c < 0.7 {
            let p = (c - 0.36) / 0.34
            g.opacity = 1 - p
            for i in 0..<4 {
                let a = Double(i) * .pi / 2 + 0.6
                cell(&g, bx + 14 + cos(a) * (1 + p * 2.5), by + 4 + sin(a) * (1 + p * 2.5), .yellow, w: 0.6, h: 0.6)
            }
            g.text(L("啪!"), size: pixel * 2.6, weight: .heavy, rounded: true, color: .orange, at: CGPoint(x: 22 * pixel, y: (by + 1 - p) * pixel))
            g.opacity = 1
        }
    }

    /// 像素柴犬（9×5 格）。step 切换两组腿，wag 摇尾巴
    func drawDog(_ g: inout some PetPainter, x: Double, y: Double, step: Int, wag: Bool, facingLeft: Bool) {
        let fur = Color(red: 0.9, green: 0.6, blue: 0.3), cream = Color(red: 1, green: 0.9, blue: 0.75)
        let ear = Color(red: 0.62, green: 0.36, blue: 0.16), ink = Color(white: 0.1)
        let rows = [
            wag ? "t......ee" : ".......ee",
            wag ? ".t....fkf" : "t.....fkf",
            ".ffffffcn",
            ".fcccff..",
            step == 0 ? ".f.f..f.f" : "..f.f.f.f",
        ]
        let pal: [Character: Color] = ["f": fur, "c": cream, "e": ear, "k": ink, "n": ink, "t": fur]
        for (j, r) in rows.enumerated() {
            for (i, ch) in r.enumerated() {
                guard let col = pal[ch] else { continue }
                let cx = facingLeft ? x + Double(8 - i) : x + Double(i)
                cell(&g, cx, y + Double(j), col)
            }
        }
        // 红项圈
        cell(&g, facingLeft ? x + 2 : x + 6, y + 1.8, Color(red: 0.9, green: 0.2, blue: 0.25), w: 1, h: 0.4)
    }

    private func leash(_ g: inout some PetPainter, from a: CGPoint, to b: CGPoint) {
        var p = Path()
        p.move(to: CGPoint(x: a.x * pixel, y: a.y * pixel))
        p.addQuadCurve(to: CGPoint(x: b.x * pixel, y: b.y * pixel),
                       control: CGPoint(x: (a.x + b.x) / 2 * pixel, y: (max(a.y, b.y) + 2) * pixel))
        g.stroke(p, with: .color(Color(red: 0.9, green: 0.2, blue: 0.25)), lineWidth: max(1, pixel * 0.3))
    }

    /// 橘猫蹲着（7×4 格），尾巴一甩一甩
    private func drawCatSitting(_ g: inout some PetPainter, x: Double, y: Double, tailUp: Bool) {
        let fur = Color(red: 0.97, green: 0.66, blue: 0.3), stripe = Color(red: 0.8, green: 0.45, blue: 0.15), ink = Color(white: 0.1)
        let rows = [
            "o...o" + (tailUp ? ".o" : ".."),
            "okoko" + (tailUp ? ".o" : ".."),
            "osoooo" + (tailUp ? "o" : "."),
            "oo.oo" + (tailUp ? ".." : "oo"),
        ]
        let pal: [Character: Color] = ["o": fur, "s": stripe, "k": ink]
        for (j, r) in rows.enumerated() { for (i, ch) in r.enumerated() { if let c = pal[ch] { cell(&g, x + Double(i), y + Double(j), c) } } }
    }

    /// 橘猫蜷成一团睡觉（7×3 格），呼吸时一起一伏
    private func drawCatCurled(_ g: inout some PetPainter, x: Double, y: Double, breathe: Bool) {
        let fur = Color(red: 0.97, green: 0.66, blue: 0.3), stripe = Color(red: 0.8, green: 0.45, blue: 0.15), ink = Color(white: 0.1)
        let rows = [
            ".o.o...",
            "okoosoo",
            "ooooooo",
        ]
        let pal: [Character: Color] = ["o": fur, "s": stripe, "k": ink]
        let lift = breathe ? -0.2 : 0
        for (j, r) in rows.enumerated() { for (i, ch) in r.enumerated() { if let c = pal[ch] { cell(&g, x + Double(i), y + Double(j) + (j < 2 ? lift : 0), c) } } }
    }
}
