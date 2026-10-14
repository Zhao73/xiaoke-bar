import Foundation

/// 宠物在做的动作（按会话里最后一次调用的工具来定）
enum PetAction: String, Codable, CaseIterable {
    // 工作中
    case idle, thinking, typing, reading, searching, running, building, planning, asking, delegating
    case photo, git, network, deploy, install
    // 自娱自乐 / 互动
    case guitar, dance, coffee, sleep, celebrate, worried, wave, stretch, juggle, skate, spin, love, dangle
    // 乐队
    case piano, bass, drums, flute, violin, erhu, musicbox
    // 心情和互动
    case whipped, eat, laugh, sulk, angry, walkDog, fetch, catNap

    var label: String {
        switch self {
        case .idle: return L("发呆")
        case .thinking: return L("思考中")
        case .typing: return L("改代码")
        case .reading: return L("看文件")
        case .searching: return L("搜索中")
        case .running: return L("跑命令")
        case .delegating: return L("派小弟干活")
        case .guitar: return L("弹吉他")
        case .dance: return L("跳舞")
        case .coffee: return L("喝咖啡")
        case .sleep: return L("睡觉")
        case .celebrate: return L("庆祝")
        case .worried: return L("有点慌")
        case .building: return L("编译测试")
        case .photo: return L("截图")
        case .git: return L("管代码版本")
        case .network: return L("联网查询")
        case .deploy: return L("部署上线")
        case .install: return L("装依赖")
        case .planning: return L("排计划")
        case .asking: return L("等你回复")
        case .wave: return L("打招呼")
        case .stretch: return L("伸懒腰")
        case .juggle: return L("抛球")
        case .skate: return L("玩滑板")
        case .spin: return L("转圈圈")
        case .love: return L("被摸头")
        case .dangle: return L("被拎起来")
        case .piano: return L("弹钢琴")
        case .bass: return L("弹贝斯")
        case .drums: return L("打鼓")
        case .flute: return L("吹长笛")
        case .violin: return L("拉小提琴")
        case .erhu: return L("拉二胡")
        case .musicbox: return L("摇八音盒")
        case .whipped: return L("挨了一鞭")
        case .eat: return L("吃零食")
        case .laugh: return L("笑得打滚")
        case .sulk: return L("闹情绪")
        case .angry: return L("生气了")
        case .walkDog: return L("遛狗")
        case .fetch: return L("和狗狗玩球")
        case .catNap: return L("陪猫睡觉")
        }
    }

    /// 工具名 → 动作（Claude Code 的工具名和 Codex 的函数名都认）
    static func from(tool: String?, detail: String? = nil) -> PetAction {
        guard let t = tool?.lowercased() else { return .thinking }
        if t.hasPrefix("mcp__") { return .typing }
        switch t {
        case "bash", "exec_command", "shell", "local_shell", "write_stdin", "monitor", "run_terminal_cmd":
            return command(detail)
        case "todowrite", "taskcreate", "taskupdate", "tasklist", "update_plan", "enterplanmode", "exitplanmode", "write_todos": return .planning
        case "askuserquestion", "request_user_input", "ask_user": return .asking
        case "edit", "write", "multiedit", "notebookedit", "apply_patch", "replace", "write_file": return .typing
        case "read", "view_image", "read_file", "read_many_files": return .reading
        case "grep", "glob", "websearch", "webfetch", "web_search", "toolsearch", "google_web_search", "web_fetch", "search_file_content", "list_directory": return .searching
        case "agent", "task", "workflow", "sendmessage", "spawn_agent": return .delegating
        default: return .typing
        }
    }

    /// 按命令说明（或命令本身）细分：同样是跑终端，截图、提交代码、联网、部署、装依赖、编译各有各的动画
    static func command(_ detail: String?) -> PetAction {
        guard let d = detail?.lowercased() else { return .running }
        let rules: [(PetAction, [String])] = [
            (.photo, ["screenshot", "screencapture", "capture", "snapshot", "截图", "截屏", "スクショ"]),
            (.git, ["git ", "commit", "branch", "merge", "rebase", "push", "pull request", "提交", "分支", "コミット"]),
            (.deploy, ["deploy", "ssh ", "publish", "release", "upload", "rsync", "wrangler", "vercel", "部署", "上线", "发布", "上传", "デプロイ"]),
            (.install, ["install", "brew ", "pip ", "npm i ", "pnpm add", "yarn add", "安装", "依赖", "インストール"]),
            (.building, ["build", "test", "compile", "xcodebuild", "cargo", "make", "gradle", "pytest", "lint", "typecheck", "打包", "编译", "构建", "测试", "ビルド", "テスト"]),
            (.network, ["curl", "fetch", "download", "http", "api", "request", "query", "查询", "下载", "请求", "联网"]),
        ]
        for (a, words) in rules where words.contains(where: { d.contains($0) }) { return a }
        return .running
    }
}

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
                var s = LiveSession(pid: pid, provider: .claude, sessionId: sid, cwd: j.str("cwd"), configDir: a.configDir,
                                    name: j.str("name"), busy: j.str("status") == "busy", startedAt: ISO.date(j["startedAt"]))
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
    static func claudeTranscript(configDir: String, cwd: String?, sessionId: String) -> String? {
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

    /// 读会话记录末尾，找最后一次调用的工具和它在做什么
    static func lastTool(transcript: String) -> (tool: String?, detail: String?) {
        guard let fh = FileHandle(forReadingAtPath: transcript) else { return (nil, nil) }
        defer { try? fh.close() }
        let size = (try? fh.seekToEnd()) ?? 0
        let start = size > 96_000 ? size - 96_000 : 0
        try? fh.seek(toOffset: start)
        guard let data = try? fh.readToEnd() else { return (nil, nil) }
        let text = String(decoding: data, as: UTF8.self)
        // Claude：…"type":"tool_use","id":"toolu_…","name":"Bash","input":{…}
        // Codex：…"type":"function_call","name":"exec_command","arguments":"…"
        let hits = ["\"type\":\"tool_use\"", "\"type\":\"function_call\"", "\"type\":\"custom_tool_call\""].compactMap { text.range(of: $0, options: .backwards) }
        guard let r = hits.max(by: { $0.lowerBound < $1.lowerBound }) else { return (nil, nil) }
        let tail = text[r.upperBound...]
        let name = value(in: tail, key: "\"name\":\"")
        var detail: String?
        for key in ["\"description\":\"", "\"file_path\":\"", "\"pattern\":\"", "\"query\":\"", "\"url\":\"", "\"command\":\"", "\"cmd\":\""] {
            if let v = value(in: tail.prefix(4000), key: key), !v.isEmpty {
                detail = key.contains("file_path") ? (v as NSString).lastPathComponent : String(Bytes.unescape(v).prefix(60))
                break
            }
        }
        return (name, detail)
    }

    /// 还没返回结果的子代理：发出了 Agent / Task / spawn_agent 调用，但记录里还没有对应的结果
    private static var agentCache: [String: (size: UInt64, n: Int)] = [:]

    static func pendingSubagents(transcript: String) -> Int {
        let size = (try? FileManager.default.attributesOfItem(atPath: transcript)[.size] as? UInt64) ?? 0
        if let c = agentCache[transcript], c.size == size { return c.n }
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
        agentCache[transcript] = (size, n)
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
