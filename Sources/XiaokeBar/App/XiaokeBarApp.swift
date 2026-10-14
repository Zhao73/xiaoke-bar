import SwiftUI
import AppKit
import Observation

@main
struct XiaokeBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() {
        // 命令行自检：XiaokeBar --selftest 打印扫描结果，方便核对数字
        if CommandLine.arguments.contains("--selftest") {
            SelfTest.run()
            exit(0)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
            Snapshot.run(dir: CommandLine.arguments[i + 1])
        }
    }

    var body: some Scene {
        Settings { EmptyView() }
    }
}

/// 菜单栏图标用原生 NSStatusItem 做：SwiftUI 的 MenuBarExtra 每次换图标都会再触发一次刷新，
/// 会陷入 CPU 100% 的死循环。这里只在内容真的变了才更新图标。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let model = AppModel()
    private var item: NSStatusItem!
    private let popover = NSPopover()
    private var animTimer: Timer?
    private var tickerTimer: Timer?
    private var frame = 0
    private var tickerIndex = 0
    private var images: [String: NSImage] = [:]
    private var lastTitle = NSAttributedString()
    private lazy var floating = FloatingPetController(model: model)

    func applicationDidFinishLaunching(_ note: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // 记住用户按住 ⌘ 拖动后的位置。刘海屏菜单栏放不下时，系统会先藏最左边的图标，拖到靠右就不会被挡
        item.autosaveName = "XiaokeBarMain"
        if let b = item.button {
            b.imagePosition = .imageLeading
            b.target = self
            b.action = #selector(clicked(_:))
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])
            b.wantsLayer = true
        }
        popover.contentSize = NSSize(width: 420, height: 680)
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        model.start()
        floating.onOpen = { [weak self] in self?.togglePopover() }
        observe()
        tickerTimer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.advanceTicker() }
        }
        // 常驻后台的工具：第一次运行时默认设为开机自动打开（之后在设置里可以关）
        if !UserDefaults.standard.bool(forKey: "didSetupLoginItem"), Bundle.main.bundlePath.hasSuffix(".app") {
            UserDefaults.standard.set(true, forKey: "didSetupLoginItem")
            model.launchAtLogin = true
        }
        // 调试：XIAOKE_DEBUG_OPEN=1 时启动 5 秒后自动弹出面板（不抢焦点），用于截图检查
        if let tab = ProcessInfo.processInfo.environment["XIAOKE_DEBUG_OPEN"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [self] in
                if let t = AppModel.Tab(rawValue: tab) { model.tab = t }
                if let b = item.button { attachContent(); popover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY); model.popoverOpened() }
            }
        }
        if ProcessInfo.processInfo.environment["XIAOKE_DEBUG_PET"] == "1" { model.floatingPet = true }
    }

    /// 只追踪菜单栏需要的几个值，变了才重画
    private func observe() {
        withObservationTracking {
            _ = model.tickerEntries
            _ = model.menuMode
            _ = model.pet.kind
            _ = model.pet.action
            _ = model.menuPercent
            _ = model.floatingPet
        } onChange: {
            Task { @MainActor in self.observe() }
        }
        updateButton()
        updateAnimation()
        floating.sync()
    }

    private func image(_ kind: Provider, _ key: String, _ pose: PetArt.Pose) -> NSImage {
        let k = kind.rawValue + key
        if let i = images[k] { return i }
        let i = PetArt.menuImage(kind, pose: pose)
        images[k] = i
        return i
    }

    private var petBusy: Bool { ![.idle, .sleep, .worried].contains(model.pet.action) }

    /// 只换宠物那一帧图片：动画计时器每 0.45 秒调一次，不碰文字和宽度（那些重算很贵）
    private func updateImage() {
        guard let b = item.button else { return }
        let pet = model.pet
        let img: NSImage
        if petBusy {
            img = image(pet.kind, "walk\(frame)", .init(armWave: frame + 1, legPhase: frame + 1))
        } else if pet.action == .sleep {
            img = image(pet.kind, "sleep", .init(eyesClosed: true))
        } else {
            img = image(pet.kind, "idle", .init())
        }
        if b.image !== img { b.image = img }
    }

    private func updateButton() {
        guard let b = item.button else { return }
        let pet = model.pet
        let img: NSImage
        if petBusy {
            img = image(pet.kind, "walk\(frame)", .init(armWave: frame + 1, legPhase: frame + 1))
        } else if pet.action == .sleep {
            img = image(pet.kind, "sleep", .init(eyesClosed: true))
        } else {
            img = image(pet.kind, "idle", .init())
        }
        if b.image !== img { b.image = img }
        let title = currentTitle()
        if !title.isEqual(to: lastTitle) {
            lastTitle = title
            b.attributedTitle = title
        }
        let len = fixedLength()
        if item.length != len { item.length = len }
        let tip = model.tickerEntries.map(\.text).joined(separator: "  ·  ")
        let t = tip.isEmpty ? L("小克额度栏") : tip
        if b.toolTip != t { b.toolTip = t }
    }

    private func currentTitle() -> NSAttributedString {
        switch model.menuMode {
        case .icon: return NSAttributedString()
        case .percent:
            let t = model.menuPercent.map { " \(Int($0))%" } ?? ""
            return NSAttributedString(string: t, attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)])
        case .ticker:
            let list = model.tickerEntries
            guard !list.isEmpty else { return NSAttributedString() }
            return attributed(list[tickerIndex % list.count])
        }
    }

    private func attributed(_ e: AppModel.TickerEntry) -> NSAttributedString {
        let out = NSMutableAttributedString(string: " ")
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        var icon: NSImage?
        if let p = e.provider, let logo = LogoStore.image(p.logo)?.copy() as? NSImage {
            logo.size = NSSize(width: 12, height: 12)
            logo.isTemplate = p == .grok
            icon = logo
        } else if let s = e.symbol {
            icon = NSImage(systemSymbolName: s, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
        }
        if let icon {
            let att = NSTextAttachment()
            att.image = icon
            att.bounds = CGRect(x: 0, y: -2, width: icon.size.width, height: icon.size.height)
            out.append(NSAttributedString(attachment: att))
            out.append(NSAttributedString(string: " "))
        }
        out.append(NSAttributedString(string: e.text, attributes: [.font: font]))
        return out
    }

    /// 轮播时宽度固定为最长那条，切换时菜单栏其他图标不会被挤来挤去
    private func fixedLength() -> CGFloat {
        guard model.menuMode == .ticker, !model.tickerEntries.isEmpty else { return NSStatusItem.variableLength }
        // 文字没变就用上次量好的宽度（量宽度要排版每一条，开销不小）
        let key = model.tickerEntries.map(\.text).joined(separator: "|")
        if key == lengthKey { return lengthCache }
        let w = model.tickerEntries.map { attributed($0).size().width }.max() ?? 0
        lengthKey = key
        lengthCache = min(170, ceil(w) + 24 + 10)
        return lengthCache
    }
    private var lengthKey = ""
    private var lengthCache: CGFloat = NSStatusItem.variableLength

    private func advanceTicker() {
        guard model.menuMode == .ticker, model.tickerEntries.count > 1, let b = item.button else { return }
        tickerIndex = (tickerIndex + 1) % model.tickerEntries.count
        // 向上滚动切换
        let tr = CATransition()
        tr.type = .push
        tr.subtype = .fromTop
        tr.duration = 0.35
        tr.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        b.layer?.add(tr, forKey: "ticker")
        updateButton()
    }

    /// 宠物在干活时菜单栏图标两帧交替（每 0.45 秒），不干活就停计时器
    private func updateAnimation() {
        if petBusy, animTimer == nil {
            animTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.frame = (self.frame + 1) % 2
                    self.updateImage()
                }
            }
        } else if !petBusy, let t = animTimer {
            t.invalidate(); animTimer = nil; frame = 0
        }
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let m = NSMenu()
            m.addItem(withTitle: L("立即刷新"), action: #selector(refresh), keyEquivalent: "r").target = self
            let pet = m.addItem(withTitle: model.floatingPet ? L("隐藏桌面宠物") : L("显示桌面宠物"), action: #selector(togglePet), keyEquivalent: "")
            pet.target = self
            let songs = NSMenu()
            songs.addItem(withTitle: L("随手扫一段 🎸"), action: #selector(guitar), keyEquivalent: "").target = self
            songs.addItem(.separator())
            for song in Song.all {
                let it = songs.addItem(withTitle: song.title, action: #selector(playSong(_:)), keyEquivalent: "")
                it.target = self
                it.representedObject = song.id
                it.state = model.nowPlaying?.song == song ? .on : .off
            }
            if model.nowPlaying != nil {
                songs.addItem(.separator())
                songs.addItem(withTitle: L("停止演奏"), action: #selector(stopSong), keyEquivalent: "").target = self
            }
            let songItem = m.addItem(withTitle: L("弹一首歌"), action: nil, keyEquivalent: "")
            m.setSubmenu(songs, for: songItem)
            m.addItem(.separator())
            m.addItem(withTitle: L("退出小克额度栏"), action: #selector(quit), keyEquivalent: "q").target = self
            item.menu = m
            item.button?.performClick(nil)
            item.menu = nil
            return
        }
        togglePopover()
    }

    private func togglePopover() {
        guard let b = item.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            attachContent()
            popover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            NSApp.activate(ignoringOtherApps: true)
            model.popoverOpened()
        }
    }

    /// 面板内容只在打开时存在：里面有不少动画，关着还挂在那里会一直耗 CPU
    private func attachContent() {
        guard popover.contentViewController == nil else { return }
        let host = NSHostingController(rootView: RootView().environment(model))
        host.view.frame = NSRect(x: 0, y: 0, width: 420, height: 680)
        popover.contentViewController = host
    }

    func popoverDidClose(_ notification: Notification) {
        popover.contentViewController = nil
        model.popoverClosed()
    }

    @objc private func refresh() { Task { await model.refreshAll(); await model.rescan() } }
    @objc private func togglePet() { model.floatingPet.toggle() }
    @objc private func guitar() { model.perform(.guitar, seconds: 9); if !model.floatingPet { model.floatingPet = true } }
    @objc private func playSong(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let song = Song.all.first(where: { $0.id == id }) else { return }
        model.play(song)
        if !model.floatingPet { model.floatingPet = true }
    }
    @objc private func stopSong() { model.stopSong() }
    @objc private func quit() { NSApp.terminate(nil) }
}
