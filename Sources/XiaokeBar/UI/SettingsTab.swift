import SwiftUI

// MARK: 设置

struct SettingsTab: View {
    @Environment(AppModel.self) private var model
    @State private var confirmPlan: AccountMaker.Plan?
    @State private var loginOn = false

    var body: some View {
        @Bindable var m = model
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                section(L("Claude 账号"), icon: "person.2.fill") {
                    ForEach(model.accounts) { a in
                        AccountSettingRow(account: a)
                        if a.id != model.accounts.last?.id { Divider().opacity(0.5) }
                    }
                    Button {
                        confirmPlan = AccountMaker.nextPlan(existing: model.accounts)
                        if confirmPlan == nil { model.flash(L("claude2～claude9 都占满了")) }
                    } label: {
                        Label(L("新增一个 Claude 账号"), systemImage: "plus.circle.fill").font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain).foregroundStyle(Provider.claude.tint)
                    .padding(.top, 2)
                }
                .staggerIn(0)

                section(L("显示"), icon: "paintpalette.fill") {
                    Picker(L("语言"), selection: $m.language) {
                        ForEach(AppLanguage.allCases) { l in Text(l.label).tag(l.rawValue) }
                    }
                    Picker(L("额度显示"), selection: $m.showRemaining) {
                        Text(L("剩余多少（和 Codex 官方一样）")).tag(true)
                        Text(L("用了多少（和 Claude 官方一样）")).tag(false)
                    }
                    SwitchRow(title: L("隐藏邮箱中间部分"), isOn: $m.hideEmail)
                    SwitchRow(title: L("隐私模式：会话标题和内容打码（录屏、截图时用）"), isOn: $m.privacyMode)
                }
                .staggerIn(1)

                section(L("菜单栏"), icon: "menubar.rectangle") {
                    Picker(L("显示方式"), selection: $m.menuMode) {
                        ForEach(AppModel.MenuMode.allCases) { Text($0.title).tag($0) }
                    }
                    if model.menuMode == .ticker {
                        Text(L("轮播内容")).font(.system(size: 11)).foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 6) {
                            ForEach(AppModel.TickerItem.allCases) { it in
                                Toggle(it.title, isOn: Binding(get: { model.tickerItems.contains(it) }, set: { on in
                                    if on { model.tickerItems.insert(it) } else { model.tickerItems.remove(it) }
                                }))
                                .toggleStyle(.checkbox).font(.system(size: 11))
                            }
                        }
                    }
                    if model.menuMode == .percent {
                        Picker(L("显示哪个账号"), selection: $m.menuAccount) {
                            Text(L("自动（最紧张的账号）")).tag("auto")
                            ForEach(model.accounts) { a in Text(model.nickname(a)).tag(a.id) }
                        }
                    }
                    Text(L("刘海屏菜单栏放不下时，系统会先藏最左边的图标。按住 ⌘ 把小克拖到靠右的位置，就不会被挡住（位置会记住）。"))
                        .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .staggerIn(2)

                section(L("宠物与提醒"), icon: "pawprint.fill") {
                    SwitchRow(title: L("桌面宠物（浮在最前面，显示会话进展）"), isOn: $m.floatingPet)
                    SwitchRow(title: L("任务做完时发通知"), isOn: $m.notifyDone)
                    SwitchRow(title: L("会话停下来等你确认时发通知"), isOn: $m.notifyAsking)
                    SwitchRow(title: L("任务做完时播放提示音"), isOn: $m.doneSound)
                    SwitchRow(title: L("养一只柴犬（空闲时会去遛狗、玩球）"), isOn: $m.hasDog)
                    SwitchRow(title: L("养一只橘猫（空闲时会趴头上、一起睡）"), isOn: $m.hasCat)
                    HStack {
                        Text(L("心情"))
                        ProgressView(value: model.happiness, total: 100).tint(model.happiness < 35 ? .orange : .green)
                        Text("\(Int(model.happiness.rounded()))").font(.system(size: 11, design: .rounded)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .help(L("摸头、喂零食、任务做完会变开心；抽鞭子、额度快用完会变难过。心情会影响表情和空闲时做什么"))
                    HStack {
                        Text(L("乐器音量"))
                        Slider(value: $m.petVolume, in: 0...1)
                        Button { model.perform(.guitar, seconds: 9) } label: { Image(systemName: "play.circle.fill") }.buttonStyle(.plain)
                            .help(L("试听"))
                    }
                    Divider().opacity(0.5)
                    SwitchRow(title: L("额度快用完时提醒（5 小时和每周）"), isOn: $m.notifyHigh)
                    if model.notifyHigh {
                        AlertLimitRow(icon: "gauge.with.needle", title: L("用到这个比例时提醒（95% 再提醒一次）"), value: $m.quotaAlertPercent, range: 50...95, step: 5, unit: "%")
                    }
                    SwitchRow(title: L("额度重置后提醒"), isOn: $m.notifyReset)
                    Divider().opacity(0.5)
                    if Pro.shared.hasAccess {
                        SwitchRow(title: L("电脑资源紧张时提醒"), isOn: $m.notifySystem)
                    } else {
                        HStack {
                            Text(L("电脑资源紧张时提醒"))
                            Spacer()
                            Button { Pro.shared.showPaywall = true } label: { Label(L("完整版功能"), systemImage: "lock.fill") }
                        }
                        .font(.system(size: 12))
                    }
                    if model.notifySystem && Pro.shared.hasAccess {
                        AlertLimitRow(icon: "cpu", title: L("CPU 持续 2 分钟超过"), value: $m.cpuAlert, range: 50...100, step: 5, unit: "%")
                        AlertLimitRow(icon: "memorychip", title: L("内存超过"), value: $m.memAlert, range: 50...99, step: 5, unit: "%")
                        AlertLimitRow(icon: "internaldrive", title: L("磁盘剩余少于"), value: $m.diskAlertGB, range: 1...200, step: 1, unit: " GB")
                    }
                }
                .staggerIn(3)

                #if APPSTORE
                proSection.staggerIn(4)
                #endif
                #if XIAOKE_PRIVATE && (!APPSTORE || IPHONE_SYNC)
                if !AppModel.demo { PhoneSyncSection().staggerIn(4) }
                #endif
                if Sandbox.isOn && !AppModel.demo { helperSection.staggerIn(4) }

                section(L("其他"), icon: "gearshape.fill") {
                    Picker(L("额度刷新间隔"), selection: $m.refreshMinutes) {
                        ForEach([3, 5, 10, 30], id: \.self) { Text(L("%d 分钟", $0)).tag($0) }
                    }
                    Text(L("有会话在跑时自动加快到 2 分钟一次。官方额度接口限流很严，再快会被暂时拒绝。"))
                        .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    SwitchRow(title: L("开机自动打开"), isOn: Binding(get: { loginOn }, set: { v in model.launchAtLogin = v; loginOn = model.launchAtLogin }))
                    HStack {
                        Button(L("打开数据文件夹")) { NSWorkspace.shared.open(Paths.support) }
                        Spacer()
                        Button(L("重新统计 Token")) { Task { await model.rescan() } }
                    }
                    .font(.system(size: 11.5))
                    Text(L("额度数据直接读取各工具已登录的凭证，只发给它们的官方接口（api.anthropic.com、chatgpt.com、cloudcode-pa.googleapis.com、grok.com），不经过任何第三方。API Key 只存在钥匙串里。"))
                        .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Text(L("小克额度栏 %@", Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.1"))
                            .font(.system(size: 10)).foregroundStyle(.tertiary)
                        Spacer()
                        Button(L("退出")) { NSApp.terminate(nil) }.keyboardShortcut("q")
                    }
                }
                .staggerIn(4)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .toggleStyle(.switch).controlSize(.small)
        }
        .scrollIndicators(.never)
        .onAppear { loginOn = model.launchAtLogin }
        .alert(item: Binding(get: { confirmPlan.map { PlanBox(plan: $0) } }, set: { confirmPlan = $0?.plan })) { box in
            Self.createAlert(box, model: model)
        }
    }

    #if APPSTORE
    /// App Store 版：完整版状态、购买入口、恢复购买、隐私政策
    private var proSection: some View {
        section(L("完整版"), icon: "sparkles") {
            HStack(spacing: 8) {
                Image(systemName: Pro.shared.purchased ? "checkmark.seal.fill" : "lock.fill")
                    .foregroundStyle(Pro.shared.purchased ? .green : Provider.claude.tint)
                Text(Pro.shared.purchased ? L("已解锁完整版") : L("免费版"))
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                if !Pro.shared.purchased {
                    Button(L("查看完整版")) { Pro.shared.showPaywall = true }
                }
                Button(L("恢复购买")) { Task { await Pro.shared.restore() } }
            }
            .font(.system(size: 11.5))
            Link(L("隐私政策"), destination: URL(string: "https://github.com/Zhao73/xiaoke-bar/blob/main/PRIVACY.md")!)
                .font(.system(size: 11))
        }
    }
    #endif

    /// App Store 版：增强组件的状态。第一次设置时跳过了，或者脚本版本旧了，可以在这里补装
    private var helperSection: some View {
        let _ = model.setupRevision
        let ok = Helper.installed && !Helper.outdated
        return section(L("增强组件"), icon: "wrench.and.screwdriver.fill") {
            HStack(spacing: 8) {
                Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(ok ? .green : .orange)
                Text(ok ? L("已安装") : (Helper.outdated ? L("有新版本，需要更新") : L("未安装")))
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                if !ok {
                    Button(Helper.outdated ? L("更新增强组件") : L("安装增强组件")) {
                        if Helper.install() { model.finishSetupStep() }
                    }
                } else if let f = Helper.folder {
                    Button(L("在访达中显示")) { NSWorkspace.shared.activateFileViewerSelecting([f.appendingPathComponent(Helper.fileName)]) }
                }
            }
            .font(.system(size: 11.5))
            Text(L("有了它才能显示 Claude Code 的额度、看到正在运行的会话、在终端里打开会话。删除脚本文件即可停用。"))
                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    struct PlanBox: Identifiable { var plan: AccountMaker.Plan; var id: String { plan.command } }

    /// 新建 claudeN 账号的确认框（设置页和额度页的「添加账号」共用）
    static func createAlert(_ box: PlanBox, model: AppModel) -> Alert {
        Alert(title: Text(L("新增账号 %@？", box.plan.command)),
              message: Text(L("会新建配置文件夹 %@ 和启动命令 %@，记忆、规则、插件和设置与主号共用，登录信息独立。\n创建后会打开终端，按提示登录新账号。",
                              Paths.pretty(box.plan.dir), Paths.pretty(box.plan.launcher))),
              primaryButton: .default(Text(L("创建并登录"))) {
                  do {
                      try AccountMaker.create(box.plan)
                      Task {
                          await model.refreshAll()
                          if let a = model.accounts.first(where: { $0.command == box.plan.command }) { Launcher.claude(a, mode: .login, dir: nil) }
                      }
                      model.flash(L("已创建 %@，请在终端里登录", box.plan.command))
                  } catch { model.flash(L("创建失败：%@", error.localizedDescription)) }
              },
              secondaryButton: .cancel(Text(L("取消"))))
    }

    private func section<C: View>(_ title: String, icon: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon).font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 9) { content() }
                .font(.system(size: 12))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.background.opacity(0.5)))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.primary.opacity(0.07)))
        }
    }
}

struct AccountSettingRow: View {
    @Environment(AppModel.self) private var model
    var account: ClaudeAccount
    @State private var name = ""

    var body: some View {
        HStack(spacing: 8) {
            Logo(provider: .claude, size: 16)
            VStack(alignment: .leading, spacing: 2) {
                TextField(account.isDefault ? L("主号") : account.command, text: $name)
                    .textFieldStyle(.plain).font(.system(size: 12, weight: .semibold))
                    .onSubmit { model.nicknames[account.id] = name }
                Text("\(account.command) · \(Paths.pretty(account.configDir))").font(.system(size: 9.5)).foregroundStyle(.secondary)
            }
            Spacer()
            Button(L("重新授权")) { Launcher.run(account.command + " auth login", title: L("%@ 重新授权", account.command)) }
                .controlSize(.mini)
                .help(L("在终端里执行 %@ auth login，浏览器里重新登录", account.command))
            Toggle("", isOn: Binding(get: { !model.hiddenAccounts.contains(account.id) }, set: { show in
                if show { model.hiddenAccounts.removeAll { $0 == account.id } } else { model.hiddenAccounts.append(account.id) }
            }))
            .labelsHidden()
            .help(L("在额度页显示这个账号"))
        }
        .onAppear { name = model.nicknames[account.id] ?? "" }
        .onChange(of: name) { _, v in model.nicknames[account.id] = v }
    }
}

/// 左边文字、右边开关
struct SwitchRow: View {
    var title: String
    @Binding var isOn: Bool
    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 8)
            Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
    }
}

/// 资源提醒的一个阈值：图标 + 说明 + 数值 + 加减
struct AlertLimitRow: View {
    var icon: String
    var title: String
    @Binding var value: Int
    var range: ClosedRange<Int>
    var step: Int
    var unit: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 10)).foregroundStyle(.secondary).frame(width: 14)
            Text(title).font(.system(size: 11.5))
            Spacer()
            Text("\(value)\(unit)").font(.system(size: 11.5, weight: .semibold, design: .rounded)).monospacedDigit()
            Stepper("", value: $value, in: range, step: step).labelsHidden().controlSize(.small)
        }
        .padding(.leading, 4)
    }
}
