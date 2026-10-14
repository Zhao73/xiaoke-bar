import SwiftUI
import AppKit

/// 截图模式：XiaokeBar --snapshot <输出目录>
/// 不弹窗、不碰菜单栏，在内存里把每个页面（深色/浅色）渲染成 PNG，用来检查界面。
@MainActor
enum Snapshot {
    static func run(dir: String) {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        AppModel.skipUsageNetwork = true
        StaggerIn.disabled = true
        let model = AppModel()
        model.start()
        let out = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        var jobs: [(AppModel.Tab, String)] = []
        for appearance in ["dark", "light"] { for t in AppModel.Tab.allCases { jobs.append((t, appearance)) } }
        func step(_ i: Int) {
            guard i < jobs.count else { exit(0) }
            let (tab, look) = jobs[i]
            model.tab = tab
            let host = NSHostingView(rootView: RootView().environment(model))
            host.frame = NSRect(x: 0, y: 0, width: 420, height: 680)
            let win = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            win.appearance = NSAppearance(named: look == "dark" ? .darkAqua : .aqua)
            win.contentView = host
            win.setFrameOrigin(NSPoint(x: -3000, y: -3000))
            win.orderFrontRegardless()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
                host.layoutSubtreeIfNeeded()
                if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                    host.cacheDisplay(in: host.bounds, to: rep)
                    let name = "\(look)-\(AppModel.Tab.allCases.firstIndex(of: tab)!)-\(tab.rawValue).png"
                    try? rep.representation(using: .png, properties: [:])?.write(to: out.appendingPathComponent(name))
                }
                win.orderOut(nil)
                step(i + 1)
            }
        }
        // 桌面宠物（演示模式下是假会话）：展开和折叠两种
        for (k, collapsed) in [false, true].enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4 + Double(k) * 5.5) {
                model.petBubblesCollapsed = collapsed
                let v = FloatingPetView(onOpen: {}, onHide: {}).environment(model).padding(12)
                let h = NSHostingView(rootView: v)
                h.frame = NSRect(origin: .zero, size: h.fittingSize)
                let w = NSWindow(contentRect: h.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                w.isOpaque = false; w.backgroundColor = .clear
                w.contentView = h
                w.setFrameOrigin(NSPoint(x: -9000, y: -3000 - CGFloat(k) * 800))
                w.orderFrontRegardless()
                // 等气泡里逐字打出来的那句话打完
                DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                    if let rep = h.bitmapImageRepForCachingDisplay(in: h.bounds) {
                        h.cacheDisplay(in: h.bounds, to: rep)
                        try? rep.representation(using: .png, properties: [:])?.write(to: out.appendingPathComponent(collapsed ? "floating-collapsed.png" : "floating.png"))
                    }
                    w.orderOut(nil)
                }
            }
        }
        // 吃饼干逐帧：检查是不是真的一口一口吃掉（每格 0.3 秒，四只宠物各一行）
        do {
            let times = stride(from: 0.0, through: 6.6, by: 0.3).map { $0 }
            let px: CGFloat = 4, cw = Int(PetView.cols * px), ch = Int(PetView.rows * px)
            let w = cw * times.count, h = ch * Provider.allCases.count
            if let ctx = CGContext(data: nil, width: w * 2, height: h * 2, bitsPerComponent: 8, bytesPerRow: 0,
                                   space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                ctx.setFillColor(CGColor(gray: 0.16, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w * 2, height: h * 2))
                ctx.scaleBy(x: 2, y: 2); ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)
                for (r, k) in Provider.allCases.enumerated() {
                    for (i, t) in times.enumerated() {
                        ctx.saveGState(); ctx.translateBy(x: CGFloat(i * cw), y: CGFloat(r * ch))
                        var p = CGPainter(ctx: ctx)
                        PetView(kind: k, action: .eat, pixel: px).render(&p, t: t)
                        ctx.restoreGState()
                    }
                }
                if let img = ctx.makeImage() {
                    try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: out.appendingPathComponent("eat-strip.png"))
                }
            }
        }
        // 宣传用动图的逐帧：每只宠物一行、每个动作一列，12fps 共 6 秒（正好一轮吃饼干），用 ffmpeg 合成 GIF
        do {
            let acts: [PetAction] = [.typing, .guitar, .dance, .eat, .skate, .coffee, .erhu]
            let px: CGFloat = 6, cellW = PetView.cols * px + 30, cellH = PetView.rows * px + 22
            let w = Int(cellW * CGFloat(acts.count) + 20), h = Int(cellH * CGFloat(Provider.allCases.count) + 20)
            let dir = out.appendingPathComponent("frames")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let start = Date()
            for f in 0..<72 {
                let t = Double(f) / 12
                guard let ctx = CGContext(data: nil, width: w * 2, height: h * 2, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { break }
                ctx.setFillColor(CGColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w * 2, height: h * 2))
                ctx.scaleBy(x: 2, y: 2); ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)
                for (r, k) in Provider.allCases.enumerated() {
                    for (i, a) in acts.enumerated() {
                        ctx.saveGState(); ctx.translateBy(x: 10 + CGFloat(i) * cellW + 15, y: 10 + CGFloat(r) * cellH + 11)
                        var p = CGPainter(ctx: ctx)
                        PetView(kind: k, action: a, pixel: px, trick: a == .skate ? .skate : nil, trickUntil: start.addingTimeInterval(600)).render(&p, t: t)
                        ctx.restoreGState()
                    }
                }
                if let img = ctx.makeImage() {
                    try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?
                        .write(to: dir.appendingPathComponent(String(format: "f%03d.png", f)))
                }
            }
        }
        // 宠物动作图鉴：每个动作一格，四只宠物各一行
        let gallery = VStack(alignment: .leading, spacing: 4) {
            ForEach(Provider.allCases) { k in
                HStack(spacing: 2) {
                    ForEach(PetAction.allCases, id: \.self) { a in
                        VStack(spacing: 0) {
                            PetView(kind: k, action: a, pixel: 3, petted: a == .love ? Date() : nil, trick: [.spin, .juggle, .skate, .wave, .stretch].contains(a) ? a : nil,
                                    trickUntil: Date().addingTimeInterval(60), dragging: a == .dangle)
                            Text(a.label).font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(8).background(Color(white: 0.16)).environment(\.colorScheme, .dark)
        let gHost = NSHostingView(rootView: gallery)
        gHost.frame = NSRect(origin: .zero, size: gHost.fittingSize)
        let gWin = NSWindow(contentRect: gHost.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        gWin.contentView = gHost
        gWin.setFrameOrigin(NSPoint(x: -6000, y: -3000))
        gWin.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if let rep = gHost.bitmapImageRepForCachingDisplay(in: gHost.bounds) {
                gHost.cacheDisplay(in: gHost.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: out.appendingPathComponent("pets-gallery.png"))
            }
            gWin.orderOut(nil)
        }
        // 乐队舞台：二泉映月（阿炳墨镜）和一首四人乐队曲，不出声音只画面
        func band(_ id: String, delay: Double, x: CGFloat) {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard let song = Song.all.first(where: { $0.id == id }) else { return }
                let v = BandStage(song: song, start: Date().addingTimeInterval(-2), pixel: 3.2)
                    .padding(10).background(Color(white: 0.85)).environment(model)
                let h = NSHostingView(rootView: v)
                h.frame = NSRect(origin: .zero, size: h.fittingSize)
                let w = NSWindow(contentRect: h.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                w.contentView = h
                w.setFrameOrigin(NSPoint(x: x, y: -3000))
                w.orderFrontRegardless()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    if let rep = h.bitmapImageRepForCachingDisplay(in: h.bounds) {
                        h.cacheDisplay(in: h.bounds, to: rep)
                        try? rep.representation(using: .png, properties: [:])?.write(to: out.appendingPathComponent("band-\(id).png"))
                    }
                    w.orderOut(nil)
                }
            }
        }
        // 鼠标命中检查：宠物是 Core Graphics 自绘、本身不接鼠标，点击要落到外层 SwiftUI 上（不能穿透到后面的窗口）
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            let h = NSHostingView(rootView: InteractivePet(kind: .claude, action: .idle, pixel: 3).environment(model))
            h.frame = NSRect(x: 0, y: 0, width: PetView.cols * 3, height: PetView.rows * 3)
            let w = NSWindow(contentRect: h.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            w.contentView = h
            w.setFrameOrigin(NSPoint(x: -12000, y: -3000))
            w.orderFrontRegardless()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let hit = h.hitTest(NSPoint(x: h.bounds.midX, y: h.bounds.midY))
                print("宠物鼠标命中：\(hit.map { String(describing: type(of: $0)) } ?? "nil（会穿透！）")")
                w.orderOut(nil)
            }
        }
        band("erquan", delay: 2, x: -9000)
        band("saints", delay: 4, x: -9500)
        // 先等数据读完
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { step(0) }
        app.run()
    }
}
