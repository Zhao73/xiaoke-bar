import Foundation

/// API 账单：用户自己添加的 API Key，查余额和本月花费。
/// 密钥只存在钥匙串里（服务名 XiaokeBar-API），配置里只记名字和类型。
struct ApiKeyEntry: Codable, Identifiable, Hashable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case anthropicAdmin, openaiAdmin, openrouter, deepseek, relay
        var id: String { rawValue }
        var title: String {
            switch self {
            case .anthropicAdmin: return L("Anthropic 管理密钥")
            case .openaiAdmin: return L("OpenAI 管理密钥")
            case .openrouter: return "OpenRouter"
            case .deepseek: return "DeepSeek"
            case .relay: return L("OpenAI 兼容中转站")
            }
        }
        var hint: String {
            switch self {
            case .anthropicAdmin: return L("在 console.anthropic.com → 设置 → Admin Keys 创建，以 sk-ant-admin 开头。能看到整个组织本月每天花了多少。")
            case .openaiAdmin: return L("在 platform.openai.com → Admin keys 创建。能看到组织本月每天花了多少。")
            case .openrouter: return L("普通 API Key 即可，能看到剩余点数和本月用量。")
            case .deepseek: return L("普通 API Key 即可，能看到账户余额。")
            case .relay: return L("one-api / new-api / sub2api 这类中转站，填站点地址和你的 Key，读取额度上限和本月用量。")
            }
        }
        var needsBaseURL: Bool { self == .relay }
        var provider: Provider? {
            switch self { case .anthropicAdmin: .claude; case .openaiAdmin: .codex; default: nil }
        }
    }
    var id = UUID().uuidString
    var name: String
    var kind: Kind
    var baseURL: String?
}

struct ApiBill: Codable, Hashable {
    var balance: Double?          // 剩余（美元或人民币，见 currency）
    var limit: Double?            // 额度上限
    var monthSpend: Double?       // 本月花费
    var daily: [String: Double] = [:]   // 日期 → 当天花费（管理接口才有）
    var currency = "USD"
    var fetchedAt: Date
    var error: String?

    var symbol: String { currency == "CNY" ? "¥" : "$" }
}

enum ApiBilling {
    static let service = "XiaokeBar-API"

    static func saveKey(_ key: String, for e: ApiKeyEntry) -> Bool { Keychain.setPassword(key, service: service, account: e.id) }
    static func key(for e: ApiKeyEntry) -> String? { Keychain.password(service: service, account: e.id) }
    static func deleteKey(for e: ApiKeyEntry) {
        Shell.run("/usr/bin/security", ["delete-generic-password", "-s", service, "-a", e.id], timeout: 4)
    }

    static func fetch(_ e: ApiKeyEntry) async -> ApiBill {
        var b = ApiBill(fetchedAt: Date())
        guard let key = key(for: e) else { b.error = L("钥匙串里找不到这个密钥"); return b }
        do {
            switch e.kind {
            case .anthropicAdmin: try await anthropic(key, &b)
            case .openaiAdmin: try await openai(key, &b)
            case .openrouter: try await openrouter(key, &b)
            case .deepseek: try await deepseek(key, &b)
            case .relay: try await relay(key, base: e.baseURL ?? "", &b)
            }
        } catch {
            if case HTTPError.status(let c, _) = error { b.error = c == 401 || c == 403 ? L("密钥无效或没有权限") : L("服务器返回 %d", c) }
            else { b.error = error.localizedDescription }
        }
        return b
    }

    private static var monthStart: Date { Calendar.current.dateInterval(of: .month, for: .now)!.start }
    private static let dayFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f }()

    /// Anthropic 成本报表：金额是「最小货币单位」的字符串（美分）
    private static func anthropic(_ key: String, _ b: inout ApiBill) async throws {
        let iso = ISO8601DateFormatter()
        var url = "https://api.anthropic.com/v1/organizations/cost_report?starting_at=\(iso.string(from: monthStart))&bucket_width=1d&limit=31"
        let h = ["x-api-key": key, "anthropic-version": "2023-06-01"]
        var total = 0.0
        for _ in 0..<4 {
            let j = try await HTTP.json(url, headers: h)
            for bucket in j["data"] as? [[String: Any]] ?? [] {
                let day = (bucket.str("starting_at")).flatMap(ISO.date).map(dayFmt.string) ?? "?"
                for r in bucket["results"] as? [[String: Any]] ?? [] {
                    let cents = Double(r.str("amount") ?? "") ?? r.num("amount") ?? 0
                    b.daily[day, default: 0] += cents / 100
                    total += cents / 100
                }
            }
            guard (j["has_more"] as? Bool) == true, let next = j.str("next_page") else { break }
            url = "https://api.anthropic.com/v1/organizations/cost_report?starting_at=\(iso.string(from: monthStart))&bucket_width=1d&limit=31&page=\(next)"
        }
        b.monthSpend = total
    }

    private static func openai(_ key: String, _ b: inout ApiBill) async throws {
        let start = Int(monthStart.timeIntervalSince1970)
        var url = "https://api.openai.com/v1/organization/costs?start_time=\(start)&bucket_width=1d&limit=31"
        var total = 0.0
        for _ in 0..<4 {
            let j = try await HTTP.json(url, headers: ["Authorization": "Bearer \(key)"])
            for bucket in j["data"] as? [[String: Any]] ?? [] {
                let day = bucket.num("start_time").map { dayFmt.string(from: Date(timeIntervalSince1970: $0)) } ?? "?"
                for r in bucket["results"] as? [[String: Any]] ?? [] {
                    let v = r.dict("amount")?.num("value") ?? 0
                    b.daily[day, default: 0] += v
                    total += v
                }
            }
            guard (j["has_more"] as? Bool) == true, let next = j.str("next_page") else { break }
            url = "https://api.openai.com/v1/organization/costs?start_time=\(start)&bucket_width=1d&limit=31&page=\(next)"
        }
        b.monthSpend = total
    }

    private static func openrouter(_ key: String, _ b: inout ApiBill) async throws {
        let h = ["Authorization": "Bearer \(key)"]
        if let c = try? await HTTP.json("https://openrouter.ai/api/v1/credits", headers: h), let d = c.dict("data") {
            let total = d.num("total_credits") ?? 0, used = d.num("total_usage") ?? 0
            b.limit = total
            b.balance = total - used
        }
        let k = try await HTTP.json("https://openrouter.ai/api/v1/key", headers: h)
        if let d = k.dict("data") {
            b.monthSpend = d.num("usage_monthly")
            if let today = d.num("usage_daily") { b.daily[dayFmt.string(from: .now)] = today }
            if b.limit == nil { b.limit = d.num("limit") }
            if b.balance == nil, let l = d.num("limit_remaining") { b.balance = l }
        }
    }

    private static func deepseek(_ key: String, _ b: inout ApiBill) async throws {
        let j = try await HTTP.json("https://api.deepseek.com/user/balance", headers: ["Authorization": "Bearer \(key)", "Accept": "application/json"])
        let infos = j["balance_infos"] as? [[String: Any]] ?? []
        if let i = infos.first(where: { $0.str("currency") == "USD" }) ?? infos.first {
            b.currency = i.str("currency") ?? "CNY"
            b.balance = Double(i.str("total_balance") ?? "") ?? i.num("total_balance")
        }
    }

    /// OpenAI 旧版账单接口，one-api / new-api / sub2api 等中转站普遍兼容（total_usage 单位是美分）
    private static func relay(_ key: String, base: String, _ b: inout ApiBill) async throws {
        var root = base.trimmingCharacters(in: .whitespaces)
        while root.hasSuffix("/") { root.removeLast() }
        if root.hasSuffix("/v1") { root.removeLast(3) }
        guard root.hasPrefix("http") else { throw HTTPError.bad }
        let h = ["Authorization": "Bearer \(key)"]
        let sub = try await HTTP.json(root + "/v1/dashboard/billing/subscription", headers: h)
        b.limit = sub.num("hard_limit_usd") ?? sub.num("system_hard_limit_usd")
        let from = dayFmt.string(from: monthStart)
        let to = dayFmt.string(from: Calendar.current.date(byAdding: .day, value: 1, to: .now)!)
        if let u = try? await HTTP.json(root + "/v1/dashboard/billing/usage?start_date=\(from)&end_date=\(to)", headers: h) {
            b.monthSpend = (u.num("total_usage") ?? 0) / 100
            for d in u["daily_costs"] as? [[String: Any]] ?? [] {
                guard let ts = d.num("timestamp") else { continue }
                let sum = (d["line_items"] as? [[String: Any]] ?? []).reduce(0.0) { $0 + ($1.num("cost") ?? 0) } / 100
                b.daily[dayFmt.string(from: Date(timeIntervalSince1970: ts)), default: 0] += sum
            }
        }
        // 很多中转站把「剩余额度」放在 hard_limit_usd 里，同时 total_usage 是历史累计
        if let l = b.limit, let used = b.monthSpend, l < 1e8 { b.balance = max(0, l - used) }
    }
}

/// 每天记一笔账单快照，没有逐日明细的接口（余额类）也能画出走势
struct ApiBillHistory: Codable {
    var days: [String: [String: ApiBill]] = [:]      // entry id → 日期 → 当天最后一次读到的账单

    static let url = Paths.support.appendingPathComponent("api-billing.json")

    static func load() -> ApiBillHistory {
        guard let d = try? Data(contentsOf: url), let h = try? JSONDecoder().decode(ApiBillHistory.self, from: d) else { return ApiBillHistory() }
        return h
    }

    mutating func record(_ b: ApiBill, for id: String) {
        guard b.error == nil else { return }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        days[id, default: [:]][f.string(from: .now)] = b
        if let d = try? JSONEncoder().encode(self) { try? d.write(to: Self.url, options: .atomic) }
    }
}
