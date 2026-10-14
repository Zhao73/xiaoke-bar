import SwiftUI
import AppKit

/// 桌面宠物：无边框透明小窗，浮在所有窗口上面，可以拖到任何地方（位置会记住）。
/// 有会话在跑时旁边冒气泡，显示会话标题、正在做什么、用时和 token；做完了会庆祝。
@MainActor
final class FloatingPetController {
    private var panel: NSPanel?
    private let model: AppModel
    var onOpen: () -> Void = {}

    init(model: AppModel) { self.model = model }

    func sync() {
        if model.floatingPet { show() } else { hide() }
    }

    private func show() {
        guard panel == nil else { return }
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: FloatingPetView.width, height: FloatingPetView.rowHeight),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.isMovableByWindowBackground = true
        p.hidesOnDeactivate = false
        let host = NSHostingView(rootView: FloatingPetView(onOpen: { [weak self] in self?.onOpen() },
                                                          onHide: { [weak self] in self?.model.floatingPet = false; self?.sync() })
            .environment(model))
        host.frame = p.contentRect(forFrameRect: p.frame)
        host.autoresizingMask = [.width, .height]
        p.contentView = host
        p.setFrameAutosaveName("XiaokeFloatingPet")
        if !p.setFrameUsingName("XiaokeFloatingPet"), let screen = NSScreen.main {
            let f = screen.visibleFrame
            p.setFrameOrigin(NSPoint(x: f.maxX - 320, y: f.minY + 40))
        }
        p.orderFrontRegardless()
        panel = p
    }

    private func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}

struct FloatingPetView: View {
    @Environment(AppModel.self) private var model
    var onOpen: () -> Void
    var onHide: () -> Void
    @State private var hover = false
    @State private var drag: (mouse: NSPoint, origin: NSPoint)?
    @State private var landed: Date?
    /// 窗口完全看不见时暂停动画
    @State private var hidden = false

    static let rowHeight: CGFloat = 120, width: CGFloat = 350, maxRows = 4
    private static let pixel: CGFloat = 3.4
    /// 气泡折叠后窗口只留宠物 + 一个小展开按钮这么宽，旁边的屏幕区域可以正常点
    static let collapsedWidth: CGFloat = PetView.cols * pixel + 34

    private var collapsed: Bool { model.petBubblesCollapsed }
    /// 乐队舞台要横排好几只宠物，在演奏时不缩窄
    private var currentWidth: CGFloat { collapsed && model.nowPlaying == nil ? Self.collapsedWidth : Self.width }

    private var window: NSWindow? { NSApp.windows.first { $0.frameAutosaveName == "XiaokeFloatingPet" } }

    /// 一行一只：有几个会话在跑就几只（最多 4 只），都没在跑就一只自己玩
    /// 在放歌时最上面多一行乐队舞台
    private var rows: [(id: String, kind: Provider, action: PetAction, session: LiveSession?)] {
        let band: [(id: String, kind: Provider, action: PetAction, session: LiveSession?)] =
            model.nowPlaying.map { [("band-" + $0.song.id, .claude, .idle, nil)] } ?? []
        let busy = Array(model.busySessions.suffix(Self.maxRows - band.count))
        if busy.isEmpty {
            if !band.isEmpty { return band }
            let p = model.pet
            return [("solo", p.kind, p.action, nil)]
        }
        return band + busy.map { ($0.id, $0.provider, $0.action, $0) }
    }

    /// 拖动宠物移动窗口（按屏幕坐标算，窗口跟着鼠标走不会抖）
    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { _ in
                guard let w = window else { return }
                let m = NSEvent.mouseLocation
                if drag == nil { drag = (m, w.frame.origin) }
                if let d = drag { w.setFrameOrigin(NSPoint(x: d.origin.x + m.x - d.mouse.x, y: d.origin.y + m.y - d.mouse.y)) }
            }
            .onEnded { _ in
                drag = nil
                landed = Date()
                window?.saveFrame(usingName: "XiaokeFloatingPet")
            }
    }

    var body: some View {
        let list = rows
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            ForEach(Array(list.enumerated()), id: \.element.id) { i, r in
                if r.id.hasPrefix("band-"), let n = model.nowPlaying {
                    BandStage(song: n.song, start: n.start, pixel: n.song.performers.count > 3 ? 3.0 : 3.4)
                        .simultaneousGesture(moveGesture)
                        .frame(height: Self.rowHeight, alignment: .bottomLeading)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                HStack(alignment: .bottom, spacing: 2) {
                    petView(r, index: i, count: list.count)
                        .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
                        .simultaneousGesture(moveGesture)
                    if collapsed {
                        if let s = r.session { expandButton(s).padding(.bottom, 10) }
                    } else {
                        bubble(r.session, solo: list.count == 1)
                            .padding(.bottom, 6)
                            // 点气泡切到这个会话所在的窗口（终端标签页 / VS Code / Claude 桌面版）；找不到就打开面板
                            .onTapGesture {
                                if let s = r.session, SessionOpener.open(s) != nil { return }
                                onOpen()
                            }
                            .help(r.session == nil ? "" : L("点一下切到这个会话的窗口"))
                            // 悬停时右上角出现折叠按钮
                            .overlay(alignment: .topTrailing) {
                                if r.session != nil, hover { collapseButton.offset(x: 6, y: -6) }
                            }
                    }
                    Spacer(minLength: 0)
                }
                .frame(height: Self.rowHeight, alignment: .bottomLeading)
                // 离场：往上飘走变淡
                .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity),
                                        removal: .offset(y: -40).combined(with: .scale(scale: 0.6, anchor: .bottomLeading)).combined(with: .opacity)))
                }
            }
        }
        .frame(width: currentWidth, height: Self.rowHeight * CGFloat(list.count), alignment: .bottomLeading)
        .animation(.spring(duration: 0.45, bounce: 0.25), value: list.map(\.id))
        .onHover { hover = $0 }
        .environment(\.petsPaused, hidden)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification)) { n in
            guard let w = n.object as? NSWindow, w == window else { return }
            hidden = !w.occlusionState.contains(.visible)
        }
        .animation(.spring(duration: 0.35, bounce: 0.2), value: collapsed)
        .onAppear { resize(list.count) }
        .onChange(of: list.count) { _, n in resize(n) }
        .onChange(of: currentWidth) { _, _ in resize(list.count) }
        .contextMenu { globalMenu }
    }

    @ViewBuilder
    private func petView(_ r: (id: String, kind: Provider, action: PetAction, session: LiveSession?), index i: Int, count: Int) -> some View {
        if let s = r.session {
            var pet = InteractivePet(session: s, model: model, pixel: Self.pixel, seed: i * 7 + 3,
                                     dragging: drag != nil, landed: landed, gaze: gaze(row: i, of: count))
            // 会话开始忙的那一刻从天上掉下来
            let _ = (pet.appearedAt = model.busyDuration(s).map { Date().addingTimeInterval(-$0) })
            pet.contextMenu { PetActionMenu(target: s.id); Divider(); globalMenu }
        } else {
            InteractivePet(kind: r.kind, action: r.action, pixel: Self.pixel, seed: i * 7 + 3,
                           dragging: drag != nil, landed: landed, gaze: gaze(row: i, of: count))
                .contextMenu { PetActionMenu(target: nil); Divider(); globalMenu }
        }
    }

    @ViewBuilder private var globalMenu: some View {
        Button(collapsed ? L("展开会话气泡") : L("折叠会话气泡")) { model.petBubblesCollapsed.toggle() }
        Toggle(L("隐私模式（标题打码）"), isOn: Binding(get: { model.privacyMode }, set: { model.privacyMode = $0 }))
        Menu(L("组乐队弹一首 🎸")) { SongMenuItems() }
        Button(L("打开面板")) { onOpen() }
        Button(L("隐藏桌面宠物")) { onHide() }
    }

    /// 折叠后的小按钮：一个状态灯 + 展开箭头，点一下把气泡展开
    private func expandButton(_ s: LiveSession) -> some View {
        Button { model.petBubblesCollapsed = false } label: {
            VStack(spacing: 3) {
                Circle().fill(.green).frame(width: 5, height: 5)
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(.secondary)
            .frame(width: 22, height: 34)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(s.provider.tint.opacity(0.4)))
        }
        .buttonStyle(.plain)
        .help(L("展开会话气泡"))
        .transition(.scale(scale: 0.6, anchor: .leading).combined(with: .opacity))
    }

    private var collapseButton: some View {
        Button { model.petBubblesCollapsed = true } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.secondary.opacity(0.3)))
        }
        .buttonStyle(.plain)
        .help(L("折叠会话气泡"))
    }

    /// 窗口高度跟着宠物数量变，底边不动（往上长）；折叠气泡时窗口变窄，左边不动
    private func resize(_ n: Int) {
        guard let w = window else { return }
        let h = Self.rowHeight * CGFloat(n), width = currentWidth
        guard abs(w.frame.height - h) > 0.5 || abs(w.frame.width - width) > 0.5 else { return }
        w.setFrame(NSRect(x: w.frame.minX, y: w.frame.minY, width: width, height: h), display: true, animate: false)
        w.saveFrame(usingName: "XiaokeFloatingPet")
    }

    /// 全屏鼠标相对第 i 只宠物身体中心的水平距离：眼睛跟着你的鼠标走
    private func gaze(row i: Int, of n: Int) -> () -> CGFloat? {
        { [weak w = window] in
            guard let w else { return nil }
            let m = NSEvent.mouseLocation
            let cx = w.frame.minX + 11 * Self.pixel
            let cy = w.frame.maxY - Self.rowHeight * (CGFloat(i) + 0.5)
            // 离得太远就不看了
            guard abs(m.y - cy) < 400, abs(m.x - cx) < 700 else { return nil }
            return m.x - cx
        }
    }

    @ViewBuilder
    private func bubble(_ s: LiveSession?, solo: Bool) -> some View {
        if let s {
            let sum = model.summary(for: s)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Logo(provider: s.provider, size: 11)
                    Text(model.shown(sum?.title ?? s.name) ?? s.provider.name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                }
                HStack(spacing: 4) {
                    Circle().fill(.green).frame(width: 5, height: 5)
                    Text(s.action.label + (model.shown(s.detail).map { " · " + $0 } ?? "")).lineLimit(1)
                    if s.subagents > 0 { Text(L("· %d 个小弟", s.subagents)).foregroundStyle(s.provider.tint) }
                }
                .font(.system(size: 10)).foregroundStyle(.secondary)
                if let say = s.say, !model.privacyMode {
                    // AI 最新说的话，新的一句逐字打出来
                    TypewriterText(text: say)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.primary.opacity(0.85))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(s.provider.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                HStack(spacing: 8) {
                    if let d = model.busyDuration(s) { Label(Fmt.duration(d), systemImage: "clock") }
                    if let sum { Label(Double(sum.tokens.total).tokenShort, systemImage: "sum") }
                    if s.rss > 0 { Label(s.rss.bytesShort, systemImage: "memorychip") }
                }
                .font(.system(size: 9.5, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .frame(width: 242, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(s.provider.tint.opacity(0.4)))
            .transition(.scale(scale: 0.7, anchor: .bottomLeading).combined(with: .opacity))
        } else if solo, let d = model.lastDone, Date().timeIntervalSince(d.at) < 60 {
            Text(L("✅ %@ 做完了", String((model.shown(model.sessionTitle(d.title)) ?? "").prefix(18))))
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
        } else if solo, hover {
            Text(L("双击表演 · 蹭蹭摸头 · 右键更多"))
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.regularMaterial, in: Capsule())
        }
    }
}

