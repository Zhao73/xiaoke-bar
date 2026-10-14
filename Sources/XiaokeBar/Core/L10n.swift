import Foundation

/// 界面语言。源码里直接写简体中文，L() 按当前语言查表翻译；表里没有的原样显示。
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, zhHans = "zh-Hans", zhHant = "zh-Hant", en, ja
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return L("跟随系统")
        case .zhHans: return "简体中文"
        case .zhHant: return "繁體中文"
        case .en: return "English"
        case .ja: return "日本語"
        }
    }

    /// 实际使用的语言（「跟随系统」时看系统首选语言）。界面每画一个字都会查，所以缓存起来，改语言时清掉
    nonisolated(unsafe) private static var cached: AppLanguage?
    static func invalidate() { cached = nil }

    static var current: AppLanguage {
        if let c = cached { return c }
        let v = resolve()
        cached = v
        return v
    }

    private static func resolve() -> AppLanguage {
        let raw = UserDefaults.standard.string(forKey: "language") ?? "system"
        let chosen = AppLanguage(rawValue: raw) ?? .system
        guard chosen == .system else { return chosen }
        let pref = Locale.preferredLanguages.first ?? "zh-Hans"
        if pref.hasPrefix("zh-Hant") || pref.hasPrefix("zh-TW") || pref.hasPrefix("zh-HK") { return .zhHant }
        if pref.hasPrefix("zh") { return .zhHans }
        if pref.hasPrefix("ja") { return .ja }
        return .en
    }

    var locale: Locale {
        switch self {
        case .zhHant: return Locale(identifier: "zh_Hant")
        case .en: return Locale(identifier: "en_US")
        case .ja: return Locale(identifier: "ja_JP")
        default: return Locale(identifier: "zh_CN")
        }
    }
}

/// 翻译；带参数时源文用 %@ / %d 占位
/// 额度名是数据层拼好的中文（「Fable 每周」「每月赠送额度」），显示时再翻译
func quotaTitle(_ s: String) -> String {
    if s.hasSuffix(" 每周") { return L("%@ 每周", L(String(s.dropLast(3)))) }
    return L(s)
}

func L(_ s: String, _ args: CVarArg...) -> String {
    let lang = AppLanguage.current
    var t = s
    if lang != .zhHans && lang != .system, let row = L10nTable.rows[s] {
        switch lang {
        case .zhHant: t = row.0
        case .en: t = row.1
        case .ja: t = row.2
        default: break
        }
    }
    return args.isEmpty ? t : String(format: t, arguments: args)
}
