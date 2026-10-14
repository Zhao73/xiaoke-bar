import Foundation

/// Codex（ChatGPT 账号登录）：订阅到期日在 id_token 里，额度走 chatgpt.com 的 wham/usage 接口，
/// 接口失败时退回读最近一次会话日志里的 rate_limits。
enum CodexProvider {
    static var home: String { ProcessInfo.processInfo.environment["CODEX_HOME"] ?? Paths.home + "/.codex" }

    struct Auth { var access: String; var accountId: String?; var email: String?; var plan: String?; var activeUntil: Date? }

    static func auth() -> Auth? {
        guard let d = FileManager.default.contents(atPath: home + "/auth.json"),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let t = j.dict("tokens"), let access = t.str("access_token") else { return nil }
        var a = Auth(access: access, accountId: t.str("account_id"))
        if let idt = t.str("id_token"), let p = JWT.payload(idt) {
            a.email = p.str("email")
            let au = p.dict("https://api.openai.com/auth")
            a.plan = au?.str("chatgpt_plan_type")
            a.activeUntil = ISO.date(au?["chatgpt_subscription_active_until"])
        }
        return a
    }

    static func fetch() async throws -> CodexStatus {
        guard let a = auth() else { throw ProviderError.notLoggedIn }
        var s = CodexStatus(email: a.email, plan: a.plan, activeUntil: a.activeUntil, fetchedAt: Date())
        var h = ["Authorization": "Bearer \(a.access)", "User-Agent": "codex-cli"]
        if let id = a.accountId { h["ChatGPT-Account-Id"] = id }
        do {
            let j = try await HTTP.json("https://chatgpt.com/backend-api/wham/usage", headers: h)
            s.email = j.str("email") ?? s.email
            s.plan = j.str("plan_type") ?? s.plan
            if let rl = j.dict("rate_limit") {
                s.limitReached = (rl["limit_reached"] as? Bool) ?? false
                for (key, fallback) in [("primary_window", "主额度"), ("secondary_window", "副额度")] {
                    guard let w = rl.dict(key), let p = w.num("used_percent") else { continue }
                    s.windows.append(QuotaWindow(id: key, title: windowTitle(seconds: w.num("limit_window_seconds"), fallback: fallback),
                                                 percent: p, resetsAt: ISO.date(w["reset_at"])))
                }
            }
            s.resetCredits = (j.dict("rate_limit_reset_credits")?["available_count"] as? Int)
            s.creditsBalance = j.dict("credits")?.str("balance")
            return s
        } catch {
            if let local = fromLatestLog(base: s) { return local }
            throw error
        }
    }

    static func windowTitle(seconds: Double?, fallback: String) -> String {
        guard let sec = seconds else { return fallback }
        if sec >= 6 * 86400 { return "本周" }
        if sec >= 86400 { return "\(Int(sec / 86400)) 天" }
        return "\(Int(sec / 3600)) 小时"
    }

    /// 最近会话日志里的额度快照（不联网也能显示个大概）
    static func fromLatestLog(base: CodexStatus) -> CodexStatus? {
        let fm = FileManager.default
        let root = home + "/sessions"
        guard let e = fm.enumerator(atPath: root) else { return nil }
        var newest: (String, Date)?
        let cutoff = Date().addingTimeInterval(-7 * 86400)
        while let p = e.nextObject() as? String {
            guard p.hasSuffix(".jsonl") else { continue }
            let full = root + "/" + p
            if let m = (try? fm.attributesOfItem(atPath: full))?[.modificationDate] as? Date, m > cutoff, m > (newest?.1 ?? .distantPast) {
                newest = (full, m)
            }
        }
        guard let path = newest?.0, let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n").reversed() where line.contains("\"rate_limits\"") {
            guard let j = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let rl = j.dict("payload")?.dict("rate_limits") else { continue }
            var s = base
            s.fromLocalLog = true
            s.fetchedAt = newest!.1
            s.plan = rl.str("plan_type") ?? s.plan
            for key in ["primary", "secondary"] {
                guard let w = rl.dict(key), let p = w.num("used_percent") else { continue }
                s.windows.append(QuotaWindow(id: key, title: windowTitle(seconds: w.num("window_minutes").map { $0 * 60 }, fallback: key),
                                             percent: p, resetsAt: ISO.date(w["resets_at"])))
            }
            s.creditsBalance = rl.dict("credits")?.str("balance")
            return s
        }
        return nil
    }
}

/// Grok Build CLI：登录信息在 ~/.grok/auth.json（{"https://auth.x.ai::<client>": {key, email, expires_at…}}）。
/// 额度用 Grok Build 自己调用的 cli-chat-proxy.grok.com/v1/billing（本月包含额度、已用、按量上限、账单周期），
/// 令牌 6 小时过期，过期后要打开一次 grok 让它自己续期，这期间显示上一次读到的数据。
enum GrokProvider {
    static let home = Paths.home + "/.grok"
    static let api = "https://cli-chat-proxy.grok.com/v1"

    static func token() -> (key: String, expires: Date?)? {
        guard let d = FileManager.default.contents(atPath: home + "/auth.json"),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        for v in j.values {
            if let o = v as? [String: Any], let k = o.str("key") { return (k, ISO.date(o["expires_at"])) }
        }
        return nil
    }

    /// 在本地状态上补上官方账单数据
    static func fetchBilling(into base: GrokStatus) async -> GrokStatus {
        var s = base
        guard s.loggedIn, let t = token() else { return s }
        if let e = t.expires, e < Date() { s.tokenExpired = true; return s }
        let h = ["Authorization": "Bearer \(t.key)", "User-Agent": "XiaokeBar/1.0"]
        if let b = try? await HTTP.json(api + "/billing", headers: h), let c = b.dict("config") {
            s.monthlyLimitCents = c.dict("monthlyLimit")?.num("val")
            s.usedCents = c.dict("used")?.num("val")
            s.onDemandCapCents = c.dict("onDemandCap")?.num("val")
            s.periodEnd = ISO.date(c["billingPeriodEnd"])
            s.billingFetchedAt = Date()
        }
        if let u = try? await HTTP.json(api + "/user", headers: h) {
            s.hasCodeAccess = u["hasGrokCodeAccess"] as? Bool
            if s.email == nil { s.email = u.str("email") }
        }
        s.tokenExpired = false
        return s
    }

    static func status() -> GrokStatus {
        var s = GrokStatus(loggedIn: false, fetchedAt: Date())
        guard let d = FileManager.default.contents(atPath: home + "/auth.json"),
              let j = try? JSONSerialization.jsonObject(with: d) else { return s }
        s.loggedIn = true
        // 文件结构没有公开文档，递归找常见字段名
        func walk(_ any: Any) {
            if let dict = any as? [String: Any] {
                for (k, v) in dict {
                    let lk = k.lowercased()
                    if s.tier == nil, lk.contains("subscription_tier") || lk == "tier", let t = v as? String { s.tier = t }
                    if s.email == nil, lk.contains("email"), let e = v as? String, e.contains("@") { s.email = e }
                    walk(v)
                }
            } else if let arr = any as? [Any] { arr.forEach(walk) }
        }
        walk(j)
        return s
    }

    static func tierName(_ t: String?) -> String {
        switch (t ?? "").lowercased() {
        case "supergrok": return "SuperGrok"
        case "supergrok_heavy": return "SuperGrok Heavy"
        case "supergrok_lite": return "SuperGrok Lite"
        case "supergrok_plus": return "SuperGrok Plus"
        case "x_premium": return "X Premium"
        case "x_premium_plus": return "X Premium+"
        case "": return "已登录"
        default: return t!
        }
    }
}
