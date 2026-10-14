import SwiftUI
import Charts

struct StatsTab: View {
    @Environment(AppModel.self) private var model
    @State private var source: Provider? = nil
    @State private var range: AppModel.Range = .week
    @Namespace private var ns

    private var providers: Set<Provider> { source.map { [$0] } ?? Set(Provider.allCases) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let p = model.scanProgress {
                    ScanBanner(progress: p).staggerIn(0)
                }
                sourcePicker.staggerIn(0)
                hero.staggerIn(1)
                breakdownTiles.staggerIn(2)
                chartCard.staggerIn(3)
                HeatmapCard(values: model.heat(providers), tint: source?.tint ?? Provider.claude.tint).staggerIn(4)
                if source == nil || source == .claude { accountCard.staggerIn(5) }
                topSessions.staggerIn(6)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .scrollIndicators(.never)
    }

    // MARK: 来源 + 时间范围

    private var sourcePicker: some View {
        VStack(spacing: 8) {
            HStack(spacing: 5) {
                sourceButton(nil, L("全部"))
                ForEach(Provider.allCases) { p in sourceButton(p, p.name) }
            }
            HStack(spacing: 0) {
                ForEach(AppModel.Range.allCases) { r in
                    Button {
                        withAnimation(.spring(duration: 0.35)) { range = r }
                    } label: {
                        Text(L(r.rawValue)).font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(range == r ? .primary : .secondary)
                            .frame(maxWidth: .infinity).padding(.vertical, 5)
                            .background {
                                if range == r {
                                    Capsule().fill(.background.opacity(0.9)).shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                                        .matchedGeometryEffect(id: "range", in: ns)
                                }
                            }
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(.primary.opacity(0.07), in: Capsule())
        }
    }

    private func sourceButton(_ p: Provider?, _ title: String) -> some View {
        let on = source == p
        return Button {
            withAnimation(.spring(duration: 0.35)) { source = p }
        } label: {
            HStack(spacing: 5) {
                if let p { Logo(provider: p, size: 13) } else { Image(systemName: "square.stack.3d.up.fill").font(.system(size: 10)) }
                Text(title).font(.system(size: 11, weight: .semibold)).lineLimit(1).fixedSize()
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(Capsule().fill(on ? (p?.tint ?? Provider.claude.tint).opacity(0.22) : Color.primary.opacity(0.06)))
            .overlay(Capsule().strokeBorder(on ? (p?.tint ?? Provider.claude.tint).opacity(0.5) : .clear))
        }
        .buttonStyle(.plain)
    }

    // MARK: 大数字

    private var hero: some View {
        let cur = model.total(providers, range)
        let prev = range == .all ? nil : model.previousSamePeriod(providers, range)
        let compareLabel = ["今天": L("比昨天全天"), "本周": L("比上周同期"), "本月": L("比上月同期")][range.rawValue] ?? L("比上期")
        return GlassCard(tint: source?.tint ?? Provider.claude.tint) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(["今天": L("今天用掉的 Token"), "本周": L("本周用掉的 Token"), "本月": L("本月用掉的 Token")][range.rawValue] ?? L("全部用掉的 Token")).font(.system(size: 11)).foregroundStyle(.secondary)
                    RollingNumber(value: Double(cur.total), font: .system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundStyle(LinearGradient(colors: source == .codex ? Palette.codex : (source == .grok ? [.primary, .secondary] : Palette.claude), startPoint: .leading, endPoint: .trailing))
                    if let prev, prev.total > 0 {
                        let ch = (Double(cur.total) - Double(prev.total)) / Double(prev.total) * 100
                        HStack(spacing: 4) {
                            Image(systemName: ch >= 0 ? "arrow.up.right" : "arrow.down.right").font(.system(size: 9, weight: .bold))
                            Text(String(format: "%@ %@%.0f%%", compareLabel, ch >= 0 ? "+" : "", ch)).font(.system(size: 10.5, weight: .medium))
                        }
                        .foregroundStyle(ch >= 0 ? .orange : .green)
                    }
                }
                Spacer()
                PetView(kind: model.pet.kind, action: model.pet.action, pixel: 1.7)
                    .opacity(0.9)
            }
        }
    }

    private var breakdownTiles: some View {
        let t = model.total(providers, range)
        return HStack(spacing: 8) {
            Tile(title: L("输入"), value: t.i, icon: "arrow.down.circle.fill", color: .blue)
            Tile(title: L("输出"), value: t.o, icon: "arrow.up.circle.fill", color: .pink)
            Tile(title: L("缓存写"), value: t.cw, icon: "square.and.arrow.down.fill", color: .orange)
            Tile(title: L("缓存读"), value: t.cr, icon: "bolt.circle.fill", color: .green)
        }
    }

    // MARK: 每日柱状图

    private var chartCard: some View {
        let days = range == .month || range == .all ? 30 : 14
        let series = model.dailySeries(providers, days: days)
        return GlassCard(tint: .blue) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L("最近 %d 天", days)).font(.system(size: 12, weight: .bold))
                    Spacer()
                    HStack(spacing: 8) {
                        ForEach(Provider.allCases.filter { providers.contains($0) }) { p in
                            HStack(spacing: 3) { Circle().fill(p.tint).frame(width: 6, height: 6); Text(p.name).font(.system(size: 9.5)).foregroundStyle(.secondary) }
                        }
                    }
                }
                DailyChart(series: series)
                    .frame(height: 120)
                    .id(days.description + providers.map(\.rawValue).sorted().joined())
            }
        }
    }

    // MARK: 按账号

    private var accountCard: some View {
        let rows: [(String, Int64)] = model.accounts.compactMap { a in
            guard let id = a.accountUuid else { return nil }
            return (model.nickname(a), model.total([], range, account: id).total)
        }
        let claudeAll = model.total([.claude], range).total
        let known = rows.reduce(0) { $0 + $1.1 }
        let maxV = max(1, rows.map(\.1).max() ?? 1, claudeAll - known)
        return GlassCard(tint: Provider.claude.tint) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L("Claude 各账号")).font(.system(size: 12, weight: .bold))
                    Spacer()
                    Text(L(range.rawValue)).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                ForEach(rows, id: \.0) { r in AccountBar(name: r.0, value: r.1, maxV: maxV) }
                if claudeAll - known > 0 {
                    AccountBar(name: L("没记账号的会话"), value: claudeAll - known, maxV: maxV, dim: true)
                }
                Text(L("能分清账号的是开了 remote-control 的会话，其余算在「没记账号」里。"))
                    .font(.system(size: 9.5)).foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: 本期最耗 token 的会话

    private var topSessions: some View {
        let keys = model.dayKeys(range)
        let list = (model.stats?.sessions ?? []).filter { providers.contains($0.provider) }
            .filter { s in keys == nil || keys!.contains(AppModel.dayFmt.string(from: s.lastActive)) }
            .sorted { $0.tokens.total > $1.tokens.total }
            .prefix(6)
        return GlassCard(tint: .purple) {
            VStack(alignment: .leading, spacing: 8) {
                Text(["今天": L("今天最费 Token 的会话"), "本周": L("本周最费 Token 的会话"), "本月": L("本月最费 Token 的会话")][range.rawValue] ?? L("全部最费 Token 的会话")).font(.system(size: 12, weight: .bold))
                if list.isEmpty { Text(L("这段时间还没有会话")).font(.system(size: 11)).foregroundStyle(.secondary) }
                ForEach(Array(list.enumerated()), id: \.element.id) { i, s in
                    HStack(spacing: 8) {
                        Text("\(i + 1)").font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundStyle(i < 3 ? Provider.claude.tint : .secondary).frame(width: 14)
                        Logo(provider: s.provider, size: 13)
                        Text(model.shown(s.title) ?? "").font(.system(size: 11)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(Double(s.tokens.total).tokenShort).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct ScanBanner: View {
    var progress: Double
    var body: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            VStack(alignment: .leading, spacing: 3) {
                Text(L("第一次统计，正在读本机的会话记录…")).font(.system(size: 11, weight: .medium))
                FlowBar(fraction: progress, colors: Palette.claude, height: 4)
            }
        }
        .padding(10)
        .background(Provider.claude.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct Tile: View {
    var title: String
    var value: Int64
    var icon: String
    var color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon).font(.system(size: 11)).foregroundStyle(color)
            RollingNumber(value: Double(value), font: .system(size: 12.5, weight: .bold, design: .rounded))
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(title).font(.system(size: 9.5)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(color.opacity(0.15)))
    }
}

struct AccountBar: View {
    var name: String
    var value: Int64
    var maxV: Int64
    var dim = false
    @State private var on = false
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(name).font(.system(size: 10.5)).foregroundStyle(dim ? .secondary : .primary)
                Spacer()
                Text(Double(value).tokenShort).font(.system(size: 10.5, weight: .semibold, design: .rounded))
            }
            GeometryReader { g in
                Capsule().fill(.primary.opacity(0.07))
                    .overlay(alignment: .leading) {
                        Capsule().fill(LinearGradient(colors: dim ? [.gray.opacity(0.5), .gray.opacity(0.3)] : Palette.claude, startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(4, g.size.width * Double(value) / Double(maxV) * (on ? 1 : 0)))
                    }
            }
            .frame(height: 5)
        }
        .onAppear { withAnimation(.spring(duration: 0.9).delay(0.2)) { on = true } }
    }
}

struct DailyChart: View {
    var series: [(date: Date, provider: Provider, tokens: Double)]
    @State private var grow: Double = 0
    @State private var hover: Date?

    var body: some View {
        Chart {
            ForEach(Array(series.enumerated()), id: \.offset) { _, s in
                BarMark(x: .value("日期", s.date, unit: .day), y: .value("Token", s.tokens * grow))
                    .foregroundStyle(by: .value("来源", s.provider.name))
                    .cornerRadius(3)
                    .opacity(hover == nil || Calendar.current.isDate(hover!, inSameDayAs: s.date) ? 1 : 0.45)
            }
            if let hover {
                let total = series.filter { Calendar.current.isDate($0.date, inSameDayAs: hover) }.reduce(0) { $0 + $1.tokens }
                RuleMark(x: .value("日期", hover, unit: .day))
                    .foregroundStyle(.primary.opacity(0.15))
                    .annotation(position: .top, alignment: .center, spacing: 2, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        Text("\(Fmt.day(hover)) · \(total.tokenShort)")
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.regularMaterial, in: Capsule())
                    }
            }
        }
        // 配色表必须覆盖所有来源：数据里出现表里没有的名字，Charts 会直接崩溃
        .chartForegroundStyleScale(domain: Provider.allCases.map(\.name), range: Provider.allCases.map { $0 == .grok ? Color.gray : $0.tint })
        .chartLegend(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { v in
                AxisGridLine().foregroundStyle(.primary.opacity(0.06))
                AxisValueLabel { if let d = v.as(Double.self) { Text(d.tokenShort).font(.system(size: 8.5)) } }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: series.count > 60 ? 7 : 3)) { _ in
                AxisValueLabel(format: .dateTime.month(.defaultDigits).day(), centered: true).font(.system(size: 8.5))
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let p):
                            if let plot = proxy.plotFrame {
                                let x = p.x - geo[plot].origin.x
                                hover = proxy.value(atX: x, as: Date.self).map { Calendar.current.startOfDay(for: $0) }
                            }
                        case .ended: hover = nil
                        }
                    }
            }
        }
        .onAppear { withAnimation(.spring(duration: 1.0, bounce: 0.2).delay(0.15)) { grow = 1 } }
    }
}

/// 最近 20 周的热力图，鼠标停留显示当天用量
struct HeatmapCard: View {
    var values: [String: Double]
    var tint: Color
    @State private var hovered: (String, Double)?
    @State private var on = false
    private let weeks = 20

    var body: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let weekday = (cal.component(.weekday, from: today) + 5) % 7      // 周一=0
        let start = cal.date(byAdding: .day, value: -(weeks - 1) * 7 - weekday, to: today)!
        let maxV = max(1, values.values.sorted().dropLast(max(0, values.count / 50)).last ?? 1)   // 去掉最高 2% 防止一天爆量把其他天压成白
        GlassCard(tint: tint) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L("热力图")).font(.system(size: 12, weight: .bold))
                    Spacer()
                    if let h = hovered {
                        Text("\(h.0.dropFirst(5).replacingOccurrences(of: "-", with: "/")) · \(h.1.tokenShort)")
                            .font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
                            .transition(.opacity)
                    } else {
                        Text(L("最近 %d 周", weeks)).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                HStack(alignment: .top, spacing: 3) {
                    ForEach(0..<weeks, id: \.self) { w in
                        VStack(spacing: 3) {
                            ForEach(0..<7, id: \.self) { d in
                                let date = cal.date(byAdding: .day, value: w * 7 + d, to: start)!
                                let key = AppModel.dayFmt.string(from: date)
                                let v = values[key] ?? 0
                                let future = date > today
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(future ? Color.clear : (v == 0 ? Color.primary.opacity(0.06) : tint.opacity(0.22 + 0.78 * min(1, sqrt(v / maxV)))))
                                    .frame(width: 13, height: 13)
                                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.primary.opacity(hovered?.0 == key ? 0.6 : 0), lineWidth: 1.2))
                                    .scaleEffect(on ? 1 : 0.2)
                                    .opacity(on ? 1 : 0)
                                    .animation(.spring(duration: 0.5, bounce: 0.3).delay(Double(w) * 0.018 + Double(d) * 0.01), value: on)
                                    .onHover { inside in
                                        withAnimation(.easeOut(duration: 0.12)) {
                                            if inside { hovered = (key, v) } else if hovered?.0 == key { hovered = nil }
                                        }
                                    }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear { on = true }
    }
}
