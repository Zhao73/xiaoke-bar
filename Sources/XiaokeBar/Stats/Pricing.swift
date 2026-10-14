import Foundation

/// 按官方 API 价格把 token 折算成美元，用来回答「这个会话如果走 API 要花多少钱」。
/// 订阅用户实际不按这个扣钱，界面上标注为「API 等价费用」。
/// Claude 价格来自 Anthropic 官方价目（2026-10）；缓存写入按 1 小时缓存价（输入价 × 2）算，
/// 因为 Claude Code 默认用 1 小时缓存。
enum Pricing {
    struct Rate { var input: Double; var output: Double; var cacheWrite: Double; var cacheRead: Double }   // 美元 / 百万 token

    static func rate(for model: String) -> Rate? {
        let m = model.lowercased()
        func r(_ i: Double, _ o: Double, cr: Double? = nil) -> Rate { Rate(input: i, output: o, cacheWrite: i * 2, cacheRead: cr ?? i * 0.1) }
        if m.contains("claude") || m.hasPrefix("opus") || m.hasPrefix("sonnet") || m.hasPrefix("haiku") || m.contains("fable") || m.contains("mythos") {
            if m.contains("fable-5-1") || m.contains("mythos-5-1") { return r(10, 50, cr: 0.25) }
            if m.contains("fable") || m.contains("mythos") { return r(10, 50) }
            if m.contains("opus-5-5") { return r(4, 20, cr: 0.2) }
            if m.contains("opus-5") || m.contains("opus-4-8") || m.contains("opus-4-7") || m.contains("opus-4-6") || m.contains("opus-4-5") { return r(5, 25) }
            if m.contains("opus") { return r(15, 75) }
            if m.contains("sonnet-5") { return r(2, 10, cr: 0.2) }
            if m.contains("sonnet") { return r(3, 15) }
            if m.contains("haiku-5-5") { return r(0.1, 0.5, cr: 0.01) }
            if m.contains("haiku-4") { return r(1, 5) }
            if m.contains("haiku") { return r(0.8, 4) }
        }
        return nil
    }

    /// 返回 nil 表示有模型不认识（比如 Codex、Gemini 的模型），不乱估
    static func cost(_ models: [String: Tok]) -> Double? {
        var sum = 0.0
        var known = false
        for (model, t) in models {
            guard let r = rate(for: model) else { continue }
            known = true
            sum += (Double(t.i) * r.input + Double(t.o) * r.output + Double(t.cw) * r.cacheWrite + Double(t.cr) * r.cacheRead) / 1e6
        }
        return known ? sum : nil
    }

    /// 读缓存省下了多少钱（同样的 token 如果按普通输入价要多花的部分）
    static func cacheSavings(_ models: [String: Tok]) -> Double? {
        var sum = 0.0, known = false
        for (model, t) in models {
            guard let r = rate(for: model) else { continue }
            known = true
            sum += Double(t.cr) * (r.input - r.cacheRead) / 1e6
        }
        return known ? sum : nil
    }
}

extension Double {
    var usd: String {
        if self >= 1000 { return String(format: "$%.0f", self) }
        if self >= 1 { return String(format: "$%.2f", self) }
        return String(format: "$%.3f", self)
    }
}
