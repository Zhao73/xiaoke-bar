import Foundation
import SwiftUI

enum Provider: String, Codable, CaseIterable, Identifiable {
    case claude, codex, grok, gemini
    var id: String { rawValue }
    var name: String {
        switch self { case .claude: "Claude"; case .codex: "Codex"; case .grok: "Grok"; case .gemini: "Gemini" }
    }
    var logo: String {
        switch self { case .claude: "claude-color"; case .codex: "codex-color"; case .grok: "grok"; case .gemini: "gemini-color" }
    }
    var tint: Color {
        switch self {
        case .claude: Color(red: 0.85, green: 0.47, blue: 0.34)
        case .codex: Color(red: 0.42, green: 0.45, blue: 1.0)
        case .grok: Color(white: 0.78)
        case .gemini: Color(red: 0.31, green: 0.55, blue: 0.98)
        }
    }
}

/// 一个有百分比和重置时间的额度窗口（5 小时、每周、某模型每周……）
struct QuotaWindow: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var percent: Double
    var resetsAt: Date?
}

/// 按金额计的额度（例如每月赠送的 $250）
struct MoneyQuota: Codable, Hashable {
    var title: String
    var used: Double
    var limit: Double
    var resetsAt: Date?
    var remaining: Double { max(0, limit - used) }
}

struct ShareRow: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var percent: Double
}

struct ClaudeAccount: Identifiable, Hashable {
    var id: String { configDir }
    var command: String           // 终端里启动它的命令，如 claude / claude2
    var configDir: String
    var configJSON: String        // 账号信息所在的 .claude.json
    var keychainService: String
    var isDefault: Bool
    // 来自 .claude.json 的账号信息
    var email: String?
    var accountUuid: String?
    var orgType: String?
    var tier: String?
    var subscriptionCreatedAt: Date?
    var promoClaimed: Bool?
    var passesRemaining: Int?

    var planName: String {
        let t = (tier ?? "").lowercased()
        if t.contains("20x") { return "Max 20x" }
        if t.contains("5x") { return "Max 5x" }
        switch orgType {
        case "claude_max": return "Max"
        case "claude_pro": return "Pro"
        case "claude_team": return "Team"
        case "claude_enterprise": return "Enterprise"
        default: return orgType == nil ? L("未登录") : L("免费版")
        }
    }

    /// 用户手动填的续费日（官方接口查不到真实账单日，推算可能不准，所以允许校正）
    var renewalAnchor: Date?

    /// 是否是用户校正过的日期（否则是按开通日推算的）
    var renewalIsManual: Bool { renewalAnchor != nil }

    /// 订阅按月续费：有校正日期就从它往后按月推，否则用开通日推算
    var nextRenewal: Date? {
        guard let start = renewalAnchor ?? subscriptionCreatedAt else { return nil }
        return Self.nextMonthly(from: start)
    }

    /// 从某个账单日起每月同一天续费，返回今天之后最近的一次。
    /// 每次都从起点加 n 个月（而不是一个月一个月累加），避免 31 号这类日子被月底截短后越推越早。
    static func nextMonthly(from start: Date, now: Date = .now) -> Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        for n in 0..<600 {
            if let d = cal.date(byAdding: .month, value: n, to: start), cal.startOfDay(for: d) >= today { return d }
        }
        return start
    }
}

struct ClaudeUsage: Codable, Hashable {
    var fiveHour: QuotaWindow?
    var weekly: QuotaWindow?
    var extraWindows: [QuotaWindow] = []
    var money: [MoneyQuota] = []
    var breakdown: [ShareRow] = []
    var extraUsageEnabled: Bool = false
    var subscriptionStatus: String?
    var fetchedAt: Date
}

struct CodexStatus: Codable, Hashable {
    var email: String?
    var plan: String?
    var activeUntil: Date?
    var windows: [QuotaWindow] = []
    var resetCredits: Int?
    var creditsBalance: String?
    var limitReached: Bool = false
    var fetchedAt: Date
    var fromLocalLog: Bool = false

    var planName: String {
        switch (plan ?? "").lowercased() {
        case "prolite": return "Pro Lite"
        case "pro": return "Pro"
        case "plus": return "Plus"
        case "team": return "Team"
        case "free": return L("免费版")
        case "": return L("未登录")
        default: return plan!.capitalized
        }
    }
}

struct GrokStatus: Codable, Hashable {
    var loggedIn: Bool
    var tier: String?
    var email: String?
    var fetchedAt: Date
    // 来自 cli-chat-proxy.grok.com/v1/billing（单位：美分）
    var monthlyLimitCents: Double?
    var usedCents: Double?
    var onDemandCapCents: Double?
    var periodEnd: Date?
    var hasCodeAccess: Bool?
    var billingFetchedAt: Date?
    var tokenExpired = false

    var usedPercent: Double? {
        guard let l = monthlyLimitCents, l > 0 else { return nil }
        return min(100, (usedCents ?? 0) / l * 100)
    }
}

/// Gemini CLI（Google 账号登录）的套餐和各模型额度
struct GeminiStatus: Codable, Hashable {
    var loggedIn: Bool
    var email: String?
    var tierName: String?
    var buckets: [QuotaWindow] = []      // percent = 已用百分比
    var fetchedAt: Date
}

/// 每个账号卡片上显示的「数据状态」
enum LoadState: Equatable {
    case idle, loading, ok, stale(String), failed(String)
}

extension Double {
    var tokenShort: String {
        let v = self
        // 中文按「万 / 亿」，其他语言按 K / M / B
        let lang = AppLanguage.current
        if lang == .zhHans || lang == .zhHant || lang == .system {
            let (yi, wan) = lang == .zhHant ? ("億", "萬") : ("亿", "万")
            if v >= 1e8 { return String(format: "%.2f %@", v / 1e8, yi) }
            if v >= 1e4 { return String(format: v >= 1e6 ? "%.0f %@" : "%.1f %@", v / 1e4, wan) }
            return String(format: "%.0f", v)
        }
        if lang == .ja {
            if v >= 1e8 { return String(format: "%.2f億", v / 1e8) }
            if v >= 1e4 { return String(format: v >= 1e6 ? "%.0f万" : "%.1f万", v / 1e4) }
            return String(format: "%.0f", v)
        }
        if lang == .ko {  // 韩语也按「만 / 억」计数
            if v >= 1e8 { return String(format: "%.2f억", v / 1e8) }
            if v >= 1e4 { return String(format: v >= 1e6 ? "%.0f만" : "%.1f만", v / 1e4) }
            return String(format: "%.0f", v)
        }
        if v >= 1e9 { return String(format: "%.2fB", v / 1e9) }
        if v >= 1e6 { return String(format: "%.1fM", v / 1e6) }
        if v >= 1e3 { return String(format: "%.1fK", v / 1e3) }
        return String(format: "%.0f", v)
    }
}

extension Int64 {
    var tokenShort: String { Double(self).tokenShort }
}

extension UInt64 {
    /// 1.2 GB / 340 MB（十进制，和访达显示的一致）
    var bytesShort: String {
        let v = Double(self)
        if v >= 1e12 { return String(format: "%.2f TB", v / 1e12) }
        if v >= 1e9 { return String(format: v >= 1e11 ? "%.0f GB" : "%.1f GB", v / 1e9) }
        if v >= 1e6 { return String(format: v >= 1e8 ? "%.0f MB" : "%.1f MB", v / 1e6) }
        return String(format: "%.0f KB", v / 1e3)
    }
}

extension Int64 {
    var bytesShort: String { UInt64(Swift.max(0, self)).bytesShort }
}

enum Fmt {
    static func countdown(to date: Date, now: Date = .now) -> String {
        let s = Int(date.timeIntervalSince(now))
        if s <= 0 { return L("已重置") }
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60, sec = s % 60
        if d > 0 { return L("%d天%d小时", d, h) }
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%d:%02d", m, sec)
    }

    /// 3 分钟 / 1 小时 20 分 / 45 秒
    static func duration(_ t: TimeInterval) -> String {
        let s = max(0, Int(t))
        if s < 60 { return L("%d 秒", s) }
        if s < 3600 { return L("%d 分钟", s / 60) }
        let h = s / 3600, m = (s % 3600) / 60
        return m == 0 ? L("%d 小时", h) : L("%d 小时 %d 分", h, m)
    }

    static func shortDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = AppLanguage.current.locale
        f.dateFormat = "HH:mm"
        if Calendar.current.isDateInToday(d) { return L("今天 %@", f.string(from: d)) }
        if Calendar.current.isDateInTomorrow(d) { return L("明天 %@", f.string(from: d)) }
        f.setLocalizedDateFormatFromTemplate("MMMd HH:mm")
        return f.string(from: d)
    }

    static func day(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = AppLanguage.current.locale; f.setLocalizedDateFormatFromTemplate("MMMd")
        return f.string(from: d)
    }

    static func daysLeft(_ d: Date) -> Int {
        max(0, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: Calendar.current.startOfDay(for: d)).day ?? 0)
    }

    static func ago(_ d: Date) -> String {
        let s = Int(Date().timeIntervalSince(d))
        if s < 60 { return L("刚刚") }
        if s < 3600 { return L("%d 分钟前", s / 60) }
        if s < 86400 { return L("%d 小时前", s / 3600) }
        if s < 86400 * 30 { return L("%d 天前", s / 86400) }
        return day(d)
    }

    /// 隐私模式的打码：只留大概长度，看不出写了什么
    static func redact(_ s: String) -> String {
        s.isEmpty ? s : String(repeating: "•", count: min(12, max(4, s.count / 2)))
    }

    static func maskEmail(_ e: String?) -> String {
        guard let e, let at = e.firstIndex(of: "@") else { return e ?? "" }
        let name = e[..<at]
        let keep = name.prefix(min(3, max(1, name.count / 3)))
        return keep + "•••" + e[at...]
    }
}
