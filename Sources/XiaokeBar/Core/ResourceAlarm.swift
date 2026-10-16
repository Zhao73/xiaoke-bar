import Foundation

/// 电脑资源提醒：CPU、内存占用过高，磁盘快满时提醒一次。
/// - CPU 偶尔冲高很正常（编译、开网页），要持续超过阈值 2 分钟才算；内存持续 1 分钟
/// - 提醒过一次后，要等它明显恢复（CPU 低于阈值 10 个点、内存低于 5 个点、磁盘多出 2 GB）才会再提醒，不会反复刷屏
struct ResourceAlarm {
    enum Kind: String, CaseIterable { case cpu, memory, disk }

    struct Limits: Equatable {
        var cpu: Double          // 百分比
        var memory: Double       // 百分比
        var diskFreeGB: Double   // 剩余空间低于多少 GB
    }

    static let cpuHold: TimeInterval = 120
    static let memoryHold: TimeInterval = 60

    private var overSince: [Kind: Date] = [:]
    private(set) var fired: Set<Kind> = []

    /// 每次采样调用；返回这一次需要提醒的项目
    mutating func check(cpu: Double, memory: Double, diskFree: Int64, limits: Limits, now: Date = .now) -> [Kind] {
        var out: [Kind] = []
        let freeGB = Double(diskFree) / 1_000_000_000
        func eval(_ k: Kind, over: Bool, recovered: Bool, hold: TimeInterval) {
            if fired.contains(k) {
                if recovered { fired.remove(k); overSince[k] = nil }
                return
            }
            guard over else { overSince[k] = nil; return }
            let since = overSince[k] ?? now
            overSince[k] = since
            if now.timeIntervalSince(since) >= hold {
                fired.insert(k)
                out.append(k)
            }
        }
        eval(.cpu, over: cpu >= limits.cpu, recovered: cpu < limits.cpu - 10, hold: Self.cpuHold)
        eval(.memory, over: memory >= limits.memory, recovered: memory < limits.memory - 5, hold: Self.memoryHold)
        // 磁盘读数为 0 说明还没取到，不判断
        if diskFree > 0 {
            eval(.disk, over: freeGB < limits.diskFreeGB, recovered: freeGB > limits.diskFreeGB + 2, hold: 0)
        }
        return out
    }
}
