import Foundation

/// 界面语言。源码里直接写简体中文，L() 按当前语言查表翻译；表里没有的原样显示。
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, zhHans = "zh-Hans", zhHant = "zh-Hant", en, ja, ko
    // 欧洲主要市场：德、法、西、意、葡（巴西）
    case de, fr, es, it, ptBR = "pt-BR"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return L("跟随系统")
        case .zhHans: return "简体中文"
        case .zhHant: return "繁體中文"
        case .en: return "English"
        case .ja: return "日本語"
        case .ko: return "한국어"
        case .de: return "Deutsch"
        case .fr: return "Français"
        case .es: return "Español"
        case .it: return "Italiano"
        case .ptBR: return "Português (Brasil)"
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
        if pref.hasPrefix("ko") { return .ko }
        if pref.hasPrefix("de") { return .de }
        if pref.hasPrefix("fr") { return .fr }
        if pref.hasPrefix("es") { return .es }
        if pref.hasPrefix("it") { return .it }
        if pref.hasPrefix("pt") { return .ptBR }   // 葡萄牙本土也先用巴西葡语，差别不影响看懂
        return .en
    }

    var locale: Locale {
        switch self {
        case .zhHant: return Locale(identifier: "zh_Hant")
        case .en: return Locale(identifier: "en_US")
        case .ja: return Locale(identifier: "ja_JP")
        case .ko: return Locale(identifier: "ko_KR")
        case .de: return Locale(identifier: "de_DE")
        case .fr: return Locale(identifier: "fr_FR")
        case .es: return Locale(identifier: "es_ES")
        case .it: return Locale(identifier: "it_IT")
        case .ptBR: return Locale(identifier: "pt_BR")
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

/// 不公开部分（iPhone App、配对、远程终端、付费解锁）的文案在 Private 文件夹里另一张表
#if XIAOKE_PRIVATE
private let privateRows = L10nPrivateTable.rows
private let privateRowsEU = L10nPrivateTableEU.rows
#else
private let privateRows: [String: (String, String, String, String)] = [:]
private let privateRowsEU: [String: (String, String, String, String, String)] = [:]
#endif

func L(_ s: String, _ args: CVarArg...) -> String {
    let lang = AppLanguage.current
    var t = s
    if lang != .zhHans && lang != .system, let row = L10nTable.rows[s] ?? privateRows[s] {
        switch lang {
        case .zhHant: t = row.0
        case .ja: t = row.2
        case .ko: t = row.3
        default: t = row.1   // 英文，也是欧洲语言没翻到时的兜底
        }
        if let eu = L10nTableEU.rows[s] ?? privateRowsEU[s] {
            switch lang {
            case .de: t = eu.0
            case .fr: t = eu.1
            case .es: t = eu.2
            case .it: t = eu.3
            case .ptBR: t = eu.4
            default: break
            }
        }
    }
    #if APPSTORE
    t = storeName(t)
    #endif
    return args.isEmpty ? t : String(format: t, arguments: args)
}

#if APPSTORE
/// 翻译表里「小克」在英日韩和欧洲语言里译成 Clawd / クロード / 클로드，那是 Anthropic 吉祥物的名字。
/// 商店版一律换成自己的品牌名，避免审核时被判使用他人商标。
private func storeName(_ s: String) -> String {
    guard s.contains("Clawd") || s.contains("クロード") || s.contains("클로드") else { return s }
    return s.replacingOccurrences(of: "Clawd Usage Bar", with: "Xiaoke Bar")
        .replacingOccurrences(of: "クロード使用量バー", with: "Xiaoke Bar")
        .replacingOccurrences(of: "클로드 사용량 바", with: "Xiaoke Bar")
        .replacingOccurrences(of: "Clawd", with: "Xiaoke")
        .replacingOccurrences(of: "クロード", with: "Xiaoke")
        .replacingOccurrences(of: "클로드", with: "Xiaoke")
}
#endif
