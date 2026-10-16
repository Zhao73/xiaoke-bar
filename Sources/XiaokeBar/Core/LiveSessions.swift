import Foundation

/// 正在运行的一个 AI 编程会话（一个终端里的 claude / codex / grok / gemini 进程）
struct LiveSession: Identifiable, Equatable {
    var id: String { pid > 0 ? "\(provider.rawValue):\(pid)" : "\(provider.rawValue):\(sessionId ?? "?")" }
    var pid: Int32
    var provider: Provider
    var sessionId: String?
    var cwd: String?
    var configDir: String?            // Claude：属于哪个账号
    var name: String?
    var busy: Bool
    var startedAt: Date?
    var transcript: String?           // 会话记录文件
    var tool: String?                 // 最后一次调用的工具
    var detail: String?               // 工具在做什么（命令说明 / 文件名 / 搜索词）
    var say: String?                  // AI 最新说的一段话（桌面宠物气泡里显示）
    var subagents = 0                 // 正在跑、还没返回结果的子代理数量（「派小弟」时小弟的数量）
    var cpu: Double = 0               // 含子进程
    var rss: UInt64 = 0
    var procs = 1
    var waitingStatus = false         // Claude 状态文件里写的不是 busy / idle（比如在等权限确认）

    /// 停下来等你：在问问题，或者 Claude 状态文件说在等
    var waiting: Bool { waitingStatus || (busy && action == .asking) }

    var action: PetAction { busy ? PetAction.from(tool: tool, detail: detail) : .idle }
}

/// 找出所有正在运行的会话。
/// Claude Code 会在 <配置目录>/sessions/<pid>.json 里写进程对应的会话 ID 和 busy / idle 状态，直接读这个最准；
/// 其他工具没有这种文件，就按进程找，再用工作目录和会话记录的修改时间对上。
enum LiveSessionFinder {
    static func find(accounts: [ClaudeAccount], table: [ProcInfo], recent: [SessionSummary]) -> [LiveSession] {
        var out: [LiveSession] = []
        var claudePids = Set<Int32>()
        let fm = FileManager.default
        for a in accounts {
            let dir = a.configDir + "/sessions"
            guard let names = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for n in names where n.hasSuffix(".json") {
                guard let pid = Int32(n.dropLast(5)), ProcessTable.isAlive(pid),
                      let d = fm.contents(atPath: dir + "/" + n),
                      let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                      let sid = j.str("sessionId") else { continue }
                // 只要交互式会话（排除 remote-control 守护进程等）
                if let kind = j.str("kind"), kind != "interactive" { continue }
                claudePids.insert(pid)
                let status = j.str("status") ?? ""
                var s = LiveSession(pid: pid, provider: .claude, sessionId: sid, cwd: j.str("cwd"), configDir: a.configDir,
                                    name: j.str("name"), busy: status == "busy", startedAt: ISO.date(j["startedAt"]))
                // 目前见过的只有 busy / idle；出现带 wait、input、permission 字样的状态就当作在等你
                let st = status.lowercased()
                s.waitingStatus = AlertRules.isWaitingStatus(st)
                s.transcript = claudeTranscript(configDir: a.configDir, cwd: s.cwd, sessionId: sid)
                out.append(s)
            }
        }
        // 其他工具：先找命令行进程，再看最近几分钟在写的会话记录（Codex 桌面版没有命令行进程，也能这样认出来）
        var cli: [(pid: Int32, prov: Provider, cwd: String?)] = []
        for p in table where !claudePids.contains(p.pid) {
            if let prov = cliProvider(p) { cli.append((p.pid, prov, ProcessTable.cwd(pid: p.pid))) }
        }
        var usedPids = Set<Int32>()
        let now = Date()
        for r in recent.prefix(60) where r.provider != .claude {
            guard let path = r.path,
                  let m = (try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date,
                  now.timeIntervalSince(m) < 180 else { continue }
            var s = LiveSession(pid: 0, provider: r.provider, sessionId: r.sessionId, cwd: r.cwd, name: r.title, busy: false)
            s.transcript = path
            s.busy = r.provider == .codex ? codexBusy(path) : now.timeIntervalSince(m) < 15
            if let c = cli.first(where: { $0.prov == r.provider && $0.cwd == r.cwd && !usedPids.contains($0.pid) }) {
                s.pid = c.pid; usedPids.insert(c.pid)
            }
            out.append(s)
        }
        // 开着但最近没说话的命令行进程，也列出来（能看到它占多少内存）
        for c in cli where !usedPids.contains(c.pid) {
            out.append(LiveSession(pid: c.pid, provider: c.prov, cwd: c.cwd, name: c.cwd.map { "\(c.prov.name) · " + ($0 as NSString).lastPathComponent }, busy: false))
        }
        return out
    }

    /// Codex 日志里最后一个任务事件是 task_started 就说明还在干活
    static func codexBusy(_ path: String) -> Bool {
        guard let fh = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? fh.close() }
        let size = (try? fh.seekToEnd()) ?? 0
        // 文件没变大就沿用上次的判断：每 3 秒都读 400KB 再搜一遍太费
        busyLock.lock()
        if let c = busyCache[path], c.size == size { busyLock.unlock(); return c.busy }
        busyLock.unlock()
        try? fh.seek(toOffset: size > 400_000 ? size - 400_000 : 0)
        guard let d = try? fh.readToEnd() else { return false }
        // 直接在字节里从后往前找，省掉把 400KB 转成字符串
        let started = d.range(of: Data("\"type\":\"task_started\"".utf8), options: .backwards)?.lowerBound
        let done = d.range(of: Data("\"type\":\"task_complete\"".utf8), options: .backwards)?.lowerBound
        let busy = started.map { s in done.map { s > $0 } ?? true } ?? false
        busyLock.lock(); busyCache[path] = (size, busy); busyLock.unlock()
        return busy
    }
    nonisolated(unsafe) private static var busyCache: [String: (size: UInt64, busy: Bool)] = [:]
    private static let busyLock = NSLock()

    private static func cliProvider(_ p: ProcInfo) -> Provider? {
        let path = p.path
        guard !path.isEmpty, !path.contains(".app/") else { return nil }
        let base = (path as NSString).lastPathComponent
        if base == "codex" { return .codex }
        if base == "grok" && path.contains("/.grok/") { return .grok }
        if base == "node" || base == "gemini" {
            if base == "gemini" { return .gemini }
            let args = ProcessTable.arguments(pid: p.pid)
            if args.contains(where: { $0.contains("gemini-cli") || $0.hasSuffix("/bin/gemini") }) { return .gemini }
        }
        return nil
    }

    /// Claude Code 把会话记录放在 projects/<把路径里非字母数字都换成 - 的文件夹>/<会话ID>.jsonl
    private static var transcriptCache: [String: String] = [:]

    static func claudeTranscript(configDir: String, cwd: String?, sessionId: String) -> String? {
        let fm = FileManager.default
        // 每 3 秒都要找一遍；找到过就记住（找不到时要把 projects 下几百个文件夹挨个试）
        let key = configDir + "|" + sessionId
        if let p = transcriptCache[key], fm.fileExists(atPath: p) { return p }
        let found = locateTranscript(configDir: configDir, cwd: cwd, sessionId: sessionId)
        if let found { transcriptCache[key] = found }
        return found
    }

    private static func locateTranscript(configDir: String, cwd: String?, sessionId: String) -> String? {
        let fm = FileManager.default
        let projects = (configDir + "/projects" as NSString).resolvingSymlinksInPath
        if let cwd {
            let slug = String(cwd.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) && $0.isASCII ? Character($0) : "-" })
            let p = projects + "/" + slug + "/" + sessionId + ".jsonl"
            if fm.fileExists(atPath: p) { return p }
        }
        guard let dirs = try? fm.contentsOfDirectory(atPath: projects) else { return nil }
        for d in dirs {
            let p = projects + "/" + d + "/" + sessionId + ".jsonl"
            if fm.fileExists(atPath: p) { return p }
        }
        return nil
    }

    /// 读会话记录末尾，找最后一次调用的工具和它在做什么。按文件大小缓存，文件没变就不重读。
    private static var toolCache: [String: (size: UInt64, tool: String?, detail: String?)] = [:]
    private static let toolMarks = ["\"type\":\"tool_use\"", "\"type\":\"function_call\"", "\"type\":\"custom_tool_call\""].map { Data($0.utf8) }

    static func lastTool(transcript: String) -> (tool: String?, detail: String?) {
        guard let fh = FileHandle(forReadingAtPath: transcript) else { return (nil, nil) }
        defer { try? fh.close() }
        let size = (try? fh.seekToEnd()) ?? 0
        if let c = toolCache[transcript], c.size == size { return (c.tool, c.detail) }
        let start = size > 96_000 ? size - 96_000 : 0
        try? fh.seek(toOffset: start)
        guard let data = try? fh.readToEnd() else { return (nil, nil) }
        // Claude：…"type":"tool_use","id":"toolu_…","name":"Bash","input":{…}
        // Codex：…"type":"function_call","name":"exec_command","arguments":"…"
        // 直接在字节里从后往前找，只把命中后面一小段转成字符串
        guard let r = toolMarks.compactMap({ data.range(of: $0, options: .backwards) }).max(by: { $0.lowerBound < $1.lowerBound }) else {
            toolCache[transcript] = (size, nil, nil)
            return (nil, nil)
        }
        let tail = String(decoding: data[r.upperBound..<min(r.upperBound + 8000, data.endIndex)], as: UTF8.self)
        let name = value(in: tail, key: "\"name\":\"")
        var detail: String?
        for key in ["\"description\":\"", "\"file_path\":\"", "\"pattern\":\"", "\"query\":\"", "\"url\":\"", "\"command\":\"", "\"cmd\":\""] {
            if let v = value(in: tail.prefix(4000), key: key), !v.isEmpty {
                detail = key.contains("file_path") ? (v as NSString).lastPathComponent : String(Bytes.unescape(v).prefix(60))
                break
            }
        }
        toolCache[transcript] = (size, name, detail)
        return (name, detail)
    }

    /// 还没返回结果的子代理：发出了 Agent / Task / spawn_agent 调用，但记录里还没有对应的结果
    private static var agentCache: [String: (size: UInt64, n: Int, at: Date)] = [:]

    static func pendingSubagents(transcript: String) -> Int {
        let size = (try? FileManager.default.attributesOfItem(atPath: transcript)[.size] as? UInt64) ?? 0
        // 干活时文件每秒都在变大；子代理数量不用秒级精确，同一个文件最多 10 秒重算一次（要在 400KB 里跑正则）
        if let c = agentCache[transcript], c.size == size || Date().timeIntervalSince(c.at) < 10 { return c.n }
        guard let fh = FileHandle(forReadingAtPath: transcript) else { return 0 }
        defer { try? fh.close() }
        try? fh.seek(toOffset: size > 400_000 ? size - 400_000 : 0)
        guard let data = try? fh.readToEnd() else { return 0 }
        let text = String(decoding: data, as: UTF8.self)
        var n = 0
        let patterns = ["\"type\":\"tool_use\",\"id\":\"([A-Za-z0-9_]+)\",\"name\":\"(?:Agent|Task)\"",
                        "\"name\":\"spawn_agent\",[^}]*?\"call_id\":\"([A-Za-z0-9_\\-]+)\""]
        for pat in patterns {
            guard let re = try? NSRegularExpression(pattern: pat) else { continue }
            for m in re.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let r = Range(m.range(at: 1), in: text) else { continue }
                let id = String(text[r])
                if !text.contains("\"tool_use_id\":\"\(id)\"") && !text.contains("\"call_id\":\"\(id)\",\"output") { n += 1 }
            }
        }
        agentCache[transcript] = (size, n, Date())
        return n
    }

    /// AI 最新说的话：从会话记录末尾往前找第一条助手文字。按文件大小缓存，文件没变就不重读。
    private static var sayCache: [String: (size: UInt64, say: String?)] = [:]

    static func lastSay(transcript: String) -> String? {
        let size = (try? FileManager.default.attributesOfItem(atPath: transcript)[.size] as? UInt64) ?? 0
        if let c = sayCache[transcript], c.size == size { return c.say }
        guard let fh = FileHandle(forReadingAtPath: transcript) else { return nil }
        defer { try? fh.close() }
        let start = size > 160_000 ? size - 160_000 : 0
        try? fh.seek(toOffset: start)
        guard let data = try? fh.readToEnd() else { return nil }
        var found: String?
        // 从最后一行往前，最多看 400 行
        let lines = data.split(separator: UInt8(ascii: "\n"))
        for line in lines.reversed().prefix(400) {
            guard line.count > 20, let j = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { continue }
            if let t = assistantText(j) { found = t; break }
        }
        let say = found.map(clean)
        sayCache[transcript] = (size, say)
        return say
    }

    /// 一行记录里的助手文字（Claude Code / Codex / Gemini 三种格式）
    private static func assistantText(_ j: [String: Any]) -> String? {
        // Claude Code：{"type":"assistant","message":{"content":[{"type":"text","text":"…"}]}}
        if j.str("type") == "assistant", let m = j.dict("message"), let content = m["content"] as? [[String: Any]] {
            let texts = content.filter { $0.str("type") == "text" }.compactMap { $0.str("text") }.filter { !$0.isEmpty }
            return texts.last
        }
        // Codex：event_msg 里的 agent_message / task_complete
        if j.str("type") == "event_msg", let p = j.dict("payload") {
            if p.str("type") == "agent_message" { return p.str("message") }
            if p.str("type") == "task_complete" { return p.str("last_agent_message") }
        }
        // Codex response_item / Gemini：role=assistant 的消息
        if let p = j.dict("payload") ?? Optional(j), (p.str("role") == "assistant" || p.str("type") == "gemini"),
           let content = p["content"] as? [[String: Any]] {
            return content.compactMap { $0.str("text") }.last
        }
        return nil
    }

    /// 去掉 Markdown 记号和链接地址，压成一段，只留最后两三句
    private static func clean(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^)]*\\)", with: "$1", options: .regularExpression)
        for mark in ["**", "`", "### ", "## ", "# ", "> "] { t = t.replacingOccurrences(of: mark, with: "") }
        t = t.replacingOccurrences(of: "\\s*\\n+\\s*", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        guard t.count > 110 else { return t }
        return "…" + String(t.suffix(110))
    }

    private static func value<S: StringProtocol>(in s: S, key: String) -> String? {
        guard let r = s.range(of: key) else { return nil }
        var out = "", esc = false
        for ch in s[r.upperBound...] {
            if esc { out.append(ch); esc = false; continue }
            if ch == "\\" { out.append(ch); esc = true; continue }
            if ch == "\"" { break }
            out.append(ch)
            if out.count > 200 { break }
        }
        return out
    }
}
