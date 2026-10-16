import XCTest
@testable import XiaokeBar

final class ResourceAlarmTests: XCTestCase {
    let limits = ResourceAlarm.Limits(cpu: 90, memory: 90, diskFreeGB: 10)
    let plenty: Int64 = 100_000_000_000

    /// CPU 短暂冲高不提醒，持续 2 分钟才提醒，而且只提醒一次
    func testCPUNeedsToStayHigh() {
        var a = ResourceAlarm()
        let t0 = Date()
        XCTAssertEqual(a.check(cpu: 95, memory: 40, diskFree: plenty, limits: limits, now: t0), [])
        XCTAssertEqual(a.check(cpu: 95, memory: 40, diskFree: plenty, limits: limits, now: t0 + 60), [])
        XCTAssertEqual(a.check(cpu: 95, memory: 40, diskFree: plenty, limits: limits, now: t0 + 121), [.cpu])
        XCTAssertEqual(a.check(cpu: 97, memory: 40, diskFree: plenty, limits: limits, now: t0 + 400), [], "提醒过就不再重复")
    }

    /// 中途掉下来一次，计时重新开始
    func testCPUSpikeResets() {
        var a = ResourceAlarm()
        let t0 = Date()
        _ = a.check(cpu: 95, memory: 40, diskFree: plenty, limits: limits, now: t0)
        _ = a.check(cpu: 50, memory: 40, diskFree: plenty, limits: limits, now: t0 + 90)
        XCTAssertEqual(a.check(cpu: 95, memory: 40, diskFree: plenty, limits: limits, now: t0 + 130), [])
        XCTAssertEqual(a.check(cpu: 95, memory: 40, diskFree: plenty, limits: limits, now: t0 + 251), [.cpu])
    }

    /// 要明显恢复（低于阈值 10 个点）才会重新开始计时、再次提醒
    func testCPURearmsOnlyAfterRecovery() {
        var a = ResourceAlarm()
        let t0 = Date()
        _ = a.check(cpu: 95, memory: 40, diskFree: plenty, limits: limits, now: t0)
        XCTAssertEqual(a.check(cpu: 95, memory: 40, diskFree: plenty, limits: limits, now: t0 + 125), [.cpu])
        _ = a.check(cpu: 85, memory: 40, diskFree: plenty, limits: limits, now: t0 + 200)   // 还没恢复到 80 以下
        XCTAssertTrue(a.fired.contains(.cpu))
        _ = a.check(cpu: 70, memory: 40, diskFree: plenty, limits: limits, now: t0 + 300)
        XCTAssertFalse(a.fired.contains(.cpu))
        _ = a.check(cpu: 95, memory: 40, diskFree: plenty, limits: limits, now: t0 + 310)
        XCTAssertEqual(a.check(cpu: 95, memory: 40, diskFree: plenty, limits: limits, now: t0 + 431), [.cpu])
    }

    func testMemoryAfterOneMinute() {
        var a = ResourceAlarm()
        let t0 = Date()
        XCTAssertEqual(a.check(cpu: 10, memory: 93, diskFree: plenty, limits: limits, now: t0), [])
        XCTAssertEqual(a.check(cpu: 10, memory: 93, diskFree: plenty, limits: limits, now: t0 + 61), [.memory])
    }

    /// 磁盘低于阈值马上提醒；多出 2 GB 以上才会再提醒；读数为 0（还没取到）不判断
    func testDisk() {
        var a = ResourceAlarm()
        let t0 = Date()
        XCTAssertEqual(a.check(cpu: 10, memory: 40, diskFree: 0, limits: limits, now: t0), [])
        XCTAssertEqual(a.check(cpu: 10, memory: 40, diskFree: 8_000_000_000, limits: limits, now: t0), [.disk])
        XCTAssertEqual(a.check(cpu: 10, memory: 40, diskFree: 7_000_000_000, limits: limits, now: t0 + 30), [])
        _ = a.check(cpu: 10, memory: 40, diskFree: 11_000_000_000, limits: limits, now: t0 + 60)
        XCTAssertTrue(a.fired.contains(.disk), "只多了 1 GB，还不算恢复")
        _ = a.check(cpu: 10, memory: 40, diskFree: 13_000_000_000, limits: limits, now: t0 + 90)
        XCTAssertEqual(a.check(cpu: 10, memory: 40, diskFree: 9_000_000_000, limits: limits, now: t0 + 120), [.disk])
    }
}
