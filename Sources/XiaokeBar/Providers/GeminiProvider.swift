import Foundation

/// Gemini CLI（Google 账号登录）。
/// 凭证在 ~/.gemini/oauth_creds.json；额度走 Gemini CLI 自己用的 Code Assist 接口：
/// loadCodeAssist 拿套餐和项目，retrieveUserQuota 拿每个模型的剩余比例和重置时间。
/// 刷新令牌需要 Gemini CLI 内置的 OAuth 客户端密钥，运行时从本机安装的 gemini-cli 里读取，不写进源码。
enum GeminiProvider {
    static let home = Paths.home + "/.gemini"
    static let clientId = "681255809395-oo8ft2oprdrnp9e3aqf6av3hmdib135j.apps.googleusercontent.com"
    private static let api = "https://cloudcode-pa.googleapis.com/v1internal"

    /// 内存里的新令牌（Google 刷新后不写回文件，避免和 Gemini CLI 抢着改它的凭证）
    nonisolated(unsafe) private static var memToken: (token: String, expires: Date)?
    nonisolated(unsafe) private static var cachedSecret: String?

    static var credsPath: String { home + "/oauth_creds.json" }
    static var installed: Bool { cliPackageDir() != nil }
    static var loggedIn: Bool { FileManager.default.fileExists(atPath: credsPath) }

    static func fetch() async throws -> GeminiStatus {
        var s = GeminiStatus(loggedIn: loggedIn, fetchedAt: Date())
        guard let d = FileManager.default.contents(atPath: credsPath),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return s }
        if let idt = j.str("id_token"), let p = JWT.payload(idt) { s.email = p.str("email") }
        let token = try await accessToken(j)
        let h = ["Authorization": "Bearer \(token)", "Content-Type": "application/json", "User-Agent": "XiaokeBar/1.0"]
        let meta: [String: Any] = ["ideType": "IDE_UNSPECIFIED", "platform": "PLATFORM_UNSPECIFIED", "pluginType": "GEMINI"]
        let load = try await HTTP.postJSON(api + ":loadCodeAssist", body: ["metadata": meta], headers: h)
        let tier = load.dict("paidTier") ?? load.dict("currentTier")
        s.tierName = tier?.str("name") ?? tier?.str("id")
        let project = load.str("cloudaicompanionProject") ?? load.dict("cloudaicompanionProject")?.str("id")
        if let project {
            let q = try await HTTP.postJSON(api + ":retrieveUserQuota", body: ["project": project], headers: h)
            s.buckets = parseBuckets(q["buckets"] as? [[String: Any]] ?? [])
        }
        return s
    }

    /// 同一个模型可能有输入/输出两个桶，取最紧张的那个
    static func parseBuckets(_ list: [[String: Any]]) -> [QuotaWindow] {
        var best: [String: QuotaWindow] = [:]
        for b in list {
            guard let model = b.str("modelId"), let frac = b.num("remainingFraction") else { continue }
            let used = max(0, min(100, (1 - frac) * 100))
            let w = QuotaWindow(id: model, title: prettyModel(model), percent: used, resetsAt: ISO.date(b["resetTime"]))
            if let old = best[model], old.percent >= used { continue }
            best[model] = w
        }
        return best.values.sorted { $0.title < $1.title }
    }

    static func prettyModel(_ id: String) -> String {
        id.replacingOccurrences(of: "gemini-", with: "Gemini ")
            .replacingOccurrences(of: "-preview", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: " pro", with: " Pro")
            .replacingOccurrences(of: " flash", with: " Flash")
            .replacingOccurrences(of: " lite", with: " Lite")
    }

    private static func accessToken(_ j: [String: Any]) async throws -> String {
        let exp = (j.num("expiry_date")).map { Date(timeIntervalSince1970: $0 / 1000) } ?? .distantPast
        if let at = j.str("access_token"), exp > Date().addingTimeInterval(60) { return at }
        if let m = memToken, m.expires > Date().addingTimeInterval(60) { return m.token }
        guard let rt = j.str("refresh_token") else { throw ProviderError.needsLogin }
        guard let secret = clientSecret() else { throw ProviderError.tokenExpired }
        let form = ["client_id": clientId, "client_secret": secret, "refresh_token": rt, "grant_type": "refresh_token"]
        let r = try await HTTP.postForm("https://oauth2.googleapis.com/token", form: form)
        guard let at = r.str("access_token") else { throw ProviderError.needsLogin }
        memToken = (at, Date().addingTimeInterval(r.num("expires_in") ?? 3000))
        return at
    }

    /// 本机 gemini-cli 安装目录（npm 全局 / Homebrew）
    static func cliPackageDir() -> String? {
        let candidates = [Paths.home + "/.npm-global/lib/node_modules/@google/gemini-cli",
                          "/opt/homebrew/lib/node_modules/@google/gemini-cli",
                          "/usr/local/lib/node_modules/@google/gemini-cli"]
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }

    private static func clientSecret() -> String? {
        if let c = cachedSecret { return c }
        guard let dir = cliPackageDir() else { return nil }
        let fm = FileManager.default
        for sub in ["/bundle", "/node_modules/@google/gemini-cli-core/dist/src/code_assist", ""] {
            guard let names = try? fm.contentsOfDirectory(atPath: dir + sub) else { continue }
            for n in names where n.hasSuffix(".js") {
                guard let text = try? String(contentsOfFile: dir + sub + "/" + n, encoding: .utf8),
                      let r = text.range(of: #"GOCSPX-[A-Za-z0-9_-]{20,}"#, options: .regularExpression) else { continue }
                cachedSecret = String(text[r])
                return cachedSecret
            }
        }
        return nil
    }
}

/// Antigravity（谷歌的「反重力」AI 编辑器）。它运行时会在本机起一个语言服务器进程，
/// 编辑器里看到的模型额度就来自这个进程的 GetUserStatus 接口（只监听 127.0.0.1，需要进程参数里的 csrf 令牌）。
/// 所以只有 Antigravity 开着时才能读到额度；没开时显示上一次读到的数据。
enum AntigravityProvider {
    struct Status: Codable, Hashable {
        var running: Bool
        var email: String?
        var plan: String?
        var models: [QuotaWindow] = []
        var fetchedAt: Date
    }

    static var installed: Bool {
        ["/Applications/Antigravity.app", Paths.home + "/Applications/Antigravity.app"].contains { FileManager.default.fileExists(atPath: $0) }
    }

    static func fetch() async -> Status {
        var s = Status(running: false, fetchedAt: Date())
        guard let (pid, csrf) = findServer() else { return s }
        s.running = true
        let body: [String: Any] = ["metadata": ["ideName": "antigravity", "extensionName": "antigravity", "locale": "en"]]
        for port in listeningPorts(pid: pid) {
            for scheme in ["https", "http"] {
                let url = "\(scheme)://127.0.0.1:\(port)/exa.language_server_pb.LanguageServerService/GetUserStatus"
                let h = ["Content-Type": "application/json", "Connect-Protocol-Version": "1", "X-Codeium-Csrf-Token": csrf]
                guard let j = try? await HTTP.postJSON(url, body: body, headers: h, insecureLocal: true),
                      let u = j.dict("userStatus") else { continue }
                s.email = u.str("email")
                s.plan = u.dict("planStatus")?.dict("planInfo")?.str("planName") ?? u.dict("userTier")?.str("name")
                let configs = u.dict("cascadeModelConfigData")?["clientModelConfigs"] as? [[String: Any]] ?? []
                for c in configs {
                    guard let q = c.dict("quotaInfo"), let frac = q.num("remainingFraction") else { continue }
                    let label = c.str("label") ?? c.dict("modelOrAlias")?.str("model") ?? "model"
                    s.models.append(QuotaWindow(id: label, title: label, percent: max(0, min(100, (1 - frac) * 100)),
                                                resetsAt: ISO.date(q["resetTime"])))
                }
                return s
            }
        }
        return s
    }

    /// 找 Antigravity 的语言服务器进程，取出 --csrf_token 参数
    private static func findServer() -> (Int32, String)? {
        for p in ProcessTable.snapshot() where p.path.contains("Antigravity") && p.path.contains("language_server") {
            let args = ProcessTable.arguments(pid: p.pid)
            if let i = args.firstIndex(of: "--csrf_token"), i + 1 < args.count { return (p.pid, args[i + 1]) }
        }
        return nil
    }

    private static func listeningPorts(pid: Int32) -> [Int] {
        let out = Shell.run("/usr/sbin/lsof", ["-nP", "-a", "-p", "\(pid)", "-iTCP", "-sTCP:LISTEN", "-Fn"], timeout: 4).out
        return out.split(separator: "\n").compactMap { line in
            guard line.hasPrefix("n"), let c = line.lastIndex(of: ":") else { return nil }
            return Int(line[line.index(after: c)...])
        }
    }
}
