import SwiftUI

// MARK: 会话页：本机性能 + 运行中的会话 + 历史会话（点开看详情）

struct SessionsTab: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var source: Provider?
    @State private var expanded: String?

    var body: some View {
        let all = model.stats?.sessions ?? []
        let list = all.filter { source == nil || $0.provider == source }
            .filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || ($0.cwd ?? "").localizedCaseInsensitiveContains(query) }
            .prefix(120)
        ScrollViewReader { proxy in
        ScrollView {
            ListStack {
                SystemStrip().staggerIn(0)
                if !model.live.isEmpty {
                    sectionTitle(L("运行中 %d", model.live.count), icon: "dot.radiowaves.left.and.right")
                    ForEach(Array(model.live.sorted { ($0.busy ? 1 : 0, $0.rss) > ($1.busy ? 1 : 0, $1.rss) }.enumerated()), id: \.element.id) { i, l in
                        LiveRow(l: l).staggerIn(min(i + 1, 8))
                    }
                }
                HStack(spacing: 6) {
                    searchField
                    sourceMenu
                }
                .padding(.top, 4)
                if list.isEmpty {
                    VStack(spacing: 10) {
                        PetView(kind: .claude, action: .sleep, pixel: 3.5)
                        Text(model.stats == nil ? L("正在读取会话…") : L("没有找到会话")).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.top, 30)
                } else {
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, s in
                        SessionRow(s: s, expanded: expanded == s.id) {
                            withAnimation(.spring(duration: 0.35)) { expanded = expanded == s.id ? nil : s.id }
                        }
                        .staggerIn(min(i, 10))
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .scrollIndicators(.never)
        .onAppear {
            // 从顶部工作小队点进来：展开那个会话并滚过去
            guard let f = model.sessionFocus else { return }
            model.sessionFocus = nil
            source = nil; query = ""
            expanded = f
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { withAnimation { proxy.scrollTo(f, anchor: .top) } }
        }
        }
    }

    private func sectionTitle(_ t: String, icon: String) -> some View {
        Label(t, systemImage: icon).font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary).padding(.top, 2)
    }

    private var searchField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.secondary)
            TextField(L("搜索会话标题或文件夹"), text: $query).textFieldStyle(.plain).font(.system(size: 12))
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var sourceMenu: some View {
        Menu {
            Button(L("全部")) { source = nil }
            ForEach(Provider.allCases) { p in Button(p.name) { source = p } }
        } label: {
            HStack(spacing: 3) {
                if let source { Logo(provider: source, size: 13) } else { Image(systemName: "line.3.horizontal.decrease.circle") }
                Text(source?.name ?? L("全部")).font(.system(size: 11, weight: .medium))
            }
        }
        .menuStyle(.borderlessButton).fixedSize()
    }
}

/// 本机：CPU、内存、磁盘剩余
struct SystemStrip: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let s = model.system
        HStack(spacing: 8) {
            gauge(icon: "cpu", title: "CPU", value: s.cpuPercent, text: "\(Int(s.cpuPercent))%", sub: L("空闲 %d%%", Int(s.cpuFree)))
            gauge(icon: "memorychip", title: L("内存"), value: s.memPercent, text: "\(Int(s.memPercent))%",
                  sub: L("可用 %@", UInt64(max(0, Int64(s.memTotal) - Int64(s.memUsed))).bytesShort))
            gauge(icon: "internaldrive", title: L("磁盘"), value: 100 - s.diskFreePercent, text: s.diskFree.bytesShort, sub: L("剩余 %d%%", Int(s.diskFreePercent)))
        }
        .help(thermal(s.thermal))
    }

    private func thermal(_ t: ProcessInfo.ThermalState) -> String {
        switch t {
        case .nominal: return L("温度正常，性能满血")
        case .fair: return L("有点热，性能略降")
        case .serious: return L("很热，系统在降频")
        case .critical: return L("过热，性能大幅下降")
        @unknown default: return ""
        }
    }

    private func gauge(icon: String, title: String, value: Double, text: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 9.5, weight: .bold)).foregroundStyle(.secondary)
                Text(title).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.75)
                Spacer(minLength: 0)
                Text(text).font(.system(size: 11.5, weight: .bold, design: .rounded)).monospacedDigit()
                    .contentTransition(.numericText(value: value))
            }
            FlowBar(fraction: value / 100, colors: Palette.ring(value, base: [Color(red: 0.4, green: 0.8, blue: 0.95), Color(red: 0.35, green: 0.55, blue: 1)]), height: 4)
            Text(sub).font(.system(size: 9)).foregroundStyle(.tertiary).lineLimit(1)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .animation(.smooth(duration: 0.6), value: value)
    }
}

/// 一个运行中的会话：在做什么、占多少 CPU / 内存
struct LiveRow: View {
    @Environment(AppModel.self) private var model
    var l: LiveSession

    var body: some View {
        let sum = model.summary(for: l)
        HStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                PetView(kind: l.provider, action: l.action, pixel: 1.5, seed: Int(l.pid % 97), cheerUntil: model.cheerUntil)
                    .frame(width: 40, height: 24)
                Circle().fill(l.busy ? Color.green : Color.gray.opacity(0.6)).frame(width: 7, height: 7)
                    .overlay(Circle().stroke(.background, lineWidth: 1.5))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(model.shown(sum?.title ?? l.name) ?? l.provider.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                HStack(spacing: 5) {
                    Text(l.busy ? l.action.label : L("空闲")).foregroundStyle(l.busy ? AnyShapeStyle(l.provider.tint) : AnyShapeStyle(.secondary))
                    if l.busy, let d = model.shown(l.detail) { Text(d).lineLimit(1) }
                    if let d = model.busyDuration(l), l.busy { Text("· " + Fmt.duration(d)) }
                }
                .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                if l.pid > 0 && l.rss > 0 {
                    Text("CPU \(Int(l.cpu.rounded()))%").font(.system(size: 10.5, weight: .semibold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(l.cpu > 80 ? .orange : .primary)
                    Text(l.rss.bytesShort).font(.system(size: 9.5, design: .rounded)).foregroundStyle(.secondary).monospacedDigit()
                } else if let sum {
                    Text(Double(sum.tokens.total).tokenShort).font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    Text(sum.bytes.bytesShort).font(.system(size: 9.5)).foregroundStyle(.secondary)
                }
            }
            .help(l.pid > 0 ? L("进程 %d，含 %d 个子进程（MCP 服务等）", Int(l.pid), max(0, l.procs - 1)) : L("桌面版或已退出的命令行，没有可统计的进程"))
        }
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(l.busy ? l.provider.tint.opacity(0.08) : Color.primary.opacity(0.035)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(l.busy ? l.provider.tint.opacity(0.3) : .clear))
    }
}

struct SessionRow: View {
    @Environment(AppModel.self) private var model
    var s: SessionSummary
    var expanded: Bool
    var toggle: () -> Void
    @State private var hover = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Logo(provider: s.provider, size: 18)
                    .padding(5)
                    .background(Circle().fill(s.provider.tint.opacity(0.13)))
                    .overlay(alignment: .bottomTrailing) {
                        if model.liveSession(for: s)?.busy == true { Circle().fill(.green).frame(width: 7, height: 7) }
                    }
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.shown(s.title) ?? "").font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    HStack(spacing: 5) {
                        Text(Fmt.ago(s.lastActive))
                        if let c = s.cwd { Text("·"); Text(model.shown((c as NSString).lastPathComponent.isEmpty ? c : (c as NSString).lastPathComponent) ?? "").lineLimit(1) }
                        Text("·")
                        Text(Double(s.tokens.total).tokenShort)
                        Text("·")
                        Text(s.bytes.bytesShort)
                        if let acc = accountName { Text("·"); Text(acc).foregroundStyle(Provider.claude.tint) }
                    }
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(expanded ? 180 : 0))
                Button(action: resume) {
                    HStack(spacing: 3) {
                        Image(systemName: liveHere ? "arrow.up.forward.app.fill" : "play.fill").font(.system(size: 8.5))
                        Text(liveHere ? L("切过去") : L("继续")).font(.system(size: 10.5, weight: .semibold))
                    }
                    .foregroundStyle(hover ? .white : .primary)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Capsule().fill(hover ? AnyShapeStyle(s.provider.tint) : AnyShapeStyle(.primary.opacity(0.08))))
                }
                .buttonStyle(.plain)
                .help(liveHere ? L("这个会话正在运行，切到它所在的窗口") : helpText)
            }
            .padding(9)
            .contentShape(Rectangle())
            .onTapGesture(perform: toggle)
            if expanded {
                SessionDetail(s: s)
                    .padding(.horizontal, 10).padding(.bottom, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.primary.opacity(hover || expanded ? 0.07 : 0.035)))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
        .contextMenu {
            Button(L("继续这个会话")) { resume() }
            if let c = s.cwd { Button(L("在访达中显示文件夹")) { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: c) } }
            if let p = s.path { Button(L("在访达中显示会话记录")) { NSWorkspace.shared.selectFile(p, inFileViewerRootedAtPath: "") } }
            Button(L("复制会话 ID")) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(s.sessionId, forType: .string) }
        }
    }

    private var account: ClaudeAccount? {
        guard s.provider == .claude else { return nil }
        if let acc = s.account, let a = model.accounts.first(where: { $0.accountUuid == acc }) { return a }
        return nil
    }

    private var accountName: String? { account.map { model.nickname($0) } }

    private var helpText: String {
        switch s.provider {
        case .claude: return L("用 %@ --resume 在 %@ 里继续", (account ?? model.accounts.first)?.command ?? "claude", Paths.pretty(s.cwd ?? "~"))
        case .codex: return L("用 codex resume 继续")
        case .grok: return L("用 grok --resume 继续")
        case .gemini: return L("用 gemini --resume 继续")
        }
    }

    /// 会话正在某个窗口里跑：点「继续」就切过去，不再另开一个
    private var liveHere: Bool { (model.liveSession(for: s)?.pid ?? 0) > 0 }

    private func resume() {
        if let l = model.liveSession(for: s), l.pid > 0, SessionOpener.open(l) != nil { return }
        let dir = s.cwd.flatMap { FileManager.default.fileExists(atPath: $0) ? $0 : nil }
        switch s.provider {
        case .claude:
            // 会话属于哪个账号就用哪个账号打开；不知道的用主号
            guard let a = account ?? model.accounts.first else { return }
            Launcher.claude(a, mode: .session(s.sessionId), dir: dir)
        case .codex:
            Launcher.run("codex resume " + Launcher.shellQuote(s.sessionId), in: dir, title: "codex")
        case .grok:
            Launcher.run("grok --resume " + Launcher.shellQuote(s.sessionId), in: dir, title: "grok")
        case .gemini:
            Launcher.run("gemini --resume " + Launcher.shellQuote(s.sessionId), in: dir, title: "gemini")
        }
    }
}

/// 会话详情：token 明细、缓存命中率、API 等价费用、估算占本周额度、文件大小、进程占用
struct SessionDetail: View {
    @Environment(AppModel.self) private var model
    var s: SessionSummary

    var body: some View {
        let t = s.tokens
        let cost = s.costUSD ?? Pricing.cost(s.models)
        VStack(alignment: .leading, spacing: 10) {
            // token 构成条
            TokenBar(t: t)
            HStack(alignment: .top, spacing: 10) {
                // 缓存命中率小环
                if let hit = s.cacheHitRate {
                    ZStack {
                        Circle().stroke(.primary.opacity(0.08), lineWidth: 5)
                        Circle().trim(from: 0, to: hit).stroke(LinearGradient(colors: Palette.money, startPoint: .top, endPoint: .bottom), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 0) {
                            Text("\(Int((hit * 100).rounded()))%").font(.system(size: 12, weight: .bold, design: .rounded))
                            Text(L("缓存命中")).font(.system(size: 7.5)).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 58, height: 58)
                    .help(L("读缓存 ÷（输入 + 写缓存 + 读缓存）。越高越省额度。"))
                }
                VStack(alignment: .leading, spacing: 5) {
                    if let cost {
                        DetailRow(icon: "dollarsign.circle", label: s.costUSD != nil ? L("实际花费（官方记录）") : L("API 等价费用"), value: cost.usd,
                                  help: s.costUSD != nil ? nil : L("按官方 API 价格折算（缓存写入按 1 小时缓存价）。订阅用户实际不按这个扣钱。"))
                    }
                    if let save = Pricing.cacheSavings(s.models), save > 0.01 {
                        DetailRow(icon: "leaf", label: L("缓存省下"), value: save.usd)
                    }
                    if let share = model.quotaShare(s) {
                        DetailRow(icon: "gauge.with.dots.needle.33percent", label: L("约占本周额度"), value: String(format: "%.1f%%", share),
                                  help: L("按本周 token 占比估算：会话本周 token ÷ 账号本周 token × 本周已用百分比。官方不提供逐会话数据。"))
                    }
                    DetailRow(icon: "doc", label: L("记录文件"), value: s.files > 1 ? L("%@（%d 个文件）", s.bytes.bytesShort, s.files) : s.bytes.bytesShort)
                }
            }
            HStack(spacing: 6) {
                if s.turns > 0 { Chip(text: L("%d 轮回复", s.turns), color: .secondary, icon: "bubble.left") }
                if s.tools > 0 { Chip(text: L("%d 次工具", s.tools), color: .secondary, icon: "wrench.and.screwdriver") }
                if let f = s.firstActive { Chip(text: Fmt.duration(s.lastActive.timeIntervalSince(f)), color: .secondary, icon: "clock") }
            }
            if !s.models.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(s.models.sorted { $0.value.total > $1.value.total }.prefix(4), id: \.key) { m, tok in
                        HStack {
                            Text(m.replacingOccurrences(of: "claude-", with: "")).font(.system(size: 10, design: .monospaced)).lineLimit(1)
                            Spacer()
                            Text(Double(tok.total).tokenShort).font(.system(size: 10, weight: .semibold, design: .rounded))
                            if let c = Pricing.cost([m: tok]) { Text(c.usd).font(.system(size: 10)).foregroundStyle(.secondary).frame(width: 52, alignment: .trailing) }
                        }
                    }
                }
            }
            if let l = model.liveSession(for: s), l.pid > 0, l.rss > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.horizontal.circle").foregroundStyle(.green)
                    Text(L("正在运行 · CPU %d%% · 内存 %@ · %d 个进程", Int(l.cpu.rounded()), l.rss.bytesShort, l.procs))
                        .font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct DetailRow: View {
    var icon: String
    var label: String
    var value: String
    var help: String? = nil
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(.secondary).frame(width: 13)
            Text(label).font(.system(size: 10.5)).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(value).font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
        }
        .help(help ?? "")
    }
}

/// 输入 / 输出 / 写缓存 / 读缓存 的比例条
struct TokenBar: View {
    var t: Tok
    @State private var on = false
    static let parts: [(KeyPath<Tok, Int64>, String, Color)] = [
        (\.i, "输入", Color(red: 0.4, green: 0.65, blue: 1)),
        (\.o, "输出", Color(red: 0.98, green: 0.6, blue: 0.4)),
        (\.cw, "写缓存", Color(red: 0.75, green: 0.5, blue: 0.95)),
        (\.cr, "读缓存", Color(red: 0.36, green: 0.82, blue: 0.62)),
    ]
    var body: some View {
        let total = max(1, Double(t.total))
        VStack(alignment: .leading, spacing: 5) {
            GeometryReader { geo in
                HStack(spacing: 1.5) {
                    ForEach(Self.parts.indices, id: \.self) { k in
                        let v = Double(t[keyPath: Self.parts[k].0])
                        if v > 0 {
                            RoundedRectangle(cornerRadius: 2).fill(Self.parts[k].2)
                                .frame(width: max(3, (geo.size.width - 6) * v / total * (on ? 1 : 0)))
                        }
                    }
                }
            }
            .frame(height: 6)
            HStack(spacing: 8) {
                ForEach(Self.parts.indices, id: \.self) { k in
                    HStack(spacing: 3) {
                        Circle().fill(Self.parts[k].2).frame(width: 5, height: 5)
                        Text("\(L(Self.parts[k].1)) \(Double(t[keyPath: Self.parts[k].0]).tokenShort)")
                    }
                }
            }
            .font(.system(size: 9.5)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .onAppear { withAnimation(.spring(duration: 0.8).delay(0.1)) { on = true } }
    }
}
