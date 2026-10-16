import AppKit
import Darwin

/// Mac App Store 版要开沙盒。沙盒里有三件事做不了，这里集中处理：
/// 1. 读 ~/.claude、~/.codex 等文件夹 → 用户在「授权」窗口里选一次个人文件夹（安全书签，之后自动生效）
/// 2. 读 Claude Code 存在钥匙串里的登录信息、看其他进程、让终端执行命令 → 用户自己把「增强组件」脚本存进
///    本 App 专属的脚本文件夹（~/Library/Application Scripts/<bundle id>/），由系统在沙盒外运行（NSUserUnixTask）
/// 3. 打开 .command 文件 → 沙盒写出的文件带隔离标记，交给增强组件去掉标记再打开
/// 开源版（不开沙盒）这些都直接做，isOn 为 false 时下面的代码都不走。
enum Sandbox {
    static let isOn = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil

    /// 真正的个人文件夹。沙盒里 homeDirectoryForCurrentUser 返回的是容器路径
    static let realHome: String = {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir { return String(cString: dir) }
        return FileManager.default.homeDirectoryForCurrentUser.path
    }()

    /// 沙盒版要先完成的设置：授权个人文件夹（必需）、安装增强组件（强烈建议）
    static var needsSetup: Bool { isOn && (!HomeAccess.granted || !Helper.installed) }
}

// MARK: - 个人文件夹授权

enum HomeAccess {
    private static let key = "homeBookmark"
    private(set) static var granted = !Sandbox.isOn
    private static var url: URL?

    /// 启动时调用：有书签就恢复访问权限
    static func restore() {
        guard Sandbox.isOn, url == nil, let data = UserDefaults.standard.data(forKey: key) else { return }
        var stale = false
        guard let u = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale) else { return }
        if u.startAccessingSecurityScopedResource() {
            url = u
            granted = true
            if stale, let fresh = try? u.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
                UserDefaults.standard.set(fresh, forKey: key)
            }
        }
    }

    /// 弹出选择窗口，默认就停在个人文件夹，用户点「授权」即可。选错文件夹会提示重选。
    @MainActor
    static func request() -> Bool {
        let panel = NSOpenPanel()
        panel.message = L("请直接点「授权」：小克只读取 ~/.claude、~/.codex 等 AI 工具的会话记录，用来统计额度和 Token。")
        panel.prompt = L("授权")
        panel.directoryURL = URL(fileURLWithPath: Sandbox.realHome, isDirectory: true)
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let u = panel.url else { return false }
        guard u.standardizedFileURL.path == Sandbox.realHome else {
            let a = NSAlert()
            a.messageText = L("请选择你的个人文件夹")
            a.informativeText = String(format: L("需要选「%@」这个文件夹本身，而不是它里面或外面的文件夹。"), (Sandbox.realHome as NSString).lastPathComponent)
            a.runModal()
            return false
        }
        guard let data = try? u.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) else { return false }
        UserDefaults.standard.set(data, forKey: key)
        restore()
        return granted
    }
}

// MARK: - 增强组件

enum Helper {
    /// 脚本有改动就加一，App 发现已安装的版本旧了会提示更新
    static let version = 7
    static let fileName = "xiaoke-helper.sh"

    static var folder: URL? {
        try? FileManager.default.url(for: .applicationScriptsDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    }
    static var scriptURL: URL? { folder?.appendingPathComponent(fileName) }

    static var installedVersion: Int? {
        guard let u = scriptURL, let s = try? String(contentsOf: u, encoding: .utf8),
              let line = s.split(separator: "\n").first(where: { $0.hasPrefix("# xiaoke-helper-version:") }),
              let v = Int(line.split(separator: ":").last?.trimmingCharacters(in: .whitespaces) ?? "") else { return nil }
        return v
    }
    static var installed: Bool { !Sandbox.isOn || installedVersion != nil }
    static var outdated: Bool { Sandbox.isOn && (installedVersion ?? version) < version }

    /// 沙盒 App 不能自己往脚本文件夹里写，只能弹出「存储」窗口让用户点一下。
    @MainActor
    static func install() -> Bool {
        guard let folder else { return false }
        let panel = NSSavePanel()
        panel.message = L("请直接点「安装」：这个脚本让小克能读取 Claude Code 的登录状态、查看正在运行的会话、在终端里打开会话。")
        panel.prompt = L("安装")
        panel.directoryURL = folder
        panel.nameFieldStringValue = fileName
        panel.canCreateDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let u = panel.url else { return false }
        guard u.deletingLastPathComponent().standardizedFileURL.path == folder.standardizedFileURL.path else {
            let a = NSAlert()
            a.messageText = L("请不要改变保存位置")
            a.informativeText = L("增强组件必须放在默认打开的那个文件夹里，系统才允许小克使用它。")
            a.runModal()
            return false
        }
        do {
            try script.write(to: u, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: u.path)
            return true
        } catch {
            return false
        }
    }

    /// 运行增强组件的一个子命令，等它结束并返回输出。不要在主线程上调用（会等子进程）。
    static func run(_ args: [String], stdin: String? = nil, timeout: TimeInterval = 8) -> (status: Int32, out: String) {
        if !Sandbox.isOn { return runDirect(args, stdin: stdin, timeout: timeout) }
        guard let u = scriptURL, let task = try? NSUserUnixTask(url: u) else { return (-1, "") }
        let outPipe = Pipe()
        task.standardOutput = outPipe.fileHandleForWriting
        // 不能用 FileHandle.nullDevice：它没法经 XPC 传给系统，会直接崩溃
        let errPipe = Pipe()
        task.standardError = errPipe.fileHandleForWriting
        errPipe.fileHandleForReading.readabilityHandler = { h in _ = h.availableData }
        var inPipe: Pipe?
        if stdin != nil { let p = Pipe(); inPipe = p; task.standardInput = p.fileHandleForReading }
        let done = DispatchSemaphore(value: 0)
        var failed = false
        task.execute(withArguments: args) { err in
            failed = err != nil
            try? outPipe.fileHandleForWriting.close()
            try? errPipe.fileHandleForWriting.close()
            errPipe.fileHandleForReading.readabilityHandler = nil
            done.signal()
        }
        if let stdin, let p = inPipe {
            p.fileHandleForWriting.write(Data(stdin.utf8))
            try? p.fileHandleForWriting.close()
        }
        // 边跑边读，避免输出塞满管道
        var data = Data()
        let reader = DispatchQueue(label: "helper.read")
        let readDone = DispatchSemaphore(value: 0)
        reader.async {
            data = outPipe.fileHandleForReading.readDataToEndOfFile()
            readDone.signal()
        }
        if done.wait(timeout: .now() + timeout) == .timedOut { return (-1, "") }
        _ = readDone.wait(timeout: .now() + 2)
        return (failed ? 1 : 0, String(decoding: data, as: UTF8.self))
    }

    /// 开源版不开沙盒：同一份脚本放进数据文件夹直接跑（iPhone 远程查看 / 输入终端用的是同一套动作和安全检查）
    private static func runDirect(_ args: [String], stdin: String?, timeout: TimeInterval) -> (status: Int32, out: String) {
        let u = Paths.support.appendingPathComponent(fileName)
        if (try? String(contentsOf: u, encoding: .utf8)) != script {
            try? script.write(to: u, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: u.path)
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = [u.path] + args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        let inPipe = stdin.map { _ in Pipe() }
        if let inPipe { p.standardInput = inPipe } else { p.standardInput = FileHandle.nullDevice }
        let done = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in done.signal() }
        do { try p.run() } catch { return (-1, "") }
        if let stdin, let inPipe {
            inPipe.fileHandleForWriting.write(Data(stdin.utf8))
            try? inPipe.fileHandleForWriting.close()
        }
        var data = Data()
        let readDone = DispatchSemaphore(value: 0)
        DispatchQueue(label: "helper.read").async {
            data = out.fileHandleForReading.readDataToEndOfFile()
            readDone.signal()
        }
        if done.wait(timeout: .now() + timeout) == .timedOut { p.terminate(); return (-1, "") }
        _ = readDone.wait(timeout: .now() + 2)
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    /// 增强组件本体。只接受下面列出的几个固定动作，参数都会先检查，不能执行任意命令。
    static let script = """
    #!/bin/zsh
    # xiaoke-helper-version: \(version)
    # Xiaoke Bar（App Store 版）的增强组件。由 App 调用，只做下面几件事：
    #   kc-read/kc-write/kc-delete  读写钥匙串里的两类条目：Claude Code 的登录状态、你在 App 里添加的 API Key
    #   procs      列出进程（用来找正在运行的 AI 会话）
    #   env/cwd    读某个进程的环境变量 / 当前文件夹
    #   ports      查某个进程在本机监听的端口（Antigravity 本机服务）
    #   focus-tab  把 Terminal / iTerm2 里某个标签页切到前台
    #   read-tab   读 Terminal / iTerm2 里某个标签页最后几屏的文字（iPhone 上「查看终端」）
    #   send-text  往 Terminal / iTerm2 里某个标签页输入文字（iPhone 远程输入，Mac 设置里打开后才会用）
    #   open       在终端里打开 App 生成的 .command 启动文件
    #   stop       结束一个 AI 编程工具的进程（只认 claude/codex/gemini/grok）
    # 删除本文件即可停用。
    set -u
    # 按字符而不是字节数长度、正确传中文和表情（App 启动它时不带语言环境）
    export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
    refuse() { echo "refused" >&2; exit 2; }
    pid_ok() { case "${1:-}" in ""|*[!0-9]*) refuse ;; esac; }
    # 只允许这两类钥匙串条目
    service_ok() {
      case "${1:-}" in
        "Claude Code-credentials"|"XiaokeBar-API") ;;
        "Claude Code-credentials-"*) case "${1#Claude Code-credentials-}" in ""|*[!0-9a-f]*) refuse ;; esac ;;
        *) refuse ;;
      esac
    }
    # 账号名只允许字母数字和 @._+-（写入时要拼进 security -i 的命令行，不能带引号）
    account_ok() { case "${1:-}" in *[!A-Za-z0-9@._+-]*) refuse ;; esac; }
    # 去掉末尾的空行（Terminal 会用空行补满窗口），再取最后 200 行
    trim_tail() { /usr/bin/awk '{l[NR]=$0} END{n=NR; while(n>0 && l[n] ~ /^[[:space:]]*$/) n--; s=n-200; if(s<0)s=0; for(i=s+1;i<=n;i++) print l[i]}'; }
    # 终端标签页的 tty 名，比如 ttys003
    tty_ok() { case "${1:-}" in ttys[0-9]*) ;; *) refuse ;; esac; case "$1" in *[!a-z0-9]*) refuse ;; esac; }
    cmd="${1:-}"; [ $# -gt 0 ] && shift
    case "$cmd" in
      ping) echo "ok \(version)" ;;
      kc-read)
        service_ok "${1:-}"; account_ok "${2:-}"
        if [ -n "${2:-}" ]; then exec /usr/bin/security find-generic-password -s "$1" -a "$2" -w
        else exec /usr/bin/security find-generic-password -s "$1" -w; fi ;;
      kc-write)
        # 内容以十六进制从标准输入传进来，不出现在进程列表里
        service_ok "${1:-}"; account_ok "${2:-}"; [ -n "${2:-}" ] || refuse
        IFS= read -r hex || true
        case "$hex" in ""|*[!0-9a-f]*) refuse ;; esac
        printf 'add-generic-password -U -a "%s" -s "%s" -X %s\n' "$2" "$1" "$hex" | /usr/bin/security -i ;;
      kc-delete)
        service_ok "${1:-}"; account_ok "${2:-}"; [ -n "${2:-}" ] || refuse
        exec /usr/bin/security delete-generic-password -s "$1" -a "$2" ;;
      procs) exec /bin/ps -axww -o pid=,ppid=,rss=,time=,tty=,command= ;;
      env) pid_ok "${1:-}"; exec /bin/ps -wwE -o command= -p "$1" ;;
      cwd) pid_ok "${1:-}"; exec /usr/sbin/lsof -a -d cwd -Fpn -p "$1" ;;
      ports) pid_ok "${1:-}"; exec /usr/sbin/lsof -nP -a -p "$1" -iTCP -sTCP:LISTEN -Fn ;;
      alive) pid_ok "${1:-}"; /bin/kill -0 "$1" 2>/dev/null && echo yes || echo no ;;
      stop)
        # 只结束 AI 编程工具的进程（iPhone 上「关闭」从这里开的会话）
        pid_ok "${1:-}"
        /bin/ps -o command= -p "$1" | /usr/bin/grep -qE '(claude|codex|gemini|grok)' || refuse
        exec /bin/kill -TERM "$1" ;;
      focus-tab)
        # tty 作为参数传给固定的 AppleScript，不拼进脚本文本
        tty="${2:-}"
        case "$tty" in ttys[0-9]*) ;; *) refuse ;; esac
        case "$tty" in *[!a-z0-9]*) refuse ;; esac
        case "${1:-}" in
          terminal) exec /usr/bin/osascript -e 'on run argv' -e 'set want to "/dev/" & item 1 of argv' \
            -e 'tell application "Terminal"' -e 'repeat with w in windows' -e 'repeat with t in tabs of w' \
            -e 'if tty of t is want then' -e 'set selected of t to true' -e 'set index of w to 1' -e 'end if' \
            -e 'end repeat' -e 'end repeat' -e 'activate' -e 'end tell' -e 'end run' "$tty" ;;
          iterm) exec /usr/bin/osascript -e 'on run argv' -e 'set want to "/dev/" & item 1 of argv' \
            -e 'tell application "iTerm2"' -e 'repeat with w in windows' -e 'repeat with t in tabs of w' \
            -e 'repeat with ss in sessions of t' -e 'if tty of ss is want then' -e 'select w' -e 'select t' -e 'select ss' \
            -e 'end if' -e 'end repeat' -e 'end repeat' -e 'end repeat' -e 'activate' -e 'end tell' -e 'end run' "$tty" ;;
          *) refuse ;;
        esac ;;
      read-tab)
        # 只读文字，tty 作为参数传给固定的 AppleScript
        tty_ok "${2:-}"
        case "${1:-}" in
          terminal) /usr/bin/osascript -e 'on run argv' -e 'set want to "/dev/" & item 1 of argv' \
            -e 'tell application "Terminal"' -e 'repeat with w in windows' -e 'repeat with t in tabs of w' \
            -e 'if tty of t is want then return history of t' -e 'end repeat' -e 'end repeat' -e 'end tell' \
            -e 'return ""' -e 'end run' "$2" | trim_tail ;;
          iterm) /usr/bin/osascript -e 'on run argv' -e 'set want to "/dev/" & item 1 of argv' \
            -e 'tell application "iTerm2"' -e 'repeat with w in windows' -e 'repeat with t in tabs of w' \
            -e 'repeat with ss in sessions of t' -e 'if tty of ss is want then return contents of ss' \
            -e 'end repeat' -e 'end repeat' -e 'end repeat' -e 'end tell' -e 'return ""' -e 'end run' "$2" | trim_tail ;;
          *) refuse ;;
        esac ;;
      send-text)
        # 文字从标准输入传进来，作为参数交给固定的 AppleScript，不会被当成脚本执行
        # line = 输入后回车；raw = 不回车（按键用，只有 iTerm2 支持）
        # 第 4 个参数是 AI 会话的进程号：必须在这个标签页里、是 AI 编程工具、而且正在前台。
        # 被 Ctrl-Z 挂起或已经退出时前台是 shell，这时输入会被当成命令执行，所以拒绝
        tty_ok "${2:-}"
        case "${3:-}" in line|raw) ;; *) refuse ;; esac
        pid_ok "${4:-}"
        [ "$(/bin/ps -o tty= -p "$4" | /usr/bin/tr -d ' ')" = "$2" ] || { echo "notfg"; exit 3; }
        /bin/ps -o command= -p "$4" | /usr/bin/grep -qE '(claude|codex|gemini|grok)' || { echo "notfg"; exit 3; }
        /bin/ps -o stat= -p "$4" | /usr/bin/grep -q '+' || { echo "notfg"; exit 3; }
        text="$(/bin/cat)"
        [ ${#text} -le 4000 ] || refuse
        case "${1:-}" in
          terminal)
            # Terminal 的 do script 总会在后面加回车
            [ "$3" = "line" ] || refuse
            exec /usr/bin/osascript -e 'on run argv' -e 'set want to "/dev/" & item 1 of argv' \
              -e 'tell application "Terminal"' -e 'repeat with w in windows' -e 'repeat with t in tabs of w' \
              -e 'if tty of t is want then' -e 'do script (item 2 of argv) in t' -e 'return "ok"' -e 'end if' \
              -e 'end repeat' -e 'end repeat' -e 'end tell' -e 'return "missing"' -e 'end run' "$2" "$text" ;;
          iterm)
            exec /usr/bin/osascript -e 'on run argv' -e 'set want to "/dev/" & item 1 of argv' \
              -e 'tell application "iTerm2"' -e 'repeat with w in windows' -e 'repeat with t in tabs of w' \
              -e 'repeat with ss in sessions of t' -e 'if tty of ss is want then' \
              -e 'if item 3 of argv is "line" then' -e 'tell ss to write text (item 2 of argv)' \
              -e 'else' -e 'tell ss to write text (item 2 of argv) newline no' -e 'end if' -e 'return "ok"' -e 'end if' \
              -e 'end repeat' -e 'end repeat' -e 'end repeat' -e 'end tell' -e 'return "missing"' -e 'end run' "$2" "$text" "$3" ;;
          *) refuse ;;
        esac ;;
      open)
        case "${1:-}" in
          *"/Library/Containers/"*"/XiaokeBar/launch/"*.command)
            /usr/bin/xattr -d com.apple.quarantine "$1" 2>/dev/null
            exec /usr/bin/open "$1" ;;
          *) refuse ;;
        esac ;;
      *) echo "unknown command" >&2; exit 2 ;;
    esac
    """
}
