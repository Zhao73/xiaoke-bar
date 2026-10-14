import SwiftUI
import AppKit

/// 四只像素宠物：
/// - 小克（Claude）：Claude Code 启动画面里那只小螃蟹，按字符画 ▐▛███▜▌ / ▝▜█████▛▘ / ▘▘ ▝▝ 还原
/// - 小 Co（Codex）：照 Codex 官方小伙伴画的：云朵脑袋、深色屏幕脸「>‿」、蓝色小身体
/// - 小 G（Grok）：带吸积环的小黑洞
/// - 小 Gem（Gemini）：Gemini 的四角星
/// 后三只是按各家 Logo 元素原创的（官方没有吉祥物）。身体都画在 16×10 的格子里，道具画在身体右边和上方。
enum PetArt {
    static let clawd = Color(red: 0.851, green: 0.467, blue: 0.341)       // #D97757

    struct Pose {
        var eyesClosed = false
        var lookOffset = 0          // 眼睛左右看
        var armsUp = false
        var armWave = 0             // 0 平举，1 左手抬，2 右手抬
        var legPhase = 0            // 走路时两组腿交替
        var squash = false          // 落地时压扁一下
        var armsHidden = false      // 演奏时不画默认的手，改由乐器画法从肩膀画到接触点
    }

    static func name(_ k: Provider) -> String {
        switch k { case .claude: L("小克"); case .codex: L("小 Co"); case .grok: L("小 G"); case .gemini: L("小 Gem") }
    }

    /// 身体轮廓（16 列 × 8 行），字母对应颜色
    private static let bodies: [Provider: [String]] = [
        .claude: [
            "..aaaaaaaaaaab..", "..bbbbbbbbbbbb..", "..bbbbbbbbbbbb..", "..bbbbbbbbbbbb..",
            "..bbbbbbbbbbbb..", "..bbbbbbbbbbbb..", "..bbbbbbbbbbbb..", "..cccccccccccc..",
        ],
        // 小 Co：Codex 图标那朵蓬松的云，颜色在 pixels() 里按位置做紫→蓝渐变
        .codex: [
            "...xxx..xxx.....", "..xxxxxxxxxxx...", ".xxxxxxxxxxxxxx.", ".xxxxxxxxxxxxxxx",
            "xxxxxxxxxxxxxxx.", ".xxxxxxxxxxxxxxx", "..xxxxxxxxxxxxx.", "...xxxx..xxxx...",
        ],
        .grok: [
            ".....gkkkkg.....", "...gkkkkkkkkg...", "..gkkkkkkkkkkg..", "..kkkkkkkkkkkk..",
            "..kkkkkkkkkkkk..", "..gkkkkkkkkkkg..", "...gkkkkkkkkg...", ".....gkkkkg.....",
        ],
        .gemini: [
            ".......aa.......", "......aaaa......", ".....bbbbbb.....", "...bbbbbbbbbb...",
            "bbbbbbbbbbbbbbbb", "...cccccccccc...", ".....cccccc.....", "......dddd......",
        ],
    ]

    private static func palette(_ k: Provider) -> [Character: Color] {
        switch k {
        case .claude: return ["a": Color(red: 0.92, green: 0.58, blue: 0.46), "b": clawd, "c": Color(red: 0.74, green: 0.38, blue: 0.27)]
        case .codex: return ["x": Color(red: 0.45, green: 0.45, blue: 1)]
        case .grok: return ["k": Color(white: 0.11), "g": Color(white: 0.32)]
        case .gemini: return ["a": Color(red: 0.44, green: 0.66, blue: 1), "b": Color(red: 0.36, green: 0.55, blue: 0.94),
                              "c": Color(red: 0.56, green: 0.44, blue: 0.85), "d": Color(red: 0.78, green: 0.42, blue: 0.6)]
        }
    }

    /// 小 Co 的渐变：左上偏紫、右下偏蓝（和 Codex 图标一致）
    static func codexGradient(_ x: Int, _ y: Int) -> Color {
        let f = min(1, max(0, (Double(x) + Double(y) * 1.4) / (15 + 7 * 1.4)))
        return Color(red: 0.66 - 0.4 * f, green: 0.5 - 0.08 * f, blue: 1.0 - 0.02 * f)
    }

    static func limbColor(_ k: Provider) -> Color {
        switch k {
        case .claude: return clawd
        case .codex: return Color(red: 0.36, green: 0.45, blue: 0.95)
        case .grok: return Color(white: 0.25)
        case .gemini: return Color(red: 0.56, green: 0.44, blue: 0.85)
        }
    }

    /// 返回 (x, y, 颜色) 列表，坐标是身体格子（0...15, 0...9）
    static func pixels(_ k: Provider, _ p: Pose) -> [(Int, Int, Color)] {
        var px: [(Int, Int, Color)] = []
        let pal = palette(k)
        let top = p.squash ? 1 : 0
        for (y, row) in (bodies[k] ?? []).enumerated() where y >= top {
            for (x, ch) in row.enumerated() {
                guard let c = pal[ch] else { continue }
                px.append((x, y, k == .codex ? codexGradient(x, y) : c))
            }
        }
        let limb = limbColor(k)
        // 手臂（Gemini 的星芒就是手，不另画；小 Co 的小短手长在身体两侧）
        if p.armsHidden {
            // 手臂交给乐器画法
        } else if k == .codex {
            // 云朵两边伸出的小圆手
            let leftUp = p.armsUp || p.armWave == 1
            let rightUp = p.armsUp || p.armWave == 2
            let lc = codexGradient(0, 5), rc = codexGradient(15, 5)
            if leftUp { px.append((-1, 3, lc)); px.append((-2, 2, lc)) } else { px.append((-1, 5, lc)); px.append((-1, 6, lc)) }
            if rightUp { px.append((16, 3, rc)); px.append((17, 2, rc)) } else { px.append((16, 5, rc)); px.append((16, 6, rc)) }
        } else if k != .gemini {
            let leftUp = p.armsUp || p.armWave == 1
            let rightUp = p.armsUp || p.armWave == 2
            let ys = k == .claude ? (4...5) : (3...4)
            for y in (leftUp ? (ys.lowerBound - 2)...(ys.upperBound - 2) : ys) { px.append((0, y, limb)); px.append((1, y, limb)) }
            for y in (rightUp ? (ys.lowerBound - 2)...(ys.upperBound - 2) : ys) { px.append((14, y, limb)); px.append((15, y, limb)) }
        } else if p.armsUp || p.armWave != 0 {
            // 星芒往上翘一下
            if p.armsUp || p.armWave == 1 { px.append((1, 3, pal["b"]!)); px.append((0, 2, pal["b"]!)) }
            if p.armsUp || p.armWave == 2 { px.append((14, 3, pal["b"]!)); px.append((15, 2, pal["b"]!)) }
        }
        // 腿
        let legs: [Int] = k == .claude ? [3, 5, 10, 12] : (k == .gemini ? [7, 8] : (k == .codex ? [5, 10] : [5, 10]))
        for (i, x) in legs.enumerated() {
            let lifted = p.legPhase != 0 && (i % 2 == (p.legPhase == 1 ? 0 : 1))
            let c = k == .gemini ? pal["d"]! : limb
            px.append((x, 8, c))
            if !lifted && k != .gemini { px.append((x, 9, c)) }
        }
        // 脸
        let lo = p.lookOffset
        switch k {
        case .claude:
            let eye = Color(red: 0.12, green: 0.10, blue: 0.09)
            for ex in [4 + lo, 11 + lo] {
                if p.eyesClosed { px.append((ex, 3 + top, eye)) } else { px.append((ex, 2 + top, eye)); px.append((ex, 3 + top, eye)) }
            }
        case .codex:
            // 白色的「>_」：眨眼时 > 压成一横；左上角一点高光让云朵有体积感
            let w = Color.white
            let y0 = top
            if p.eyesClosed { px.append((4 + lo, 4 + y0, w)); px.append((5 + lo, 4 + y0, w)) }
            else { px.append((4 + lo, 3 + y0, w)); px.append((5 + lo, 4 + y0, w)); px.append((4 + lo, 5 + y0, w)) }
            for x in 7...9 { px.append((x + lo, 5 + y0, w)) }
            px.append((3, 2 + y0, Color.white.opacity(0.35))); px.append((4, 1 + y0, Color.white.opacity(0.35)))
        case .grok:
            let w = Color.white
            for ex in [5 + lo, 10 + lo] {
                if p.eyesClosed { px.append((ex, 3, w)) } else { px.append((ex, 2, w)); px.append((ex, 3, w)) }
            }
            // 吸积环：从左下斜穿到右上
            let ring = Color(white: 0.86)
            for (x, y) in [(0, 6), (1, 6), (2, 6), (3, 6), (4, 5), (5, 5), (6, 5), (7, 5), (8, 5), (9, 5), (10, 5), (11, 4), (12, 4), (13, 4), (14, 3), (15, 3)] {
                px.append((x, y, ring))
            }
        case .gemini:
            let eye = Color(red: 0.1, green: 0.08, blue: 0.27)
            for ex in [6 + lo, 9 + lo] {
                if p.eyesClosed { px.append((ex, 4, eye)) } else { px.append((ex, 3, eye)); px.append((ex, 4, eye)) }
            }
        }
        return px
    }

    /// 菜单栏小图标：身体 16×10 格
    static func menuImage(_ k: Provider = .claude, pose: Pose = Pose(), scale: CGFloat = 1.5) -> NSImage {
        let w = 16 * scale, h = 10 * scale
        let img = NSImage(size: NSSize(width: w, height: h), flipped: true) { _ in
            // 1.5pt 一格 = Retina 上正好 3 个物理像素，关掉抗锯齿保持像素画的硬边
            NSGraphicsContext.current?.shouldAntialias = false
            NSGraphicsContext.current?.imageInterpolation = .none
            for (x, y, c) in pixels(k, pose) {
                NSColor(c).setFill()
                NSRect(x: CGFloat(x) * scale, y: CGFloat(y) * scale, width: scale, height: scale).fill()
            }
            return true
        }
        img.isTemplate = false
        return img
    }
}

