import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Namespace private var tabNS

    var body: some View {
        VStack(spacing: 0) {
            header
            if !model.busySessions.isEmpty {
                CrewStrip().transition(.move(edge: .top).combined(with: .opacity))
            }
            tabBar
            ZStack {
                switch model.tab {
                case .quota: QuotaTab().transition(.blurReplace)
                case .stats: StatsTab().transition(.blurReplace)
                case .sessions: SessionsTab().transition(.blurReplace)
                case .billing: BillingTab().transition(.blurReplace)
                case .settings: SettingsTab().transition(.blurReplace)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.spring(duration: 0.4), value: model.tab)
            footer
        }
        .animation(.spring(duration: 0.45, bounce: 0.2), value: model.busySessions.isEmpty)
        .frame(width: 420, height: 680)
        .id(model.language)          // 换语言时整页重建
        .background(AuroraBackground(mood: model.mood))
        .overlay(alignment: .bottom) {
            if let t = model.toast {
                Text(t).font(.system(size: 11.5, weight: .medium))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(radius: 8)
                    .padding(.bottom, 44)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(shortcuts)
    }

    // MARK: 顶栏：小克 + 一句话

    private var header: some View {
        HStack(alignment: .center, spacing: 6) {
            let pet = model.pet
            WanderingPet(kind: pet.kind, action: pet.action, line: petLine) { model.celebrate(seconds: 1.2) }
                .contextMenu {
                    PetActionMenu(target: nil)
                    Menu(L("组乐队弹一首 🎸")) { SongMenuItems() }
                    Divider()
                    Button(model.floatingPet ? L("隐藏桌面宠物") : L("放到桌面上")) { model.floatingPet.toggle() }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting).font(.system(size: 14, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.8)
                SystemChips()
            }
            Spacer(minLength: 0)
            Menu { SongMenuItems() } label: {
                Image(systemName: model.nowPlaying == nil ? "guitars.fill" : "music.note")
                    .font(.system(size: 13, weight: .semibold))
                    .symbolEffect(.bounce, options: .repeating, isActive: model.nowPlaying != nil)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help(L("让宠物弹一首歌（有声音）"))
            IconButton(icon: "arrow.clockwise", help: L("立即刷新（⌘R）"), spinning: model.refreshing) {
                Task { await model.refreshAll(); await model.rescan() }
            }
        }
        .padding(.leading, 6).padding(.trailing, 12).padding(.top, 10)
    }

    private var greeting: String {
        let pet = model.pet
        let name = PetArt.name(pet.kind)
        if let n = model.nowPlaying { return L("%@在弹《%@》🎸", name, n.song.title) }
        if let s = pet.session, s.busy {
            let n = model.live.filter(\.busy).count
            // 多个会话的细节在下面的小队卡片里，标题只说个数，保持一行
            return n > 1 ? L("%d 个会话在跑", n) : L("%@正在%@", name, pet.action.label)
        }
        switch pet.action {
        case .guitar: return L("%@在弹吉他 🎸", name)
        case .dance: return L("%@在跳舞", name)
        case .coffee: return L("%@在喝咖啡", name)
        case .sleep: return model.mood == .sleepy ? L("额度快见底啦") : L("夜深了，早点休息")
        case .worried: return L("悠着点用哦")
        case .celebrate: return model.lastDone != nil ? L("做完啦！") : L("耶！")
        default:
            let h = Calendar.current.component(.hour, from: .now)
            if h < 12 { return L("早上好") }
            if h < 18 { return L("下午好") }
            return L("晚上好")
        }
    }

    private var statusLine: String {
        let busy = model.busySessions
        if busy.count >= 2 {
            let cpu = busy.reduce(0) { $0 + $1.cpu }
            let mem = busy.reduce(UInt64(0)) { $0 + $1.rss }
            var parts = [L("今天 %@ token", Double(model.total(Set(Provider.allCases), .today).total).tokenShort)]
            if mem > 0 { parts.append(L("合计 CPU %d%% · 内存 %@", Int(cpu), mem.bytesShort)) }
            parts.append(L("磁盘剩 %@", model.system.diskFree.bytesShort))
            return parts.joined(separator: " · ")
        }
        if let s = model.pet.session, s.busy {
            let title = model.shown(model.summary(for: s)?.title ?? s.name) ?? ""
            return [model.shown(s.detail), title.isEmpty ? nil : title].compactMap { $0 }.joined(separator: " · ")
        }
        let today = model.total(Set(Provider.allCases), .today).total
        var parts = [L("今天 %@ token", Double(today).tokenShort)]
        parts.append("CPU \(Int(model.system.cpuPercent))%")
        parts.append(L("磁盘剩 %@", model.system.diskFree.bytesShort))
        if let t = model.lastRefresh { parts.append(L("%@更新", Fmt.ago(t))) }
        return parts.joined(separator: " · ")
    }

    private var petLine: String {
        let today = model.total(Set(Provider.allCases), .today).total
        let lines: [String] = [
            L("今天一起烧了 %@ token！", Double(today).tokenShort),
            model.menuPercent.map { $0 > 80 ? L("5 小时额度用了 %d%%，歇会儿？", Int($0)) : L("额度还很充足，放心冲！") } ?? L("我在盯着额度呢"),
            L("本周累计 %@", Double(model.total(Set(Provider.allCases), .week).total).tokenShort),
            L("右键我可以弹吉他 🎸"),
            L("双击我，给你表演一个"),
            L("鼠标在我身上来回蹭蹭 = 摸头 ❤︎"),
        ]
        return lines[Int(Date().timeIntervalSince1970 / 3) % lines.count]
    }

    // MARK: 标签栏（滑动的胶囊）

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(AppModel.Tab.allCases) { t in
                Button {
                    withAnimation(.spring(duration: 0.38, bounce: 0.22)) { model.tab = t }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: t.icon).font(.system(size: 10.5, weight: .semibold))
                            .symbolEffect(.bounce, value: model.tab == t)
                        Text(t.title).font(.system(size: 11.5, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(model.tab == t ? .primary : .secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 7)
                    .background {
                        if model.tab == t {
                            Capsule()
                                .fill(.background.opacity(0.95))
                                .shadow(color: .black.opacity(0.14), radius: 4, y: 1)
                                .overlay(Capsule().strokeBorder(Provider.claude.tint.opacity(0.35), lineWidth: 1))
                                .matchedGeometryEffect(id: "tab", in: tabNS)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(.primary.opacity(0.07), in: Capsule())
        .padding(.horizontal, 14).padding(.top, 8)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(Provider.allCases) { p in Logo(provider: p, size: 11).opacity(0.7) }
            }
            Text(model.scanProgress.map { L("首次统计中… %d%%", Int($0 * 100)) } ?? L("数据只在本机读取")).font(.system(size: 9.5)).foregroundStyle(.tertiary)
            Spacer()
            Button { NSApp.terminate(nil) } label: { Text(L("退出")).font(.system(size: 10.5)).foregroundStyle(.secondary) }
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(.primary.opacity(0.03))
    }

    /// 键盘快捷键：⌘1-4 切换页面，⌘R 刷新，⌘, 设置
    private var shortcuts: some View {
        Group {
            ForEach(Array(AppModel.Tab.allCases.enumerated()), id: \.offset) { i, t in
                Button("") { withAnimation(.spring(duration: 0.38)) { model.tab = t } }
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
            }
            Button("") { Task { await model.refreshAll(); await model.rescan() } }.keyboardShortcut("r", modifiers: .command)
            Button("") { withAnimation { model.tab = .settings } }.keyboardShortcut(",", modifiers: .command)
        }
        .opacity(0).frame(width: 0, height: 0).allowsHitTesting(false)
    }
}

/// 背景：慢慢漂移的柔光，颜色跟着小克的心情变。
/// 用系统动画移动三块径向渐变，不做逐帧重绘和实时模糊，打开面板时也几乎不占 CPU。
struct AuroraBackground: View {
    var mood: PetMood

    var body: some View {
        let warm = mood == .sleepy || mood == .worried
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            AuroraLayer(colors: [Provider.claude.tint, warm ? .red : Provider.codex.tint, mood == .working ? .yellow : .teal])
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }

    private func blob(_ c: Color, size: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(colors: [c.opacity(0.24), c.opacity(0)], center: .center, startRadius: 0, endRadius: size / 2))
            .frame(width: size, height: size)
    }
}

// MARK: 工作小队：同时有好几个会话在跑时，每个会话一张卡片、一只宠物

struct CrewStrip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let crew = model.busySessions
        Group {
            if crew.count <= 2 {
                HStack(spacing: 6) { ForEach(crew) { CrewCard(s: $0) } }
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) { ForEach(crew) { CrewCard(s: $0).frame(width: 190) } }
                        .padding(.horizontal, 1)
                }
                .scrollIndicators(.never)
            }
        }
        .padding(.horizontal, 14).padding(.top, 6)
        .animation(.spring(duration: 0.4), value: crew.map(\.id))
    }
}

struct CrewCard: View {
    @Environment(AppModel.self) private var model
    var s: LiveSession
    @State private var hover = false

    var body: some View {
        let sum = model.summary(for: s)
        HStack(spacing: 4) {
            InteractivePet(session: s, model: model, pixel: 1.6, seed: Int(s.pid % 97))
                .frame(width: PetView.cols * 1.6, height: PetView.rows * 1.6)
                .contextMenu { PetActionMenu(target: s.id) }
            VStack(alignment: .leading, spacing: 1.5) {
                HStack(spacing: 3) {
                    Logo(provider: s.provider, size: 9)
                    Text(model.shown(sum?.title ?? s.name) ?? s.provider.name).font(.system(size: 10.5, weight: .semibold)).lineLimit(1)
                }
                HStack(spacing: 4) {
                    Text(s.action.label + (model.shown(s.detail).map { " · " + $0 } ?? ""))
                        .foregroundStyle(s.provider.tint).lineLimit(1)
                        .contentTransition(.opacity)
                    Spacer(minLength: 2)
                    if let d = model.busyDuration(s) { Text(Fmt.duration(d)).foregroundStyle(.secondary).monospacedDigit().fixedSize() }
                }
                .font(.system(size: 9.5))
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 2).padding(.trailing, 8).padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(s.provider.tint.opacity(hover ? 0.16 : 0.09)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(s.provider.tint.opacity(0.28)))
        .overlay(alignment: .topTrailing) {
            PulseDot().frame(width: 5, height: 5).padding(6)
        }
        .scaleEffect(hover ? 1.02 : 1)
        .animation(.spring(duration: 0.25), value: hover)
        .onHover { hover = $0 }
        .contentShape(Rectangle())
        .onTapGesture {
            model.sessionFocus = sum?.id
            withAnimation(.spring(duration: 0.38, bounce: 0.22)) { model.tab = .sessions }
        }
        .help(model.shown(s.say) ?? L("点开看这个会话的详情"))
        .contextMenu {
            Button(L("切到它的窗口")) { SessionOpener.open(s) }
            Button(L("看详情")) { model.sessionFocus = sum?.id; model.tab = .sessions }
        }
        .transition(.scale(scale: 0.8).combined(with: .opacity))
    }
}

/// 呼吸灯：表示还在跑
struct Pulse: ViewModifier {
    func body(content: Content) -> some View {
        LowFPS(fps: 6, period: 1.8) { ph in
            let k = 0.5 + 0.5 * cos(ph * 2 * .pi)
            content.opacity(0.35 + 0.65 * k).scaleEffect(0.7 + 0.3 * k)
        }
    }
}

/// 低帧率的循环动画（呼吸灯、光圈、背景漂移）。
/// repeatForever 会按屏幕最高刷新率（ProMotion 是每秒 120 帧）一直重画，面板开着时很费 CPU；这里限到每秒十几帧。
struct LowFPS<Content: View>: View {
    var fps: Double = 12
    var period: Double
    @ViewBuilder var content: (Double) -> Content    // 参数是 0...1 的相位

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / fps)) { ctx in
            content(ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period)
        }
    }
}

// MARK: 顶栏第二行：本机 CPU / 内存 / 磁盘 / 今日 token，各带一根迷你条

struct SystemChips: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let sys = model.system
        HStack(spacing: 10) {
            chip("cpu", "\(Int(sys.cpuPercent.rounded()))%", fill: sys.cpuPercent / 100, help: L("CPU 已用，还剩 %d%%", Int(sys.cpuFree)))
            chip("memorychip", "\(Int(sys.memPercent.rounded()))%", fill: sys.memPercent / 100,
                 help: L("内存已用 %@ / %@", sys.memUsed.bytesShort, sys.memTotal.bytesShort))
            chip("internaldrive", sys.diskFree > 0 ? Int64(sys.diskFree).bytesShort : "—", fill: 1 - sys.diskFreePercent / 100,
                 help: L("磁盘还剩 %@（%d%%）", Int64(sys.diskFree).bytesShort, Int(sys.diskFreePercent)))
            chip("sum", Double(model.total(Set(Provider.allCases), .today).total).tokenShort, fill: nil, help: L("今天所有工具合计用掉的 token"))
        }
        .font(.system(size: 10, weight: .medium, design: .rounded))
        .foregroundStyle(.secondary)
    }

    /// 图标 + 数字 + 一根细条（超过 85% 变橙、95% 变红）
    private func chip(_ icon: String, _ value: String, fill: Double?, help: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 8.5))
            VStack(alignment: .leading, spacing: 1.5) {
                Text(value).monospacedDigit().lineLimit(1).fixedSize()
                if let f = fill {
                    let v = min(1, max(0, f))
                    Capsule().fill(.primary.opacity(0.12)).frame(width: 30, height: 2.5)
                        .overlay(alignment: .leading) {
                            Capsule().fill(v > 0.95 ? Color.red : (v > 0.85 ? .orange : .green.opacity(0.8))).frame(width: 30 * v, height: 2.5)
                        }
                }
            }
        }
        .help(help)
    }
}
