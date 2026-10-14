import SwiftUI

/// 右键某一只宠物时的动作菜单：只有这一只演，别的宠物继续做自己的事
struct PetActionMenu: View {
    @Environment(AppModel.self) private var model
    /// 会话 id；nil = 主宠物
    var target: String?

    var body: some View {
        Section(L("逗它玩")) {
            Button(L("喂零食 🍪")) { model.perform(.eat, seconds: PetView.eatLength, target: target) }
            Button(L("挠痒痒 🤭")) { model.perform(.laugh, seconds: 4, target: target) }
            Button(L("跳个舞")) { model.perform(.dance, target: target) }
            Button(L("喝杯咖啡")) { model.perform(.coffee, target: target) }
            if model.hasDog {
                Button(L("去遛狗 🐕")) { model.perform(.walkDog, seconds: 10, target: target) }
                Button(L("和狗狗玩球 🎾")) { model.perform(.fetch, seconds: 9.6, target: target) }
            }
            if model.hasCat { Button(L("陪猫睡一会 🐈")) { model.perform(.catNap, seconds: 13, target: target) } }
            Button(L("偷懒？抽一鞭 🪢")) { model.perform(.whipped, seconds: 4.8, target: target) }
        }
        Section(L("心情 %d / 100", Int(model.happiness.rounded()))) { EmptyView() }
    }
}

/// 乐队舞台：每只宠物拿自己的乐器，跟着同一首曲子的拍子演奏；一只只依次跳上台
struct BandStage: View {
    @Environment(AppModel.self) private var model
    var song: Song
    var start: Date
    var pixel: CGFloat

    var body: some View {
        let members = song.performers
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(Array(members.enumerated()), id: \.offset) { i, m in
                    InteractivePet(kind: m.member, action: m.instrument.action, pixel: pixel, seed: i * 11 + 5,
                                   rowID: "band-\(i)", musicStart: start,
                                   songID: song.parts.contains { $0.member == m.member && $0.role == .lead } ? song.id : nil, bpm: song.bpm,
                                   glasses: song.wearsGlasses && m.instrument == .erhu,
                                   appearedAt: start.addingTimeInterval(Double(i) * 0.3))
                        .frame(width: PetView.cols * pixel, height: PetView.rows * pixel)
                        .help("\(PetArt.name(m.member)) · \(m.instrument.label)")
                }
            }
            HStack(spacing: 5) {
                Image(systemName: "music.note")
                Text(L("《%@》", song.title)).fontWeight(.semibold)
                Text(members.map { "\(PetArt.name($0.member)) \($0.instrument.label)" }.joined(separator: " · "))
                    .foregroundStyle(.secondary).lineLimit(1)
            }
            .font(.system(size: 10.5))
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(.regularMaterial, in: Capsule())
            .onTapGesture { model.stopSong() }
            .help(L("点一下停止"))
        }
    }
}
