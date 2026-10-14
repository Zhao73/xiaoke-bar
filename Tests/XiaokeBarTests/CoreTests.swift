import XCTest
@testable import XiaokeBar

final class CoreTests: XCTestCase {
    func testParseClaudeUsage() {
        let j: [String: Any] = [
            "five_hour": ["utilization": 7.0, "resets_at": "2026-10-14T05:40:00.475591+00:00"],
            "seven_day": ["utilization": 38.0, "resets_at": "2026-10-19T12:00:00.475620+00:00"],
            "iguana_necktie": ["utilization": 93.7, "limit_dollars": 250, "used_dollars": 234.31691, "resets_at": "2026-11-05T07:59:00+00:00"],
            "seven_day_opus": NSNull(),
            "limits": [["kind": "weekly_scoped", "percent": 12, "resets_at": "2026-10-19T12:00:00+00:00",
                        "scope": ["model": ["display_name": "Fable"]]]],
            "seven_day_breakdown": ["rows": [["key": "claude_code", "percent": 37], ["key": "cowork", "percent": 62]]],
        ]
        let u = ClaudeProvider.parseUsage(j)
        XCTAssertEqual(u.fiveHour?.percent, 7)
        XCTAssertEqual(u.weekly?.percent, 38)
        XCTAssertNotNil(u.fiveHour?.resetsAt, "6 位小数的时间也要能解析")
        XCTAssertEqual(u.money.first?.title, "每月赠送额度")
        XCTAssertEqual(u.money.first?.remaining ?? 0, 15.68309, accuracy: 0.0001)
        XCTAssertEqual(u.extraWindows.map(\.title), ["Fable 每周"])
        XCTAssertEqual(u.breakdown.map(\.name), ["Claude Code", "Cowork"])
    }

    func testDayKeyParse() {
        let (day, epoch) = DayKey.parse("2026-10-12T14:22:53.172Z")!
        XCTAssertEqual(epoch, 1791814973, accuracy: 1)
        XCTAssertEqual(day, DayKey.local(Date(timeIntervalSince1970: 1791814973)))
    }

    func testByteHelpers() {
        let line = #"{"type":"assistant","message":{"model":"claude-x","id":"msg_ABC","content":[{"type":"tool_use","input":{"usage":{"fake":1}}}],"usage":{"input_tokens":2,"output_tokens":5,"cache_creation_input_tokens":10,"cache_read_input_tokens":100,"x":{"y":"}"}}},"requestId":"req_1","timestamp":"2026-10-12T14:22:53.172Z"}"#
        Data(line.utf8).withUnsafeBytes { raw in
            XCTAssertEqual(Bytes.stringValue(raw, key: "\"id\":\"msg_"), "msg_ABC")
            XCTAssertEqual(Bytes.lastStringValue(raw, key: "\"requestId\":\""), "req_1")
            let obj = Bytes.lastObject(raw, key: "\"usage\":{\"input_tokens\"")!
            let u = try! JSONSerialization.jsonObject(with: obj) as! [String: Any]
            XCTAssertEqual(u["cache_read_input_tokens"] as? Int, 100, "要取真正的 usage，不能被工具参数里的 usage 骗到")
        }
    }

    func testClaudeScanDedupesAndIsIncremental() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = dir.appendingPathComponent("s1.jsonl")
        func row(_ id: String, _ out: Int) -> String {
            #"{"type":"assistant","message":{"id":"msg_\#(id)","usage":{"input_tokens":1,"output_tokens":\#(out),"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"requestId":"r\#(id)","timestamp":"2026-10-12T01:00:00.000Z"}"# + "\n"
        }
        // 同一条回复写了两行（两个内容块），只能算一次
        try (row("a", 10) + row("a", 10) + #"{"type":"ai-title","aiTitle":"测试会话","sessionId":"s1"}"# + "\n").write(to: f, atomically: true, encoding: .utf8)
        let s = TokenScannerTestHook.scanClaude(path: f.path, rec: FileRecord(provider: .claude))
        XCTAssertEqual(s.days.values.first?.o, 10)
        XCTAssertEqual(s.title, "测试会话")
        // 追加一行后从上次位置继续读
        let h = try FileHandle(forWritingTo: f); h.seekToEndOfFile(); h.write(row("b", 5).data(using: .utf8)!); try h.close()
        let s2 = TokenScannerTestHook.scanClaude(path: f.path, rec: s)
        XCTAssertEqual(s2.days.values.first?.o, 15)
    }

    func testRenewalIsInFuture() {
        var a = ClaudeAccount(command: "claude", configDir: "/x", configJSON: "/x.json", keychainService: "s", isDefault: true)
        a.subscriptionCreatedAt = ISO.date("2025-05-23T02:38:03.139353Z")
        XCTAssertGreaterThan(a.nextRenewal!, Date())
        XCTAssertLessThan(a.nextRenewal!, Date().addingTimeInterval(32 * 86400))
    }

    /// 隐私模式打码：看不出原文，长度只露个大概
    func testRedact() {
        let r = Fmt.redact("上线新的引导流程给客户看")
        XCTAssertFalse(r.contains("客户"))
        XCTAssertTrue(r.allSatisfy { $0 == "•" })
        XCTAssertEqual(Fmt.redact(""), "")
        XCTAssertEqual(Fmt.redact(String(repeating: "a", count: 100)).count, 12)
    }
}
