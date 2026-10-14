import AppKit

/// 在「终端」里打开命令。做法是写一个 .command 文件再用系统打开：
/// 不需要「自动化」权限，并且用交互式登录 shell 运行，你在 .zshrc 里的别名（例如 claude --remote-control）照样生效。
enum Launcher {
    static func run(_ command: String, in dir: String? = nil, title: String) {
        let folder = Paths.support.appendingPathComponent("launch", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        cleanup(folder)
        let cwd = dir.map(Paths.expand) ?? Paths.home
        let safeTitle = title.replacingOccurrences(of: "\"", with: "")
        let script = """
        #!/bin/zsh -il
        printf '\\e]0;\(safeTitle)\\a'
        cd \(shellQuote(cwd)) || cd ~
        clear
        \(command)
        """
        let url = folder.appendingPathComponent("\(UUID().uuidString.prefix(8)).command")
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            NSWorkspace.shared.open(url)
        } catch {
            NSSound.beep()
        }
    }

    static func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    /// 删掉一小时前的临时启动文件
    private static func cleanup(_ folder: URL) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey]) else { return }
        let cutoff = Date().addingTimeInterval(-3600)
        for u in items {
            if let d = try? u.resourceValues(forKeys: [.creationDateKey]).creationDate, d < cutoff { try? fm.removeItem(at: u) }
        }
    }

    // MARK: 各工具的常用命令

    static func claude(_ account: ClaudeAccount, mode: ClaudeMode, dir: String?) {
        let base = account.command
        let cmd: String
        switch mode {
        case .new: cmd = base
        case .continueLast: cmd = base + " --continue"
        case .pick: cmd = base + " --resume"
        case .session(let id): cmd = base + " --resume " + shellQuote(id)
        case .login: cmd = base   // 没登录的账号启动后会自己引导登录
        }
        run(cmd, in: dir, title: "\(base) · \(Paths.pretty(Paths.expand(dir ?? "~")))")
    }

    enum ClaudeMode { case new, continueLast, pick, session(String), login }
}

/// 新增一个 Claude 账号（claude3、claude4……），做法和现有的 claude2 一致：
/// 新建 ~/.claude-c 之类的配置目录，记忆/规则/插件/设置用软链接与主号共用，登录信息独立。
enum AccountMaker {
    static let shared = ["agents", "CLAUDE.md", "commands", "file-history", "history.jsonl", "mods", "plans", "plugins",
                         "projects", "settings.json", "settings.local.json", "skills", "token-activity", "transcripts"]

    struct Plan { var command: String; var dir: String; var launcher: String }

    static func nextPlan(existing: [ClaudeAccount]) -> Plan? {
        let fm = FileManager.default
        let bin = Paths.home + "/.local/bin"
        for n in 2...9 {
            let cmd = "claude\(n)"
            let letter = Character(UnicodeScalar(UInt8(96 + n)))   // 2→b, 3→c …
            let dir = Paths.home + "/.claude-\(letter)"
            if existing.contains(where: { $0.command == cmd || $0.configDir == dir }) { continue }
            if fm.fileExists(atPath: bin + "/" + cmd) || fm.fileExists(atPath: dir) { continue }
            return Plan(command: cmd, dir: dir, launcher: bin + "/" + cmd)
        }
        return nil
    }

    static func claudeBinary() -> String {
        let candidates = [Paths.home + "/.npm-global/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude", Paths.home + "/.local/bin/claude"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "claude"
    }

    static func create(_ p: Plan) throws {
        let fm = FileManager.default
        let main = Paths.home + "/.claude"
        try fm.createDirectory(atPath: p.dir, withIntermediateDirectories: true)
        for name in shared where fm.fileExists(atPath: main + "/" + name) {
            try? fm.createSymbolicLink(atPath: p.dir + "/" + name, withDestinationPath: main + "/" + name)
        }
        // 只带上 MCP 服务器和项目信任设置，账号信息让新号自己登录
        var seed: [String: Any] = [:]
        if let d = fm.contents(atPath: Paths.home + "/.claude.json"), let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            if let m = j["mcpServers"] { seed["mcpServers"] = m }
            if let pr = j["projects"] { seed["projects"] = pr }
            seed["hasCompletedOnboarding"] = true
        }
        let data = try JSONSerialization.data(withJSONObject: seed, options: [.prettyPrinted])
        fm.createFile(atPath: p.dir + "/.claude.json", contents: data, attributes: [.posixPermissions: 0o600])
        try fm.createDirectory(atPath: (p.launcher as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        let script = """
        #!/bin/zsh
        # 由「小克额度栏」创建：Claude 账号 \(p.command)，登录信息独立存放在 \(Paths.pretty(p.dir))，
        # 记忆/规则/skills/插件/设置通过软链接与 ~/.claude 共用。
        export CLAUDE_CONFIG_DIR="$HOME/\((p.dir as NSString).lastPathComponent)"
        exec "\(claudeBinary())" --remote-control "$@"

        """
        try script.write(toFile: p.launcher, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: p.launcher)
    }
}
