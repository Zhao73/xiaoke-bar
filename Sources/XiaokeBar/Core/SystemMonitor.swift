import Foundation
import Darwin

/// 一个进程的快照（来自 libproc，直接调系统接口，不开 ps 子进程）
struct ProcInfo {
    var pid: Int32
    var ppid: Int32
    var path: String
    var cpuNanos: UInt64      // 累计 CPU 时间
    var rss: UInt64           // 常驻内存（字节）
}

enum ProcessTable {
    /// Apple 芯片上 libproc 给的 CPU 时间单位是 mach tick，要换算成纳秒
    private static let tickToNanos: Double = {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        return tb.denom == 0 ? 1 : Double(tb.numer) / Double(tb.denom)
    }()

    static func snapshot() -> [ProcInfo] {
        let n = proc_listallpids(nil, 0)
        guard n > 0 else { return [] }
        var pids = [Int32](repeating: 0, count: Int(n) + 64)
        let got = pids.withUnsafeMutableBufferPointer { proc_listallpids($0.baseAddress, Int32($0.count * MemoryLayout<Int32>.size)) }
        guard got > 0 else { return [] }
        var out: [ProcInfo] = []
        out.reserveCapacity(Int(got))
        var pathBuf = [CChar](repeating: 0, count: 4096)
        for pid in pids.prefix(Int(got)) where pid > 0 {
            var info = proc_taskallinfo()
            let sz = Int32(MemoryLayout<proc_taskallinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTASKALLINFO, 0, &info, sz) == sz else { continue }
            let len = proc_pidpath(pid, &pathBuf, UInt32(pathBuf.count))
            let path = len > 0 ? String(cString: pathBuf) : ""
            let ticks = info.ptinfo.pti_total_user + info.ptinfo.pti_total_system
            out.append(ProcInfo(pid: pid, ppid: Int32(info.pbsd.pbi_ppid), path: path,
                                cpuNanos: UInt64(Double(ticks) * tickToNanos), rss: info.ptinfo.pti_resident_size))
        }
        return out
    }

    /// 进程的启动参数（argv）
    static func arguments(pid: Int32) -> [String] { procArgs(pid).args }

    /// 进程的环境变量（用来看 CLAUDE_CONFIG_DIR 区分 claude / claude2）
    static func environment(pid: Int32) -> [String: String] {
        var env: [String: String] = [:]
        for e in procArgs(pid).env { if let i = e.firstIndex(of: "=") { env[String(e[..<i])] = String(e[e.index(after: i)...]) } }
        return env
    }

    private static func procArgs(_ pid: Int32) -> (args: [String], env: [String]) {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 4 else { return ([], []) }
        var buf = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buf, &size, nil, 0) == 0 else { return ([], []) }
        let argc = Int(buf.withUnsafeBytes { $0.load(as: Int32.self) })
        var i = 4
        while i < size && buf[i] != 0 { i += 1 }          // 可执行文件路径
        while i < size && buf[i] == 0 { i += 1 }          // 对齐用的 0
        var items: [String] = []
        var start = i
        while i < size {
            if buf[i] == 0 {
                if i > start { items.append(String(decoding: buf[start..<i], as: UTF8.self)) } else { break }
                start = i + 1
            }
            i += 1
        }
        return (Array(items.prefix(argc)), Array(items.dropFirst(argc)))
    }

    /// 进程当前所在的文件夹
    static func cwd(pid: Int32) -> String? {
        var vi = proc_vnodepathinfo()
        let sz = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &vi, sz) == sz else { return nil }
        return withUnsafeBytes(of: &vi.pvi_cdir.vip_path) { raw in
            let s = String(cString: raw.bindMemory(to: CChar.self).baseAddress!)
            return s.isEmpty ? nil : s
        }
    }

    static func isAlive(_ pid: Int32) -> Bool { kill(pid, 0) == 0 || errno == EPERM }
}

/// 整机状态：CPU 占用、内存、磁盘
struct SystemStats: Equatable {
    var cpuPercent: Double = 0          // 0~100，所有核心平均
    var memUsed: UInt64 = 0
    var memTotal: UInt64 = ProcessInfo.processInfo.physicalMemory
    var diskFree: Int64 = 0
    var diskTotal: Int64 = 0
    var thermal: ProcessInfo.ThermalState = .nominal
    var cores = ProcessInfo.processInfo.activeProcessorCount

    var memPercent: Double { memTotal == 0 ? 0 : Double(memUsed) / Double(memTotal) * 100 }
    var cpuFree: Double { max(0, 100 - cpuPercent) }
    var diskFreePercent: Double { diskTotal == 0 ? 0 : Double(diskFree) / Double(diskTotal) * 100 }
}

/// 采样器：两次采样之差算 CPU 百分比
final class SystemMonitor {
    private var lastTicks: (busy: UInt64, total: UInt64)?
    private var lastProc: [Int32: (cpu: UInt64, at: Double)] = [:]

    private var disk: (Int64, Int64) = (0, 0)
    private var diskAt = Date.distantPast

    func sample() -> SystemStats {
        var s = SystemStats()
        s.cpuPercent = cpu()
        (s.memUsed, s.memTotal) = memory()
        // 「可用空间」要系统算一遍可清理的缓存，挺慢；磁盘空间变化也慢，30 秒查一次就够
        if Date().timeIntervalSince(diskAt) > 30,
           let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]) {
            disk = (v.volumeAvailableCapacityForImportantUsage ?? 0, Int64(v.volumeTotalCapacity ?? 0))
            diskAt = Date()
        }
        (s.diskFree, s.diskTotal) = disk
        s.thermal = ProcessInfo.processInfo.thermalState
        return s
    }

    private func cpu() -> Double {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) }
        }
        guard r == KERN_SUCCESS else { return 0 }
        let t = info.cpu_ticks
        let user = UInt64(t.0), sys = UInt64(t.1), idle = UInt64(t.2), nice = UInt64(t.3)
        let busy = user + sys + nice, total = busy + idle
        defer { lastTicks = (busy, total) }
        guard let last = lastTicks, total > last.total else { return 0 }
        return Double(busy - last.busy) / Double(total - last.total) * 100
    }

    /// 和「活动监视器」的「已使用内存」同一口径：App 内存 + 联动内存 + 被压缩
    private func memory() -> (UInt64, UInt64) {
        var vm = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        let total = ProcessInfo.processInfo.physicalMemory
        guard r == KERN_SUCCESS else { return (0, total) }
        let page = UInt64(vm_kernel_page_size)
        let app = UInt64(vm.internal_page_count) - min(UInt64(vm.internal_page_count), UInt64(vm.purgeable_count))
        let used = (app + UInt64(vm.wire_count) + UInt64(vm.compressor_page_count)) * page
        return (min(used, total), total)
    }

    /// 一组进程（连同它们的所有子进程，例如 MCP 服务）的 CPU 百分比和内存
    func usage(of roots: [Int32], in table: [ProcInfo]) -> [Int32: (cpu: Double, rss: UInt64, procs: Int)] {
        var children: [Int32: [Int32]] = [:]
        var byPid: [Int32: ProcInfo] = [:]
        for p in table { children[p.ppid, default: []].append(p.pid); byPid[p.pid] = p }
        let now = Date().timeIntervalSince1970
        var out: [Int32: (Double, UInt64, Int)] = [:]
        var seenNow: [Int32: (UInt64, Double)] = [:]
        for root in roots {
            var stack = [root], cpu = 0.0, rss: UInt64 = 0, n = 0
            while let pid = stack.popLast() {
                guard let p = byPid[pid] else { continue }
                n += 1
                rss += p.rss
                if let last = lastProc[pid], now > last.at, p.cpuNanos >= last.cpu {
                    cpu += Double(p.cpuNanos - last.cpu) / 1e9 / (now - last.at) * 100
                }
                seenNow[pid] = (p.cpuNanos, now)
                stack += children[pid] ?? []
            }
            out[root] = (cpu, rss, n)
        }
        lastProc = seenNow.mapValues { (cpu: $0.0, at: $0.1) }
        return out
    }
}

extension UInt64 {
    /// 1.2 GB / 340 MB（十进制，和访达显示的一致）
    var bytesShort: String {
        let v = Double(self)
        if v >= 1e12 { return String(format: "%.2f TB", v / 1e12) }
        if v >= 1e9 { return String(format: v >= 1e11 ? "%.0f GB" : "%.1f GB", v / 1e9) }
        if v >= 1e6 { return String(format: v >= 1e8 ? "%.0f MB" : "%.1f MB", v / 1e6) }
        return String(format: "%.0f KB", v / 1e3)
    }
}

extension Int64 {
    var bytesShort: String { UInt64(Swift.max(0, self)).bytesShort }
}
