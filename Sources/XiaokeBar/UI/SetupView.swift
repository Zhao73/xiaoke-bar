import SwiftUI

/// App Store 版（沙盒）第一次打开时的两步设置：授权个人文件夹 → 安装增强组件。
/// 开源版不开沙盒，永远不会显示这个页面。
struct SetupView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let _ = model.setupRevision      // 设置完一步后刷新
        let homeOK = HomeAccess.granted
        let helperOK = Helper.installed && !Helper.outdated
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("还差两步就能用了")).font(.system(size: 20, weight: .bold, design: .rounded))
                    Text(L("App Store 版运行在系统沙盒里，读取 AI 工具的数据前需要你点头同意。两步都只要点一下按钮。"))
                        .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 4)

                step(index: 1, done: homeOK, tint: Provider.claude.tint,
                     title: L("授权读取个人文件夹"),
                     detail: L("用来读取 ~/.claude、~/.codex、~/.gemini、~/.grok 里的会话记录，统计 Token 和正在运行的会话。只读取这些 AI 工具的文件夹。"),
                     button: L("授权个人文件夹"), icon: "folder.badge.person.crop") {
                    if HomeAccess.request() { model.finishSetupStep() }
                }
                .staggerIn(0)

                step(index: 2, done: helperOK, tint: Provider.codex.tint,
                     title: Helper.outdated ? L("更新增强组件") : L("安装增强组件"),
                     detail: L("一个很短的脚本，放在本 App 专属的脚本文件夹里。有了它，小克才能读取 Claude Code 的登录状态（显示额度）、看到正在运行的会话、一键在终端里打开或恢复会话。删除它即可停用。"),
                     button: Helper.outdated ? L("更新增强组件") : L("安装增强组件"), icon: "wrench.and.screwdriver") {
                    if Helper.install() { model.finishSetupStep() }
                }
                .disabled(!homeOK)
                .opacity(homeOK ? 1 : 0.5)
                .staggerIn(1)

                if homeOK && !helperOK {
                    Button(L("先跳过，只看 Token 统计")) { model.skipHelper() }
                        .buttonStyle(.plain).font(.system(size: 11.5)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                Button { AppModel.setDemo(true) } label: {
                    Label(L("先看看演示（用示例数据，不读取任何文件）"), systemImage: "play.circle")
                }
                .buttonStyle(.plain).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Provider.claude.tint)
                .frame(maxWidth: .infinity)

                Label(L("所有数据只在你的 Mac 上处理，不经过任何第三方服务器。"), systemImage: "lock.shield")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .padding(.horizontal, 4).padding(.top, 4)
            }
            .padding(14)
        }
    }

    private func step(index: Int, done: Bool, tint: Color, title: String, detail: String, button: String, icon: String, action: @escaping () -> Void) -> some View {
        GlassCard(tint: tint) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle().fill(done ? Color.green.opacity(0.18) : tint.opacity(0.16)).frame(width: 30, height: 30)
                    if done {
                        Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.green)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Text("\(index)").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(tint)
                    }
                }
                .animation(.spring(duration: 0.4, bounce: 0.4), value: done)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.system(size: 13.5, weight: .semibold))
                    Text(detail).font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if !done {
                        PillButton(title: button, icon: icon, tint: tint, prominent: true, action: action).padding(.top, 2)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}
