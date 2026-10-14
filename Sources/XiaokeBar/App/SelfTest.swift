import Foundation

/// 不开界面跑一遍数据读取，打印结果（凭证不打印）。用于核对数字是否和官方一致。
enum SelfTest {
    static func run() {
        let t0 = Date()
        let accounts = ClaudeProvider.discoverAccounts()
        print("== Claude 账号 \(accounts.count) 个")
        for a in accounts {
            print("  \(a.command)  \(Paths.pretty(a.configDir))  套餐=\(a.planName)  续费推算=\(a.nextRenewal.map(Fmt.day) ?? "-")  钥匙串=\(ClaudeProvider.token(for: a) != nil ? "有" : "无")")
        }
        let sem = DispatchSemaphore(value: 0)
        Task {
            // 官方额度接口限流很严，默认不查，加 --with-usage 才查
            for a in accounts where CommandLine.arguments.contains("--with-usage") {
                do {
                    let u = try await ClaudeProvider.fetchUsage(a)
                    print("  [\(a.command)] 5h=\(u.fiveHour?.percent ?? -1)% 周=\(u.weekly?.percent ?? -1)% 其他=\(u.extraWindows.map { "\($0.title) \($0.percent)%" }) 金额=\(u.money.map { "\($0.title) 剩$\(String(format: "%.2f", $0.remaining))/\($0.limit) \($0.resetsAt.map(Fmt.day) ?? "")" })")
                } catch { print("  [\(a.command)] 失败: \(error.localizedDescription)") }
            }
            do {
                let c = try await CodexProvider.fetch()
                print("== Codex 套餐=\(c.planName) 到期=\(c.activeUntil.map(Fmt.day) ?? "-") 窗口=\(c.windows.map { "\($0.title) \($0.percent)% 重置\($0.resetsAt.map(Fmt.shortDate) ?? "")" }) 免费重置=\(c.resetCredits.map(String.init) ?? "-") 离线=\(c.fromLocalLog)")
            } catch { print("== Codex 失败: \(error.localizedDescription)") }
            let g = await GrokProvider.fetchBilling(into: GrokProvider.status())
            print("== Grok 已登录=\(g.loggedIn) 档位=\(g.tier ?? "-") 令牌过期=\(g.tokenExpired) 本月额度¢=\(g.monthlyLimitCents ?? -1) 已用¢=\(g.usedCents ?? -1) 账期止=\(g.periodEnd.map(Fmt.day) ?? "-") 编程权限=\(g.hasCodeAccess.map { "\($0)" } ?? "-")")
            if GeminiProvider.loggedIn {
                do {
                    let gm = try await GeminiProvider.fetch()
                    print("== Gemini \(gm.email ?? "-") 套餐=\(gm.tierName ?? "-") 额度=\(gm.buckets.map { "\($0.title) \(Int($0.percent))%" })")
                } catch { print("== Gemini 失败: \(error.localizedDescription)") }
            } else { print("== Gemini 未登录（已安装=\(GeminiProvider.installed)）") }
            let ag = await AntigravityProvider.fetch()
            print("== Antigravity 已安装=\(AntigravityProvider.installed) 运行中=\(ag.running) 模型=\(ag.models.count)")
            sem.signal()
        }
        sem.wait()
        let scanner = TokenScanner()
        let t1 = Date()
        let s = scanner.scan()
        print("== 扫描耗时 \(String(format: "%.1f", Date().timeIntervalSince(t1)))s，会话 \(s.sessions.count) 个")
        let cal = Calendar.current
        for p in Provider.allCases {
            let days = s.days[p] ?? [:]
            let all = days.values.reduce(Tok()) { var x = $0; x += $1; return x }
            let today = days[AppModel.dayFmt.string(from: Date())] ?? Tok()
            var week = Tok()
            for i in 0..<7 { if let v = days[AppModel.dayFmt.string(from: cal.date(byAdding: .day, value: -i, to: Date())!)] { week += v } }
            print("  \(p.name): 今天 \(today.total) (入\(today.i) 出\(today.o) 写\(today.cw) 读\(today.cr))  近7天 \(week.total)  累计 \(all.total)")
        }
        print("  按账号: " + s.claudeAccountDays.map { k, v in "\(k.prefix(8))=\(v.values.reduce(Int64(0)) { $0 + $1.total })" }.joined(separator: " "))
        for x in s.sessions.prefix(6) {
            let cost = x.costUSD ?? Pricing.cost(x.models)
            print("  最近: [\(x.provider.name)] \(x.title.prefix(24)) tok=\(x.tokens.total) 命中=\(x.cacheHitRate.map { String(format: "%.0f%%", $0 * 100) } ?? "-") 费用=\(cost.map(\.usd) ?? "-") 文件=\(x.bytes.bytesShort)/\(x.files) 轮=\(x.turns) 工具=\(x.tools)")
        }
        let mon = SystemMonitor()
        _ = mon.sample(); usleep(500_000)
        let sys = mon.sample()
        print("== 本机 CPU \(Int(sys.cpuPercent))% 内存 \(sys.memUsed.bytesShort)/\(sys.memTotal.bytesShort) 磁盘剩 \(sys.diskFree.bytesShort)/\(sys.diskTotal.bytesShort)")
        let table = ProcessTable.snapshot()
        _ = mon.usage(of: [], in: table)
        let live = LiveSessionFinder.find(accounts: accounts, table: table, recent: s.sessions)
        usleep(1_000_000)
        let use = mon.usage(of: live.map(\.pid).filter { $0 > 0 }, in: ProcessTable.snapshot())
        print("== 运行中 \(live.count) 个（进程表 \(table.count) 个）")
        for l in live {
            let tool = l.transcript.map { LiveSessionFinder.lastTool(transcript: $0) }
            let u = use[l.pid]
            print("  [\(l.provider.name)] pid=\(l.pid) \(l.busy ? "忙" : "闲") \(l.name ?? "-") 工具=\(tool?.tool ?? "-") 细节=\(tool?.detail ?? "-") CPU=\(u.map { String(format: "%.0f%%", $0.cpu) } ?? "-") 内存=\(u.map { $0.rss.bytesShort } ?? "-")/\(u?.procs ?? 0)进程")
            if let t = l.transcript {
                print("      子代理=\(LiveSessionFinder.pendingSubagents(transcript: t)) 最新的话=\(LiveSessionFinder.lastSay(transcript: t) ?? "-")")
            }
            if l.pid > 0 { print("      宿主窗口=\(SessionOpener.hostApp(of: l.pid).map { "\($0.localizedName ?? "?") (\($0.bundleIdentifier ?? "-"))" } ?? "找不到")") }
        }
        // 热扫描一致性：只扫在跑的会话文件，合计不能比全量多出一截（多出来就是重复计数）
        let sum = { (x: StatsSnapshot) in x.sessions.reduce(Int64(0)) { $0 + $1.tokens.total } }
        let full1 = sum(scanner.scan())
        let hot = live.compactMap { l in l.transcript.map { ($0, l.provider) } }
        let hotSum = sum(scanner.scan(only: hot))
        let full2 = sum(scanner.scan())
        print("== 热扫描一致性：全量 \(full1) → 热扫 \(hotSum) → 全量 \(full2)（只会因为会话在跑而略增）")
        // 曲子离线渲染：峰值、平均响度、长度
        let onlySong = ProcessInfo.processInfo.environment["XIAOKE_ONLY_SONG"]
        for song in Song.all where onlySong == nil || onlySong == song.id {
            let pcm = GuitarSynth.shared.renderOffline(song, volume: 0.6)
            let peak = pcm.map { abs($0) }.max() ?? 0
            let rms = sqrt(pcm.reduce(0) { $0 + $1 * $1 } / Float(max(1, pcm.count)))
            print("  曲子《\(song.title)》 \(String(format: "%.1f", song.duration))秒 峰值=\(String(format: "%.2f", peak)) 响度=\(String(format: "%.3f", rms))")
            if let dir = ProcessInfo.processInfo.environment["XIAOKE_SONG_DIR"] {
                WAV.write(pcm, rate: 44_100, to: dir + "/\(song.id).wav")
                // 每个声部单独导出一份，用来比较各件乐器谁太响
                if ProcessInfo.processInfo.environment["XIAOKE_PARTS"] != nil {
                    for (i, p) in song.parts.enumerated() {
                        let one = GuitarSynth.shared.renderOffline(song, volume: 0.6, onlyPart: i)
                        WAV.write(one, rate: 44_100, to: dir + "/\(song.id)__\(i)_\(p.instrument)_\(p.role).wav")
                    }
                }
            }
        }
        print("总耗时 \(String(format: "%.1f", Date().timeIntervalSince(t0)))s")
    }
}

/// 写 16 位单声道 WAV（自检时导出曲子用）
enum WAV {
    static func write(_ pcm: [Float], rate: Int, to path: String) {
        var d = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
        d.append("RIFF".data(using: .ascii)!); u32(UInt32(36 + pcm.count * 2)); d.append("WAVEfmt ".data(using: .ascii)!)
        u32(16); u16(1); u16(1); u32(UInt32(rate)); u32(UInt32(rate * 2)); u16(2); u16(16)
        d.append("data".data(using: .ascii)!); u32(UInt32(pcm.count * 2))
        for s in pcm { u16(UInt16(bitPattern: Int16(max(-1, min(1, s)) * 32767))) }
        try? d.write(to: URL(fileURLWithPath: path))
    }
}
