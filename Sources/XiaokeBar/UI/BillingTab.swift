import SwiftUI
import Charts

// MARK: 账单页：本机用量按 API 价折算 + 自己添加的 API Key 余额与花费

struct BillingTab: View {
    @Environment(AppModel.self) private var model
    @State private var adding = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                EquivalentCard().staggerIn(0)
                ForEach(Array(model.apiKeys.enumerated()), id: \.element.id) { i, e in
                    ApiKeyCard(entry: e).staggerIn(i + 1)
                }
                if adding {
                    AddApiKeyForm { adding = false }
                        .transition(.scale(scale: 0.95).combined(with: .opacity))
                } else {
                    Button { withAnimation(.spring(duration: 0.35)) { adding = true } } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "key.fill").foregroundStyle(Provider.claude.tint)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(L("添加 API Key")).font(.system(size: 12.5, weight: .semibold))
                                Text(L("Anthropic / OpenAI 管理密钥、OpenRouter、DeepSeek、中转站")).font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.primary.opacity(0.035)))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])).foregroundStyle(.primary.opacity(0.18)))
                    }
                    .buttonStyle(.plain)
                    .staggerIn(model.apiKeys.count + 1)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .scrollIndicators(.never)
    }
}

/// 本月本机所有 Claude 会话如果走 API 要花多少钱（按模型逐个折算）
struct EquivalentCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let (month, today, daily) = compute()
        GlassCard(tint: Palette.money[1]) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "function").foregroundStyle(Palette.money[0])
                    Text(L("订阅用量 · 按 API 价折算")).font(.system(size: 12.5, weight: .bold))
                    Spacer()
                }
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L("本月")).font(.system(size: 10)).foregroundStyle(.secondary)
                        Text(month.usd).font(.system(size: 22, weight: .bold, design: .rounded)).contentTransition(.numericText(value: month))
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L("今天")).font(.system(size: 10)).foregroundStyle(.secondary)
                        Text(today.usd).font(.system(size: 15, weight: .bold, design: .rounded))
                    }
                    Spacer()
                }
                if !daily.isEmpty {
                    Chart(daily, id: \.0) { d in
                        BarMark(x: .value("day", d.0, unit: .day), y: .value("usd", d.1))
                            .foregroundStyle(LinearGradient(colors: Palette.money, startPoint: .top, endPoint: .bottom))
                            .cornerRadius(2)
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis { AxisMarks(position: .trailing) { v in AxisValueLabel { if let d = v.as(Double.self) { Text(d.usd).font(.system(size: 8)) } } } }
                    .frame(height: 60)
                }
                Text(L("只算 Claude（按官方 API 价，缓存写入按 1 小时价）。用订阅时实际不按这个收钱，这里帮你看订阅值不值。"))
                    .font(.system(size: 9.5)).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 会话的每日 token 没有按模型拆开，所以按会话的模型比例分摊到每天
    private func compute() -> (Double, Double, [(Date, Double)]) {
        guard let s = model.stats, let monthKeys = model.dayKeys(.month) else { return (0, 0, []) }
        var byDay: [String: Double] = [:]
        for sess in s.sessions where sess.provider == .claude {
            guard let cost = Pricing.cost(sess.models), sess.tokens.total > 0 else { continue }
            let perToken = cost / Double(sess.tokens.total)
            for (d, t) in sess.days where monthKeys.contains(d) { byDay[d, default: 0] += Double(t.total) * perToken }
        }
        let todayKey = AppModel.dayFmt.string(from: .now)
        let daily = byDay.compactMap { k, v in AppModel.dayFmt.date(from: k).map { ($0, v) } }.sorted { $0.0 < $1.0 }
        return (byDay.values.reduce(0, +), byDay[todayKey] ?? 0, daily)
    }
}

struct ApiKeyCard: View {
    @Environment(AppModel.self) private var model
    var entry: ApiKeyEntry
    @State private var confirmDelete = false

    var body: some View {
        let b = model.apiBills[entry.id]
        let tint = entry.kind.provider?.tint ?? Color(red: 0.4, green: 0.7, blue: 0.9)
        GlassCard(tint: tint) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    if let p = entry.kind.provider { Logo(provider: p, size: 20) } else { Image(systemName: "key.horizontal.fill").foregroundStyle(tint).frame(width: 20) }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.name).font(.system(size: 13, weight: .bold))
                        Text(entry.kind.title + (entry.baseURL.map { " · " + (URL(string: $0)?.host ?? $0) } ?? "")).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let b { StateDot(state: b.error == nil ? .ok : .failed(b.error!)) }
                    Menu {
                        Button(L("立即刷新")) { Task { await model.refreshApiBills() } }
                        Button(L("删除这个 Key"), role: .destructive) { confirmDelete = true }
                    } label: { Image(systemName: "ellipsis.circle").foregroundStyle(.secondary) }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                }
                if let b, b.error == nil {
                    HStack(spacing: 10) {
                        if let bal = b.balance { stat(L("余额"), b.symbol + String(format: "%.2f", bal)) }
                        if let m = b.monthSpend { stat(L("本月花费"), b.symbol + String(format: "%.2f", m)) }
                        if let l = b.limit, l < 1e8 { stat(L("额度上限"), b.symbol + String(format: "%.2f", l)) }
                    }
                    let series = history(b)
                    if series.count > 1 {
                        Chart(series, id: \.0) { d in
                            AreaMark(x: .value("day", d.0, unit: .day), y: .value("v", d.1))
                                .foregroundStyle(LinearGradient(colors: [tint.opacity(0.45), tint.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                                .interpolationMethod(.monotone)
                            LineMark(x: .value("day", d.0, unit: .day), y: .value("v", d.1)).foregroundStyle(tint).interpolationMethod(.monotone)
                        }
                        .chartXAxis(.hidden).chartYAxis(.hidden)
                        .frame(height: 44)
                    }
                    Text(L("%@更新 · 每天自动记一笔，可以看走势", Fmt.ago(b.fetchedAt))).font(.system(size: 9.5)).foregroundStyle(.tertiary)
                } else if let e = b?.error {
                    ErrorLine(text: e)
                } else {
                    ShimmerPlaceholder().frame(height: 40)
                }
            }
        }
        .confirmationDialog(L("删除「%@」？", entry.name), isPresented: $confirmDelete) {
            Button(L("删除"), role: .destructive) { model.removeApiKey(entry) }
        } message: { Text(L("会同时从钥匙串里删掉这个密钥。")) }
    }

    private func stat(_ t: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(t).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(v).font(.system(size: 15, weight: .bold, design: .rounded)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 有逐日明细就画每天花费；只有余额的就画每天记下的余额
    private func history(_ b: ApiBill) -> [(Date, Double)] {
        if b.daily.count > 1 {
            return b.daily.compactMap { k, v in AppModel.dayFmt.date(from: k).map { ($0, v) } }.sorted { $0.0 < $1.0 }
        }
        let h = model.apiHistory.days[entry.id] ?? [:]
        return h.compactMap { k, v in AppModel.dayFmt.date(from: k).flatMap { d in (v.balance ?? v.monthSpend).map { (d, $0) } } }.sorted { $0.0 < $1.0 }
    }
}

struct AddApiKeyForm: View {
    @Environment(AppModel.self) private var model
    var done: () -> Void
    @State private var kind: ApiKeyEntry.Kind = .anthropicAdmin
    @State private var name = ""
    @State private var base = ""
    @State private var key = ""

    var body: some View {
        GlassCard(tint: Provider.claude.tint) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L("添加 API Key")).font(.system(size: 13, weight: .bold))
                Picker(L("类型"), selection: $kind) {
                    ForEach(ApiKeyEntry.Kind.allCases) { Text($0.title).tag($0) }
                }
                Text(kind.hint).font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                TextField(L("名字（例如：公司账号）"), text: $name).textFieldStyle(.roundedBorder)
                if kind.needsBaseURL {
                    TextField(L("站点地址，例如 https://api.example.com"), text: $base).textFieldStyle(.roundedBorder)
                }
                SecureField(L("粘贴 API Key"), text: $key).textFieldStyle(.roundedBorder)
                Text(L("密钥只存在本机钥匙串里，只发给对应的官方地址。")).font(.system(size: 9.5)).foregroundStyle(.tertiary)
                HStack {
                    Spacer()
                    Button(L("取消")) { withAnimation { done() } }
                    Button(L("保存并查询")) { save() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty || (kind.needsBaseURL && !base.hasPrefix("http")))
                }
            }
            .font(.system(size: 12))
            .controlSize(.small)
        }
    }

    private func save() {
        let e = ApiKeyEntry(name: name.isEmpty ? kind.title : name, kind: kind, baseURL: kind.needsBaseURL ? base : nil)
        if model.addApiKey(e, key: key.trimmingCharacters(in: .whitespacesAndNewlines)) {
            withAnimation { done() }
        } else {
            model.flash(L("没能存进钥匙串"))
        }
    }
}
