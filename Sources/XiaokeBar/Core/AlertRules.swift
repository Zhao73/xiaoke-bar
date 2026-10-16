import Foundation

/// 提醒和定时发送的判断规则。写成不碰界面、不碰时间源的纯函数，方便单元测试。
enum AlertRules {
    /// 额度提醒：用户设的那一档（限制在 50–99）和 95% 两档；返回已达到的最高一档，没到返回 nil。
    /// 只取最高一档，是为了一次刷新跨过两档时只弹一条。
    static func quotaLevel(percent: Double, setting: Int) -> Int? {
        let levels = Array(Set([min(99, max(50, setting)), 95])).sorted()
        return levels.last { percent >= Double($0) }
    }

    /// Claude 状态文件里的状态值是不是「停下来等你」（等权限确认、等输入）。
    /// 目前只见过 busy / idle 两种值，这里按字面兜底匹配，以后出现新值也能认出来。
    static func isWaitingStatus(_ status: String) -> Bool {
        let s = status.lowercased()
        return s.contains("wait") || s.contains("input") || s.contains("permission")
    }

    enum ScheduleDecision: Equatable { case wait, send, missed, sessionGone }

    /// 定时发送这一轮该怎么处理。
    /// - dueAt: 到点时间；nil 表示「做完当前任务后」
    /// - grace: 到点后多久内还补发（Mac 睡眠醒来），超过就算错过
    /// - createdAt: 「做完后发」刚设好的前 30 秒不发：刚发出去的话 Mac 还没看到会话变忙，会误以为已经做完
    static func schedule(dueAt: Date?, now: Date, sessionAlive: Bool, sessionIdle: Bool, createdAt: Date? = nil,
                         grace: TimeInterval = 1800) -> ScheduleDecision {
        if let dueAt {
            if now < dueAt { return .wait }
            if now.timeIntervalSince(dueAt) > grace { return .missed }
        }
        guard sessionAlive else { return .sessionGone }
        if dueAt == nil {
            if !sessionIdle { return .wait }
            if let createdAt, now.timeIntervalSince(createdAt) < 30 { return .wait }
        }
        return .send
    }
}
