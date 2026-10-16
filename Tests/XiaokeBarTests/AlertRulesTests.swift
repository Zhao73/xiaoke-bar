import XCTest
@testable import XiaokeBar

final class AlertRulesTests: XCTestCase {
    func testQuotaLevelPicksHighestReached() {
        XCTAssertNil(AlertRules.quotaLevel(percent: 79.9, setting: 80))
        XCTAssertEqual(AlertRules.quotaLevel(percent: 80, setting: 80), 80)
        XCTAssertEqual(AlertRules.quotaLevel(percent: 96, setting: 80), 95)     // 一次跨过两档只报 95
        XCTAssertEqual(AlertRules.quotaLevel(percent: 60, setting: 10), 50)     // 设得太低按 50 算
        XCTAssertEqual(AlertRules.quotaLevel(percent: 99, setting: 120), 99)    // 设得太高按 99 算
        XCTAssertEqual(AlertRules.quotaLevel(percent: 95, setting: 95), 95)     // 两档重合不重复
    }

    func testWaitingStatus() {
        XCTAssertFalse(AlertRules.isWaitingStatus("busy"))
        XCTAssertFalse(AlertRules.isWaitingStatus("idle"))
        XCTAssertTrue(AlertRules.isWaitingStatus("waiting_for_permission"))
        XCTAssertTrue(AlertRules.isWaitingStatus("Awaiting-Input"))
    }

    func testScheduleAtTime() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        func d(_ now: TimeInterval, alive: Bool = true) -> AlertRules.ScheduleDecision {
            AlertRules.schedule(dueAt: t0, now: t0.addingTimeInterval(now), sessionAlive: alive, sessionIdle: false)
        }
        XCTAssertEqual(d(-1), .wait)
        XCTAssertEqual(d(-1, alive: false), .wait)          // 没到点不提前判失败
        XCTAssertEqual(d(0), .send)                         // 到点就发，会话忙也发（用户选的是时间）
        XCTAssertEqual(d(1800), .send)                      // 睡眠醒来 30 分钟内补发
        XCTAssertEqual(d(1801), .missed)
        XCTAssertEqual(d(10, alive: false), .sessionGone)
    }

    func testScheduleWhenIdle() {
        let now = Date()
        XCTAssertEqual(AlertRules.schedule(dueAt: nil, now: now, sessionAlive: true, sessionIdle: false), .wait)
        XCTAssertEqual(AlertRules.schedule(dueAt: nil, now: now, sessionAlive: true, sessionIdle: true), .send)
        XCTAssertEqual(AlertRules.schedule(dueAt: nil, now: now, sessionAlive: false, sessionIdle: false), .sessionGone)
        // 刚设好的 30 秒内不发（Mac 可能还没看到会话变忙）
        XCTAssertEqual(AlertRules.schedule(dueAt: nil, now: now, sessionAlive: true, sessionIdle: true, createdAt: now.addingTimeInterval(-5)), .wait)
        XCTAssertEqual(AlertRules.schedule(dueAt: nil, now: now, sessionAlive: true, sessionIdle: true, createdAt: now.addingTimeInterval(-31)), .send)
        // 定时的不受这个限制
        XCTAssertEqual(AlertRules.schedule(dueAt: now, now: now, sessionAlive: true, sessionIdle: false, createdAt: now), .send)
    }
}
