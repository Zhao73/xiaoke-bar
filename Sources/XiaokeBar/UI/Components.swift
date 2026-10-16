import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: 品牌 Logo（官方矢量标志，来自 LobeHub 图标库）

struct Logo: View {
    var provider: Provider
    var size: CGFloat = 22
    var body: some View {
        #if APPSTORE || !os(macOS)
        // 商店版不用各家官方标志（商标），换成小克家族自己的像素头像
        PixelBadge(provider: provider).frame(width: size, height: size)
        #else
        Group {
            if let img = LogoStore.image(provider.logo) {
                Image(nsImage: img)
                    .resizable()
                    .renderingMode(provider == .grok ? .template : .original)
                    .interpolation(.high)
            } else {
                Text(provider.name.prefix(1)).font(.system(size: size * 0.6, weight: .bold))
            }
        }
        .foregroundStyle(.primary)
        .frame(width: size, height: size)
        #endif
    }
}

/// 宠物身体的像素画，缩放到正方形里居中（商店版代替官方 Logo）
struct PixelBadge: View {
    var provider: Provider
    var body: some View {
        Canvas { g, size in
            let px = PetArt.pixels(provider, PetArt.Pose())
            guard let minX = px.map(\.0).min(), let maxX = px.map(\.0).max(),
                  let minY = px.map(\.1).min(), let maxY = px.map(\.1).max() else { return }
            let w = CGFloat(maxX - minX + 1), h = CGFloat(maxY - minY + 1)
            let cell = min(size.width / w, size.height / h)
            let ox = (size.width - w * cell) / 2, oy = (size.height - h * cell) / 2
            for (x, y, c) in px {
                g.fill(Path(CGRect(x: ox + CGFloat(x - minX) * cell, y: oy + CGFloat(y - minY) * cell, width: cell + 0.3, height: cell + 0.3)), with: .color(c))
            }
        }
        .accessibilityHidden(true)
    }
}

#if os(macOS)
enum LogoStore {
    private static var cache: [String: NSImage] = [:]
    static func image(_ name: String) -> NSImage? {
        if let c = cache[name] { return c }
        let url = Bundle.main.url(forResource: name, withExtension: "pdf", subdirectory: "Logos")
            ?? Bundle.main.url(forResource: name, withExtension: "pdf")
            // 开发时直接运行二进制：从仓库的 Resources 目录找
            ?? [FileManager.default.currentDirectoryPath + "/Resources/Logos/\(name).pdf"].map(URL.init(fileURLWithPath:)).first { FileManager.default.fileExists(atPath: $0.path) }
        guard let url, let img = NSImage(contentsOf: url) else { return nil }
        cache[name] = img
        return img
    }
}
#endif

// MARK: 颜色

enum Palette {
    static func level(_ p: Double) -> [Color] {
        if p >= 90 { return [Color(red: 1, green: 0.42, blue: 0.38), Color(red: 0.93, green: 0.22, blue: 0.35)] }
        if p >= 75 { return [Color(red: 1, green: 0.78, blue: 0.35), Color(red: 1, green: 0.55, blue: 0.25)] }
        return []
    }
    static func ring(_ p: Double, base: [Color]) -> [Color] {
        let l = level(p); return l.isEmpty ? base : l
    }
    static let claude = [Color(red: 0.98, green: 0.62, blue: 0.45), Color(red: 0.85, green: 0.42, blue: 0.30)]
    static let codex = [Color(red: 0.55, green: 0.62, blue: 1.0), Color(red: 0.62, green: 0.38, blue: 0.98)]
    static let grok = [Color(white: 0.9), Color(white: 0.55)]
    static let gemini = [Color(red: 0.36, green: 0.6, blue: 1.0), Color(red: 0.62, green: 0.45, blue: 0.88)]
    static let money = [Color(red: 0.36, green: 0.86, blue: 0.62), Color(red: 0.18, green: 0.68, blue: 0.62)]
}

// MARK: 环形额度表

struct RingGauge: View {
    var percent: Double            // 已用百分比
    var colors: [Color]
    var title: String
    var resetsAt: Date?
    var remaining = false          // true 时显示剩余（和 Codex / ChatGPT 官方一样）
    var size: CGFloat = 86
    var line: CGFloat = 9
    @State private var shown: Double = 0

    private var value: Double { remaining ? max(0, 100 - percent) : percent }

    var body: some View {
        let c = Palette.ring(percent, base: colors)
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(.primary.opacity(0.08), lineWidth: line)
                Circle()
                    .trim(from: 0, to: max(0.001, min(1, shown / 100)))
                    .stroke(AngularGradient(colors: c + [c.first!], center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)),
                            style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: c.last!.opacity(0.55), radius: 6)
                // 进度头上的小光点
                Circle()
                    .fill(.white)
                    .frame(width: line * 0.45, height: line * 0.45)
                    .offset(y: -size / 2)
                    .rotationEffect(.degrees(360 * min(1, shown / 100)))
                    .opacity(shown > 2 ? 0.9 : 0)
                VStack(spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text("\(Int(shown.rounded()))")
                            .font(.system(size: size * 0.27, weight: .bold, design: .rounded))
                            .contentTransition(.numericText(value: shown))
                        Text("%").font(.system(size: size * 0.13, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
                    }
                    Text(remaining ? L("%@剩余", title) : L("%@已用", title)).font(.system(size: 9.5, weight: .medium)).foregroundStyle(.secondary)
                        .lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.8)   // 长语言折成两行，不截断
                        .frame(maxWidth: size - line * 2 - 6)
                }
            }
            .frame(width: size, height: size)
            if let resetsAt {
                CountdownLabel(target: resetsAt)
            }
        }
        .onAppear { withAnimation(.spring(duration: 1.1, bounce: 0.15).delay(0.08)) { shown = value } }
        .onChange(of: value) { _, v in withAnimation(.spring(duration: 0.9)) { shown = v } }
        .help(L("%@已用 %d%%，剩余 %d%%", title, Int(percent.rounded()), Int((100 - percent).rounded())) + (resetsAt.map { L("，%@ 重置", Fmt.shortDate($0)) } ?? ""))
    }
}

struct CountdownLabel: View {
    var target: Date
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            HStack(spacing: 3) {
                Image(systemName: "arrow.clockwise").font(.system(size: 8, weight: .bold))
                Text(Fmt.countdown(to: target, now: ctx.date))
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded).monospacedDigit())
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7).padding(.vertical, 2.5)
            .background(.primary.opacity(0.06), in: Capsule())
        }
    }
}

// MARK: 条形进度（带流光）

struct FlowBar: View {
    var fraction: Double
    var colors: [Color]
    var height: CGFloat = 7
    @State private var shown: Double = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.08))
                Capsule()
                    .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height, geo.size.width * min(1, shown)))
                    .shadow(color: colors.last!.opacity(0.4), radius: 4)
                    .overlay {
                        #if os(macOS)
                        // 流光：Core Animation 在渲染进程里跑，不让 SwiftUI 逐帧重算
                        SweepShine().clipShape(Capsule())
                        #endif
                    }
            }
        }
        .frame(height: height)
        .onAppear {
            withAnimation(.spring(duration: 1.0).delay(0.15)) { shown = fraction }
        }
        .onChange(of: fraction) { _, v in withAnimation(.spring(duration: 0.8)) { shown = v } }
    }
}

// MARK: 小胶囊标签

struct Chip: View {
    var text: String
    var color: Color = .secondary
    var icon: String? = nil
    var body: some View {
        HStack(spacing: 3) {
            if let icon { Image(systemName: icon).font(.system(size: 8.5, weight: .bold)) }
            Text(text).font(.system(size: 10, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7).padding(.vertical, 2.5)
        .background(color.opacity(0.13), in: Capsule())
    }
}

// MARK: 卡片外观

struct GlassCard<Content: View>: View {
    var tint: Color
    @ViewBuilder var content: Content
    @State private var hover = false

    var body: some View {
        content
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.background.opacity(0.55))
                    // 阴影只挂在底板上：内容里有倒计时和流光在动，挂在整张卡上会每帧重算阴影
                    .shadow(color: .black.opacity(hover ? 0.16 : 0.08), radius: hover ? 14 : 8, y: hover ? 6 : 3)
                    .overlay(alignment: .topLeading) {
                        // 左上角品牌色光晕
                        RadialGradient(colors: [tint.opacity(hover ? 0.30 : 0.20), .clear], center: .topLeading, startRadius: 4, endRadius: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.04), tint.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            )
            .scaleEffect(hover ? 1.006 : 1)
            .animation(.spring(duration: 0.35), value: hover)
            .onHover { hover = $0 }
    }
}

// MARK: 按钮

struct PillButton: View {
    var title: String
    var icon: String
    var tint: Color
    var prominent = false
    var action: () -> Void
    @State private var hover = false
    @State private var pressed = false

    var body: some View {
        Button(action: {
            withAnimation(.spring(duration: 0.2)) { pressed = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { withAnimation(.spring(duration: 0.3)) { pressed = false } }
            action()
        }) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 10, weight: .bold))
                Text(title).font(.system(size: 11, weight: .semibold)).lineLimit(1).fixedSize()
            }
            .foregroundStyle(prominent ? .white : .primary)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background {
                if prominent {
                    Capsule().fill(LinearGradient(colors: [tint.opacity(hover ? 1 : 0.92), tint.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                        .shadow(color: tint.opacity(hover ? 0.5 : 0.3), radius: hover ? 8 : 4, y: 2)
                } else {
                    Capsule().fill(.primary.opacity(hover ? 0.12 : 0.07))
                }
            }
            .scaleEffect(pressed ? 0.93 : (hover ? 1.03 : 1))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct IconButton: View {
    var icon: String
    var help: String
    var spinning = false
    var action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .rotationEffect(.degrees(spinning ? 360 : 0))
                .animation(spinning ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .default, value: spinning)
                .frame(width: 26, height: 26)
                .background(Circle().fill(.primary.opacity(hover ? 0.12 : 0.0)))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
    }
}

/// 数字滚动显示（token 总数）
struct RollingNumber: View {
    var value: Double
    var font: Font
    @State private var shown: Double = 0
    var body: some View {
        Text(shown.tokenShort)
            .font(font)
            .contentTransition(.numericText(value: shown))
            .onAppear { withAnimation(.spring(duration: 1.0)) { shown = value } }
            .onChange(of: value) { _, v in withAnimation(.spring(duration: 0.8)) { shown = v } }
    }
}

/// 进入时依次浮现
struct StaggerIn: ViewModifier {
    /// 截图模式离屏渲染时，懒加载行的 onAppear 不一定触发，直接显示最终状态
    nonisolated(unsafe) static var disabled = false
    var index: Int
    @State private var on = StaggerIn.disabled
    func body(content: Content) -> some View {
        content
            .opacity(on ? 1 : 0)
            .offset(y: on ? 0 : 14)
            .blur(radius: on ? 0 : 4)
            .onAppear { withAnimation(.spring(duration: 0.55, bounce: 0.2).delay(0.05 + Double(index) * 0.06)) { on = true } }
    }
}

extension View {
    func staggerIn(_ i: Int) -> some View { modifier(StaggerIn(index: i)) }
}

/// 长列表：平时懒加载；截图模式离屏渲染时 LazyVStack 会漏画行，改用普通 VStack
struct ListStack<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        if StaggerIn.disabled {
            VStack(alignment: .leading, spacing: 8) { content }
        } else {
            LazyVStack(alignment: .leading, spacing: 8) { content }
        }
    }
}
