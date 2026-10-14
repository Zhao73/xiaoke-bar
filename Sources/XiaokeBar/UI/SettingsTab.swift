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
                    SwitchRow(title: L("5 小时额度用到 80% 和 95% 时提醒"), isOn: $m.notifyHigh)
                    SwitchRow(title: L("额度重置后提醒"), isOn: $m.notifyReset)
                }
                .staggerIn(3)

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
                        Text(L("小克额度栏 %@", "1.1")).font(.system(size: 10)).foregroundStyle(.tertiary)
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
