import Foundation

/// 四类 token：输入 / 输出 / 缓存写入 / 缓存读取
struct Tok: Codable, Hashable {
    var i: Int64 = 0, o: Int64 = 0, cw: Int64 = 0, cr: Int64 = 0
    var total: Int64 { i + o + cw + cr }
    static func += (l: inout Tok, r: Tok) { l.i += r.i; l.o += r.o; l.cw += r.cw; l.cr += r.cr }
}

/// 每个会话文件扫描后的结果。文件只追加不改写，所以记住读到哪里，下次从那里接着读。
struct FileRecord: Codable {
    var provider: Provider
    var offset: UInt64 = 0
    var size: UInt64 = 0
    var mtime: Double = 0
    var sessionId: String = ""
    var title: String?
    var lastPrompt: String?
    var cwd: String?
    var account: String?
    var model: String?
    var firstTs: Double?
    var lastTs: Double?
    var days: [String: Tok] = [:]
    var recentKeys: [String] = []     // Claude：同一条回复会按内容块写多行，用 消息id+请求id 去重
    var prevTotal: Tok?               // Codex：日志里是累计值，用差值算每次新增
    var isSub = false                 // 子代理的记录，算进父会话
    var models: [String: Tok] = [:]   // 按模型分开的 token（折算 API 费用要按模型算）
    var turns = 0                     // 模型回复次数
    var tools = 0                     // 工具调用次数
    var costUSD: Double?              // 官方记录的真实花费（目前只有 Grok 有）

    init(provider: Provider) { self.provider = provider }

    /// 新加的字段用 decodeIfPresent，旧版缓存（v3）也能读进来
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        provider = try c.decode(Provider.self, forKey: .provider)
        offset = try c.decodeIfPresent(UInt64.self, forKey: .offset) ?? 0
        size = try c.decodeIfPresent(UInt64.self, forKey: .size) ?? 0
        mtime = try c.decodeIfPresent(Double.self, forKey: .mtime) ?? 0
        sessionId = try c.decodeIfPresent(String.self, forKey: .sessionId) ?? ""
        title = try c.decodeIfPresent(String.self, forKey: .title)
        lastPrompt = try c.decodeIfPresent(String.self, forKey: .lastPrompt)
        cwd = try c.decodeIfPresent(String.self, forKey: .cwd)
        account = try c.decodeIfPresent(String.self, forKey: .account)
        model = try c.decodeIfPresent(String.self, forKey: .model)
        firstTs = try c.decodeIfPresent(Double.self, forKey: .firstTs)
        lastTs = try c.decodeIfPresent(Double.self, forKey: .lastTs)
        days = try c.decodeIfPresent([String: Tok].self, forKey: .days) ?? [:]
        recentKeys = try c.decodeIfPresent([String].self, forKey: .recentKeys) ?? []
        prevTotal = try c.decodeIfPresent(Tok.self, forKey: .prevTotal)
        isSub = try c.decodeIfPresent(Bool.self, forKey: .isSub) ?? false
        models = try c.decodeIfPresent([String: Tok].self, forKey: .models) ?? [:]
        turns = try c.decodeIfPresent(Int.self, forKey: .turns) ?? 0
        tools = try c.decodeIfPresent(Int.self, forKey: .tools) ?? 0
        costUSD = try c.decodeIfPresent(Double.self, forKey: .costUSD)
    }
}

struct ScanCache: Codable {
    var version = 4
    var files: [String: FileRecord] = [:]
}

struct SessionSummary: Identifiable, Hashable {
    var id: String { provider.rawValue + ":" + sessionId }
    var provider: Provider
    var sessionId: String
    var title: String
    var cwd: String?
    var account: String?
    var model: String?
    var lastActive: Date
    var tokens: Tok
    var path: String?                 // 主会话记录文件
    var bytes: UInt64 = 0             // 会话记录（含子代理）占的磁盘空间
    var files = 0
    var firstActive: Date?
    var days: [String: Tok] = [:]
    var models: [String: Tok] = [:]
    var turns = 0
    var tools = 0
    var costUSD: Double?

    /// 缓存命中率：读缓存占全部输入的比例
    var cacheHitRate: Double? {
        let input = tokens.i + tokens.cw + tokens.cr
        return input > 0 ? Double(tokens.cr) / Double(input) : nil
    }
}

struct StatsSnapshot {
    /// provider -> 本地日期(yyyy-MM-dd) -> token
    var days: [Provider: [String: Tok]] = [:]
    /// Claude 账号 uuid -> 日期 -> token（只有开启了 remote-control 的会话能知道属于哪个账号）
    var claudeAccountDays: [String: [String: Tok]] = [:]
    var sessions: [SessionSummary] = []
    var recentFiles: [String] = []
    var scannedAt = Date()
}

final class TokenScanner {
    private let cacheURL = Paths.support.appendingPathComponent("scan-cache.json")
    private var cache = ScanCache()
    private let lock = NSLock()

    init() {
        guard let d = try? Data(contentsOf: cacheURL), let c = try? JSONDecoder().decode(ScanCache.self, from: d) else { return }
        if c.version == 4 {
            cache = c
        } else if c.version == 3 {
            // 旧版缓存升级：先备份；已经被删掉的会话文件保留历史统计（重扫不到了），还在的文件重扫一遍补上新字段
            try? d.write(to: cacheURL.deletingLastPathComponent().appendingPathComponent("scan-cache.v3.bak.json"), options: .atomic)
            let fm = FileManager.default
            cache = ScanCache()
            for (path, rec) in c.files where !fm.fileExists(atPath: path) { cache.files[path] = rec }
            migratedHistory = cache.files.count
        }
    }

    /// 从旧缓存里保住的、文件已删除的会话数
    private(set) var migratedHistory = 0

    /// 有可用缓存就是增量扫描；只有迁移来的历史记录时，现存文件还要整扫一遍，仍算首次
    var hasCache: Bool { cache.files.count > migratedHistory }

    // MARK: 文件发现

    /// 热扫描的路径要和全量扫描时记下的写法一模一样（软链接展开后的），否则同一个文件会被记两份、token 重复计算。
    /// 有任何一个对不上（新开的会话还没被全量扫到），返回 nil 让调用方退回全量扫描
    private func canonical(_ list: [(String, Provider)]) -> [(String, Provider)]? {
        lock.lock(); defer { lock.unlock() }
        var out: [(String, Provider)] = []
        for (p, prov) in list where prov == .claude || prov == .codex {
            if cache.files[p] != nil { out.append((p, prov)); continue }
            let real = (p as NSString).resolvingSymlinksInPath
            guard cache.files[real] != nil else { return nil }
            out.append((real, prov))
        }
        return out
    }

    private var dirty = false
    private var lastSave = Date()

    private func claudeRoots() -> [String] {
        // 多个账号的 projects 可能是软链接到同一处，按真实路径去重
        var roots = Set<String>()
        for a in ClaudeProvider.discoverAccounts() {
            let p = a.configDir + "/projects"
            let real = (p as NSString).resolvingSymlinksInPath
            if FileManager.default.fileExists(atPath: real) { roots.insert(real) }
        }
        return Array(roots)
    }

    private func listFiles() -> [(String, Provider)] {
        var out: [(String, Provider)] = []
        let fm = FileManager.default
        for root in claudeRoots() {
            guard let e = fm.enumerator(atPath: root) else { continue }
            while let p = e.nextObject() as? String { if p.hasSuffix(".jsonl") { out.append((root + "/" + p, .claude)) } }
        }
        for sub in ["/sessions", "/archived_sessions"] {
            let root = CodexProvider.home + sub
            guard let e = fm.enumerator(atPath: root) else { continue }
            while let p = e.nextObject() as? String { if p.hasSuffix(".jsonl") { out.append((root + "/" + p, .codex)) } }
        }
        // Gemini CLI：~/.gemini/tmp/<项目>/chats/session-*.json(l)
        let gem = GeminiProvider.home + "/tmp"
        if let e = fm.enumerator(atPath: gem) {
            while let p = e.nextObject() as? String {
                if p.contains("/chats/session-"), p.hasSuffix(".json") || p.hasSuffix(".jsonl") { out.append((gem + "/" + p, .gemini)) }
            }
        }
        let groot = GrokProvider.home + "/sessions"
        if let e = fm.enumerator(atPath: groot) {
            while let p = e.nextObject() as? String { if p.hasSuffix("/usage.json") { out.append((groot + "/" + p, .grok)) } }
        }
        return out
    }

    // MARK: 扫描

    /// 增量扫描并汇总。首次几 GB 日志需要十几秒，之后通常不到 1 秒。
    /// only：只扫这几个文件（有会话在跑时的热扫描，不用把几千个会话文件都列一遍）
    func scan(only: [(String, Provider)]? = nil, progress: ((Double) -> Void)? = nil) -> StatsSnapshot {
        let files = only.flatMap(canonical) ?? listFiles()
        let fm = FileManager.default
        var jobs: [(String, Provider, FileRecord, UInt64, Double)] = []
        var alive = Set<String>()
        for (path, prov) in files {
            alive.insert(path)
            guard let a = try? fm.attributesOfItem(atPath: path) else { continue }
            let size = (a[.size] as? NSNumber)?.uint64Value ?? 0
            let mtime = (a[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            let old = cache.files[path]
            if let old, old.size == size, old.mtime == mtime { continue }
            var rec = old ?? FileRecord(provider: prov)
            // 文件变小了（被重写），从头来；Grok 的 usage.json 每次整份重写
            if size < rec.offset || prov == .grok || prov == .gemini { rec = FileRecord(provider: prov) }
            jobs.append((path, prov, rec, size, mtime))
        }
        let total = max(1, jobs.count)
        var done = 0
        let queue = DispatchQueue(label: "scan.results")
        var results: [(String, FileRecord)] = []
        let codexTitles = jobs.contains { $0.1 == .codex } ? loadCodexTitles() : [:]
        DispatchQueue.concurrentPerform(iterations: jobs.count) { idx in
            let (path, prov, rec, size, mtime) = jobs[idx]
            var r: FileRecord
            switch prov {
            case .claude: r = scanClaude(path: path, rec: rec)
            case .codex: r = scanCodex(path: path, rec: rec, titles: codexTitles)
            case .grok: r = scanGrok(path: path)
            case .gemini: r = scanGemini(path: path)
            }
            r.size = size
            r.mtime = mtime
            queue.sync {
                results.append((path, r))
                done += 1
                if done % 20 == 0 { progress?(Double(done) / Double(total)) }
            }
        }
        lock.lock()
        for (p, r) in results { cache.files[p] = r }
        // 已删除的会话文件：保留统计（历史用量不该因为 Claude Code 清理旧记录而消失），只是不再重扫
        _ = alive
        let snap = summarize()
        lock.unlock()
        // 缓存文件有好几 MB：有变化才写，而且热扫描时最多 5 分钟写一次。
        // 读取位置和累计数是一起存的，就算没来得及写、下次从旧位置重读也不会重复计数
        if !jobs.isEmpty { dirty = true }
        if dirty, only == nil || Date().timeIntervalSince(lastSave) > 300 {
            if let d = try? JSONEncoder().encode(cache) { try? d.write(to: cacheURL, options: .atomic) }
            dirty = false
            lastSave = Date()
        }
        return snap
    }

    private func summarize() -> StatsSnapshot {
        var s = StatsSnapshot()
        var sessions: [String: SessionSummary] = [:]
        var recent: [(String, Double)] = []
        for (path, r) in cache.files {
            for (day, t) in r.days {
                s.days[r.provider, default: [:]][day, default: Tok()] += t
                if r.provider == .claude, let acc = r.account {
                    s.claudeAccountDays[acc, default: [:]][day, default: Tok()] += t
                }
            }
            if r.provider == .claude { recent.append((path, r.mtime)) }
            guard !r.sessionId.isEmpty else { continue }
            let key = r.provider.rawValue + ":" + r.sessionId
            var tok = Tok()
            for t in r.days.values { tok += t }
            let last = Date(timeIntervalSince1970: r.lastTs ?? r.mtime)
            let first = r.firstTs.map { Date(timeIntervalSince1970: $0) }
            var ex = sessions[key] ?? SessionSummary(provider: r.provider, sessionId: r.sessionId,
                                                     title: r.cwd.map { "\(r.provider.name) · " + (($0 as NSString).lastPathComponent) } ?? L("未命名会话"),
                                                     cwd: r.cwd, account: r.account, model: r.model, lastActive: last, tokens: Tok())
            ex.tokens += tok
            if last > ex.lastActive { ex.lastActive = last }
            if let f = first, f < (ex.firstActive ?? .distantFuture) { ex.firstActive = f }
            ex.bytes += r.size
            ex.files += 1
            ex.turns += r.turns
            ex.tools += r.tools
            if let c = r.costUSD { ex.costUSD = (ex.costUSD ?? 0) + c }
            for (d, t) in r.days { ex.days[d, default: Tok()] += t }
            for (m, t) in r.models { ex.models[m, default: Tok()] += t }
            if !r.isSub {
                if let t = r.title ?? r.lastPrompt { ex.title = t }
                ex.path = path
                ex.cwd = r.cwd ?? ex.cwd
                ex.account = r.account ?? ex.account
                ex.model = r.model ?? ex.model
            }
            sessions[key] = ex
        }
        s.sessions = sessions.values.filter { $0.tokens.total > 0 }.sorted { $0.lastActive > $1.lastActive }
        s.recentFiles = recent.sorted { $0.1 > $1.1 }.prefix(12).map(\.0)
        return s
    }

    // MARK: 逐行读取（按块读，不把几百 MB 的文件一次读进内存）

    private func forEachLine(path: String, from offset: UInt64, _ body: (UnsafeRawBufferPointer) -> Void) -> UInt64 {
        guard let fh = FileHandle(forReadingAtPath: path) else { return offset }
        defer { try? fh.close() }
        do { try fh.seek(toOffset: offset) } catch { return offset }
        var pos = offset
        var carry = Data()
        while true {
            guard let chunk = try? fh.read(upToCount: 4 << 20), !chunk.isEmpty else { break }
            var buf = carry
            buf.append(chunk)
            var consumed = 0
            buf.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }
                var start = 0
                let n = raw.count
                while start < n {
                    guard let nl = memchr(base + start, 0x0A, n - start) else { break }
                    let end = base.distance(to: UnsafeRawPointer(nl))
                    body(UnsafeRawBufferPointer(start: base + start, count: end - start))
                    start = end + 1
                }
                consumed = start
            }
            pos += UInt64(consumed)
            carry = consumed < buf.count ? buf.subdata(in: consumed..<buf.count) : Data()
        }
        // 最后一行还没写完（没有换行），留到下次再读
        return pos
    }

    // MARK: Claude

    fileprivate func scanClaude(path: String, rec: FileRecord) -> FileRecord {
        var r = rec
        if r.sessionId.isEmpty {
            let url = URL(fileURLWithPath: path)
            if path.contains("/subagents/") {
                r.isSub = true
                r.sessionId = url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
            } else {
                r.sessionId = url.deletingPathExtension().lastPathComponent
            }
        }
        var seen = Set(r.recentKeys)
        var recent = r.recentKeys
        let startOffset = r.offset
        let newOffset = forEachLine(path: path, from: startOffset) { line in
            if r.cwd == nil, let v = Bytes.stringValue(line, key: "\"cwd\":\"") { r.cwd = v }
            if Bytes.contains(line, "\"type\":\"assistant\"") {
                guard let usage = Bytes.lastObject(line, key: "\"usage\":{\"input_tokens\"") ?? Bytes.lastObject(line, key: "\"usage\":{"),
                      let u = try? JSONSerialization.jsonObject(with: usage) as? [String: Any],
                      let ts = Bytes.lastStringValue(line, key: "\"timestamp\":\"") else { return }
                let key = (Bytes.stringValue(line, key: "\"id\":\"msg_") ?? "") + ":" + (Bytes.lastStringValue(line, key: "\"requestId\":\"") ?? "")
                if key != ":" {
                    if seen.contains(key) { return }
                    seen.insert(key); recent.append(key)
                    if recent.count > 64 { let drop = recent.removeFirst(); seen.remove(drop) }
                }
                var t = Tok()
                t.i = Int64(u.num("input_tokens") ?? 0)
                t.o = Int64(u.num("output_tokens") ?? 0)
                t.cw = Int64(u.num("cache_creation_input_tokens") ?? 0)
                t.cr = Int64(u.num("cache_read_input_tokens") ?? 0)
                guard t.total > 0, let (day, epoch) = DayKey.parse(ts) else { return }
                r.days[day, default: Tok()] += t
                if r.firstTs == nil { r.firstTs = epoch }
                if epoch > (r.lastTs ?? 0) { r.lastTs = epoch }
                if let m = Bytes.stringValue(line, key: "\"model\":\"") { r.model = m }
                r.models[r.model ?? "unknown", default: Tok()] += t
                r.turns += 1
                r.tools += Bytes.count(line, "\"type\":\"tool_use\"")
            } else if Bytes.contains(line, "\"type\":\"ai-title\"") {
                r.title = Bytes.stringValue(line, key: "\"aiTitle\":\"").map(Bytes.unescape)
            } else if Bytes.contains(line, "\"type\":\"custom-title\"") {
                if let t = Bytes.stringValue(line, key: "\"customTitle\":\"") { r.title = Bytes.unescape(t) }
            } else if Bytes.contains(line, "\"type\":\"last-prompt\"") {
                r.lastPrompt = Bytes.stringValue(line, key: "\"lastPrompt\":\"").map { String(Bytes.unescape($0).prefix(60)) }
            } else if Bytes.contains(line, "\"type\":\"bridge-session\"") {
                if let acc = Bytes.stringValue(line, key: "\"ownerAccountUuid\":\"") { r.account = acc }
            }
        }
        r.offset = newOffset
        r.recentKeys = recent
        return r
    }

    // MARK: Codex

    private func loadCodexTitles() -> [String: String] {
        var map: [String: String] = [:]
        guard let text = try? String(contentsOfFile: CodexProvider.home + "/session_index.jsonl", encoding: .utf8) else { return map }
        for line in text.split(separator: "\n") {
            guard let j = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let id = j.str("id"), let name = j.str("thread_name") else { continue }
            map[id] = name
        }
        return map
    }

    private func scanCodex(path: String, rec: FileRecord, titles: [String: String]) -> FileRecord {
        var r = rec
        let startOffset = r.offset
        let newOffset = forEachLine(path: path, from: startOffset) { line in
            if r.sessionId.isEmpty, Bytes.contains(line, "\"type\":\"session_meta\"") {
                r.sessionId = Bytes.stringValue(line, key: "\"session_id\":\"") ?? Bytes.stringValue(line, key: "\"id\":\"") ?? ""
                r.cwd = Bytes.stringValue(line, key: "\"cwd\":\"")
                r.account = Bytes.stringValue(line, key: "\"creator_account_id\":\"")
                return
            }
            if Bytes.contains(line, "\"type\":\"turn_context\"") {
                r.model = Bytes.stringValue(line, key: "\"model\":\"") ?? r.model
                return
            }
            if Bytes.contains(line, "\"type\":\"function_call\"") || Bytes.contains(line, "\"type\":\"custom_tool_call\"") {
                if Bytes.contains(line, "\"type\":\"response_item\"") { r.tools += 1 }
                return
            }
            if Bytes.contains(line, "\"type\":\"task_complete\"") { r.turns += 1; return }
            if r.lastPrompt == nil, Bytes.contains(line, "\"type\":\"user_message\"") {
                if let m = Bytes.stringValue(line, key: "\"message\":\"") { r.lastPrompt = String(Bytes.unescape(m).prefix(60)) }
                return
            }
            guard Bytes.contains(line, "\"type\":\"token_count\""),
                  let obj = Bytes.lastObject(line, key: "\"total_token_usage\":{"),
                  let u = try? JSONSerialization.jsonObject(with: obj) as? [String: Any],
                  let ts = Bytes.stringValue(line, key: "\"timestamp\":\""), let (day, epoch) = DayKey.parse(ts) else { return }
            // OpenAI 的 input_tokens 已经包含缓存命中部分，拆开存，和 Claude 的口径对齐
            let cached = Int64(u.num("cached_input_tokens") ?? 0)
            var cur = Tok()
            cur.i = Int64(u.num("input_tokens") ?? 0) - cached
            cur.o = Int64(u.num("output_tokens") ?? 0)
            cur.cr = cached
            let prev = r.prevTotal ?? Tok()
            guard cur.total > prev.total else { return }
            let delta = Tok(i: max(0, cur.i - prev.i), o: max(0, cur.o - prev.o), cw: 0, cr: max(0, cur.cr - prev.cr))
            r.prevTotal = cur
            r.days[day, default: Tok()] += delta
            r.models[r.model ?? "unknown", default: Tok()] += delta
            if r.firstTs == nil { r.firstTs = epoch }
            if epoch > (r.lastTs ?? 0) { r.lastTs = epoch }
        }
        r.offset = newOffset
        if !r.sessionId.isEmpty, let t = titles[r.sessionId] { r.title = t }
        if r.title == nil, r.lastPrompt == nil, let c = r.cwd { r.title = "Codex · " + (c as NSString).lastPathComponent }
        return r
    }

    // MARK: Grok

    private func scanGrok(path: String) -> FileRecord {
        var r = FileRecord(provider: .grok)
        let dir = URL(fileURLWithPath: path).deletingLastPathComponent()
        r.sessionId = dir.lastPathComponent
        guard let d = FileManager.default.contents(atPath: path),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return r }
        r.model = j.dict("session")?.str("primaryModelId")
        if let turns = j["turns"] as? [[String: Any]] {
            for t in turns {
                guard let ended = ISO.date(t["endedAt"]) else { continue }
                let day = DayKey.local(ended)
                let cached = Int64(t.num("cachedReadTokens") ?? 0)
                var tok = Tok()
                tok.i = Int64(t.num("inputTokens") ?? 0) - cached
                tok.o = Int64(t.num("outputTokens") ?? 0)
                tok.cw = Int64(t.num("cacheCreationTokens") ?? 0)
                tok.cr = cached
                r.days[day, default: Tok()] += tok
                r.models[t.str("primaryModelId") ?? r.model ?? "grok", default: Tok()] += tok
                r.turns += 1
                // costUsdTicks：xAI 记录的真实花费，1 tick = 1e-10 美元
                if let ticks = t.num("costUsdTicks") { r.costUSD = (r.costUSD ?? 0) + ticks / 1e10 }
                let e = ended.timeIntervalSince1970
                if r.firstTs == nil { r.firstTs = e }
                if e > (r.lastTs ?? 0) { r.lastTs = e }
            }
        }
        if let sd = FileManager.default.contents(atPath: dir.appendingPathComponent("summary.json").path),
           let sj = try? JSONSerialization.jsonObject(with: sd) as? [String: Any] {
            r.title = sj.str("session_summary")
            r.cwd = sj.dict("info")?.str("cwd")
        }
        return r
    }

    // MARK: Gemini

    /// Gemini CLI 的会话记录：整份 JSON（旧版）或每行一条（新版，同一条消息更新时会再写一行）。
    /// 按消息 id 去重，只认 type=gemini 且带 tokens 的回复。
    private func scanGemini(path: String) -> FileRecord {
        var r = FileRecord(provider: .gemini)
        guard let data = FileManager.default.contents(atPath: path) else { return r }
        var messages: [[String: Any]] = []
        if let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            r.sessionId = j.str("sessionId") ?? ""
            messages = j["messages"] as? [[String: Any]] ?? []
        } else {
            for line in data.split(separator: 0x0A) {
                guard let j = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { continue }
                if r.sessionId.isEmpty, let sid = j.str("sessionId") { r.sessionId = sid }
                if let ms = j["messages"] as? [[String: Any]] { messages += ms } else if j["type"] != nil { messages.append(j) }
            }
        }
        if r.sessionId.isEmpty { r.sessionId = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent }
        var byId: [String: [String: Any]] = [:]
        var order: [String] = []
        for (i, m) in messages.enumerated() {
            let id = m.str("id") ?? "#\(i)"
            if byId[id] == nil { order.append(id) }
            byId[id] = m
        }
        for id in order {
            guard let m = byId[id] else { continue }
            if m.str("type") == "user", r.lastPrompt == nil, let c = m["content"] as? String { r.lastPrompt = String(c.prefix(60)) }
            guard m.str("type") == "gemini", let t = m.dict("tokens"), let ts = ISO.date(m["timestamp"]) else { continue }
            // promptTokenCount 已经包含缓存命中，拆开存，和 Claude 的口径对齐
            let cached = Int64(t.num("cached") ?? 0)
            var tok = Tok()
            tok.i = max(0, Int64(t.num("input") ?? 0) - cached)
            tok.o = Int64(t.num("output") ?? 0) + Int64(t.num("thoughts") ?? 0)
            tok.cr = cached
            guard tok.total > 0 else { continue }
            r.days[DayKey.local(ts), default: Tok()] += tok
            if let mdl = m.str("model") { r.model = mdl }
            r.models[r.model ?? "gemini", default: Tok()] += tok
            r.turns += 1
            r.tools += (m["toolCalls"] as? [Any])?.count ?? 0
            let e = ts.timeIntervalSince1970
            if r.firstTs == nil { r.firstTs = e }
            if e > (r.lastTs ?? 0) { r.lastTs = e }
        }
        return r
    }

    /// 找最近在写的 Claude 会话文件，用来判断「小克正在工作」
    func isClaudeActive(files: [String], within seconds: TimeInterval = 25) -> Bool {
        let fm = FileManager.default
        let now = Date()
        for f in files {
            if let m = (try? fm.attributesOfItem(atPath: f))?[.modificationDate] as? Date, now.timeIntervalSince(m) < seconds { return true }
        }
        return false
    }
}

/// UTC 时间戳 → 本地日期。按小时缓存换算结果，几百万行时快很多。
enum DayKey {
    private static var cache: [Int: (String, Double)] = [:]
    private static let lock = NSLock()
    private static let fmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()

    static func local(_ d: Date) -> String {
        lock.lock(); defer { lock.unlock() }
        return fmt.string(from: d)
    }

    /// 解析 "2026-10-12T14:22:53.172Z"
    static func parse(_ s: String) -> (String, Double)? {
        let u = Array(s.utf8)
        guard u.count >= 19 else { return nil }
        func n(_ a: Int, _ b: Int) -> Int { var v = 0; for k in a..<b { v = v * 10 + Int(u[k] &- 48) }; return v }
        let y = n(0, 4), mo = n(5, 7), d = n(8, 10), h = n(11, 13), mi = n(14, 16), se = n(17, 19)
        let hourKey = ((y * 100 + mo) * 100 + d) * 100 + h
        lock.lock()
        if let (day, base) = cache[hourKey] { lock.unlock(); return (day, base + Double(mi * 60 + se)) }
        lock.unlock()
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d; c.hour = h
        c.timeZone = TimeZone(identifier: "UTC")
        guard let date = Calendar(identifier: .gregorian).date(from: c) else { return nil }
        let day = local(date)
        lock.lock(); cache[hourKey] = (day, date.timeIntervalSince1970); lock.unlock()
        return (day, date.timeIntervalSince1970 + Double(mi * 60 + se))
    }
}

/// 在原始字节里找字段，避免把每行几 KB 的 JSON 全部解析一遍。
/// JSON 字符串里的引号都会被转义，所以 `"key":` 这种片段只会匹配到真正的字段名。
enum Bytes {
    static func find(_ hay: UnsafeRawBufferPointer, _ needle: String, from: Int = 0, last: Bool = false) -> Int? {
        guard let base = hay.baseAddress else { return nil }
        return needle.utf8CString.withUnsafeBufferPointer { nb -> Int? in
            let nlen = nb.count - 1
            guard nlen > 0, hay.count - from >= nlen else { return nil }
            var found: Int?
            var start = from
            while start <= hay.count - nlen {
                guard let p = memmem(base + start, hay.count - start, nb.baseAddress!, nlen) else { break }
                let idx = base.distance(to: UnsafeRawPointer(p))
                found = idx
                if !last { break }
                start = idx + 1
            }
            return found
        }
    }

    static func contains(_ hay: UnsafeRawBufferPointer, _ needle: String) -> Bool { find(hay, needle) != nil }

    static func count(_ hay: UnsafeRawBufferPointer, _ needle: String) -> Int {
        var n = 0, from = 0
        while let i = find(hay, needle, from: from) { n += 1; from = i + 1 }
        return n
    }

    private static func readString(_ hay: UnsafeRawBufferPointer, at i: Int, prefix: String) -> String? {
        var j = i
        var escaped = false
        while j < hay.count {
            let c = hay[j]
            if escaped { escaped = false } else if c == 0x5C { escaped = true } else if c == 0x22 { break }
            j += 1
        }
        guard j < hay.count else { return nil }
        let bytes = UnsafeRawBufferPointer(rebasing: hay[i..<j])
        return prefix + String(decoding: bytes, as: UTF8.self)
    }

    /// key 形如 `"cwd":"`，返回紧随其后的字符串值（保留转义）
    static func stringValue(_ hay: UnsafeRawBufferPointer, key: String) -> String? {
        guard let i = find(hay, key) else { return nil }
        // 像 "id":"msg_ 这种把值的前缀也写进 key 的，要把前缀补回去
        let pre = key.components(separatedBy: "\":\"").last ?? ""
        return readString(hay, at: i + key.utf8.count, prefix: pre)
    }

    static func lastStringValue(_ hay: UnsafeRawBufferPointer, key: String) -> String? {
        guard let i = find(hay, key, last: true) else { return nil }
        return readString(hay, at: i + key.utf8.count, prefix: "")
    }

    /// 取 key 后面那个 {...} 对象的原始字节（括号配对，跳过字符串里的括号）
    static func lastObject(_ hay: UnsafeRawBufferPointer, key: String) -> Data? {
        guard let k = find(hay, key, last: true) else { return nil }
        guard let brace = find(hay, "{", from: k) else { return nil }
        var depth = 0, j = brace, inStr = false, esc = false
        while j < hay.count {
            let c = hay[j]
            if inStr {
                if esc { esc = false } else if c == 0x5C { esc = true } else if c == 0x22 { inStr = false }
            } else if c == 0x22 { inStr = true }
            else if c == 0x7B { depth += 1 }
            else if c == 0x7D { depth -= 1; if depth == 0 { return Data(UnsafeRawBufferPointer(rebasing: hay[brace...j])) } }
            j += 1
        }
        return nil
    }

    static func unescape(_ s: String) -> String {
        guard s.contains("\\") else { return s }
        if let d = ("\"" + s + "\"").data(using: .utf8), let v = try? JSONSerialization.jsonObject(with: d, options: .fragmentsAllowed) as? String {
            return v
        }
        return s
    }
}

/// 给单元测试用的入口
enum TokenScannerTestHook {
    static func scanClaude(path: String, rec: FileRecord) -> FileRecord { TokenScanner().scanClaude(path: path, rec: rec) }
}
