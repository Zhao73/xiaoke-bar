import SwiftUI

struct QuotaTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if Pro.shared.hasAccess {
                    ForEach(Array(model.visibleAccounts.enumerated()), id: \.element.id) { i, a in
                        ClaudeCard(account: a).staggerIn(i)
                    }
                    let n = model.visibleAccounts.count
                    CodexCard().staggerIn(n)
                    GeminiCard().staggerIn(n + 1)
                    GrokCard().staggerIn(n + 2)
                    AddAccountCard().staggerIn(n + 3)
                } else {
                    // 免费版：只看主账号，其余换成一张解锁卡片
                    if let a = model.visibleAccounts.first { ClaudeCard(account: a).staggerIn(0) }
                    ProCard(hiddenAccounts: max(0, model.visibleAccounts.count - 1)).staggerIn(1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .scrollIndicators(.never)
    }
}

// MARK: 公共：卡片头部

struct CardHeader: View {
    var provider: Provider
    var title: String
    var plan: String
    var subtitle: String
    var state: LoadState
    var body: some View {
        HStack(spacing: 10) {
            Logo(provider: provider, size: 26)
                .padding(5)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.primary.opacity(0.06)))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title).font(.system(size: 13.5, weight: .bold))
                    Chip(text: plan, color: provider == .grok ? .primary : provider.tint)
                }
                Text(subtitle).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            StateDot(state: state)
        }
    }
}

struct StateDot: View {
    var state: LoadState
    var body: some View {
        let (color, tip): (Color, String) = {
            switch state {
            case .ok: return (.green, L("数据是最新的"))
            case .loading: return (.blue, L("正在读取…"))
            case .idle: return (.gray, "")
            case .stale(let m): return (.orange, m)
            case .failed(let m): return (.red, m)
            }
        }()
        Circle().fill(color)
            .frame(width: 7, height: 7)
            .overlay {
                // 只有读取中才放光圈动画，平时静止（一直动很费 CPU）
                if case .loading = state {
                    LowFPS(period: 1.6) { ph in
                        Circle().stroke(color.opacity(0.5), lineWidth: 4).scaleEffect(1 + 1.2 * ph).opacity(0.8 * (1 - ph))
                    }
                } else {
                    Circle().stroke(color.opacity(0.25), lineWidth: 3).scaleEffect(1.6)
                }
            }
            .help(tip)
    }
}

struct InfoRow: View {
    var icon: String
    var label: String
    var value: String
    var tint: Color = .secondary
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 10, weight: .semibold)).foregroundStyle(tint).frame(width: 14)
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(value).font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1)
        }
    }
}

struct ErrorLine: View {
    var text: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(text).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: Claude 账号卡片

struct ClaudeCard: View {
    @Environment(AppModel.self) private var model
    var account: ClaudeAccount

    var body: some View {
        let usage = model.claudeUsage[account.id]
        let state = model.claudeState[account.id] ?? .idle
        GlassCard(tint: Provider.claude.tint) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(provider: .claude, title: "Claude · \(model.nickname(account))", plan: account.planName,
                           subtitle: subtitle, state: state)
                if let usage {
                    HStack(alignment: .top, spacing: 14) {
                        if let w = usage.fiveHour {
                            RingGauge(percent: w.percent, colors: Palette.claude, title: L("5 小时"), resetsAt: w.resetsAt, remaining: model.showRemaining)
                        }
                        if let w = usage.weekly {
                            RingGauge(percent: w.percent, colors: Palette.claude, title: L("本周"), resetsAt: w.resetsAt, remaining: model.showRemaining)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(usage.money, id: \.title) { m in MoneyBlock(m: m, claimed: account.promoClaimed) }
                            if usage.money.isEmpty {
                                // 官方接口里这一项是空的：说明这个套餐没有发，不是没读到
                                HStack(spacing: 4) {
                                    Image(systemName: "gift").font(.system(size: 9.5)).foregroundStyle(.tertiary)
                                    Text(L("这个套餐没有每月赠送额度")).font(.system(size: 10)).foregroundStyle(.tertiary)
                                }
                                .help(L("官方额度接口里每月赠送额度这一项是空的。目前只看到 Max 套餐有返回。"))
                            }
                            ForEach(usage.extraWindows) { w in WindowBar(w: w, colors: Palette.claude) }
                        }
                        .frame(maxWidth: .infinity)
                    }
                } else if case .failed(let m) = state {
                    ErrorLine(text: m)
                } else {
                    ShimmerPlaceholder().frame(height: 110)
                }
                if case .stale(let m) = state, usage != nil { Text(m).font(.system(size: 10)).foregroundStyle(.orange) }
                MoreSection {
                    if let usage, !usage.breakdown.isEmpty, usage.breakdown.contains(where: { $0.percent > 0 }) {
                        BreakdownBar(rows: usage.breakdown)
                    }
                    RenewalRow(account: account)
                }
                if model.needsReauth.contains(account.id) {
                    HStack(spacing: 8) {
                        Image(systemName: "key.fill").foregroundStyle(.orange)
                        Text(L("登录已失效，需要在浏览器里重新登录一次")).font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        PillButton(title: L("重新授权"), icon: "arrow.triangle.2.circlepath", tint: .orange, prominent: true) {
                            Launcher.run(account.command + " auth login", title: L("%@ 重新授权", account.command))
                        }
                    }
                    .padding(8)
                    .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }
                LaunchRow(account: account)
            }
        }
    }

    private var subtitle: String {
        guard let e = account.email else { return account.command }
        return (model.maskEmails ? Fmt.maskEmail(e) : e) + " · " + account.command
    }
}

/// 一行小进度条：某个模型的单独额度
struct WindowBar: View {
    @Environment(AppModel.self) private var model
    var w: QuotaWindow
    var colors: [Color]
    var body: some View {
        let shown = model.showRemaining ? 100 - w.percent : w.percent
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(quotaTitle(w.title)).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 2)
                Text(model.showRemaining ? L("剩 %d%%", Int(shown.rounded())) : "\(Int(shown.rounded()))%")
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
            }
            FlowBar(fraction: shown / 100, colors: Palette.ring(w.percent, base: colors), height: 5)
            if let r = w.resetsAt { Text(L("%@ 重置", Fmt.shortDate(r))).font(.system(size: 9)).foregroundStyle(.tertiary) }
        }
        .help(L("已用 %d%%", Int(w.percent)))
    }
}

/// 续费日：官方接口不给真实账单日，默认按开通日推算；点一下可以改成账单上的日期
struct RenewalRow: View {
    @Environment(AppModel.self) private var model
    var account: ClaudeAccount
    @State private var editing = false
    @State private var date = Date()

    var body: some View {
        if let r = account.nextRenewal {
            let status = model.profileStatus[account.id]
            let active = status == nil || status == "active"
            Button { date = r; editing = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar").font(.system(size: 10, weight: .semibold)).foregroundStyle(Fmt.daysLeft(r) <= 3 ? .red : .secondary).frame(width: 14)
                    Text(active ? L("下次续费") : L("订阅到期")).font(.system(size: 11)).foregroundStyle(.secondary)
                    Chip(text: account.renewalIsManual ? L("已校正") : L("推算"), color: account.renewalIsManual ? .green : .secondary)
                    Spacer(minLength: 4)
                    Text(L("%@ · 还有 %d 天", Fmt.day(r), Fmt.daysLeft(r))).font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
                    Image(systemName: "pencil").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L("官方接口不提供真实账单日，这里按开通日每月推算。点一下改成你账单上的日期，之后每月自动往后推。"))
            .popover(isPresented: $editing, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L("%@ 的下次续费日", model.nickname(account))).font(.system(size: 13, weight: .bold))
                    Text(L("在 claude.ai → 设置 → 账单 里能看到。保存后每月同一天自动续推。")).font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    DatePicker("", selection: $date, displayedComponents: .date).datePickerStyle(.graphical).labelsHidden()
                    HStack {
                        if account.renewalIsManual {
                            Button(L("恢复推算")) { model.setRenewal(nil, for: account); editing = false }
                        }
                        Spacer()
                        Button(L("取消")) { editing = false }
                        Button(L("保存日期")) { model.setRenewal(date, for: account); editing = false }.keyboardShortcut(.defaultAction)
                    }
                }
                .padding(14)
                .frame(width: 280)
            }
        }
    }
}

struct MoneyBlock: View {
    var m: MoneyQuota
    var claimed: Bool?
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "gift.fill").font(.system(size: 9.5)).foregroundStyle(Palette.money[0])
                Text(quotaTitle(m.title)).font(.system(size: 10.5)).foregroundStyle(.secondary)
                if claimed == true { Chip(text: L("已领取"), color: .green) }
            }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(String(format: "$%.2f", m.remaining)).font(.system(size: 15, weight: .bold, design: .rounded))
                    .contentTransition(.numericText(value: m.remaining))
                Text(L("/ $%.0f 剩余", m.limit)).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            FlowBar(fraction: m.remaining / max(m.limit, 1), colors: m.remaining / max(m.limit, 1) < 0.1 ? Palette.level(95) : Palette.money, height: 5)
            if let r = m.resetsAt {
                Text(L("%@ 重新发放 · 还有 %d 天", Fmt.day(r), Fmt.daysLeft(r))).font(.system(size: 9.5)).foregroundStyle(.secondary)
            }
        }
        .help(L("每月发放一次，用不完不累积。"))
    }
}

struct BreakdownBar: View {
    var rows: [ShareRow]
    static let colors: [String: Color] = ["claude_code": Color(red: 0.95, green: 0.55, blue: 0.4), "cowork": Color(red: 0.55, green: 0.6, blue: 1),
                                          "chat": Color(red: 0.4, green: 0.8, blue: 0.65), "other": .gray]
    @State private var on = false
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L("本周用在哪")).font(.system(size: 10)).foregroundStyle(.secondary)
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(rows.filter { $0.percent > 0 }) { r in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Self.colors[r.id] ?? .gray)
                            .frame(width: max(4, (geo.size.width - 6) * r.percent / 100 * (on ? 1 : 0)))
                    }
                }
            }
            .frame(height: 6)
            HStack(spacing: 10) {
                ForEach(rows.filter { $0.percent > 0 }) { r in
                    HStack(spacing: 4) {
                        Circle().fill(Self.colors[r.id] ?? .gray).frame(width: 6, height: 6)
                        Text("\(r.name) \(Int(r.percent))%").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onAppear { withAnimation(.spring(duration: 0.9).delay(0.3)) { on = true } }
    }
}

struct LaunchRow: View {
    @Environment(AppModel.self) private var model
    var account: ClaudeAccount
    var body: some View {
        HStack(spacing: 6) {
            PillButton(title: L("新会话"), icon: "plus", tint: Provider.claude.tint, prominent: true) {
                launch(.new)
            }
            PillButton(title: L("继续上次"), icon: "arrow.uturn.forward", tint: Provider.claude.tint) {
                launch(.continueLast)
            }
            PillButton(title: L("选会话"), icon: "list.bullet", tint: Provider.claude.tint) {
                launch(.pick)
            }
            Spacer(minLength: 0)
            WorkDirMenu()
        }
    }

    /// 一键开 / 继续 / 恢复会话是完整版功能
    private func launch(_ mode: Launcher.ClaudeMode) {
        guard Pro.shared.hasAccess else { Pro.shared.showPaywall = true; return }
        Launcher.claude(account, mode: mode, dir: model.workDir)
    }
}

/// 选择在哪个文件夹里打开（列出最近用过的项目）
struct WorkDirMenu: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        Menu {
            Section(L("在这个文件夹里打开")) {
                ForEach(recentDirs, id: \.self) { d in
                    Button { model.workDir = d } label: {
                        if Paths.expand(d) == Paths.expand(model.workDir) { Label(Paths.pretty(d), systemImage: "checkmark") } else { Text(Paths.pretty(d)) }
                    }
                }
            }
            Divider()
            Button(L("选择其他文件夹…")) { pick() }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "folder").font(.system(size: 10, weight: .semibold))
                Text(shortName).font(.system(size: 10.5, weight: .medium)).lineLimit(1)
            }
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .fixedSize()
        .help(L("新会话在这个文件夹里打开：%@", Paths.pretty(Paths.expand(model.workDir))))
    }

    private var shortName: String {
        let p = Paths.expand(model.workDir)
        return p == Paths.home ? "~" : (p as NSString).lastPathComponent
    }

    private var recentDirs: [String] {
        var seen = Set<String>()
        var out = ["~"]
        seen.insert(Paths.home)
        for s in model.stats?.sessions ?? [] {
            guard let c = s.cwd, !c.hasPrefix("/private/tmp"), !c.hasPrefix("/tmp"), !c.contains("/scratchpad"), FileManager.default.fileExists(atPath: c) else { continue }
            if seen.insert(c).inserted { out.append(c) }
            if out.count >= 10 { break }
        }
        return out
    }

    private func pick() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.prompt = L("在这里打开")
        NSApp.activate(ignoringOtherApps: true)
        if p.runModal() == .OK, let u = p.url { model.workDir = u.path }
    }
}

// MARK: Codex 卡片

struct CodexCard: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let s = model.codex
        GlassCard(tint: Provider.codex.tint) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(provider: .codex, title: "Codex", plan: s?.planName ?? L("未登录"), subtitle: subtitle(s), state: model.codexState)
                if let s {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(s.windows.prefix(2)) { w in
                            RingGauge(percent: w.percent, colors: Palette.codex, title: L(w.title), resetsAt: w.resetsAt, remaining: model.showRemaining)
                        }
                        VStack(alignment: .leading, spacing: 9) {
                            InfoRow(icon: "arrow.counterclockwise.circle.fill", label: L("免费重置次数"), value: s.resetCredits.map { L("%d 次", $0) } ?? "—", tint: Palette.codex[0])
                            InfoRow(icon: "creditcard.fill", label: L("额外点数"), value: s.creditsBalance.map { $0 == "0" ? "0" : $0 } ?? "—", tint: Palette.codex[1])
                            if let u = s.activeUntil {
                                InfoRow(icon: "calendar", label: L("订阅到期"), value: L("%@ · %d天", Fmt.day(u), Fmt.daysLeft(u)), tint: Fmt.daysLeft(u) <= 3 ? .red : .secondary)
                            }
                            if s.limitReached { Chip(text: L("已触顶，等重置"), color: .red, icon: "hand.raised.fill") }
                        }
                        .frame(maxWidth: .infinity)
                    }
                } else if case .failed(let m) = model.codexState {
                    ErrorLine(text: m)
                } else {
                    ShimmerPlaceholder().frame(height: 100)
                }
                HStack(spacing: 6) {
                    PillButton(title: L("新会话"), icon: "plus", tint: Provider.codex.tint, prominent: true) {
                        Launcher.run("codex", in: model.workDir, title: "codex")
                    }
                    PillButton(title: L("继续上次"), icon: "arrow.uturn.forward", tint: Provider.codex.tint) {
                        Launcher.run("codex resume --last", in: model.workDir, title: "codex")
                    }
                    PillButton(title: L("选会话"), icon: "list.bullet", tint: Provider.codex.tint) {
                        Launcher.run("codex resume", in: model.workDir, title: "codex")
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func subtitle(_ s: CodexStatus?) -> String {
        guard let s else { return "~/.codex" }
        var parts: [String] = []
        if let e = s.email { parts.append(model.maskEmails ? Fmt.maskEmail(e) : e) }
        if s.fromLocalLog { parts.append(L("离线数据 · %@", Fmt.ago(s.fetchedAt))) }
        return parts.joined(separator: " · ")
    }
}

// MARK: Grok 卡片

struct GrokCard: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let g = model.grok
        GlassCard(tint: .gray) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(provider: .grok, title: "Grok Build", plan: g.loggedIn ? GrokProvider.tierName(g.tier) : L("未登录"),
                           subtitle: g.email.map { model.maskEmails ? Fmt.maskEmail($0) : $0 } ?? (g.loggedIn ? "~/.grok" : L("命令行还没登录")),
                           state: !g.loggedIn ? .stale(L("Grok 命令行未登录")) : (g.tokenExpired ? .stale(L("令牌已过期（6 小时有效），打开一次 grok 就会续期")) : .ok))
                if g.loggedIn, g.billingFetchedAt != nil {
                    if let pct = g.usedPercent {
                        HStack(alignment: .top, spacing: 14) {
                            RingGauge(percent: pct, colors: Palette.grok, title: L("本月"), resetsAt: g.periodEnd, remaining: model.showRemaining)
                            VStack(alignment: .leading, spacing: 9) {
                                InfoRow(icon: "dollarsign.circle.fill", label: L("本月包含额度"), value: ((g.monthlyLimitCents ?? 0) / 100).usd)
                                InfoRow(icon: "chart.bar.fill", label: L("已用"), value: ((g.usedCents ?? 0) / 100).usd)
                                if let cap = g.onDemandCapCents, cap > 0 { InfoRow(icon: "bolt.fill", label: L("按量付费上限"), value: (cap / 100).usd) }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle.fill").foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L("这个账号没有包含额度")).font(.system(size: 11.5, weight: .semibold))
                                Text(L("官方账单显示本月包含额度为 $0（未订阅 SuperGrok / X Premium）。已用 %@%@", ((g.usedCents ?? 0) / 100).usd,
                                       g.periodEnd.map { L("，%@ 进入新账期", Fmt.day($0)) } ?? ""))
                                    .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                HStack(spacing: 10) {
                    MiniStat(title: L("今天"), value: model.total([.grok], .today).total)
                    MiniStat(title: L("本周"), value: model.total([.grok], .week).total)
                    MiniStat(title: L("本月"), value: model.total([.grok], .month).total)
                }
                HStack(spacing: 6) {
                    if g.loggedIn {
                        PillButton(title: L("新会话"), icon: "plus", tint: .gray, prominent: true) { Launcher.run("grok", in: model.workDir, title: "grok") }
                        PillButton(title: L("继续上次"), icon: "arrow.uturn.forward", tint: .gray) { Launcher.run("grok --continue", in: model.workDir, title: "grok") }
                    } else {
                        PillButton(title: L("登录 Grok"), icon: "person.crop.circle.badge.plus", tint: .gray, prominent: true) { Launcher.run("grok login", title: "grok login") }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

// MARK: Gemini 卡片（Gemini CLI + Antigravity）

struct GeminiCard: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let g = model.gemini
        let ag = model.antigravity
        GlassCard(tint: Provider.gemini.tint) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(provider: .gemini, title: "Gemini", plan: g?.tierName ?? (g?.loggedIn == true ? L("已登录") : L("未登录")),
                           subtitle: g?.email.map { model.maskEmails ? Fmt.maskEmail($0) : $0 } ?? (GeminiProvider.installed ? L("Gemini CLI 已安装，还没登录") : L("没有安装 Gemini CLI")),
                           state: g?.loggedIn == true ? model.geminiState : .stale(L("Gemini CLI 未登录")))
                if let g, !g.buckets.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(g.buckets.prefix(4)) { w in WindowBar(w: w, colors: Palette.gemini) }
                    }
                } else if g?.loggedIn == true, case .failed(let m) = model.geminiState {
                    ErrorLine(text: m)
                }
                // 反重力（Antigravity）：编辑器开着时读它本机语言服务器里的模型额度
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.and.down.and.sparkles").font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.gemini[1])
                        Text("Antigravity").font(.system(size: 11.5, weight: .semibold))
                        if let p = ag?.plan { Chip(text: p, color: Palette.gemini[1]) }
                        Spacer()
                        Text(agStatus(ag)).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    if let ag, !ag.models.isEmpty {
                        ForEach(ag.models.prefix(6)) { w in WindowBar(w: w, colors: Palette.gemini) }
                    } else {
                        Text(AntigravityProvider.installed ? L("打开 Antigravity 后这里会显示每个模型的剩余额度。") : L("本机没有安装 Antigravity（谷歌的 AI 编辑器）。装好并打开后，这里会显示它的模型额度。"))
                            .font(.system(size: 10)).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(10)
                .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                HStack(spacing: 10) {
                    MiniStat(title: L("今天"), value: model.total([.gemini], .today).total)
                    MiniStat(title: L("本周"), value: model.total([.gemini], .week).total)
                    MiniStat(title: L("本月"), value: model.total([.gemini], .month).total)
                }
                HStack(spacing: 6) {
                    if g?.loggedIn == true {
                        PillButton(title: L("新会话"), icon: "plus", tint: Provider.gemini.tint, prominent: true) { Launcher.run("gemini", in: model.workDir, title: "gemini") }
                        PillButton(title: L("继续上次"), icon: "arrow.uturn.forward", tint: Provider.gemini.tint) { Launcher.run("gemini --resume latest", in: model.workDir, title: "gemini") }
                    } else if GeminiProvider.installed {
                        PillButton(title: L("登录 Gemini"), icon: "person.crop.circle.badge.plus", tint: Provider.gemini.tint, prominent: true) { Launcher.run("gemini", title: "gemini") }
                    }
                    if AntigravityProvider.installed {
                        PillButton(title: L("打开 Antigravity"), icon: "arrow.up.forward.app", tint: Provider.gemini.tint) {
                            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Antigravity.app"))
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func agStatus(_ ag: AntigravityProvider.Status?) -> String {
        guard let ag else { return AntigravityProvider.installed ? L("未运行") : L("未安装") }
        if ag.running { return ag.email.map { model.maskEmails ? Fmt.maskEmail($0) : $0 } ?? L("运行中") }
        return ag.models.isEmpty ? (AntigravityProvider.installed ? L("未运行") : L("未安装")) : L("%@的数据", Fmt.ago(ag.fetchedAt))
    }
}

// MARK: 添加账号

struct AddAccountCard: View {
    @Environment(AppModel.self) private var model
    @State private var hover = false
    @State private var confirm: AccountMaker.Plan?

    var body: some View {
        Menu {
            Section(L("Claude")) {
                Button(L("新增一个 Claude 账号（claude2、claude3…）")) {
                    confirm = AccountMaker.nextPlan(existing: model.accounts)
                    if confirm == nil { model.flash(L("claude2～claude9 都占满了")) }
                }
                ForEach(model.accounts) { a in
                    Button(L("重新登录 %@", model.nickname(a))) { Launcher.run(a.command + " auth login", title: L("%@ 重新授权", a.command)) }
                }
            }
            Section(L("其他工具")) {
                Button(L("登录 Codex（ChatGPT 账号）")) { Launcher.run("codex login", title: "codex login") }
                Button(L("登录 Gemini（Google 账号）")) { Launcher.run("gemini", title: "gemini") }
                Button(L("登录 Grok")) { Launcher.run("grok login", title: "grok login") }
            }
            Section(L("API")) {
                Button(L("添加 API Key（查余额和账单）…")) { model.tab = .billing }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill").font(.system(size: 16)).foregroundStyle(Provider.claude.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("添加账号 / 重新授权")).font(.system(size: 12.5, weight: .semibold))
                    Text(L("新增 Claude 账号、登录 Codex / Gemini / Grok、添加 API Key")).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.primary.opacity(hover ? 0.07 : 0.035)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])).foregroundStyle(.primary.opacity(0.18)))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .onHover { hover = $0 }
        .alert(item: Binding(get: { confirm.map { SettingsTab.PlanBox(plan: $0) } }, set: { confirm = $0?.plan })) { box in
            SettingsTab.createAlert(box, model: model)
        }
    }
}

struct MiniStat: View {
    var title: String
    var value: Int64
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            RollingNumber(value: Double(value), font: .system(size: 14, weight: .bold, design: .rounded))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct ShimmerPlaceholder: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20)) { ctx in
            let ph = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
            RoundedRectangle(cornerRadius: 12)
                .fill(.primary.opacity(0.06))
                .overlay {
                    GeometryReader { geo in
                        LinearGradient(colors: [.clear, .white.opacity(0.18), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 80)
                            .offset(x: CGFloat(ph) * (geo.size.width + 160) - 120)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
        }
    }
}

/// 卡片里的次要信息（本周用在哪、续费日）默认收起，点「更多」展开；展开状态所有卡片共用、会记住
struct MoreSection<Content: View>: View {
    @AppStorage("quotaMoreExpanded") private var expanded = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.spring(duration: 0.3)) { expanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Text(expanded ? L("收起") : L("更多：本周用在哪 · 续费日"))
                    Image(systemName: "chevron.down").rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded { content.transition(.opacity.combined(with: .move(edge: .top))) }
        }
    }
}
