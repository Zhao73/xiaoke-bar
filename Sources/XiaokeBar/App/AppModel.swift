import SwiftUI
import UserNotifications
import ServiceManagement

enum PetMood: Equatable { case idle, working, sleepy, celebrate, worried }

@MainActor
@Observable
final class AppModel {
    // 账号与额度
    var accounts: [ClaudeAccount] = []
    var claudeUsage: [String: ClaudeUsage] = [:]
    var claudeState: [String: LoadState] = [:]
    var profileStatus: [String: String] = [:]
    var codex: CodexStatus?
    var codexState: LoadState = .idle
    var grok = GrokStatus(loggedIn: false, fetchedAt: .now)
    var gemini: GeminiStatus?
    var geminiState: LoadState = .idle
    var antigravity: AntigravityProvider.Status?

    // 本机与运行中的会话
    var system = SystemStats()
    var live: [LiveSession] = []
    var popoverVisible = false

    // API 账单
    var apiKeys: [ApiKeyEntry] { didSet { saveApiKeys() } }
    var apiBills: [String: ApiBill] = [:]
    var apiHistory = ApiBillHistory.load()

    // 宠物
    /// 手动让宠物做的动作。target = 哪一只（会话 id）；nil = 主宠物（顶栏那只 / 桌面最显眼那只），别的宠物继续各干各的
    var petOverride: (action: PetAction, until: Date, target: String?)?

    // 统计
    var stats: StatsSnapshot?
    var scanProgress: Double?
    var claudeActive = false

    // 界面
    var tab: Tab = .quota
    /// 沙盒版设置页：每完成一步加一，让页面重新判断状态
    var setupRevision = 0
    var helperSkipped = UserDefaults.standard.bool(forKey: "helperSkipped")
    var showSetup: Bool {
        _ = setupRevision
        return Sandbox.isOn && !Self.demo && (!HomeAccess.granted || ((!Helper.installed || Helper.outdated) && !helperSkipped))
    }

    func finishSetupStep() {
        setupRevision += 1
        Task { await refreshAll(); await rescan() }
    }

    func skipHelper() {
        helperSkipped = true
        UserDefaults.standard.set(true, forKey: "helperSkipped")
        finishSetupStep()
    }
    var lastRefresh: Date?
    var refreshing = false
    var celebrateUntil: Date?
    var toast: String?

    enum Tab: String, CaseIterable, Identifiable {
        case quota, sessions, stats, billing, settings
        var id: String { rawValue }
        var title: String {
            switch self { case .quota: L("额度"); case .sessions: L("会话"); case .stats: L("统计"); case .billing: L("账单"); case .settings: L("设置") }
        }
        var icon: String {
            switch self {
            case .quota: "gauge.with.dots.needle.67percent"; case .stats: "chart.bar.xaxis"; case .sessions: "bubble.left.and.text.bubble.right"
            case .billing: "creditcard"; case .settings: "slider.horizontal.3"
            }
        }
    }

    /// 菜单栏显示方式
    enum MenuMode: String, CaseIterable, Identifiable {
        case ticker, percent, icon
        var id: String { rawValue }
        var title: String { switch self { case .ticker: L("轮播（额度 + 性能）"); case .percent: L("只显示 5 小时额度"); case .icon: L("只显示小克") } }
    }

    /// 轮播里可以出现的内容
    enum TickerItem: String, CaseIterable, Identifiable {
        case claude, codex, gemini, cpu, memory, disk, tokens
        var id: String { rawValue }
        var title: String {
            switch self {
            case .claude: L("Claude 各账号额度"); case .codex: L("Codex 额度"); case .gemini: L("Gemini 额度")
            case .cpu: L("CPU 占用"); case .memory: L("内存占用"); case .disk: L("磁盘剩余"); case .tokens: L("今天 token")
            }
        }
    }

    // 设置（存在 UserDefaults）
    var refreshMinutes: Int { didSet { defaults.set(refreshMinutes, forKey: "refreshMinutes"); scheduleRefresh() } }
    var hideEmail: Bool { didSet { defaults.set(hideEmail, forKey: "hideEmail") } }
    /// 隐私模式：会话标题、AI 说的话、在做的事、文件夹名、邮箱全部打码（录屏 / 截图 / 直播时用）
    var privacyMode: Bool { didSet { defaults.set(privacyMode, forKey: "privacyMode") } }
    var maskEmails: Bool { hideEmail || privacyMode }
    /// 显示会话里的文字前过一遍：隐私模式下打码
    func shown(_ s: String?) -> String? { s.map { privacyMode ? Fmt.redact($0) : $0 } }
    var notifyHigh: Bool { didSet { defaults.set(notifyHigh, forKey: "notifyHigh"); if notifyHigh { requestNotify() } } }
    var notifyReset: Bool { didSet { defaults.set(notifyReset, forKey: "notifyReset"); if notifyReset { requestNotify() } } }
    /// 电脑资源提醒：CPU / 内存持续高于阈值、磁盘剩余低于阈值时发通知
    var notifySystem: Bool { didSet { defaults.set(notifySystem, forKey: "notifySystem"); if notifySystem { requestNotify() } } }
    var cpuAlert: Int { didSet { defaults.set(cpuAlert, forKey: "cpuAlert") } }
    var memAlert: Int { didSet { defaults.set(memAlert, forKey: "memAlert") } }
    var diskAlertGB: Int { didSet { defaults.set(diskAlertGB, forKey: "diskAlertGB") } }
    var alertLimits: ResourceAlarm.Limits { .init(cpu: Double(cpuAlert), memory: Double(memAlert), diskFreeGB: Double(diskAlertGB)) }
    var menuShowsPercent: Bool { didSet { defaults.set(menuShowsPercent, forKey: "menuShowsPercent") } }
    var menuAccount: String { didSet { defaults.set(menuAccount, forKey: "menuAccount") } }
    var nicknames: [String: String] { didSet { defaults.set(nicknames, forKey: "nicknames") } }
    var hiddenAccounts: [String] { didSet { defaults.set(hiddenAccounts, forKey: "hiddenAccounts") } }
    var workDir: String { didSet { defaults.set(workDir, forKey: "workDir") } }
    var showRemaining: Bool { didSet { defaults.set(showRemaining, forKey: "showRemaining") } }
    var menuMode: MenuMode { didSet { defaults.set(menuMode.rawValue, forKey: "menuMode") } }
    var tickerItems: Set<TickerItem> { didSet { defaults.set(tickerItems.map(\.rawValue), forKey: "tickerItems") } }
    var renewalOverrides: [String: Double] { didSet { defaults.set(renewalOverrides, forKey: "renewalOverrides"); applyOverrides() } }
    var floatingPet: Bool { didSet { defaults.set(floatingPet, forKey: "floatingPet") } }
    var notifyDone: Bool { didSet { defaults.set(notifyDone, forKey: "notifyDone"); if notifyDone { requestNotify() } } }
    /// 会话停下来等你确认 / 回答时提醒
    var notifyAsking: Bool { didSet { defaults.set(notifyAsking, forKey: "notifyAsking"); if notifyAsking { requestNotify() } } }
    /// 额度用到百分之多少开始提醒（另外 95% 再提醒一次）
    var quotaAlertPercent: Int { didSet { defaults.set(quotaAlertPercent, forKey: "quotaAlertPercent") } }
    var doneSound: Bool { didSet { defaults.set(doneSound, forKey: "doneSound") } }
    var petVolume: Double { didSet { defaults.set(petVolume, forKey: "petVolume") } }
    var hasDog: Bool { didSet { defaults.set(hasDog, forKey: "hasDog") } }
    var hasCat: Bool { didSet { defaults.set(hasCat, forKey: "hasCat") } }
    /// 桌面宠物旁边的会话气泡折叠起来，只留宠物（不挡屏幕）
    var petBubblesCollapsed: Bool { didSet { defaults.set(petBubblesCollapsed, forKey: "petBubblesCollapsed") } }
    /// 心情 0–100：摸头、喂零食、任务做完会变好，抽鞭子、额度快用完会变差；平时慢慢回到 60
    var happiness: Double { didSet { if Int(happiness) != Int(oldValue) { defaults.set(happiness, forKey: "happiness") } } }
    var language: String { didSet { defaults.set(language, forKey: "language"); AppLanguage.invalidate() } }

    /// 演示模式：全部用编好的假数据，不联网、不扫描真实会话、设置存到单独的地方。
    /// XIAOKE_DEMO=1 给宣传截图用；App Store 版的设置页也能手动进入（审核员的电脑上没有 Claude Code，需要它看到完整功能）
    static let demoByUser = UserDefaults.standard.bool(forKey: "demoMode")
    static let demo = ProcessInfo.processInfo.environment["XIAOKE_DEMO"] == "1" || demoByUser

    /// 进入 / 退出演示：所有数据源在启动时就定了，所以记下开关后重启 App
    static func setDemo(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: "demoMode")
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: cfg) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
    private let defaults: UserDefaults = {
        guard AppModel.demo, let d = UserDefaults(suiteName: "com.zjp73.xiaokebar.demo") else { return .standard }
        d.removePersistentDomain(forName: "com.zjp73.xiaokebar.demo")
        return d
    }()
    private let scanner = TokenScanner()
    private var refreshTimer: Timer?
    private var pulseTimer: Timer?
    private var notified: Set<String> = []
    private var profileFetchedAt: [String: Date] = [:]
    private var lastPercents: [String: Double] = [:]
    private let usageCacheURL = Paths.support.appendingPathComponent("usage-cache.json")
    private let monitor = SystemMonitor()
    private var claudeFetchedAt: [String: Date] = [:]
    private var claudeBackoff: [String: (until: Date, step: Double, retried: Bool)] = [:]
    private var busySince: [String: Date] = [:]
    private var lastScanAt = Date.distantPast
    private var lastFullScanAt = Date.distantPast
    private var tickCount = 0

    init() {
        HomeAccess.restore()
        defaults.register(defaults: ["refreshMinutes": 3, "hideEmail": false, "notifyHigh": true, "notifyReset": true, "menuShowsPercent": true,
                                     "showRemaining": true, "menuMode": "ticker", "tickerItems": ["claude", "codex", "cpu", "memory", "disk"],
                                     "floatingPet": false, "notifyDone": true, "doneSound": true, "petVolume": 0.6, "language": "system",
                                     "hasDog": true, "hasCat": true, "happiness": 70.0,
                                     "notifySystem": true, "cpuAlert": 90, "memAlert": 90, "diskAlertGB": 10,
                                     "notifyAsking": true, "quotaAlertPercent": 80])
        refreshMinutes = defaults.integer(forKey: "refreshMinutes")
        hideEmail = defaults.bool(forKey: "hideEmail")
        privacyMode = defaults.bool(forKey: "privacyMode")
        notifyHigh = defaults.bool(forKey: "notifyHigh")
        notifyReset = defaults.bool(forKey: "notifyReset")
        notifySystem = defaults.bool(forKey: "notifySystem")
        cpuAlert = defaults.integer(forKey: "cpuAlert")
        memAlert = defaults.integer(forKey: "memAlert")
        diskAlertGB = defaults.integer(forKey: "diskAlertGB")
        menuShowsPercent = defaults.bool(forKey: "menuShowsPercent")
        menuAccount = defaults.string(forKey: "menuAccount") ?? "auto"
        nicknames = (defaults.dictionary(forKey: "nicknames") as? [String: String]) ?? [:]
        hiddenAccounts = defaults.stringArray(forKey: "hiddenAccounts") ?? []
        workDir = defaults.string(forKey: "workDir") ?? "~"
        showRemaining = defaults.bool(forKey: "showRemaining")
        menuMode = MenuMode(rawValue: defaults.string(forKey: "menuMode") ?? "") ?? .ticker
        tickerItems = Set((defaults.stringArray(forKey: "tickerItems") ?? []).compactMap(TickerItem.init))
        renewalOverrides = (defaults.dictionary(forKey: "renewalOverrides") as? [String: Double]) ?? [:]
        floatingPet = defaults.bool(forKey: "floatingPet")
        notifyDone = defaults.bool(forKey: "notifyDone")
        notifyAsking = defaults.bool(forKey: "notifyAsking")
        quotaAlertPercent = defaults.integer(forKey: "quotaAlertPercent")
        doneSound = defaults.bool(forKey: "doneSound")
        petVolume = defaults.double(forKey: "petVolume")
        hasDog = defaults.bool(forKey: "hasDog")
        hasCat = defaults.bool(forKey: "hasCat")
        petBubblesCollapsed = defaults.bool(forKey: "petBubblesCollapsed")
        happiness = defaults.double(forKey: "happiness")
        language = defaults.string(forKey: "language") ?? "system"
        apiKeys = (defaults.data(forKey: "apiKeys")).flatMap { try? JSONDecoder().decode([ApiKeyEntry].self, from: $0) } ?? []
        notified = Set(defaults.stringArray(forKey: "notified") ?? [])
        loadUsageCache()
        accounts = ClaudeProvider.discoverAccounts()
        applyOverrides()
        grok = GrokProvider.status()
        system = monitor.sample()
    }

    private var started = false

    func start() {
        // 菜单栏图标重绘时可能再次触发，只允许启动一次，否则会形成「刷新→重绘→再刷新」的死循环
        guard !started else { return }
        started = true
        if Self.demo {
            fillDemo()
            pulseTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.system = self?.monitor.sample() ?? SystemStats() }
            }
            return
        }
        Task { await refreshAll() }
        Task { await rescan() }
        scheduleRefresh()
        // 每 3 秒看一眼：哪些会话在跑、在做什么、CPU/内存。只读几个小文件 + 两个系统调用，开销可以忽略
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func scheduleRefresh() {
        refreshTimer?.invalidate()
        // 有会话在跑时额度 2 分钟刷新一次（官方接口限流很严，再快会被 429），平时按设置的间隔
        let minutes = claudeActive ? min(2, max(1, refreshMinutes)) : max(1, refreshMinutes)
        // 只刷新额度；token 统计由 tick 里的热扫描（30 秒）和全量扫描（10 分钟）负责
        refreshTimer = Timer.scheduledTimer(withTimeInterval: Double(minutes) * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshAll() }
        }
    }

    /// 打开面板时：马上重新统计 token（热扫不到 1 秒），额度超过 2 分钟没刷新就刷新
    func popoverOpened() {
        popoverVisible = true
        tick()
        // 一分钟内刚全量扫过就不再扫（来回开关面板时不重复遍历几千个文件）
        if Date().timeIntervalSince(lastFullScanAt) > 60 { Task { await rescan() } }
        if let t = lastRefresh, Date().timeIntervalSince(t) < 120 { return }
        Task { await refreshAll() }
    }

    func popoverClosed() { popoverVisible = false }

    // MARK: 实时：运行中的会话、性能、完成提醒

    private func tick() {
        if Self.demo { return }
        tickCount += 1
        // 没有会话在干活、面板也关着时，6 秒查一次就够（有会话开始干活最多晚 3 秒发现）
        if !popoverVisible, !claudeActive, tickCount % 2 == 1 { return }
        driftHappiness()
        system = monitor.sample()
        checkSystemAlerts()
        // 进程表只在面板开着时取（为了显示每个会话的 CPU / 内存）
        let table = popoverVisible ? ProcessTable.snapshot() : []
        var list = LiveSessionFinder.find(accounts: accounts, table: table, recent: stats?.sessions ?? [])
        if !table.isEmpty {
            let use = monitor.usage(of: list.map(\.pid).filter { $0 > 0 }, in: table)
            for i in list.indices { if let u = use[list[i].pid] { list[i].cpu = u.cpu; list[i].rss = u.rss; list[i].procs = u.procs } }
        }
        for i in list.indices {
            guard let t = list[i].transcript else { continue }
            if list[i].busy { (list[i].tool, list[i].detail) = LiveSessionFinder.lastTool(transcript: t) }
            list[i].say = LiveSessionFinder.lastSay(transcript: t)
            list[i].subagents = list[i].busy ? LiveSessionFinder.pendingSubagents(transcript: t) : 0
        }
        detectCompletions(list)
        detectWaiting(list)
        // 实时事件：AI 说了新的话 → 宠物张嘴说话；换了工具 → 头上蹦个「!」
        let now = Date()
        for l in list {
            guard let old = live.first(where: { $0.id == l.id }) else { continue }
            if let say = l.say, say != old.say { saidAt[l.id] = now }
            if l.busy, l.tool != nil, l.tool != old.tool || l.detail != old.detail { toolChangedAt[l.id] = now }
        }
        if list != live { live = list }
        let active = list.contains { $0.busy }
        if active != claudeActive { claudeActive = active; scheduleRefresh() }
        // 有会话在跑时每 30 秒热扫一次（只读在跑的那几个会话文件），让会话 token 跟着涨；每 10 分钟全量扫一次
        let full = Date().timeIntervalSince(lastFullScanAt) > 600
        if full, Date().timeIntervalSince(lastScanAt) > 30 {
            Task { await rescan() }
        } else if active, Date().timeIntervalSince(lastScanAt) > 30 {
            let hot = list.compactMap { l in l.transcript.map { ($0, l.provider) } }
            if !hot.isEmpty { Task { await rescan(only: hot) } }
        }
        // 限流等待到点就马上重查，不用等下一轮定时刷新
        for a in accounts {
            if let b = claudeBackoff[a.id], b.until <= now, !b.retried {
                claudeBackoff[a.id]?.retried = true
                claudeFetchedAt[a.id] = nil
                Task { await refreshClaude(a); saveUsageCache() }
            }
        }
    }

    /// 「14:32 自动再查」：给具体时刻，提示文字不会因为没刷新而停在「0 秒」
    private func retryText(_ until: Date) -> String {
        let left = until.timeIntervalSinceNow
        if left < 60 { return L("官方接口限流，马上自动再查") }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return L("官方接口限流，%@ 自动再查", f.string(from: until))
    }

    /// busy → idle：任务做完了。超过 20 秒的任务才提醒，免得每句闲聊都弹
    private func detectCompletions(_ list: [LiveSession]) {
        let now = Date()
        let byId = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for (id, since) in busySince {
            let cur = byId[id]
            guard cur == nil || cur!.busy == false else { continue }
            busySince[id] = nil
            let dur = now.timeIntervalSince(since)
            guard dur >= 20 else { continue }
            let old = live.first { $0.id == id }
            let title = (cur ?? old).flatMap { summary(for: $0)?.title } ?? cur?.name ?? old?.name ?? L("会话")
            let prov = (cur ?? old)?.provider ?? .claude
            celebrate(seconds: 3)
            cheerUntil = now.addingTimeInterval(3)     // 小队里其他宠物也一起欢呼（各用各的庆祝动作）
            cheer(4)
            if doneSound { NSSound(named: "Glass")?.play() }
            let doneTitle = L("✅ %@ 做完了", String((shown(sessionTitle(title)) ?? "").prefix(40)))
            let doneBody = L("%@ · 用时 %@", prov.name, Fmt.duration(dur))
            // Mac 上关了提醒，iPhone 照样要收到
            if notifyDone { send(.done, doneTitle, doneBody) } else { relay(.done, doneTitle, doneBody) }
            lastDone = (title, prov, now)
        }
        for s in list where s.busy && busySince[s.id] == nil { busySince[s.id] = now }
    }

    var lastDone: (title: String, provider: Provider, at: Date)?

    /// 会话停下来等你（权限确认、提问）：进入等待状态时提醒一次
    private var waitingIDs = Set<String>()
    private func detectWaiting(_ list: [LiveSession]) {
        let now = Set(list.filter(\.waiting).map(\.id))
        for s in list where s.waiting && !waitingIDs.contains(s.id) {
            let title = L("⏸ %@ 在等你确认", String((shown(sessionTitle(summary(for: s)?.title ?? s.name ?? s.provider.name)) ?? "").prefix(40)))
            let body = L("%@ · 回终端看看，或在 iPhone 上处理。", s.provider.name)
            if notifyAsking { send(.asking, title, body) } else { relay(.asking, title, body) }
        }
        waitingIDs = now
    }
    /// 每个会话最近一次「AI 说新话」「换工具」的时间，驱动宠物的实时反应
    var saidAt: [String: Date] = [:]
    var toolChangedAt: [String: Date] = [:]

    /// 有会话做完时，所有宠物一起欢呼到这个时间
    var cheerUntil: Date?
    /// 点了工作小队的卡片：会话页打开时展开这个会话
    var sessionFocus: String?

    /// 在忙的会话，按开始时间排（顺序稳定，卡片不会跳来跳去）
    var busySessions: [LiveSession] {
        live.filter(\.busy).sorted { (busySince[$0.id] ?? .distantPast) < (busySince[$1.id] ?? .distantPast) }
    }

    func sessionTitle(_ raw: String) -> String {
        if let s = stats?.sessions.first(where: { $0.title == raw || $0.sessionId == raw }) { return s.title }
        return raw
    }

    /// 运行中的会话对应的统计（标题、token）
    func summary(for l: LiveSession) -> SessionSummary? {
        guard let sid = l.sessionId else { return nil }
        return stats?.sessions.first { $0.provider == l.provider && $0.sessionId == sid }
    }

    func liveSession(for s: SessionSummary) -> LiveSession? {
        live.first { $0.provider == s.provider && $0.sessionId == s.sessionId }
    }

    /// 宠物当前要演的：手动点的动作优先；否则跟着最近在忙的会话；都不忙就看额度心情
    var pet: (kind: Provider, action: PetAction, session: LiveSession?) {
        if let o = petOverride, o.target == nil, o.until > Date() { return (focusSession?.provider ?? .claude, o.action, focusSession) }
        if let n = nowPlaying, focusSession?.busy != true, let first = n.song.performers.first { return (first.member, first.instrument.action, nil) }
        if let f = focusSession, f.busy { return (f.provider, f.action, f) }
        switch mood {
        case .celebrate: return (lastDone?.provider ?? .claude, .celebrate, nil)
        case .sleepy: return (.claude, .sleep, nil)
        case .worried: return (.claude, .worried, nil)
        default:
            let h = Calendar.current.component(.hour, from: .now)
            if h >= 1 && h < 6 { return (.claude, .sleep, nil) }
            return (.claude, .idle, nil)
        }
    }

    /// 最值得展示的会话：在忙的里面最近开始的那个
    var focusSession: LiveSession? {
        live.filter(\.busy).max { (busySince[$0.id] ?? .distantPast) < (busySince[$1.id] ?? .distantPast) }
    }

    func busyDuration(_ l: LiveSession) -> TimeInterval? { busySince[l.id].map { Date().timeIntervalSince($0) } }

    /// 正在弹的曲子（弹完自动清掉）。start 让每只宠物的演奏动作和拍子对上
    var nowPlaying: (song: Song, start: Date, until: Date)?

    /// 弹一首完整的曲子：几只宠物组成乐队，各拿各的乐器，弹完为止
    func play(_ song: Song) {
        let d = GuitarSynth.shared.play(song, volume: petVolume)
        let start = Date()
        nowPlaying = (song, start, start.addingTimeInterval(d))
        cheer(3)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(d + 0.2))
            if let n = nowPlaying, n.until <= Date() { nowPlaying = nil }
        }
    }

    func stopSong() {
        GuitarSynth.shared.stop()
        nowPlaying = nil
    }

    /// 让某一只宠物做个动作（target = 会话 id；nil = 主宠物）。互动动作顺带改心情
    func perform(_ a: PetAction, seconds: Double = 8, target: String? = nil) {
        petOverride = (a, Date().addingTimeInterval(seconds), target)
        switch a {
        case .guitar: GuitarSynth.shared.strum(volume: petVolume)
        case .whipped: cheer(-12)
        case .eat: cheer(10)
        case .laugh: cheer(5)
        case .walkDog, .fetch, .catNap: cheer(4)
        default: break
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds + 0.1))
            if let o = petOverride, o.until <= Date() { petOverride = nil }
        }
    }

    /// 改心情（正数开心，负数难过）
    func cheer(_ delta: Double) { happiness = min(100, max(0, happiness + delta)) }

    /// 每 3 秒一次：心情慢慢回到 60；额度快用完时往 30 掉
    private var lastDrift = Date()

    private func driftHappiness() {
        let target: Double = (menuPercent ?? 0) >= 95 ? 30 : 60
        // 每 3 秒 0.025 ≈ 每 10 分钟 5 点；按实际经过的时间算，检查频率变了速度也不变
        let now = Date()
        let step = 0.025 * min(4, now.timeIntervalSince(lastDrift) / 3)
        lastDrift = now
        if happiness > target + step { happiness -= step } else if happiness < target - step { happiness += step }
    }

    var visibleAccounts: [ClaudeAccount] { accounts.filter { !hiddenAccounts.contains($0.id) } }

    func nickname(_ a: ClaudeAccount) -> String {
        if let n = nicknames[a.id], !n.isEmpty { return n }
        return a.isDefault ? L("主号") : a.command
    }

    private func applyOverrides() {
        for i in accounts.indices { accounts[i].renewalAnchor = renewalOverrides[accounts[i].id].map(Date.init(timeIntervalSince1970:)) }
    }

    func setRenewal(_ d: Date?, for a: ClaudeAccount) {
        if let d { renewalOverrides[a.id] = d.timeIntervalSince1970 } else { renewalOverrides[a.id] = nil }
    }

    // MARK: 刷新

    func refreshAll() async {
        guard !refreshing, !Self.demo else { return }
        refreshing = true
        defer { refreshing = false; lastRefresh = Date() }
        accounts = ClaudeProvider.discoverAccounts()
        applyOverrides()
        var g = GrokProvider.status()
        // 保留上一次的账单数据，令牌过期时还能显示
        g.monthlyLimitCents = grok.monthlyLimitCents; g.usedCents = grok.usedCents; g.onDemandCapCents = grok.onDemandCapCents
        g.periodEnd = grok.periodEnd; g.billingFetchedAt = grok.billingFetchedAt; g.hasCodeAccess = grok.hasCodeAccess
        await withTaskGroup(of: Void.self) { group in
            for a in accounts {
                group.addTask { await self.refreshClaude(a) }
            }
            group.addTask { await self.refreshCodex() }
            group.addTask { await self.refreshGemini() }
            group.addTask {
                let filled = await GrokProvider.fetchBilling(into: g)
                await MainActor.run { withAnimation(.spring(duration: 0.8)) { self.grok = filled } }
            }
            group.addTask {
                let ag = await AntigravityProvider.fetch()
                await MainActor.run { if ag.running || self.antigravity == nil { self.antigravity = ag } }
            }
            group.addTask { await self.refreshApiBills() }
        }
        saveUsageCache()
        checkNotifications()
    }

    /// 截图模式用：只读本地缓存，不打官方额度接口（它限流很严）
    static var skipUsageNetwork = false

    private func refreshClaude(_ a: ClaudeAccount) async {
        if Self.skipUsageNetwork { if claudeUsage[a.id] != nil { claudeState[a.id] = .ok }; return }
        claudeState[a.id] = claudeUsage[a.id] == nil ? .loading : claudeState[a.id] ?? .loading
        // 官方额度接口限流很严：同一账号两次之间至少隔 100 秒，被限流后按退避时间等
        if let b = claudeBackoff[a.id], b.until > Date() {
            if let u = claudeUsage[a.id] {
                claudeState[a.id] = .stale(L("%@的数据 · %@", Fmt.ago(u.fetchedAt), retryText(b.until)))
            }
            return
        }
        if let t = claudeFetchedAt[a.id], Date().timeIntervalSince(t) < 100, claudeUsage[a.id] != nil { return }
        claudeFetchedAt[a.id] = Date()
        do {
            let u = try await ClaudeProvider.fetchUsage(a)
            detectReset(key: a.id, old: claudeUsage[a.id]?.fiveHour, new: u.fiveHour)
            withAnimation(.spring(duration: 0.8)) { claudeUsage[a.id] = u }
            claudeState[a.id] = .ok
            claudeBackoff[a.id] = nil
        } catch {
            var msg = describe(error)
            if case HTTPError.rateLimited(let after) = error {
                let step = min(1800, max(300, (claudeBackoff[a.id]?.step ?? 150) * 2))
                let wait = after ?? step
                let until = Date().addingTimeInterval(wait)
                claudeBackoff[a.id] = (until, step, false)
                msg = retryText(until)
            }
            // 实时查不到时，用 Claude Code 自己缓存的那份（如果比我们手上的新）
            if let cached = ClaudeProvider.cachedUsage(a), cached.fetchedAt > (claudeUsage[a.id]?.fetchedAt ?? .distantPast) {
                claudeUsage[a.id] = cached
            }
            if let u = claudeUsage[a.id] {
                claudeState[a.id] = .stale(L("%@的数据 · %@", Fmt.ago(u.fetchedAt), msg))
            } else {
                claudeState[a.id] = .failed(msg)
            }
            if let p = error as? ProviderError, [.needsLogin, .keychainWrite, .notLoggedIn].contains(p) { needsReauth.insert(a.id) }
        }
        if case .ok = claudeState[a.id] { needsReauth.remove(a.id) }
        // 资料每小时拉一次就够
        if Date().timeIntervalSince(profileFetchedAt[a.id] ?? .distantPast) > 3600 {
            profileFetchedAt[a.id] = Date()
            if let p = try? await ClaudeProvider.fetchProfile(a), let i = accounts.firstIndex(where: { $0.id == a.id }) {
                if let o = p.orgType { accounts[i].orgType = o }
                if let t = p.tier { accounts[i].tier = t }
                if let s = p.subCreated { accounts[i].subscriptionCreatedAt = s }
                if accounts[i].email == nil { accounts[i].email = p.email }
                profileStatus[a.id] = p.status ?? "unknown"
            }
        }
    }

    /// 需要重新登录的账号（续期失败）
    var needsReauth: Set<String> = []

    private func refreshCodex() async {
        if codex == nil { codexState = .loading }
        do {
            let s = try await CodexProvider.fetch()
            withAnimation(.spring(duration: 0.8)) { codex = s }
            codexState = s.fromLocalLog ? .stale(L("实时接口没连上，显示的是最近一次会话里的数据")) : .ok
        } catch {
            codexState = codex != nil ? .stale(describe(error)) : .failed(describe(error))
        }
    }

    private func refreshGemini() async {
        guard GeminiProvider.loggedIn else {
            gemini = GeminiStatus(loggedIn: false, fetchedAt: Date()); geminiState = .idle; return
        }
        do {
            let g = try await GeminiProvider.fetch()
            withAnimation(.spring(duration: 0.8)) { gemini = g }
            geminiState = .ok
        } catch {
            geminiState = gemini?.loggedIn == true ? .stale(describe(error)) : .failed(describe(error))
            if gemini == nil { gemini = GeminiStatus(loggedIn: true, fetchedAt: Date()) }
        }
    }

    // MARK: API 账单

    func refreshApiBills() async {
        for e in apiKeys {
            let b = await ApiBilling.fetch(e)
            apiBills[e.id] = b
            apiHistory.record(b, for: e.id)
        }
    }

    func addApiKey(_ e: ApiKeyEntry, key: String) -> Bool {
        guard ApiBilling.saveKey(key, for: e) else { return false }
        apiKeys.append(e)
        Task {
            let b = await ApiBilling.fetch(e)
            apiBills[e.id] = b
            apiHistory.record(b, for: e.id)
        }
        return true
    }

    func removeApiKey(_ e: ApiKeyEntry) {
        ApiBilling.deleteKey(for: e)
        apiKeys.removeAll { $0.id == e.id }
        apiBills[e.id] = nil
    }

    private func saveApiKeys() {
        if Self.demo { return }
        if let d = try? JSONEncoder().encode(apiKeys) { defaults.set(d, forKey: "apiKeys") }
    }

    private func describe(_ e: Error) -> String {
        if let p = e as? ProviderError { return p.errorDescription ?? L("出错了") }
        if case HTTPError.rateLimited = e { return L("官方接口限流，稍后自动再查") }
        if case HTTPError.status(let c, _) = e {
            switch c {
            case 401: return L("登录已失效，打开一次这个账号就会刷新")
            default: return L("服务器返回 %d", c)
            }
        }
        if (e as NSError).domain == NSURLErrorDomain { return L("网络连不上") }
        return e.localizedDescription
    }

    private var scanning = false

    func rescan(only: [(String, Provider)]? = nil) async {
        if Self.demo { return }
        // 同一时间只跑一次扫描，避免两次扫描同时改缓存
        guard !scanning else { return }
        scanning = true
        lastScanAt = Date()
        if only == nil { lastFullScanAt = Date() }
        defer { scanning = false }
        let first = !scanner.hasCache
        if first { scanProgress = 0 }
        let scanner = self.scanner
        let snap = await Task.detached(priority: .utility) { () -> StatsSnapshot in
            scanner.scan(only: only) { p in Task { @MainActor in if first { self.scanProgress = p } } }
        }.value
        withAnimation(.smooth(duration: 0.6)) {
            stats = snap
            scanProgress = nil
        }
    }

    /// 估算这个会话占了账号本周额度的多少：
    /// 会话本周 token ÷ 账号本周全部 token × 账号本周已用百分比。只是按 token 比例估，官方不提供逐会话数据
    func quotaShare(_ s: SessionSummary) -> Double? {
        guard s.provider == .claude, let keys = dayKeys(.week) else { return nil }
        let acc = s.account.flatMap { uuid in accounts.first { $0.accountUuid == uuid } } ?? accounts.first
        guard let acc, let weekly = claudeUsage[acc.id]?.weekly?.percent else { return nil }
        var mine: Int64 = 0
        for (d, t) in s.days where keys.contains(d) { mine += t.total }
        guard mine > 0 else { return 0 }
        let all = acc.accountUuid.map { total([.claude], .week, account: $0).total } ?? 0
        let base = all > 0 ? all : total([.claude], .week).total
        guard base > 0 else { return nil }
        return min(weekly, Double(mine) / Double(base) * weekly)
    }

    // MARK: 菜单栏显示

    /// 菜单栏上显示的那个百分比：默认取所有账号里最紧张的 5 小时额度
    var menuPercent: Double? {
        if menuAccount != "auto", let u = claudeUsage[menuAccount] { return u.fiveHour?.percent }
        let all = visibleAccounts.compactMap { claudeUsage[$0.id]?.fiveHour?.percent }
        return all.max()
    }

    /// 菜单栏轮播的每一条（图标 + 文字）
    struct TickerEntry: Equatable { var symbol: String?; var provider: Provider?; var text: String }

    var tickerEntries: [TickerEntry] {
        var out: [TickerEntry] = []
        let rem = showRemaining
        func pct(_ used: Double) -> String { rem ? L("剩%d%%", Int((100 - used).rounded())) : "\(Int(used.rounded()))%" }
        if tickerItems.contains(.claude) {
            for a in visibleAccounts {
                guard let u = claudeUsage[a.id] else { continue }
                let name = visibleAccounts.count > 1 ? nickname(a) + " " : ""
                if let w = u.fiveHour { out.append(.init(provider: .claude, text: "\(name)5h \(pct(w.percent))")) }
                if let w = u.weekly { out.append(.init(provider: .claude, text: "\(name)\(L("周")) \(pct(w.percent))")) }
            }
        }
        if tickerItems.contains(.codex), let w = codex?.windows.first {
            out.append(.init(provider: .codex, text: "Codex \(pct(w.percent))"))
        }
        if tickerItems.contains(.gemini), let b = gemini?.buckets.max(by: { $0.percent < $1.percent }) {
            out.append(.init(provider: .gemini, text: "Gemini \(pct(b.percent))"))
        }
        if tickerItems.contains(.cpu) { out.append(.init(symbol: "cpu", text: "CPU \(Int(system.cpuPercent.rounded()))%")) }
        if tickerItems.contains(.memory) { out.append(.init(symbol: "memorychip", text: L("内存 %d%%", Int(system.memPercent.rounded())))) }
        if tickerItems.contains(.disk) { out.append(.init(symbol: "internaldrive", text: L("剩 %@", system.diskFree.bytesShort))) }
        if tickerItems.contains(.tokens) { out.append(.init(symbol: "sum", text: Double(total(Set(Provider.allCases), .today).total).tokenShort)) }
        return out
    }

    var mood: PetMood {
        if let c = celebrateUntil, c > Date() { return .celebrate }
        if let p = menuPercent, p >= 95 { return .sleepy }
        if claudeActive { return .working }
        if let p = menuPercent, p >= 80 { return .worried }
        return .idle
    }

    func celebrate(seconds: Double = 3) {
        celebrateUntil = Date().addingTimeInterval(seconds)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds + 0.1))
            if let c = celebrateUntil, c <= Date() { celebrateUntil = nil }
        }
    }

    // MARK: 通知

    private func requestNotify() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func detectReset(key: String, old: QuotaWindow?, new: QuotaWindow?) {
        guard let old, let new else { return }
        if old.percent >= 50, new.percent < 10, (old.resetsAt ?? .distantFuture) <= Date().addingTimeInterval(120) {
            celebrate(seconds: 4)
            if let a = accounts.first(where: { $0.id == key }) {
                let (title, body) = (L("%@ 的 5 小时额度已重置", nickname(a)), L("又可以放心用啦。"))
                if notifyReset { send(.reset, title, body) } else { relay(.reset, title, body) }
            }
        }
    }

    /// 额度用到设定的百分比、以及 95% 时各提醒一次（每个重置周期只提醒一次）
    private func checkNotifications() {
        let phone = phoneWants?(.quota) ?? false
        guard notifyHigh || phone else { return }
        func check(_ key: String, _ who: String, _ w: QuotaWindow, weekly: Bool) {
            let stamp = w.resetsAt.map { String(Int($0.timeIntervalSince1970)) } ?? "x"
            // 只提醒达到的最高一档，免得一次弹两条
            guard let level = AlertRules.quotaLevel(percent: w.percent, setting: quotaAlertPercent) else { return }
            let k = "\(key)|\(stamp)|\(level)"
            guard notified.insert(k).inserted else { return }
            let title = weekly ? L("%@ 的本周额度用了 %d%%", who, Int(w.percent)) : L("%@ 的 5 小时额度用了 %d%%", who, Int(w.percent))
            let body = w.resetsAt.map { L("注意节奏，%@ 重置。", Fmt.shortDate($0)) } ?? L("注意节奏。")
            if notifyHigh { send(.quota, title, body) } else { relay(.quota, title, body) }
        }
        for a in visibleAccounts {
            guard let u = claudeUsage[a.id] else { continue }
            if let w = u.fiveHour { check(a.id, nickname(a), w, weekly: false) }
            if let w = u.weekly { check(a.id + "|week", nickname(a), w, weekly: true) }
        }
        for w in codex?.windows ?? [] {
            check("codex|" + w.id, "Codex", w, weekly: w.id.contains("week") || w.title.contains("周"))
        }
        if notified.count > 200 { notified = Set(notified.suffix(100)) }
        defaults.set(Array(notified), forKey: "notified")
    }

    private var resourceAlarm = ResourceAlarm()

    private func checkSystemAlerts() {
        guard notifySystem, Pro.shared.hasAccess else { return }   // 资源提醒是完整版功能
        let s = system
        for k in resourceAlarm.check(cpu: s.cpuPercent, memory: s.memPercent, diskFree: s.diskFree, limits: alertLimits) {
            switch k {
            case .cpu:
                send(.system, L("CPU 占用持续偏高"), L("超过 %d%% 已经两分钟，现在是 %d%%。可以看看是哪个程序在占用。", cpuAlert, Int(s.cpuPercent)))
            case .memory:
                send(.system, L("内存快用满了"), L("已用 %d%%（%@ / %@），电脑可能会变卡。", Int(s.memPercent), s.memUsed.bytesShort, s.memTotal.bytesShort))
            case .disk:
                send(.system, L("磁盘空间快满了"), L("只剩 %@，低于你设的 %d GB，建议清理一下。", s.diskFree.bytesShort, diskAlertGB))
            }
        }
    }

    /// App Store 版用它把提醒同步推送到 iPhone
    var onEvent: ((AlertKind, String, String) -> Void)?
    /// iPhone 是否想收这类提醒（App Store 版由 DeskSync 设置）；Mac 上关了的提醒，iPhone 照样可以收
    var phoneWants: ((AlertKind) -> Bool)?

    enum AlertKind: String { case done, asking, quota, reset, system, schedule }

    /// 只转发给 iPhone，Mac 上不弹
    private func relay(_ kind: AlertKind, _ title: String, _ body: String) { onEvent?(kind, title, body) }

    func send(_ kind: AlertKind, _ title: String, _ body: String) {
        onEvent?(kind, title, body)
        let c = UNMutableNotificationContent()
        c.title = title; c.body = body; c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }

    // MARK: 开机启动

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do { newValue ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
            catch { flash(L("没设置成功：%@", error.localizedDescription)) }
        }
    }

    func flash(_ s: String) {
        withAnimation(.spring) { toast = s }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.6))
            withAnimation(.easeOut) { if toast == s { toast = nil } }
        }
    }

    // MARK: 缓存（启动时先显示上一次的数据）

    private struct UsageCache: Codable {
        var claude: [String: ClaudeUsage]; var codex: CodexStatus?
        var grok: GrokStatus?; var gemini: GeminiStatus?; var antigravity: AntigravityProvider.Status?; var bills: [String: ApiBill]?
    }

    private func saveUsageCache() {
        if Self.demo { return }
        let c = UsageCache(claude: claudeUsage, codex: codex, grok: grok, gemini: gemini, antigravity: antigravity, bills: apiBills)
        if let d = try? JSONEncoder().encode(c) { try? d.write(to: usageCacheURL, options: .atomic) }
    }

    private func loadUsageCache() {
        guard let d = try? Data(contentsOf: usageCacheURL), let c = try? JSONDecoder().decode(UsageCache.self, from: d) else { return }
        claudeUsage = c.claude
        codex = c.codex
        if let g = c.grok { grok = g }
        gemini = c.gemini
        antigravity = c.antigravity
        apiBills = c.bills ?? [:]
        for k in c.claude.keys { claudeState[k] = .stale(L("正在更新…")) }
    }

    // MARK: 统计查询

    enum Range: String, CaseIterable, Identifiable { case today = "今天", week = "本周", month = "本月", all = "全部"; var id: String { rawValue } }

    nonisolated(unsafe) static let dayFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f }()

    func dayKeys(_ r: Range, offset: Int = 0) -> Set<String>? {
        let cal = Calendar.current
        let now = Date()
        var start: Date, end: Date
        switch r {
        case .all: return nil
        case .today:
            start = cal.startOfDay(for: now); end = cal.date(byAdding: .day, value: 1, to: start)!
            start = cal.date(byAdding: .day, value: -offset, to: start)!; end = cal.date(byAdding: .day, value: -offset, to: end)!
        case .week:
            var c = cal; c.firstWeekday = 2
            start = c.dateInterval(of: .weekOfYear, for: now)!.start; end = c.date(byAdding: .day, value: 7, to: start)!
            start = cal.date(byAdding: .day, value: -7 * offset, to: start)!; end = cal.date(byAdding: .day, value: -7 * offset, to: end)!
        case .month:
            start = cal.dateInterval(of: .month, for: now)!.start
            start = cal.date(byAdding: .month, value: -offset, to: start)!
            end = cal.date(byAdding: .month, value: 1, to: start)!
        }
        var keys = Set<String>()
        var d = start
        while d < end { keys.insert(Self.dayFmt.string(from: d)); d = cal.date(byAdding: .day, value: 1, to: d)! }
        return keys
    }

    /// 上一个周期的「同期」：本周已过 3 天，就只取上周的前 3 天来比，避免拿半周和整周比
    func previousSamePeriod(_ providers: Set<Provider>, _ r: Range) -> Tok {
        guard r == .week || r == .month, let cur = dayKeys(r), let prev = dayKeys(r, offset: 1) else { return total(providers, r, offset: 1) }
        let today = Self.dayFmt.string(from: .now)
        let elapsed = cur.sorted().filter { $0 <= today }.count
        return total(providers, keys: Set(prev.sorted().prefix(elapsed)))
    }

    func total(_ providers: Set<Provider>, keys: Set<String>) -> Tok {
        guard let s = stats else { return Tok() }
        var t = Tok()
        for p in providers { for (day, v) in s.days[p] ?? [:] where keys.contains(day) { t += v } }
        return t
    }

    func total(_ providers: Set<Provider>, _ r: Range, offset: Int = 0, account: String? = nil) -> Tok {
        guard let s = stats else { return Tok() }
        let keys = dayKeys(r, offset: offset)
        var t = Tok()
        if let account {
            for (day, v) in s.claudeAccountDays[account] ?? [:] where keys?.contains(day) ?? true { t += v }
            return t
        }
        for p in providers {
            for (day, v) in s.days[p] ?? [:] where keys?.contains(day) ?? true { t += v }
        }
        return t
    }

    func dailySeries(_ providers: Set<Provider>, days: Int) -> [(date: Date, provider: Provider, tokens: Double)] {
        guard let s = stats else { return [] }
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        var out: [(Date, Provider, Double)] = []
        for i in stride(from: days - 1, through: 0, by: -1) {
            let d = cal.date(byAdding: .day, value: -i, to: today)!
            let k = Self.dayFmt.string(from: d)
            for p in Provider.allCases where providers.contains(p) {
                out.append((d, p, Double(s.days[p]?[k]?.total ?? 0)))
            }
        }
        return out
    }

    func heat(_ providers: Set<Provider>) -> [String: Double] {
        guard let s = stats else { return [:] }
        var m: [String: Double] = [:]
        for p in providers { for (k, v) in s.days[p] ?? [:] { m[k, default: 0] += Double(v.total) } }
        return m
    }
}


// MARK: - 演示数据

extension AppModel {
    /// 编好的假数据：两个 Claude 账号、Codex、Gemini、Grok，四个正在干活的会话，30 天 token 曲线，一个 API 账单
    fileprivate func fillDemo() {
        let now = Date()
        let zh = [.zhHans, .zhHant].contains(AppLanguage.current), ja = AppLanguage.current == .ja
        let hant = AppLanguage.current == .zhHant
        // 繁中界面的演示数据转成繁体字（台湾、香港的商店截图要用）
        func t(_ en: String, _ c: String, _ j: String) -> String {
            guard zh else { return ja ? j : en }
            return hant ? (c.applyingTransform(StringTransform("Hans-Hant"), reverse: false) ?? c) : c
        }
        let h = 3600.0, d = 86400.0

        accounts = [
            ClaudeAccount(command: "claude", configDir: "/demo/.claude", configJSON: "", keychainService: "", isDefault: true,
                          email: "ada@example.com", orgType: "claude_max", tier: "default_claude_max_20x",
                          subscriptionCreatedAt: now.addingTimeInterval(-40 * d), promoClaimed: false, passesRemaining: 2),
            ClaudeAccount(command: "claude2", configDir: "/demo/.claude-b", configJSON: "", keychainService: "", isDefault: false,
                          email: "ada.work@example.com", orgType: "claude_max", tier: "default_claude_max_5x",
                          subscriptionCreatedAt: now.addingTimeInterval(-12 * d), promoClaimed: true),
        ]
        claudeUsage = [
            "/demo/.claude": ClaudeUsage(fiveHour: .init(id: "5h", title: "5 小时", percent: 42, resetsAt: now.addingTimeInterval(2.3 * h)),
                                         weekly: .init(id: "7d", title: "本周", percent: 63, resetsAt: now.addingTimeInterval(2.6 * d)),
                                         extraWindows: [.init(id: "7d-opus", title: "Fable 每周", percent: 31, resetsAt: now.addingTimeInterval(2.6 * d))],
                                         money: [MoneyQuota(title: "每月赠送额度", used: 37.5, limit: 200, resetsAt: now.addingTimeInterval(17 * d))],
                                         breakdown: [.init(id: "a", name: "Fable", percent: 58), .init(id: "b", name: "Opus", percent: 27), .init(id: "c", name: "Sonnet", percent: 15)],
                                         fetchedAt: now),
            "/demo/.claude-b": ClaudeUsage(fiveHour: .init(id: "5h", title: "5 小时", percent: 88, resetsAt: now.addingTimeInterval(0.7 * h)),
                                           weekly: .init(id: "7d", title: "本周", percent: 47, resetsAt: now.addingTimeInterval(4.2 * d)),
                                           money: [MoneyQuota(title: "每月赠送额度", used: 12, limit: 100, resetsAt: now.addingTimeInterval(19 * d))],
                                           fetchedAt: now),
        ]
        for a in accounts { claudeState[a.id] = .ok }
        codex = CodexStatus(email: "ada@example.com", plan: "pro", activeUntil: now.addingTimeInterval(23 * d),
                            windows: [.init(id: "5h", title: "5 小时", percent: 18, resetsAt: now.addingTimeInterval(3.1 * h)),
                                      .init(id: "7d", title: "本周", percent: 54, resetsAt: now.addingTimeInterval(3.4 * d))],
                            resetCredits: 2, creditsBalance: "120", fetchedAt: now)
        codexState = .ok
        gemini = GeminiStatus(loggedIn: true, email: "ada@example.com", tierName: "Google AI Pro",
                              buckets: [.init(id: "pro", title: "Gemini 3 Pro", percent: 22, resetsAt: now.addingTimeInterval(9 * h)),
                                        .init(id: "flash", title: "Gemini 3 Flash", percent: 6, resetsAt: now.addingTimeInterval(9 * h))],
                              fetchedAt: now)
        geminiState = .ok
        antigravity = nil
        grok = GrokStatus(loggedIn: true, tier: "SuperGrok", email: "ada@example.com", fetchedAt: now,
                          monthlyLimitCents: 5000, usedCents: 1830, periodEnd: now.addingTimeInterval(11 * d), hasCodeAccess: true, billingFetchedAt: now)

        // 30 天的 token：工作日多、周末少，最近几天在涨
        var stat = StatsSnapshot()
        var rng = SplitMix(seed: 42)
        func tok(_ scale: Double) -> Tok {
            let k = scale * (0.75 + 0.5 * abs(rng.signed()))
            return Tok(i: Int64(k * 0.02e6), o: Int64(k * 0.05e6), cw: Int64(k * 0.9e6), cr: Int64(k * 14e6))
        }
        let cal = Calendar.current
        for back in 0..<140 {
            let day = now.addingTimeInterval(-Double(back) * d)
            let key = DayKey.local(day)
            let weekend = cal.isDateInWeekend(day)
            let trend = 1 + Double(max(0, 30 - back)) / 30
            let base = (weekend ? 0.35 : 1.0) * trend * (back > 100 ? 0.4 : 1)
            stat.days[.claude, default: [:]][key] = tok(9 * base)
            stat.days[.codex, default: [:]][key] = tok(3.2 * base)
            stat.days[.gemini, default: [:]][key] = tok(0.8 * base)
            if back % 3 == 0 { stat.days[.grok, default: [:]][key] = tok(0.6 * base) }
            stat.claudeAccountDays["/demo/.claude", default: [:]][key] = tok(6 * base)
            stat.claudeAccountDays["/demo/.claude-b", default: [:]][key] = tok(3 * base)
        }
        let titles: [(Provider, String, String, String, Double, String?)] = [
            (.claude, "s1", t("Ship the onboarding redesign", "上线新的引导流程", "オンボーディングを刷新"), "~/code/acme-web", 3.2, "/demo/.claude"),
            (.claude, "s2", t("Fix flaky checkout tests", "修复不稳定的结算测试", "決済テストの不安定を修正"), "~/code/acme-shop", 1.4, "/demo/.claude-b"),
            (.codex, "s3", t("Refactor the billing service", "重构计费服务", "課金サービスをリファクタ"), "~/code/billing", 2.1, nil),
            (.gemini, "s4", t("Draft the v2 release notes", "写 2.0 版发布说明", "v2 リリースノートの下書き"), "~/code/docs", 0.4, nil),
            (.claude, "s5", t("Add dark mode to settings", "设置页加深色模式", "設定画面にダークモード"), "~/code/acme-web", 0.9, "/demo/.claude"),
            (.claude, "s6", t("Migrate images to WebP", "图片批量转 WebP", "画像を WebP に移行"), "~/code/acme-web", 0.6, "/demo/.claude"),
            (.codex, "s7", t("Write API rate-limit middleware", "写接口限流中间件", "API レート制限を実装"), "~/code/billing", 1.1, nil),
            (.grok, "s8", t("Summarize user interviews", "整理用户访谈", "ユーザーインタビューを要約"), "~/notes", 0.3, nil),
        ]
        stat.sessions = titles.enumerated().map { i, x in
            var s = SessionSummary(provider: x.0, sessionId: x.1, title: x.2, cwd: x.3, account: x.5, model: x.0 == .claude ? "claude-fable-5-1" : nil,
                                   lastActive: now.addingTimeInterval(-Double(i) * 2.7 * h), tokens: tok(x.4 * 10))
            s.bytes = UInt64(x.4 * 9_000_000); s.files = 1 + i % 3; s.turns = Int(x.4 * 60); s.tools = Int(x.4 * 140)
            s.firstActive = now.addingTimeInterval(-Double(i) * 2.7 * h - 1.5 * h)
            s.costUSD = x.4 * 6.4
            // 账单页按模型和日期折算，所以把 token 摊到最近几天
            if x.0 == .claude { s.models = ["claude-opus-5-5": s.tokens] }
            let spread = 4 + i * 2
            for n in 0..<spread {
                let key = AppModel.dayFmt.string(from: s.lastActive.addingTimeInterval(-Double(n) * d))
                let f = Double(spread)
                s.days[key] = Tok(i: Int64(Double(s.tokens.i) / f), o: Int64(Double(s.tokens.o) / f), cw: Int64(Double(s.tokens.cw) / f), cr: Int64(Double(s.tokens.cr) / f))
            }
            return s
        }
        stat.scannedAt = now
        stats = stat

        // 正在干活的四个会话：不同的事、不同的动作
        live = [
            LiveSession(pid: 0, provider: .claude, sessionId: "s1", cwd: "~/code/acme-web", configDir: "/demo/.claude", busy: true, startedAt: now.addingTimeInterval(-1460),
                        tool: "Agent", detail: t("Audit every page for a11y", "逐页检查无障碍", "全ページのアクセシビリティ確認"),
                        say: t("Spinning up 3 helpers to check the forms, nav and modals in parallel.", "派 3 个小弟分头检查表单、导航和弹窗。", "フォーム・ナビ・モーダルを 3 体の助手で並行チェックします。"),
                        subagents: 3, cpu: 18, rss: 420_000_000),
            LiveSession(pid: 0, provider: .claude, sessionId: "s2", cwd: "~/code/acme-shop", configDir: "/demo/.claude-b", busy: true, startedAt: now.addingTimeInterval(-610),
                        tool: "Bash", detail: t("Run the checkout test suite", "跑结算测试", "決済テストを実行"),
                        say: t("Found it — the test waited on a timer. Switching to a fake clock.", "找到了：测试在等真实计时器，换成假时钟。", "原因はタイマー待ちでした。フェイククロックに置き換えます。"),
                        cpu: 64, rss: 610_000_000),
            LiveSession(pid: 0, provider: .codex, sessionId: "s3", cwd: "~/code/billing", busy: true, startedAt: now.addingTimeInterval(-2210),
                        tool: "Edit", detail: "invoice.ts",
                        say: t("Pulled the tax math into one pure function and added tests.", "把税额计算抽成一个纯函数，补了测试。", "税計算を純粋関数に切り出してテストを追加しました。"),
                        cpu: 9, rss: 280_000_000),
        ]
        for l in live { busySince[l.id] = l.startedAt }

        apiKeys = [ApiKeyEntry(name: "Team console", kind: .anthropicAdmin), ApiKeyEntry(name: "OpenRouter", kind: .openrouter)]
        var bill = ApiBill(fetchedAt: now)
        bill.monthSpend = 184.2; bill.limit = 500
        for back in 0..<14 { bill.daily[DayKey.local(now.addingTimeInterval(-Double(back) * d))] = 6 + Double((back * 7) % 11) * 1.3 }
        apiBills[apiKeys[0].id] = bill
        var orb = ApiBill(fetchedAt: now); orb.balance = 37.8; orb.limit = 50
        apiBills[apiKeys[1].id] = orb
        happiness = 86
        lastRefresh = now
    }
}
