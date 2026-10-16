import XCTest
@testable import XiaokeBar

/// App Store 版的增强组件在沙盒外运行，必须只做白名单里的事。这里直接跑脚本，确认越界的请求都被拒绝。
/// （不测真正读写钥匙串的路径，免得碰到本机的真实条目）
final class HelperScriptTests: XCTestCase {
    var url: URL!

    override func setUpWithError() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("xiaoke-helper-\(UUID().uuidString).sh")
        try Helper.script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: url) }

    @discardableResult
    func run(_ args: [String], stdin: String = "") -> (status: Int32, out: String, err: String) {
        let p = Process()
        p.executableURL = url
        p.arguments = args
        let o = Pipe(), e = Pipe(), i = Pipe()
        p.standardOutput = o; p.standardError = e; p.standardInput = i
        try? p.run()
        i.fileHandleForWriting.write(Data(stdin.utf8)); try? i.fileHandleForWriting.close()
        let out = String(decoding: o.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let err = String(decoding: e.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        p.waitUntilExit()
        return (p.terminationStatus, out, err)
    }

    func testSyntaxAndPing() throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-n", url.path]
        try p.run(); p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 0, "脚本有语法错误")
        XCTAssertEqual(run(["ping"]).out.trimmingCharacters(in: .whitespacesAndNewlines), "ok \(Helper.version)")
    }

    func testKeychainOnlyAllowedServices() {
        XCTAssertEqual(run(["kc-read", "Chrome Safe Storage"]).status, 2)
        XCTAssertEqual(run(["kc-read", "Claude Code-credentials-../x"]).status, 2)
        XCTAssertEqual(run(["kc-read", "Claude Code-credentials-ABC"]).status, 2, "只认小写十六进制后缀")
        XCTAssertEqual(run(["kc-delete", "iCloud", "me"]).status, 2)
        XCTAssertEqual(run(["kc-write", "Claude Code-credentials", "me\" -s other"], stdin: "aa\n").status, 2, "账号名里的引号可能注入命令")
        XCTAssertEqual(run(["kc-write", "XiaokeBar-API", "id1"], stdin: "not hex\n").status, 2)
        XCTAssertEqual(run(["kc-write", "XiaokeBar-API", ""], stdin: "aa\n").status, 2)
    }

    func testRemovedPassthroughs() {
        for cmd in ["security", "osascript", "lsof", "sh", ""] {
            XCTAssertEqual(run([cmd, "-h"]).status, 2, "\(cmd) 不应该被转发")
        }
    }

    func testArgumentsAreChecked() {
        XCTAssertEqual(run(["env", "1;id"]).status, 2)
        XCTAssertEqual(run(["ports", "-p1"]).status, 2)
        XCTAssertEqual(run(["stop", ""]).status, 2)
        XCTAssertEqual(run(["focus-tab", "terminal", "ttys001\" & do shell script \"id"]).status, 2)
        XCTAssertEqual(run(["focus-tab", "Finder", "ttys001"]).status, 2)
        XCTAssertEqual(run(["open", "/Applications/Calculator.app"]).status, 2)
        XCTAssertEqual(run(["alive", "\(ProcessInfo.processInfo.processIdentifier)"]).out.trimmingCharacters(in: .whitespacesAndNewlines), "yes")
    }

    /// 读写终端只认 Terminal / iTerm2 + ttys 名字；Terminal 不支持不回车的按键
    func testTerminalActionsAreChecked() {
        XCTAssertEqual(run(["read-tab", "terminal", "../x"]).status, 2)
        XCTAssertEqual(run(["read-tab", "terminal", "ttys0;id"]).status, 2)
        XCTAssertEqual(run(["read-tab", "warp", "ttys001"]).status, 2)
        XCTAssertEqual(run(["send-text", "terminal", "ttys001", "raw"], stdin: "x").status, 2, "Terminal 的 do script 一定会回车")
        XCTAssertEqual(run(["send-text", "iterm", "ttys001", "exec"], stdin: "x").status, 2)
        XCTAssertEqual(run(["send-text", "terminal", "tty1", "line"], stdin: "x").status, 2)
        XCTAssertEqual(run(["send-text", "iterm", "ttys001", "line"], stdin: String(repeating: "a", count: 4001)).status, 2, "太长的文字不送")
    }
}
