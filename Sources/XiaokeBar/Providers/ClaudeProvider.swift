import Foundation

/// 找到本机所有 Claude Code 账号，并读取每个账号的实时额度。
///
/// 账号的来源：
/// - 默认账号：~/.claude + ~/.claude.json，钥匙串条目「Claude Code-credentials」
/// - 其他账号：~/.local/bin 里设置了 CLAUDE_CONFIG_DIR 的启动脚本（如 claude2），
///   钥匙串条目是「Claude Code-credentials-<配置目录 sha256 前 8 位>」，这是 Claude Code 自己的命名规则。
enum ClaudeProvider {
    static let binDirs = ["~/.local/bin", "~/bin"].map(Paths.expand)

    static func discoverAccounts() -> [ClaudeAccount] {
        var list: [ClaudeAccount] = []
        let home = Paths.home
        list.append(load(ClaudeAccount(command: "claude", configDir: home + "/.claude", configJSON: home + "/.claude.json",
                                       keychainService: "Claude Code-credentials", isDefault: true)))
        var seen = Set([home + "/.claude"])
        let fm = FileManager.default
        for dir in binDirs {
            guard let names = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for name in names.sorted() where name.hasPrefix("claude") {
                let path = dir + "/" + name
                guard let attrs = try? fm.attributesOfItem(atPath: path),
                      (attrs[.size] as? Int ?? 0) < 8192,
                      let text = try? String(contentsOfFile: path, encoding: .utf8),
                      let cfg = configDir(in: text) else { continue }
                let resolved = (cfg as NSString).standardizingPath
                guard !seen.contains(resolved), fm.fileExists(atPath: resolved) else { continue }
                seen.insert(resolved)
                list.append(load(ClaudeAccount(command: name, configDir: resolved, configJSON: resolved + "/.claude.json",
                                               keychainService: "Claude Code-credentials-" + Hash.sha256Prefix(resolved),
                                               isDefault: false)))
            }
        }
        return list
    }

    private static func configDir(in script: String) -> String? {
        guard let r = script.range(of: #"CLAUDE_CONFIG_DIR=["']?([^"'\s]+)"#, options: .regularExpression) else { return nil }
        var v = String(script[r]).replacingOccurrences(of: "CLAUDE_CONFIG_DIR=", with: "")
        v = v.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        return Paths.expand(v)
    }

    /// 从 .claude.json 读邮箱、套餐等账号信息（Claude Code 自己缓存的资料）
    static func load(_ base: ClaudeAccount) -> ClaudeAccount {
        var a = base
        guard let data = FileManager.default.contents(atPath: a.configJSON),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return a }
        if let o = j.dict("oauthAccount") {
            a.email = o.str("emailAddress")
            a.accountUuid = o.str("accountUuid")
            a.orgType = o.str("organizationType")
            a.tier = o.str("organizationRateLimitTier") ?? o.str("userRateLimitTier")
            a.subscriptionCreatedAt = ISO.date(o["subscriptionCreatedAt"])
        }
        if let p = j.dict("promoStartupStatusCache"), p.str("accountUuid") == a.accountUuid {
            a.promoClaimed = p["claimed"] as? Bool
        }
        if let n = j["passesLastSeenRemaining"] as? Int { a.passesRemaining = n }
        return a
    }

    struct Token { var access: String; var expiresAt: Date?; var subscription: String?; var tier: String? }

    static func token(for a: ClaudeAccount) -> Token? {
        // 新版 Claude Code 把凭证存在「账户名=当前用户」的条目里，老条目可能残留且已失效，所以先查新的
        let raw = Keychain.password(service: a.keychainService, account: NSUserName())
            ?? Keychain.password(service: a.keychainService)
        guard let raw, let d = raw.data(using: .utf8),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let o = j.dict("claudeAiOauth"), let t = o.str("accessToken") else { return nil }
        return Token(access: t, expiresAt: ISO.date(o["expiresAt"]), subscription: o.str("subscriptionType"), tier: o.str("rateLimitTier"))
    }

    private static func headers(_ t: Token) -> [String: String] {
        ["Authorization": "Bearer \(t.access)", "anthropic-beta": "oauth-2025-04-20", "User-Agent": "XiaokeBar/1.0"]
    }

    static let windowNames: [String: String] = [
        "seven_day_opus": "Opus 每周",
        "seven_day_sonnet": "Sonnet 每周",
        "seven_day_oauth_apps": "第三方应用 每周",
        "seven_day_cowork": "Cowork 每周",
    ]

    /// 已知的按金额计额度。iguana_necktie 是接口里的内部代号，实测是每月赠送的 $250 额度，按月重置。
    static let moneyNames: [String: String] = [
        "iguana_necktie": "每月赠送额度",
        "omelette_promotional": "活动赠送额度",
    ]

    static func fetchUsage(_ a: ClaudeAccount) async throws -> ClaudeUsage {
        guard var t = token(for: a) else { throw ProviderError.notLoggedIn }
        // 令牌过期（这个号一段时间没用）：按 Claude Code 自己的方式续期，再查
        if let exp = t.expiresAt, exp < Date().addingTimeInterval(60) {
            t = try await refresh(a)
        }
        do {
            return parseUsage(try await HTTP.json("https://api.anthropic.com/api/oauth/usage", headers: headers(t)))
        } catch HTTPError.status(401, _) {
            t = try await refresh(a)
            return parseUsage(try await HTTP.json("https://api.anthropic.com/api/oauth/usage", headers: headers(t)))
        }
    }

    // MARK: 令牌续期

    static let tokenURL = "https://platform.claude.com/v1/oauth/token"
    static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"   // Claude Code 的公开 OAuth 客户端 ID

    /// 读出钥匙串原文和它所在的账户名（新版存在「当前用户名」下，老版在「Claude Code」下）
    private static func rawCredentials(_ a: ClaudeAccount) -> (json: [String: Any], account: String)? {
        for acct in [NSUserName(), "Claude Code"] {
            if let raw = Keychain.password(service: a.keychainService, account: acct), let d = raw.data(using: .utf8),
               let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any], j["claudeAiOauth"] != nil {
                return (j, acct)
            }
        }
        return nil
    }

    /// 用刷新令牌换新的访问令牌并写回钥匙串，协议和 Claude Code 一致：
    /// 1. 先在配置目录建 .oauth_refresh.lock 目录（Claude Code 用同一把锁），抢不到说明它正在续期，稍后再来；
    /// 2. 锁内重新读一次钥匙串，如果已经被别的进程续好了就直接用；
    /// 3. 新令牌写回同一条钥匙串，Claude Code 下次读到的就是新的，两边不会互相顶掉。
    static func refresh(_ a: ClaudeAccount) async throws -> Token {
        let lock = a.configDir + "/.oauth_refresh.lock"
        let fm = FileManager.default
        if let attrs = try? fm.attributesOfItem(atPath: lock), let m = attrs[.modificationDate] as? Date, Date().timeIntervalSince(m) > 60 {
            try? fm.removeItem(atPath: lock)   // 超过 1 分钟没人碰的锁是遗留的
        }
        guard (try? fm.createDirectory(atPath: lock, withIntermediateDirectories: false)) != nil else { throw ProviderError.refreshBusy }
        defer { try? fm.removeItem(atPath: lock) }

        guard let (json, acct) = rawCredentials(a), var o = json["claudeAiOauth"] as? [String: Any],
              let rt = o["refreshToken"] as? String else { throw ProviderError.notLoggedIn }
        if let exp = ISO.date(o["expiresAt"]), exp > Date().addingTimeInterval(120), let at = o["accessToken"] as? String {
            return Token(access: at, expiresAt: exp, subscription: o.str("subscriptionType"), tier: o.str("rateLimitTier"))
        }
        let scopes = (o["scopes"] as? [String]) ?? ["user:inference", "user:profile"]
        var req = URLRequest(url: URL(string: tokenURL)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["grant_type": "refresh_token", "refresh_token": rt,
                                                                    "client_id": clientID, "scope": scopes.joined(separator: " ")])
        let (data, resp) = try await HTTP.session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200, let r = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let at = r.str("access_token") else {
            // 400/401 = 刷新令牌本身也失效了，只能重新登录
            throw (code == 400 || code == 401) ? ProviderError.needsLogin : HTTPError.status(code, String(decoding: data.prefix(200), as: UTF8.self))
        }
        let now = Date().timeIntervalSince1970 * 1000
        o["accessToken"] = at
        if let newRT = r.str("refresh_token") { o["refreshToken"] = newRT }
        if let sec = r.num("expires_in") { o["expiresAt"] = Int64(now + sec * 1000) }
        if let sec = r.num("refresh_token_expires_in") { o["refreshTokenExpiresAt"] = Int64(now + sec * 1000) }
        if let sc = r.str("scope") { o["scopes"] = sc.split(separator: " ").map(String.init) }
        var out = json
        out["claudeAiOauth"] = o
        let text = String(decoding: try JSONSerialization.data(withJSONObject: out), as: UTF8.self)
        guard Keychain.setPassword(text, service: a.keychainService, account: acct),
              rawCredentials(a)?.json.dict("claudeAiOauth")?.str("accessToken") == at else {
            throw ProviderError.keychainWrite
        }
        return Token(access: at, expiresAt: ISO.date(o["expiresAt"]), subscription: o.str("subscriptionType"), tier: o.str("rateLimitTier"))
    }

    static func parseUsage(_ j: [String: Any]) -> ClaudeUsage {
        var u = ClaudeUsage(fetchedAt: Date())
        func window(_ key: String, _ title: String) -> QuotaWindow? {
            guard let w = j.dict(key), let p = w.num("utilization") else { return nil }
            return QuotaWindow(id: key, title: title, percent: p, resetsAt: ISO.date(w["resets_at"]))
        }
        u.fiveHour = window("five_hour", "5 小时")
        u.weekly = window("seven_day", "本周")
        for (k, v) in j {
            guard let w = v as? [String: Any] else { continue }
            if let limit = w.num("limit_dollars"), limit > 0 {
                u.money.append(MoneyQuota(title: moneyNames[k] ?? "赠送额度", used: w.num("used_dollars") ?? 0, limit: limit,
                                          resetsAt: ISO.date(w["resets_at"])))
            } else if k != "five_hour" && k != "seven_day", w["utilization"] != nil, let p = w.num("utilization") {
                u.extraWindows.append(QuotaWindow(id: k, title: windowNames[k] ?? k, percent: p, resetsAt: ISO.date(w["resets_at"])))
            }
        }
        // limits 数组里有按模型单独计的周额度（例如 Fable 每周）
        if let limits = j["limits"] as? [[String: Any]] {
            for (i, l) in limits.enumerated() where l.str("kind") == "weekly_scoped" {
                let name = (l.dict("scope")?.dict("model")?.str("display_name")) ?? (l.dict("scope")?.dict("surface")?.str("display_name")) ?? "专属"
                let id = "scoped-\(i)-\(name)"
                if !u.extraWindows.contains(where: { $0.title.hasPrefix(name) }) {
                    u.extraWindows.append(QuotaWindow(id: id, title: "\(name) 每周", percent: l.num("percent") ?? 0, resetsAt: ISO.date(l["resets_at"])))
                }
            }
        }
        u.extraWindows.sort { $0.title < $1.title }
        u.money.sort { $0.title < $1.title }
        if let rows = j.dict("seven_day_breakdown")?["rows"] as? [[String: Any]] {
            u.breakdown = rows.compactMap { r in
                guard let p = r.num("percent") else { return nil }
                let names = ["claude_code": "Claude Code", "chat": "聊天", "cowork": "Cowork", "other": "其他"]
                let key = r.str("key") ?? UUID().uuidString
                return ShareRow(id: key, name: names[key] ?? r.str("display_name") ?? key, percent: p)
            }
        }
        u.extraUsageEnabled = (j.dict("extra_usage")?["is_enabled"] as? Bool) ?? false
        return u
    }

    /// Claude Code 自己缓存的最近一次额度（令牌过期、没法实时查询时用来兜底）
    static func cachedUsage(_ a: ClaudeAccount) -> ClaudeUsage? {
        guard let data = FileManager.default.contents(atPath: a.configJSON),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let c = j.dict("cachedUsageUtilization"), let u = c.dict("utilization") else { return nil }
        if let acc = c.str("accountUuid"), let mine = a.accountUuid, acc != mine { return nil }
        var usage = parseUsage(u)
        usage.fetchedAt = ISO.date(c["fetchedAtMs"]) ?? .distantPast
        return usage
    }

    /// 实时资料（套餐、订阅状态）。比 .claude.json 里的缓存新。
    static func fetchProfile(_ a: ClaudeAccount) async throws -> (orgType: String?, tier: String?, status: String?, subCreated: Date?, email: String?) {
        guard let t = token(for: a) else { throw ProviderError.notLoggedIn }
        let j = try await HTTP.json("https://api.anthropic.com/api/oauth/profile", headers: headers(t))
        let org = j.dict("organization")
        return (org?.str("organization_type"), org?.str("rate_limit_tier"), org?.str("subscription_status"),
                ISO.date(org?["subscription_created_at"]), j.dict("account")?.str("email"))
    }
}

enum ProviderError: Error, LocalizedError {
    case notLoggedIn, tokenExpired, needsLogin, refreshBusy, keychainWrite
    var errorDescription: String? {
        switch self {
        case .notLoggedIn: return L("这个账号还没登录")
        case .tokenExpired: return L("登录令牌过期了")
        case .needsLogin: return L("登录已彻底失效，点「重新授权」在浏览器里登录一次")
        case .refreshBusy: return L("Claude Code 正在续期登录，稍后自动重试")
        case .keychainWrite: return L("新令牌没能写回钥匙串，请点「重新授权」")
        }
    }
}
