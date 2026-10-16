import SwiftUI

#if !XIAOKE_PRIVATE
/// 开源版（从公开源码自己编译）：Mac 上的功能全部免费可用，没有付费解锁，也没有 iPhone 配对。
/// 发布页下载的 App 由完整源码编译，带 iPhone 配对和远程功能；那部分代码不公开。
@MainActor @Observable
final class Pro {
    static let shared = Pro()
    let purchased = true
    var hasAccess: Bool { true }
    var showPaywall = false
    func start() {}
    func restore() async {}
}

/// 开源版不会走到加锁界面，留着让界面代码不用分两套
struct ProGate: View {
    var title: String
    var detail: String
    var icon: String
    var body: some View { EmptyView() }
}

struct ProCard: View {
    var hiddenAccounts: Int
    var body: some View { EmptyView() }
}

struct PaywallView: View {
    var body: some View { EmptyView() }
}
#endif
