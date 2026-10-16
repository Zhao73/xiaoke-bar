import Foundation
import CryptoKit

/// 运行外部命令的小工具。读钥匙串必须走 /usr/bin/security：
/// Claude Code 用这个命令写入凭证，钥匙串只信任它读取，换成本 App 直接读会弹授权框。
enum Shell {
    @discardableResult
    static func run(_ launchPath: String, _ args: [String], timeout: TimeInterval = 8) -> (status: Int32, out: String) {
        // 沙盒里不能开系统命令；需要的几件事各自走增强组件的固定动作（见 Keychain、Helper.script）
        if Sandbox.isOn { return (-1, "") }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: launchPath)
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do { try task.run() } catch { return (-1, "") }
        let deadline = Date().addingTimeInterval(timeout)
        var data = Data()
        let handle = pipe.fileHandleForReading
        // 先读完再等退出，避免输出塞满管道导致子进程卡住
        data = handle.readDataToEndOfFile()
        while task.isRunning && Date() < deadline { usleep(20_000) }
        if task.isRunning { task.terminate() }
        return (task.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}

extension Shell {
    /// 把内容从标准输入喂给命令（用于 security -i，避免令牌出现在进程列表里）
    @discardableResult
    static func run(_ launchPath: String, _ args: [String], stdin: String) -> Int32 {
        if Sandbox.isOn { return -1 }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: launchPath)
        task.arguments = args
        let inPipe = Pipe()
        task.standardInput = inPipe
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        do { try task.run() } catch { return -1 }
        inPipe.fileHandleForWriting.write(Data(stdin.utf8))
        try? inPipe.fileHandleForWriting.close()
        task.waitUntilExit()
        return task.terminationStatus
    }
}

enum Keychain {
    /// 更新（没有就新建）一条通用密码，内容以十六进制经标准输入传给 security
    static func setPassword(_ value: String, service: String, account: String) -> Bool {
        let hex = Data(value.utf8).map { String(format: "%02x", $0) }.joined()
        func q(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
        if Sandbox.isOn { return Helper.run(["kc-write", service, account], stdin: hex + "\n").status == 0 }
        let cmd = "add-generic-password -U -a \(q(account)) -s \(q(service)) -X \(hex)\n"
        return Shell.run("/usr/bin/security", ["-i"], stdin: cmd) == 0
    }

    static func delete(service: String, account: String) {
        if Sandbox.isOn { _ = Helper.run(["kc-delete", service, account], timeout: 4); return }
        Shell.run("/usr/bin/security", ["delete-generic-password", "-s", service, "-a", account], timeout: 4)
    }

    /// 读取通用密码条目的内容；account 为空时只按 service 查。
    static func password(service: String, account: String? = nil) -> String? {
        var args = ["find-generic-password", "-s", service]
        if let account { args += ["-a", account] }
        args.append("-w")
        let r = Sandbox.isOn ? Helper.run(["kc-read", service, account ?? ""], timeout: 5)
                             : Shell.run("/usr/bin/security", args, timeout: 5)
        guard r.status == 0 else { return nil }
        let s = r.out.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }
}

enum Hash {
    static func sha256Prefix(_ s: String, _ n: Int = 8) -> String {
        let d = SHA256.hash(data: Data(s.utf8))
        return d.map { String(format: "%02x", $0) }.joined().prefix(n).description
    }
}

enum Paths {
    static let home = Sandbox.realHome
    static func expand(_ p: String) -> String {
        var s = p.replacingOccurrences(of: "$HOME", with: home).replacingOccurrences(of: "${HOME}", with: home)
        if s.hasPrefix("~") { s = home + s.dropFirst() }
        return s
    }
    static func pretty(_ p: String) -> String {
        p.hasPrefix(home) ? "~" + p.dropFirst(home.count) : p
    }
    static var support: URL {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("XiaokeBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
}

enum HTTPError: Error, LocalizedError {
    case status(Int, String)
    case rateLimited(retryAfter: Double?)
    case bad
    var errorDescription: String? {
        switch self {
        case .status(let c, _): return "HTTP \(c)"
        case .rateLimited: return L("官方接口限流")
        case .bad: return L("返回格式不对")
        }
    }
}

enum HTTP {
    static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 15
        c.httpCookieStorage = nil
        return URLSession(configuration: c)
    }()

    /// 只给 127.0.0.1 用：本机语言服务器（Antigravity）用的是自签名证书
    private final class LocalTrust: NSObject, URLSessionDelegate {
        func urlSession(_ s: URLSession, didReceive ch: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
            if ch.protectionSpace.host == "127.0.0.1", let t = ch.protectionSpace.serverTrust { return (.useCredential, URLCredential(trust: t)) }
            return (.performDefaultHandling, nil)
        }
    }
    static let localSession: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 4
        return URLSession(configuration: c, delegate: LocalTrust(), delegateQueue: nil)
    }()

    static func json(_ url: String, headers: [String: String]) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: url)!)
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        return try await send(req, session: session)
    }

    static func postJSON(_ url: String, body: [String: Any], headers: [String: String], insecureLocal: Bool = false) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: url)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(req, session: insecureLocal ? localSession : session)
    }

    static func postForm(_ url: String, form: [String: String]) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: url)!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics; allowed.insert(charactersIn: "-._~")
        req.httpBody = form.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&").data(using: .utf8)
        return try await send(req, session: session)
    }

    private static func send(_ req: URLRequest, session: URLSession) async throws -> [String: Any] {
        let (data, resp) = try await session.data(for: req)
        let http = resp as? HTTPURLResponse
        let code = http?.statusCode ?? 0
        if code == 429 {
            throw HTTPError.rateLimited(retryAfter: (http?.value(forHTTPHeaderField: "Retry-After")).flatMap(Double.init))
        }
        guard code == 200 else { throw HTTPError.status(code, String(decoding: data.prefix(300), as: UTF8.self)) }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw HTTPError.bad }
        return obj
    }
}

enum JWT {
    static func payload(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var s = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        guard let d = Data(base64Encoded: s) else { return nil }
        return try? JSONSerialization.jsonObject(with: d) as? [String: Any]
    }
}

enum ISO {
    private static let f1: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static let f2: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()
    static func date(_ any: Any?) -> Date? {
        if let n = any as? Double { return Date(timeIntervalSince1970: n > 1e12 ? n / 1000 : n) }
        if let n = any as? Int { return Date(timeIntervalSince1970: Double(n)) }
        guard var s = any as? String, !s.isEmpty else { return nil }
        // 服务端偶尔给 6 位小数，ISO8601DateFormatter 只认 3 位
        if let dot = s.firstIndex(of: "."), let end = s[dot...].firstIndex(where: { $0 == "+" || $0 == "Z" || $0 == "-" }) {
            let frac = s[s.index(after: dot)..<end]
            if frac.count > 3 { s.replaceSubrange(s.index(after: dot)..<end, with: frac.prefix(3)) }
        }
        return f1.date(from: s) ?? f2.date(from: s)
    }
}

extension Dictionary where Key == String, Value == Any {
    func dict(_ k: String) -> [String: Any]? { self[k] as? [String: Any] }
    func str(_ k: String) -> String? { self[k] as? String }
    func num(_ k: String) -> Double? {
        if let d = self[k] as? Double { return d }
        if let i = self[k] as? Int { return Double(i) }
        if let s = self[k] as? String { return Double(s) }
        return nil
    }
}
