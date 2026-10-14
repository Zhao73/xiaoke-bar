import AppKit
import Darwin

/// 点会话 → 把它所在的窗口切到前台。
/// 从会话进程沿父进程一路往上找，第一个「有界面的 App」就是它的宿主（终端、iTerm、VS Code、Claude 桌面版、Codex 桌面版……）。
/// Terminal 和 iTerm 再按 tty 选中对应的标签页，多开几个窗口也能切对。
enum SessionOpener {
    /// 打开成功返回 App 名字；找不到宿主（比如进程已经退出）返回 nil
    @discardableResult
    static func open(_ s: LiveSession) -> String? {
        guard s.pid > 0, let app = hostApp(of: s.pid) else { return nil }
        let tty = ttyName(of: s.pid)
        switch app.bundleIdentifier {
        case "com.apple.Terminal" where tty != nil:
            runAppleScript("""
            tell application "Terminal"
                repeat with w in windows
                    repeat with t in tabs of w
                        if tty of t is "/dev/\(tty!)" then
                            set selected of t to true
                            set index of w to 1
                        end if
                    end repeat
                end repeat
                activate
            end tell
            """)
        case "com.googlecode.iterm2" where tty != nil:
            runAppleScript("""
            tell application "iTerm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with ss in sessions of t
                            if tty of ss is "/dev/\(tty!)" then
                                select w
                                select t
                                select ss
                            end if
                        end repeat
                    end repeat
                end repeat
                activate
            end tell
            """)
        default:
            app.activate()
        }
        return app.localizedName
    }

    /// 沿父进程链往上找第一个普通 App（最多 30 层，防止意外死循环）
    static func hostApp(of pid: Int32) -> NSRunningApplication? {
        var cur = pid
        for _ in 0..<30 {
            if let app = NSRunningApplication(processIdentifier: cur), app.activationPolicy == .regular { return app }
            guard let p = parent(of: cur), p > 1, p != cur else { return nil }
            cur = p
        }
        return nil
    }

    private static func parent(of pid: Int32) -> Int32? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }

    /// 进程的终端名，比如 "ttys003"；没有终端（桌面 App 里跑的）返回 nil
    private static func ttyName(of pid: Int32) -> String? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let dev = info.kp_eproc.e_tdev
        guard dev != -1, dev != 0, let name = devname(dev, S_IFCHR) else { return nil }
        return String(cString: name)
    }

    private static func runAppleScript(_ src: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            var err: NSDictionary?
            NSAppleScript(source: src)?.executeAndReturnError(&err)
        }
    }
}
