import Cocoa
import SwiftUI
import Darwin
import IOKit

// MARK: - Диспетчер задач (как в Windows): процессы, производительность, подробности

struct TMRow: Identifiable {
    let id: String              // ключ группы: путь к .app или к исполняемому файлу
    var name: String
    var pids: [Int32]
    var cpu: Double             // % от всей мощности процессора
    var mem: UInt64             // байт (как «Память» в Мониторинге системы)
    var isApp: Bool
    var icon: NSImage?
    var path: String
    var diskR = 0.0             // байт/с
    var diskW = 0.0
    var netIn = 0.0
    var netOut = 0.0
    var energy = 0.0            // условная оценка влияния на энергию
}

/// Один процесс (для вкладки «Подробности» и раскрытия групп)
struct TMProc: Identifiable {
    let id: Int32               // PID
    var ppid: Int32
    var name: String
    var path: String
    var user: String
    var status: Int32           // 1 запуск, 2 работает, 3 спит, 4 остановлен, 5 зомби
    var cpu: Double             // % от всей мощности процессора
    var mem: UInt64
    var threads: Int
    var nice: Int
    var diskR: Double
    var diskW: Double
    var netIn: Double
    var netOut: Double
    var energy: Double
    var group: String
}

struct TMIface: Identifiable {
    var id: String { name }
    var name: String
    var ip: String
    var down: Double
    var up: Double
}

struct TMMemParts {
    var app: UInt64 = 0
    var wired: UInt64 = 0
    var compressed: UInt64 = 0
    var cached: UInt64 = 0
    var free: UInt64 = 0
}

struct TMBattery {
    var percent: Double
    var charging: Bool
    var plugged: Bool
    var cycles: Int?
    var health: Double?
    var minutes: Int?
}

/// Сбор данных: процессы (libproc), процессор и ядра, память, диск, сеть, видеокарта, батарея. Работает, пока открыто окно.
final class TMSampler: ObservableObject {
    static let shared = TMSampler()

    @Published var apps: [TMRow] = []
    @Published var background: [TMRow] = []
    @Published var procs: [Int32: TMProc] = [:]
    @Published var processCount = 0
    @Published var threadCount = 0
    @Published var cpuNow = 0.0
    @Published var memUsed: UInt64 = 0
    @Published var memTotal: UInt64 = ProcessInfo.processInfo.physicalMemory
    @Published var memParts = TMMemParts()
    @Published var swapUsed: UInt64 = 0
    @Published var swapTotal: UInt64 = 0
    @Published var pressure = 1
    @Published var diskTotal: Int64 = 0
    @Published var diskFree: Int64 = 0
    @Published var diskReadNow = 0.0
    @Published var diskWriteNow = 0.0
    @Published var netDownNow = 0.0
    @Published var netUpNow = 0.0
    @Published var cpuHistory: [Double] = []
    @Published var coreHistory: [[Double]] = []
    @Published var memHistory: [Double] = []
    @Published var diskReadHistory: [Double] = []
    @Published var diskWriteHistory: [Double] = []
    @Published var netDown: [Double] = []
    @Published var netUp: [Double] = []
    @Published var ifaces: [TMIface] = []
    @Published var ifaceDown: [String: [Double]] = [:]
    @Published var ifaceUp: [String: [Double]] = [:]
    @Published var gpuName: String? = nil
    @Published var gpuNow = 0.0
    @Published var gpuHistory: [Double] = []
    @Published var battery: TMBattery? = nil
    @Published var batteryHistory: [Double] = []

    static let historyLength = 60
    var windowVisible = false               // окно открыто: частый опрос; иначе (фон) — реже
    private var skip = 0

    private var timer: Timer?
    private let queue = DispatchQueue(label: "tm.sampler", qos: .utility)
    private var prevCPU: [Int32: UInt64] = [:]
    private var prevDisk: [Int32: (UInt64, UInt64)] = [:]
    private var prevWake: [Int32: UInt64] = [:]
    private var prevWall: UInt64 = 0
    private var prevTicks: (UInt32, UInt32, UInt32, UInt32)?
    private var prevCores: [[UInt32]] = []
    private var prevNet: [String: (UInt32, UInt32)] = [:]
    private var prevIO: (UInt64, UInt64)?
    private var pathCache: [Int32: String] = [:]
    private var nameCache: [String: String] = [:]
    private var userCache: [UInt32: String] = [:]
    private var iconCache: [String: NSImage] = [:]
    private var timebase = mach_timebase_info_data_t(numer: 1, denom: 1)
    private let ncpu = Double(max(1, ProcessInfo.processInfo.activeProcessorCount))

    // сеть по процессам: счётчики даёт nettop
    private let netLock = NSLock()
    private var netCum: [Int32: (UInt64, UInt64)] = [:]
    private var netRates: [Int32: (Double, Double)] = [:]
    private var netLastT: UInt64 = 0
    private var nettopRunning = false

    private struct Acc {
        var name: String
        var path: String
        var bundle: Bool
        var pids: [Int32] = []
        var cpu = 0.0
        var mem: UInt64 = 0
        var dr = 0.0, dw = 0.0, ni = 0.0, no = 0.0, en = 0.0
    }

    func start() {
        guard timer == nil else { return }
        mach_timebase_info(&timebase)
        prevWall = 0
        prevCPU = [:]
        prevDisk = [:]
        prevWake = [:]
        prevTicks = nil
        prevCores = []
        prevNet = [:]
        prevIO = nil
        netLock.lock(); netCum = [:]; netRates = [:]; netLastT = 0; netLock.unlock()
        sample()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.sample() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        TMJournal.shared.save()
    }

    // MARK: Действия

    /// Снять задачу: обычное завершение, а с `force` — принудительное
    func end(_ r: TMRow, force: Bool) {
        let k = TMGuard.kind(path: r.path, name: r.name, user: r.pids.first.flatMap { procs[$0]?.user } ?? "", pids: r.pids)
        if !TMGuard.confirm(r.name, k, verb: T("Завершить")) { return }
        if k == .selfApp { NSApp.terminate(nil); return }
        if r.isApp, let a = NSWorkspace.shared.runningApplications.first(where: { $0.bundleURL?.path == r.id }) {
            if force {
                a.forceTerminate()
                for p in r.pids where p > 1 { kill(p, SIGKILL) }
            } else {
                a.terminate()
            }
            return
        }
        for p in r.pids where p > 1 { kill(p, force ? SIGKILL : SIGTERM) }
    }

    func endPid(_ pid: Int32, force: Bool) {
        if pid <= 1 { NSSound.beep(); return }
        let p = procs[pid]
        let k = TMGuard.kind(path: p?.path ?? "", name: p?.name ?? "", user: p?.user ?? "", pids: [pid])
        if !TMGuard.confirm(p?.name ?? "\(pid)", k, verb: T("Завершить")) { return }
        if k == .selfApp { NSApp.terminate(nil); return }
        if kill(pid, force ? SIGKILL : SIGTERM) != 0 { NSSound.beep() }
    }

    /// Приостановить / продолжить процесс
    func suspend(_ pid: Int32, _ on: Bool) { suspend([pid], on) }

    func suspend(_ pids: [Int32], _ on: Bool) {
        guard let first = pids.first else { return }
        if pids.contains(getpid()) { NSSound.beep(); return }
        if on {
            let p = procs[first]
            let k = TMGuard.kind(path: p?.path ?? "", name: p?.name ?? "", user: p?.user ?? "", pids: pids)
            if !TMGuard.confirm(p?.name ?? "\(first)", k, verb: T("Приостановить")) { return }
        }
        for pid in pids where pid > 1 {
            if kill(pid, on ? SIGSTOP : SIGCONT) != 0 { NSSound.beep() }
        }
    }

    /// Приоритет (nice): повысить значение (сделать менее важным) можно без прав администратора
    func setNice(_ pid: Int32, _ value: Int32) { setNice([pid], value) }

    /// Повысить значение (понизить приоритет) можно сразу; понизить значение (повысить приоритет) просит пароль администратора
    func setNice(_ pids: [Int32], _ value: Int32) {
        var failed: [Int32] = []
        for pid in pids where pid > 1 {
            if setpriority(PRIO_PROCESS, id_t(pid), value) != 0 { failed.append(pid) }
        }
        guard !failed.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let r = TMAdmin.run("/usr/bin/renice", ["-n", "\(value)", "-p"] + failed.map { "\($0)" })
            if !r.ok { DispatchQueue.main.async { NSSound.beep() } }
        }
    }

    func reveal(_ r: TMRow) {
        guard !r.path.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: r.path)])
    }

    func reveal(path: String) {
        guard !path.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    // MARK: Сбор

    private func sample() {
        if !windowVisible {
            skip += 1
            if skip % 3 != 0 { return }
        } else { skip = 0 }
        queue.async { [weak self] in self?.collect() }
        pollNettop()
    }

    private func path(of pid: Int32) -> String {
        if let p = pathCache[pid] { return p }
        var buf = [CChar](repeating: 0, count: 4096)
        let n = proc_pidpath(pid, &buf, UInt32(buf.count))
        let p = n > 0 ? String(cString: buf) : ""
        pathCache[pid] = p
        return p
    }

    private func bundleName(_ bundlePath: String) -> String {
        if let n = nameCache[bundlePath] { return n }
        var name = (bundlePath as NSString).lastPathComponent
        if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
        if let b = Bundle(path: bundlePath) {
            if let d = b.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, !d.isEmpty { name = d }
            else if let d = b.object(forInfoDictionaryKey: "CFBundleName") as? String, !d.isEmpty { name = d }
        }
        nameCache[bundlePath] = name
        return name
    }

    private func userName(_ uid: UInt32) -> String {
        if let n = userCache[uid] { return n }
        var n = String(uid)
        if let pw = getpwuid(uid_t(uid)), let c = pw.pointee.pw_name { n = String(cString: c) }
        userCache[uid] = n
        return n
    }

    /// Счётчики сети по процессам: утилита nettop, раз в цикл, в фоне
    private func pollNettop() {
        netLock.lock()
        if nettopRunning { netLock.unlock(); return }
        nettopRunning = true
        netLock.unlock()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            var cum: [Int32: (UInt64, UInt64)] = [:]
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
            p.arguments = ["-P", "-L", "1", "-n", "-x", "-J", "bytes_in,bytes_out"]
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = FileHandle.nullDevice
            if (try? p.run()) != nil {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                let text = String(data: data, encoding: .utf8) ?? ""
                for line in text.split(separator: "\n") {
                    let f = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
                    guard let k = f.firstIndex(where: {
                        !$0.contains(":") && $0.rangeOfCharacter(from: .letters) != nil
                            && $0.range(of: "\\.\\d+$", options: .regularExpression) != nil
                    }), k + 2 < f.count,
                    let i = UInt64(f[k + 1]), let o = UInt64(f[k + 2]),
                    let pidText = f[k].split(separator: ".").last, let pid = Int32(pidText) else { continue }
                    cum[pid] = (i, o)
                }
            }
            let now = DispatchTime.now().uptimeNanoseconds
            self.netLock.lock()
            let dt = self.netLastT == 0 ? 0 : Double(now &- self.netLastT) / 1e9
            var rates: [Int32: (Double, Double)] = [:]
            if dt > 0 {
                for (pid, c) in cum {
                    if let prev = self.netCum[pid], c.0 >= prev.0, c.1 >= prev.1 {
                        rates[pid] = (Double(c.0 - prev.0) / dt, Double(c.1 - prev.1) / dt)
                    }
                }
            }
            self.netRates = rates
            self.netCum = cum
            self.netLastT = now
            self.nettopRunning = false
            self.netLock.unlock()
        }
    }

    // MARK: Системные датчики

    private func sysctlString(_ name: String) -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return "" }
        return String(cString: buf)
    }

    private func diskIO() -> (UInt64, UInt64)? {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(0, IOServiceMatching("IOBlockStorageDriver"), &it) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(it) }
        var r: UInt64 = 0, w: UInt64 = 0
        var found = false
        var svc = IOIteratorNext(it)
        while svc != 0 {
            if let st = IORegistryEntryCreateCFProperty(svc, "Statistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any] {
                if let x = (st["Bytes (Read)"] as? NSNumber)?.uint64Value { r &+= x; found = true }
                if let x = (st["Bytes (Write)"] as? NSNumber)?.uint64Value { w &+= x; found = true }
            }
            IOObjectRelease(svc)
            svc = IOIteratorNext(it)
        }
        return found ? (r, w) : nil
    }

    private func gpuInfo() -> (String, Double)? {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(0, IOServiceMatching("IOAccelerator"), &it) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(it) }
        var best: (String, Double)?
        var svc = IOIteratorNext(it)
        while svc != 0 {
            if let st = IORegistryEntryCreateCFProperty(svc, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any] {
                let v = ((st["Device Utilization %"] ?? st["GPU Activity(%)"]) as? NSNumber)?.doubleValue
                if let v = v {
                    var name = "GPU"
                    if let m = IORegistryEntryCreateCFProperty(svc, "model" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() {
                        if let s = m as? String { name = s }
                        else if let d = m as? Data, let s = String(data: d, encoding: .utf8) { name = s.trimmingCharacters(in: CharacterSet(charactersIn: "\0")) }
                    }
                    if best == nil || v > best!.1 { best = (name, v) }
                }
            }
            IOObjectRelease(svc)
            svc = IOIteratorNext(it)
        }
        return best
    }

    private func batteryInfo() -> TMBattery? {
        let svc = IOServiceGetMatchingService(0, IOServiceMatching("AppleSmartBattery"))
        guard svc != 0 else { return nil }
        defer { IOObjectRelease(svc) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(svc, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let d = props?.takeRetainedValue() as? [String: Any] else { return nil }
        func num(_ k: String) -> Double? { (d[k] as? NSNumber)?.doubleValue }
        guard let cur = num("CurrentCapacity"), let mx = num("MaxCapacity"), mx > 0 else { return nil }
        var health: Double? = nil
        if let design = num("DesignCapacity"), design > 0 {
            let raw = num("AppleRawMaxCapacity") ?? mx
            if raw > 100 { health = min(100, raw / design * 100) }
        }
        var minutes: Int? = nil
        if let t = num("TimeRemaining"), t > 0, t < 6000 { minutes = Int(t) }
        return TMBattery(percent: min(100, cur / mx * 100),
                         charging: (d["IsCharging"] as? Bool) ?? false,
                         plugged: (d["ExternalConnected"] as? Bool) ?? false,
                         cycles: (d["CycleCount"] as? NSNumber)?.intValue,
                         health: health, minutes: minutes)
    }

    private func collect() {
        let wall = DispatchTime.now().uptimeNanoseconds
        let dt = prevWall == 0 ? 0 : Double(wall &- prevWall) / 1e9
        prevWall = wall

        netLock.lock()
        let nRates = netRates
        netLock.unlock()

        // список процессов
        let bytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard bytes > 0 else { return }
        var pids = [Int32](repeating: 0, count: Int(bytes) / MemoryLayout<Int32>.size + 64)
        let got = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(pids.count * MemoryLayout<Int32>.size))
        let count = max(0, Int(got) / MemoryLayout<Int32>.size)

        var groups: [String: Acc] = [:]
        var plist: [Int32: TMProc] = [:]
        var newCPU: [Int32: UInt64] = [:]
        var newDisk: [Int32: (UInt64, UInt64)] = [:]
        var newWake: [Int32: UInt64] = [:]
        var alive = Set<Int32>()
        var total = 0
        var threadsTotal = 0
        for i in 0..<min(count, pids.count) {
            let pid = pids[i]
            if pid <= 0 { continue }
            var ri = rusage_info_v4()
            let rc = withUnsafeMutablePointer(to: &ri) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
            }
            if rc != 0 { continue }
            total += 1
            alive.insert(pid)
            let ticks = ri.ri_user_time &+ ri.ri_system_time
            let ns = ticks &* UInt64(timebase.numer) / UInt64(max(1, timebase.denom))
            newCPU[pid] = ns
            var cpu = 0.0
            if dt > 0, let prev = prevCPU[pid], ns >= prev {
                cpu = Double(ns - prev) / 1e9 / dt / ncpu * 100
            }
            // диск
            let dR = ri.ri_diskio_bytesread, dW = ri.ri_diskio_byteswritten
            newDisk[pid] = (dR, dW)
            var rate = (0.0, 0.0)
            if dt > 0, let p = prevDisk[pid], dR >= p.0, dW >= p.1 {
                rate = (Double(dR - p.0) / dt, Double(dW - p.1) / dt)
            }
            // пробуждения → условная оценка энергии
            let wk = ri.ri_pkg_idle_wkups
            newWake[pid] = wk
            var wkRate = 0.0
            if dt > 0, let p = prevWake[pid], wk >= p { wkRate = Double(wk - p) / dt }
            let energy = cpu * ncpu / 10 + wkRate / 200
            let net = nRates[pid] ?? (0, 0)

            let p = path(of: pid)
            var key = p
            var bundle = false
            var name = (p as NSString).lastPathComponent
            if let r = p.range(of: ".app/") {
                key = String(p[p.startIndex..<r.lowerBound]) + ".app"
                bundle = true
                name = bundleName(key)
            } else if p.isEmpty {
                var nb = [CChar](repeating: 0, count: 256)
                _ = proc_name(pid, &nb, UInt32(nb.count))
                name = String(cString: nb)
                key = "pid:" + name
            }
            if name.isEmpty { continue }

            // сведения о процессе
            var bsd = proc_bsdinfo()
            let bsz = Int32(MemoryLayout<proc_bsdinfo>.size)
            let br = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, bsz)
            var ti = proc_taskinfo()
            let tsz = Int32(MemoryLayout<proc_taskinfo>.size)
            let tr = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &ti, tsz)
            let threads = tr == tsz ? Int(ti.pti_threadnum) : 0
            threadsTotal += threads
            let procName = bundle ? ((p as NSString).lastPathComponent) : name
            plist[pid] = TMProc(id: pid, ppid: br == bsz ? Int32(bsd.pbi_ppid) : 0, name: procName, path: p,
                                user: br == bsz ? userName(bsd.pbi_uid) : "", status: br == bsz ? Int32(bsd.pbi_status) : 0,
                                cpu: cpu, mem: ri.ri_phys_footprint, threads: threads,
                                nice: br == bsz ? Int(bsd.pbi_nice) : 0,
                                diskR: rate.0, diskW: rate.1, netIn: net.0, netOut: net.1, energy: energy, group: key)

            var g = groups[key] ?? Acc(name: name, path: key.hasPrefix("pid:") ? "" : key, bundle: bundle)
            g.pids.append(pid)
            g.cpu += cpu
            g.mem += ri.ri_phys_footprint
            g.dr += rate.0; g.dw += rate.1
            g.ni += net.0; g.no += net.1
            g.en += energy
            groups[key] = g
        }
        prevCPU = newCPU
        prevDisk = newDisk
        prevWake = newWake
        pathCache = pathCache.filter { alive.contains($0.key) }

        // процессор целиком
        var cpuTotal = cpuNow
        var load = host_cpu_load_info()
        var cnt = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &load) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(cnt)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &cnt) }
        }
        if kr == KERN_SUCCESS {
            let t = (load.cpu_ticks.0, load.cpu_ticks.1, load.cpu_ticks.2, load.cpu_ticks.3)
            if let p = prevTicks {
                let user = Double(t.0 &- p.0), sys = Double(t.1 &- p.1), idle = Double(t.2 &- p.2), nice = Double(t.3 &- p.3)
                let busy = user + sys + nice
                if busy + idle > 0 { cpuTotal = busy / (busy + idle) * 100 }
            }
            prevTicks = t
        }

        // по ядрам
        var coreNow: [Double] = []
        var nCores: natural_t = 0
        var cinfo: processor_info_array_t? = nil
        var cinfoCnt: mach_msg_type_number_t = 0
        if host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &nCores, &cinfo, &cinfoCnt) == KERN_SUCCESS, let ci = cinfo {
            var ticksNow: [[UInt32]] = []
            for c in 0..<Int(nCores) {
                let b = 4 * c
                ticksNow.append([UInt32(bitPattern: ci[b]), UInt32(bitPattern: ci[b + 1]), UInt32(bitPattern: ci[b + 2]), UInt32(bitPattern: ci[b + 3])])
            }
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: ci)),
                          vm_size_t(cinfoCnt) * vm_size_t(MemoryLayout<integer_t>.size))
            if prevCores.count == ticksNow.count {
                for c in 0..<ticksNow.count {
                    let a = ticksNow[c], p = prevCores[c]
                    let busy = Double(a[0] &- p[0]) + Double(a[1] &- p[1]) + Double(a[3] &- p[3])
                    let idle = Double(a[2] &- p[2])
                    coreNow.append(busy + idle > 0 ? busy / (busy + idle) * 100 : 0)
                }
            }
            prevCores = ticksNow
        }

        // память
        var vm = vm_statistics64()
        var vc = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let vr = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(vc)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &vc) }
        }
        var used: UInt64 = 0
        var parts = TMMemParts()
        if vr == KERN_SUCCESS {
            let page = UInt64(vm_kernel_page_size)
            let appPages = UInt64(vm.internal_page_count) > UInt64(vm.purgeable_count)
                ? UInt64(vm.internal_page_count) - UInt64(vm.purgeable_count) : 0
            used = (appPages + UInt64(vm.wire_count) + UInt64(vm.compressor_page_count)) * page
            parts = TMMemParts(app: appPages * page, wired: UInt64(vm.wire_count) * page,
                               compressed: UInt64(vm.compressor_page_count) * page,
                               cached: (UInt64(vm.external_page_count) + UInt64(vm.purgeable_count)) * page,
                               free: UInt64(vm.free_count) * page)
        }
        var sw = xsw_usage()
        var swSize = MemoryLayout<xsw_usage>.size
        var swUsed: UInt64 = 0, swTotal: UInt64 = 0
        if sysctlbyname("vm.swapusage", &sw, &swSize, nil, 0) == 0 { swUsed = sw.xsu_used; swTotal = sw.xsu_total }
        var press: Int32 = 1
        var pSize = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &press, &pSize, nil, 0) != 0 { press = 1 }

        // сеть (счётчики интерфейсов 32-разрядные: считаем приращение по модулю)
        var down: UInt64 = 0, up: UInt64 = 0
        var ifap: UnsafeMutablePointer<ifaddrs>?
        var newNet: [String: (UInt32, UInt32)] = [:]
        var ifRate: [String: (Double, Double)] = [:]
        var ifIP: [String: String] = [:]
        if getifaddrs(&ifap) == 0, let first = ifap {
            var cur: UnsafeMutablePointer<ifaddrs>? = first
            while let a = cur {
                let name = String(cString: a.pointee.ifa_name)
                if let addr = a.pointee.ifa_addr, !name.hasPrefix("lo") {
                    if addr.pointee.sa_family == UInt8(AF_LINK), let d = a.pointee.ifa_data {
                        let data = d.assumingMemoryBound(to: if_data.self).pointee
                        newNet[name] = (data.ifi_ibytes, data.ifi_obytes)
                        if let p = prevNet[name] {
                            let di = UInt64(data.ifi_ibytes &- p.0), dout = UInt64(data.ifi_obytes &- p.1)
                            down += di; up += dout
                            ifRate[name] = dt > 0 ? (Double(di) / dt, Double(dout) / dt) : (0, 0)
                        }
                    } else if addr.pointee.sa_family == UInt8(AF_INET) {
                        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                            ifIP[name] = String(cString: host)
                        }
                    }
                }
                cur = a.pointee.ifa_next
            }
            freeifaddrs(ifap)
        }
        prevNet = newNet
        let downRate = dt > 0 ? Double(down) / dt : 0
        let upRate = dt > 0 ? Double(up) / dt : 0
        var ifList: [TMIface] = []
        for (n, ip) in ifIP {
            let r = ifRate[n] ?? (0, 0)
            ifList.append(TMIface(name: n, ip: ip, down: r.0, up: r.1))
        }
        ifList.sort { $0.name < $1.name }

        // диск: место и скорость
        var dTotal: Int64 = 0, dFree: Int64 = 0
        if let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]) {
            dTotal = Int64(v.volumeTotalCapacity ?? 0)
            dFree = v.volumeAvailableCapacityForImportantUsage ?? 0
        }
        var readRate = 0.0, writeRate = 0.0
        if let io = diskIO() {
            if let p = prevIO, dt > 0, io.0 >= p.0, io.1 >= p.1 {
                readRate = Double(io.0 - p.0) / dt
                writeRate = Double(io.1 - p.1) / dt
            }
            prevIO = io
        }

        let gpu = gpuInfo()
        let bat = batteryInfo()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            var appByPath: [String: NSRunningApplication] = [:]
            for a in NSWorkspace.shared.runningApplications where a.activationPolicy == .regular {
                if let p = a.bundleURL?.path { appByPath[p] = a }
            }
            var apps: [TMRow] = [], bg: [TMRow] = []
            for (key, g) in groups {
                let isApp = appByPath[key] != nil
                var icon: NSImage? = nil
                if isApp { icon = appByPath[key]?.icon }
                else if g.bundle {
                    if let c = self.iconCache[key] { icon = c }
                    else { let i = NSWorkspace.shared.icon(forFile: key); self.iconCache[key] = i; icon = i }
                }
                let row = TMRow(id: key, name: g.name, pids: g.pids, cpu: g.cpu, mem: g.mem, isApp: isApp, icon: icon, path: g.path,
                                diskR: g.dr, diskW: g.dw, netIn: g.ni, netOut: g.no, energy: g.en)
                if isApp { apps.append(row) } else { bg.append(row) }
            }
            self.apps = apps
            self.background = bg
            self.procs = plist
            self.processCount = total
            self.threadCount = threadsTotal
            self.cpuNow = cpuTotal
            self.memUsed = used
            self.memTotal = ProcessInfo.processInfo.physicalMemory
            self.memParts = parts
            self.swapUsed = swUsed
            self.swapTotal = swTotal
            self.pressure = Int(press)
            self.diskTotal = dTotal
            self.diskFree = dFree
            self.diskReadNow = readRate
            self.diskWriteNow = writeRate
            self.netDownNow = downRate
            self.netUpNow = upRate
            self.ifaces = ifList
            self.gpuName = gpu?.0
            self.gpuNow = gpu?.1 ?? 0
            self.battery = bat
            TMExtras.afterSample(self)
            func push(_ a: inout [Double], _ v: Double) {
                a.append(v)
                if a.count > TMSampler.historyLength { a.removeFirst(a.count - TMSampler.historyLength) }
            }
            push(&self.cpuHistory, cpuTotal)
            if !coreNow.isEmpty {
                if self.coreHistory.count != coreNow.count { self.coreHistory = Array(repeating: [], count: coreNow.count) }
                for c in 0..<coreNow.count { push(&self.coreHistory[c], coreNow[c]) }
            }
            push(&self.memHistory, self.memTotal > 0 ? Double(used) / Double(self.memTotal) * 100 : 0)
            push(&self.diskReadHistory, readRate)
            push(&self.diskWriteHistory, writeRate)
            push(&self.netDown, downRate)
            push(&self.netUp, upRate)
            for i in ifList {
                var d = self.ifaceDown[i.name] ?? [], u = self.ifaceUp[i.name] ?? []
                push(&d, i.down); push(&u, i.up)
                self.ifaceDown[i.name] = d; self.ifaceUp[i.name] = u
            }
            if gpu != nil { push(&self.gpuHistory, self.gpuNow) }
            if let b = bat { push(&self.batteryHistory, b.percent) }
        }
    }
}

// MARK: - Форматирование

func tmBytes(_ b: Double) -> String {
    let f = ByteCountFormatter()
    f.countStyle = .memory
    f.allowsNonnumericFormatting = false
    return f.string(fromByteCount: Int64(max(0, b)))
}

func tmRate(_ b: Double) -> String {
    if b < 1 { return "0 " + T("Б/с") }
    let f = ByteCountFormatter()
    f.countStyle = .binary
    f.allowsNonnumericFormatting = false
    return f.string(fromByteCount: Int64(b)) + T("/с")
}

func tmEnergyText(_ e: Double) -> String {
    if e < 0.3 { return T("Очень низкое") }
    if e < 1.5 { return T("Низкое") }
    if e < 4 { return T("Умеренное") }
    if e < 10 { return T("Высокое") }
    return T("Очень высокое")
}

func tmEnergyColor(_ e: Double) -> Color {
    if e < 1.5 { return .green }
    if e < 4 { return .yellow }
    if e < 10 { return .orange }
    return .red
}

// MARK: - Интерфейс

struct TMRootView: View {
    @ObservedObject private var s = TMSampler.shared
    @State private var tab = 0
    @State private var showRules = false
    @State private var onTop = UserDefaults.standard.bool(forKey: "tm.onTop")
    @State private var menuBar = UserDefaults.standard.bool(forKey: "tm.menubar")

    private func tabButton(_ title: String, _ i: Int) -> some View {
        Button { tab = i } label: {
            Text(title)
                .font(.system(size: 13, weight: tab == i ? .semibold : .regular))
                .foregroundColor(tab == i ? .accentColor : .secondary)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .overlay(Rectangle().fill(tab == i ? Color.accentColor : Color.clear).frame(height: 2), alignment: .bottom)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toolButton(_ icon: String, _ help: String, _ on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(on ? .accentColor : .secondary)
                .frame(width: 28, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                tabButton(T("Процессы"), 0)
                tabButton(T("Производительность"), 1)
                tabButton(T("Журнал"), 5)
                tabButton(T("Подробности"), 4)
                if TMUsers.count(s.procs) > 1 { tabButton(T("Пользователи"), 6) }
                tabButton(T("Службы"), 7)
                tabButton(T("Автозагрузка"), 2)
                Spacer()
                toolButton(onTop ? "pin.fill" : "pin", T("Поверх остальных окон"), onTop) {
                    onTop.toggle()
                    TMWindowController.shared.setOnTop(onTop)
                }
                toolButton("chart.xyaxis.line", T("Значок с графиком ЦП в строке меню"), menuBar) {
                    menuBar.toggle()
                    TMMenuBar.shared.setEnabled(menuBar)
                }
                toolButton("bolt.badge.clock", T("Автоматические действия"), TMRules.shared.enabled) { showRules = true }
                    .popover(isPresented: $showRules) { TMRulesView() }
            }
            .padding(.horizontal, 8)
            Divider()
            switch tab {
            case 0: TMProcessesView(s: s)
            case 1: TMPerformanceView(s: s)
            case 2: TMStartupView()
            case 5: TMJournalView()
            case 6: TMUsersView(s: s)
            case 7: TMServicesView(s: s)
            default: TMDetailsView(s: s)
            }
        }
        .frame(minWidth: 700, minHeight: 440)
    }
}

// MARK: Процессы

private enum TMCol: String, CaseIterable {
    case cpu, mem, disk, net, energy, count
    var title: String {
        switch self {
        case .cpu: return T("ЦП")
        case .mem: return T("Память")
        case .disk: return T("Диск")
        case .net: return T("Сеть")
        case .energy: return T("Энергопотребление")
        case .count: return T("Процессов")
        }
    }
    var width: CGFloat {
        switch self {
        case .cpu: return 76
        case .mem: return 96
        case .disk, .net: return 100
        case .energy: return 130
        case .count: return 76
        }
    }
}

struct TMProcessesView: View {
    @ObservedObject var s: TMSampler
    @State private var selected: String? = nil
    @State private var sortKey = "name"
    @State private var asc = true
    @State private var query = ""
    @State private var expanded = Set<String>()
    @State private var colsRaw = UserDefaults.standard.string(forKey: "tm.cols") ?? "cpu,mem,disk,net,energy"

    private var cols: [TMCol] { TMCol.allCases.filter { colsRaw.split(separator: ",").contains(Substring($0.rawValue)) } }

    private func toggleCol(_ c: TMCol) {
        var set = Set(colsRaw.split(separator: ",").map(String.init))
        if set.contains(c.rawValue) { set.remove(c.rawValue) } else { set.insert(c.rawValue) }
        colsRaw = TMCol.allCases.map { $0.rawValue }.filter { set.contains($0) }.joined(separator: ",")
        UserDefaults.standard.set(colsRaw, forKey: "tm.cols")
    }

    private func value(_ r: TMRow, _ key: String) -> Double {
        switch key {
        case "cpu": return r.cpu
        case "mem": return Double(r.mem)
        case "disk": return r.diskR + r.diskW
        case "net": return r.netIn + r.netOut
        case "energy": return r.energy
        default: return Double(r.pids.count)
        }
    }

    private func sorted(_ a: [TMRow]) -> [TMRow] {
        let f = query.isEmpty ? a : a.filter { $0.name.localizedCaseInsensitiveContains(query) }
        return f.sorted { x, y in
            if sortKey == "name" {
                let r = x.name.localizedCaseInsensitiveCompare(y.name)
                return asc ? r == .orderedAscending : r == .orderedDescending
            }
            let va = value(x, sortKey), vb = value(y, sortKey)
            return asc ? va < vb : va > vb
        }
    }

    private func childRows(_ r: TMRow) -> [TMRow] {
        r.pids.compactMap { s.procs[$0] }.map { childRow($0) }.sorted { $0.cpu > $1.cpu }
    }

    private func childRow(_ p: TMProc) -> TMRow {
        TMRow(id: "p:\(p.id)", name: "\(p.name) (\(p.id))", pids: [p.id], cpu: p.cpu, mem: p.mem, isApp: false,
              icon: nil, path: p.path, diskR: p.diskR, diskW: p.diskW, netIn: p.netIn, netOut: p.netOut, energy: p.energy)
    }

    private var selectedRow: TMRow? {
        guard let id = selected else { return nil }
        if id.hasPrefix("p:"), let pid = Int32(id.dropFirst(2)), let p = s.procs[pid] { return childRow(p) }
        return (s.apps + s.background).first { $0.id == id }
    }

    private func header(_ title: String, _ sub: String, _ key: String, width: CGFloat?, leading: Bool) -> some View {
        Button {
            if sortKey == key { asc.toggle() } else { sortKey = key; asc = key == "name" }
        } label: {
            VStack(alignment: leading ? .leading : .trailing, spacing: 1) {
                Text(sub.isEmpty ? " " : sub).font(.system(size: 13))
                HStack(spacing: 3) {
                    Text(title).lineLimit(1)
                    if sortKey == key { Image(systemName: asc ? "chevron.up" : "chevron.down").font(.system(size: 8, weight: .bold)) }
                }
                .font(.caption).foregroundColor(.secondary)
            }
            .frame(maxWidth: width ?? .infinity, alignment: leading ? .leading : .trailing)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func heat(_ v: Double) -> Color { Color.orange.opacity(min(0.55, max(0, v))) }

    @ViewBuilder private func cell(_ c: TMCol, _ r: TMRow) -> some View {
        switch c {
        case .cpu:
            Text(String(format: "%.1f%%", r.cpu))
                .frame(width: c.width, alignment: .trailing).padding(.vertical, 5).padding(.trailing, 6)
                .background(heat(r.cpu / 40))
        case .mem:
            Text(tmBytes(Double(r.mem)))
                .frame(width: c.width, alignment: .trailing).padding(.vertical, 5).padding(.trailing, 6)
                .background(heat(Double(r.mem) / 3e9))
        case .disk:
            Text(tmRate(r.diskR + r.diskW)).lineLimit(1)
                .frame(width: c.width, alignment: .trailing).padding(.vertical, 5).padding(.trailing, 6)
                .background(heat((r.diskR + r.diskW) / 50e6))
        case .net:
            Text(tmRate(r.netIn + r.netOut)).lineLimit(1)
                .frame(width: c.width, alignment: .trailing).padding(.vertical, 5).padding(.trailing, 6)
                .background(heat((r.netIn + r.netOut) / 5e6))
        case .energy:
            HStack(spacing: 5) {
                Circle().fill(tmEnergyColor(r.energy)).frame(width: 7, height: 7)
                Text(tmEnergyText(r.energy)).lineLimit(1)
            }
            .frame(width: c.width, alignment: .leading).padding(.leading, 6)
        case .count:
            Text("\(r.pids.count)")
                .frame(width: c.width, alignment: .trailing).padding(.trailing, 6)
                .foregroundColor(.secondary)
        }
    }

    private func rowView(_ r: TMRow, child: Bool = false) -> some View {
        let sel = selected == r.id
        let canExpand = !child && r.pids.count > 1
        return HStack(spacing: 0) {
            HStack(spacing: 6) {
                if child {
                    Spacer().frame(width: 26)
                } else if canExpand {
                    Image(systemName: expanded.contains(r.id) ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold)).foregroundColor(.secondary).frame(width: 12)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if expanded.contains(r.id) { expanded.remove(r.id) } else { expanded.insert(r.id) }
                        }
                } else {
                    Spacer().frame(width: 12)
                }
                if let i = r.icon {
                    Image(nsImage: i).resizable().frame(width: 16, height: 16)
                } else if !child {
                    Image(systemName: "gearshape").frame(width: 16, height: 16).foregroundColor(.secondary)
                }
                Text(r.name).lineLimit(1)
                if !child && r.pids.count > 1 { Text("(\(r.pids.count))").foregroundColor(.secondary) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(cols, id: \.rawValue) { cell($0, r) }
        }
        .font(.system(size: child ? 12 : 13))
        .foregroundColor(child ? .secondary : .primary)
        .padding(.leading, 12).padding(.trailing, 6)
        .background(sel ? Color.accentColor.opacity(0.28) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { selected = r.id }
        .contextMenu {
            Button(T("Снять задачу")) { s.end(r, force: false) }
            Button(T("Принудительно завершить")) { s.end(r, force: true) }
            Divider()
            Button(T("Приостановить")) { s.suspend(r.pids, true) }
            Button(T("Продолжить")) { s.suspend(r.pids, false) }
            Menu(T("Приоритет")) {
                ForEach(TMPriority.all) { pr in Button(pr.title) { s.setNice(r.pids, pr.value) } }
            }
            Divider()
            if canExpand { Button(expanded.contains(r.id) ? T("Свернуть") : T("Развернуть")) {
                if expanded.contains(r.id) { expanded.remove(r.id) } else { expanded.insert(r.id) } } }
            if !r.path.isEmpty {
                Button(T("Показать в Finder")) { s.reveal(r) }
                Button(T("Скопировать путь")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(r.path, forType: .string)
                }
            }
        }
    }

    private func sectionTitle(_ title: String, _ n: Int) -> some View {
        Text("\(title) (\(n))")
            .font(.system(size: 12, weight: .semibold)).foregroundColor(.accentColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 4)
    }

    @ViewBuilder private func group(_ list: [TMRow]) -> some View {
        ForEach(list) { r in
            rowView(r)
            if expanded.contains(r.id) && r.pids.count > 1 {
                ForEach(childRows(r)) { rowView($0, child: true) }
            }
        }
    }

    private var totalDisk: Double { s.diskReadNow + s.diskWriteNow }

    private func columnSub(_ c: TMCol) -> String {
        switch c {
        case .cpu: return String(format: "%.0f%%", s.cpuNow)
        case .mem: return s.memTotal > 0 ? String(format: "%.0f%%", Double(s.memUsed) / Double(s.memTotal) * 100) : ""
        case .disk: return tmRate(totalDisk)
        case .net: return tmRate(s.netDownNow + s.netUpNow)
        default: return ""
        }
    }

    var body: some View {
        let apps = sorted(s.apps), bg = sorted(s.background)
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                header(T("Имя"), "", "name", width: nil, leading: true)
                ForEach(cols, id: \.rawValue) { c in
                    header(c.title, columnSub(c), c.rawValue, width: c.width + 6, leading: false)
                }
            }
            .padding(.leading, 12).padding(.trailing, 6).padding(.vertical, 6)
            .contextMenu {
                ForEach(TMCol.allCases, id: \.rawValue) { c in
                    Button((cols.contains(c) ? "✓ " : "    ") + c.title) { toggleCol(c) }
                }
            }
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    sectionTitle(T("Приложения"), apps.count)
                    group(apps)
                    sectionTitle(T("Фоновые процессы"), bg.count)
                    group(bg)
                }
                .padding(.bottom, 8)
            }
            Divider()
            HStack(spacing: 10) {
                TextField(T("Поиск процессов"), text: $query)
                    .textFieldStyle(.roundedBorder).frame(width: 220)
                Text(T("Правый клик по заголовку — выбор столбцов")).font(.caption).foregroundColor(.secondary)
                Spacer()
                Button(T("Снять задачу")) { if let r = selectedRow { s.end(r, force: false) } }
                    .disabled(selectedRow == nil)
            }
            .padding(10)
        }
    }
}

// MARK: Подробности

struct TMDetailsView: View {
    @ObservedObject var s: TMSampler
    @State private var selected: Int32? = nil
    @State private var sortKey = "pid"
    @State private var asc = true
    @State private var query = ""

    private func stateText(_ st: Int32) -> String {
        switch st {
        case 1: return T("Запуск")
        case 2: return T("Выполняется")
        case 3: return T("Спит")
        case 4: return T("Остановлен")
        case 5: return T("Зомби")
        default: return "—"
        }
    }

    private func sorted() -> [TMProc] {
        var a = Array(s.procs.values)
        if !query.isEmpty {
            a = a.filter { $0.name.localizedCaseInsensitiveContains(query) || String($0.id) == query || $0.user.localizedCaseInsensitiveContains(query) }
        }
        return a.sorted { x, y in
            switch sortKey {
            case "name":
                let r = x.name.localizedCaseInsensitiveCompare(y.name)
                return asc ? r == .orderedAscending : r == .orderedDescending
            case "user":
                let r = x.user.localizedCaseInsensitiveCompare(y.user)
                return asc ? r == .orderedAscending : r == .orderedDescending
            case "state": return asc ? x.status < y.status : x.status > y.status
            case "cpu": return asc ? x.cpu < y.cpu : x.cpu > y.cpu
            case "mem": return asc ? x.mem < y.mem : x.mem > y.mem
            case "threads": return asc ? x.threads < y.threads : x.threads > y.threads
            case "ppid": return asc ? x.ppid < y.ppid : x.ppid > y.ppid
            default: return asc ? x.id < y.id : x.id > y.id
            }
        }
    }

    private func header(_ title: String, _ key: String, width: CGFloat?, trailing: Bool = false) -> some View {
        Button {
            if sortKey == key { asc.toggle() } else { sortKey = key; asc = key == "pid" || key == "name" || key == "user" }
        } label: {
            HStack(spacing: 3) {
                Text(title)
                if sortKey == key { Image(systemName: asc ? "chevron.up" : "chevron.down").font(.system(size: 8, weight: .bold)) }
            }
            .font(.caption).foregroundColor(.secondary)
            .frame(maxWidth: width ?? .infinity, alignment: trailing ? .trailing : .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func rowView(_ p: TMProc) -> some View {
        let sel = selected == p.id
        return HStack(spacing: 0) {
            Text(String(p.id)).frame(width: 64, alignment: .leading).foregroundColor(.secondary)
            Text(p.name).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            Text(p.user).lineLimit(1).frame(width: 90, alignment: .leading)
            Text(stateText(p.status)).frame(width: 100, alignment: .leading)
            Text(String(format: "%.1f%%", p.cpu)).frame(width: 70, alignment: .trailing)
            Text(tmBytes(Double(p.mem))).frame(width: 90, alignment: .trailing)
            Text("\(p.threads)").frame(width: 66, alignment: .trailing)
            Text("\(p.nice)").frame(width: 56, alignment: .trailing)
            Text(String(p.ppid)).frame(width: 70, alignment: .trailing).foregroundColor(.secondary)
        }
        .font(.system(size: 12))
        .padding(.leading, 12).padding(.trailing, 12).padding(.vertical, 3)
        .background(sel ? Color.accentColor.opacity(0.28) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { selected = p.id }
        .contextMenu { actions(p) }
    }

    @ViewBuilder private func actions(_ p: TMProc) -> some View {
        Button(T("Снять задачу")) { s.endPid(p.id, force: false) }
        Button(T("Принудительно завершить")) { s.endPid(p.id, force: true) }
        Divider()
        Button(T("Приостановить")) { s.suspend(p.id, true) }
        Button(T("Продолжить")) { s.suspend(p.id, false) }
        Divider()
        Menu(T("Приоритет")) {
            ForEach(TMPriority.all) { pr in Button(pr.title) { s.setNice([p.id], pr.value) } }
        }
        if !p.path.isEmpty {
            Divider()
            Button(T("Показать в Finder")) { s.reveal(path: p.path) }
            Button(T("Скопировать путь")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(p.path, forType: .string)
            }
        }
    }

    var body: some View {
        let list = sorted()
        let cur = selected.flatMap { s.procs[$0] }
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                header("PID", "pid", width: 64)
                header(T("Имя"), "name", width: nil)
                header(T("Пользователь"), "user", width: 90)
                header(T("Состояние"), "state", width: 100)
                header(T("ЦП"), "cpu", width: 70, trailing: true)
                header(T("Память"), "mem", width: 90, trailing: true)
                header(T("Потоки"), "threads", width: 66, trailing: true)
                Text(T("Приор.")).font(.caption).foregroundColor(.secondary).frame(width: 56, alignment: .trailing)
                header(T("Родитель"), "ppid", width: 70, trailing: true)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) { ForEach(list) { rowView($0) } }
            }
            Divider()
            HStack(spacing: 10) {
                TextField(T("Поиск: имя, PID или пользователь"), text: $query)
                    .textFieldStyle(.roundedBorder).frame(width: 240)
                Text("\(list.count)").font(.caption).foregroundColor(.secondary)
                Spacer()
                if let c = cur {
                    Menu(T("Действия")) { actions(c) }.frame(width: 100)
                    Button(T("Снять задачу")) { s.endPid(c.id, force: false) }
                } else {
                    Menu(T("Действия")) { Text(T("Выберите процесс")) }.frame(width: 100).disabled(true)
                    Button(T("Снять задачу")) { }.disabled(true)
                }
            }
            .padding(10)
        }
    }
}

// MARK: Производительность

struct TMGraph: View {
    let series: [[Double]]
    let colors: [Color]
    let maxValue: Double

    private func line(_ v: [Double], _ size: CGSize, closed: Bool) -> Path {
        var p = Path()
        guard !v.isEmpty else { return p }
        let n = TMSampler.historyLength
        func pt(_ i: Int) -> CGPoint {
            let x = size.width * CGFloat(i + n - v.count) / CGFloat(n - 1)
            let y = size.height * (1 - CGFloat(min(1, max(0, v[i] / max(maxValue, 0.0001)))))
            return CGPoint(x: x, y: y)
        }
        p.move(to: closed ? CGPoint(x: pt(0).x, y: size.height) : pt(0))
        if closed { p.addLine(to: pt(0)) }
        for i in 1..<max(1, v.count) where v.count > 1 { p.addLine(to: pt(i)) }
        if closed { p.addLine(to: CGPoint(x: pt(v.count - 1).x, y: size.height)); p.closeSubpath() }
        return p
    }

    var body: some View {
        GeometryReader { g in
            ZStack {
                Rectangle().fill(Color.primary.opacity(0.03))
                Path { p in
                    for i in 1..<4 {
                        let y = g.size.height * CGFloat(i) / 4
                        p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: g.size.width, y: y))
                    }
                    for i in 1..<6 {
                        let x = g.size.width * CGFloat(i) / 6
                        p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: g.size.height))
                    }
                }
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                ForEach(0..<series.count, id: \.self) { k in
                    line(series[k], g.size, closed: true).fill(colors[k].opacity(0.18))
                    line(series[k], g.size, closed: false).stroke(colors[k], lineWidth: 1.5)
                }
            }
            .overlay(Rectangle().stroke(Color.primary.opacity(0.3), lineWidth: 1))
        }
    }
}

struct TMPerformanceView: View {
    @ObservedObject var s: TMSampler
    @State private var sel = 0
    @State private var iface = ""          // "" — все интерфейсы

    private let sysInfo = TMSysInfo()

    private var memPct: Double { s.memTotal > 0 ? Double(s.memUsed) / Double(s.memTotal) * 100 : 0 }
    private var diskUsed: Int64 { max(0, s.diskTotal - s.diskFree) }
    private var diskPct: Double { s.diskTotal > 0 ? Double(diskUsed) / Double(s.diskTotal) * 100 : 0 }
    private var netMax: Double { max(100_000, (s.netDown + s.netUp).max() ?? 0) * 1.2 }
    private var diskMax: Double { max(1_000_000, (s.diskReadHistory + s.diskWriteHistory).max() ?? 0) * 1.2 }

    private var curDown: [Double] { iface.isEmpty ? s.netDown : (s.ifaceDown[iface] ?? []) }
    private var curUp: [Double] { iface.isEmpty ? s.netUp : (s.ifaceUp[iface] ?? []) }
    private var curIface: TMIface? { s.ifaces.first { $0.name == iface } }
    private var curDownNow: Double { iface.isEmpty ? s.netDownNow : (curIface?.down ?? 0) }
    private var curUpNow: Double { iface.isEmpty ? s.netUpNow : (curIface?.up ?? 0) }
    private var curNetMax: Double { max(100_000, (curDown + curUp).max() ?? 0) * 1.2 }

    private func card(_ i: Int, _ title: String, _ value: String, _ series: [[Double]], _ colors: [Color], _ maxV: Double) -> some View {
        Button { sel = i } label: {
            HStack(spacing: 8) {
                TMGraph(series: series, colors: colors, maxValue: maxV).frame(width: 64, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Text(value).font(.caption).foregroundColor(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(sel == i ? Color.accentColor.opacity(0.18) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundColor(.secondary)
            Text(value).font(.system(size: 15)).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func uptime() -> String {
        let t = Int(ProcessInfo.processInfo.systemUptime)
        let d = t / 86400, h = (t % 86400) / 3600, m = (t % 3600) / 60, sec = t % 60
        return d > 0 ? String(format: "%d:%02d:%02d:%02d", d, h, m, sec) : String(format: "%d:%02d:%02d", h, m, sec)
    }

    private func pressureText() -> (String, Color) {
        switch s.pressure {
        case 4: return (T("Критическое"), .red)
        case 2: return (T("Предупреждение"), .orange)
        default: return (T("Нормальное"), .green)
        }
    }

    private func legend(_ color: Color, _ title: String, _ v: UInt64) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(title).font(.caption).foregroundColor(.secondary)
            Text(tmBytes(Double(v))).font(.caption)
        }
    }

    private var memBar: some View {
        let p = s.memParts
        let items: [(Color, UInt64)] = [(.purple, p.app), (.orange, p.wired), (.yellow, p.compressed), (.gray, p.cached)]
        let total = Double(max(1, s.memTotal))
        return VStack(alignment: .leading, spacing: 6) {
            Text(T("Состав памяти")).font(.caption).foregroundColor(.secondary)
            GeometryReader { g in
                HStack(spacing: 0) {
                    ForEach(0..<items.count, id: \.self) { i in
                        Rectangle().fill(items[i].0.opacity(0.75)).frame(width: g.size.width * CGFloat(Double(items[i].1) / total))
                    }
                    Spacer(minLength: 0)
                }
                .overlay(Rectangle().stroke(Color.primary.opacity(0.3), lineWidth: 1))
            }
            .frame(height: 22)
            HStack(spacing: 14) {
                legend(.purple, T("Программы"), p.app)
                legend(.orange, T("Закреплённая"), p.wired)
                legend(.yellow, T("Сжатая"), p.compressed)
                legend(.gray, T("Кэш"), p.cached)
                legend(Color.primary.opacity(0.15), T("Свободно"), p.free)
            }
        }
    }

    private var coreGrid: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(T("Загрузка по ядрам")).font(.caption).foregroundColor(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
                ForEach(0..<s.coreHistory.count, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 2) {
                        TMGraph(series: [s.coreHistory[i]], colors: [.blue], maxValue: 100).frame(height: 36)
                        Text("\(i + 1) · " + String(format: "%.0f%%", s.coreHistory[i].last ?? 0))
                            .font(.system(size: 10)).foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private func grid<C: View>(@ViewBuilder _ stats: () -> C) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14, alignment: .topLeading)], alignment: .leading, spacing: 12) { stats() }
    }

    private func panel<G: View, E: View, C: View>(_ title: String, _ subtitle: String, _ value: String, _ graph: G,
                                                  @ViewBuilder _ extra: () -> E, @ViewBuilder _ stats: () -> C) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.system(size: 22, weight: .semibold))
                    Spacer()
                    Text(subtitle).font(.system(size: 13)).foregroundColor(.secondary).lineLimit(1)
                }
                graph.frame(height: 170)
                Text(value).font(.system(size: 13)).foregroundColor(.secondary)
                extra()
                grid(stats)
            }
        }
    }

    @ViewBuilder private var detail: some View {
        switch sel {
        case 0:
            panel(T("ЦП"), sysInfo.cpuName, String(format: "%.0f%%", s.cpuNow),
                  TMGraph(series: [s.cpuHistory], colors: [.blue], maxValue: 100)) {
                if !s.coreHistory.isEmpty { coreGrid }
            } _: {
                stat(T("Использование"), String(format: "%.0f%%", s.cpuNow))
                stat(T("Процессов"), "\(s.processCount)")
                stat(T("Потоков"), "\(s.threadCount)")
                stat(T("Время работы"), uptime())
                stat(T("Ядер"), sysInfo.coresText)
                if !sysInfo.model.isEmpty { stat(T("Модель"), sysInfo.model) }
            }
        case 1:
            let pr = pressureText()
            panel(T("Память"), tmBytes(Double(s.memTotal)), tmBytes(Double(s.memUsed)) + " / " + tmBytes(Double(s.memTotal)),
                  TMGraph(series: [s.memHistory], colors: [.purple], maxValue: 100)) {
                memBar
            } _: {
                stat(T("Занято"), tmBytes(Double(s.memUsed)))
                stat(T("Свободно"), tmBytes(Double(s.memTotal) - Double(s.memUsed)))
                stat(T("Использование"), String(format: "%.0f%%", memPct))
                stat(T("Файл подкачки"), s.swapTotal > 0 ? tmBytes(Double(s.swapUsed)) + " / " + tmBytes(Double(s.swapTotal)) : tmBytes(Double(s.swapUsed)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(T("Давление памяти")).font(.caption).foregroundColor(.secondary)
                    HStack(spacing: 5) {
                        Circle().fill(pr.1).frame(width: 8, height: 8)
                        Text(pr.0).font(.system(size: 15))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case 2:
            panel(T("Диск"), tmBytes(Double(s.diskTotal)),
                  T("Чтение") + " " + tmRate(s.diskReadNow) + "   " + T("Запись") + " " + tmRate(s.diskWriteNow),
                  TMGraph(series: [s.diskReadHistory, s.diskWriteHistory], colors: [.blue, .orange], maxValue: diskMax)) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(T("Занято") + String(format: " %.0f%%", diskPct)).font(.caption).foregroundColor(.secondary)
                    ProgressView(value: min(1, max(0, diskPct / 100))).progressViewStyle(.linear)
                }
            } _: {
                stat(T("Чтение"), tmRate(s.diskReadNow))
                stat(T("Запись"), tmRate(s.diskWriteNow))
                stat(T("Занято"), tmBytes(Double(diskUsed)))
                stat(T("Свободно"), tmBytes(Double(s.diskFree)))
                stat(T("Всего"), tmBytes(Double(s.diskTotal)))
            }
        case 3:
            panel(T("Сеть"), iface.isEmpty ? T("Все интерфейсы") : iface,
                  "↓ " + tmRate(curDownNow) + "   ↑ " + tmRate(curUpNow),
                  TMGraph(series: [curDown, curUp], colors: [.blue, .orange], maxValue: curNetMax)) {
                HStack {
                    Text(T("Интерфейс")).font(.caption).foregroundColor(.secondary)
                    Picker("", selection: $iface) {
                        Text(T("Все")).tag("")
                        ForEach(s.ifaces) { Text($0.name).tag($0.name) }
                    }
                    .labelsHidden().frame(width: 140)
                    Spacer()
                }
            } _: {
                stat(T("Приём"), tmRate(curDownNow))
                stat(T("Передача"), tmRate(curUpNow))
                if !iface.isEmpty, let i = curIface { stat(T("IP-адрес"), i.ip) }
                if iface.isEmpty {
                    ForEach(s.ifaces) { stat($0.name, $0.ip) }
                }
            }
        case 4:
            panel(T("Видеокарта"), s.gpuName ?? "", String(format: "%.0f%%", s.gpuNow),
                  TMGraph(series: [s.gpuHistory], colors: [.pink], maxValue: 100)) { EmptyView() } _: {
                stat(T("Использование"), String(format: "%.0f%%", s.gpuNow))
                stat(T("Модель"), s.gpuName ?? "—")
            }
        default:
            if let b = s.battery {
                panel(T("Батарея"), String(format: "%.0f%%", b.percent),
                      b.charging ? T("Заряжается") : (b.plugged ? T("От сети, не заряжается") : T("От батареи")),
                      TMGraph(series: [s.batteryHistory], colors: [.green], maxValue: 100)) { EmptyView() } _: {
                    stat(T("Заряд"), String(format: "%.0f%%", b.percent))
                    if let m = b.minutes { stat(b.charging ? T("До полного заряда") : T("Осталось"), String(format: "%d:%02d", m / 60, m % 60)) }
                    if let c = b.cycles { stat(T("Циклов зарядки"), "\(c)") }
                    if let h = b.health { stat(T("Состояние батареи"), String(format: "%.0f%%", h)) }
                }
            } else {
                EmptyView()
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 4) {
                    card(0, T("ЦП"), String(format: "%.0f%%", s.cpuNow), [s.cpuHistory], [.blue], 100)
                    card(1, T("Память"), tmBytes(Double(s.memUsed)) + String(format: " (%.0f%%)", memPct), [s.memHistory], [.purple], 100)
                    card(2, T("Диск"), tmRate(s.diskReadNow + s.diskWriteNow), [s.diskReadHistory, s.diskWriteHistory], [.blue, .orange], diskMax)
                    card(3, T("Сеть"), "↓ " + tmRate(s.netDownNow), [s.netDown, s.netUp], [.blue, .orange], netMax)
                    if s.gpuName != nil {
                        card(4, T("Видеокарта"), String(format: "%.0f%%", s.gpuNow), [s.gpuHistory], [.pink], 100)
                    }
                    if let b = s.battery {
                        card(5, T("Батарея"), String(format: "%.0f%%", b.percent) + (b.charging ? " ⚡︎" : ""), [s.batteryHistory], [.green], 100)
                    }
                }
                .padding(10)
            }
            .frame(width: 230)
            Divider()
            detail.padding(18)
        }
    }
}

/// Неизменные сведения о компьютере
struct TMSysInfo {
    var cpuName = ""
    var model = ""
    var coresText = ""

    init() {
        func str(_ n: String) -> String {
            var size = 0
            guard sysctlbyname(n, nil, &size, nil, 0) == 0, size > 0 else { return "" }
            var b = [CChar](repeating: 0, count: size)
            guard sysctlbyname(n, &b, &size, nil, 0) == 0 else { return "" }
            return String(cString: b)
        }
        func int(_ n: String) -> Int? {
            var v: Int32 = 0
            var size = MemoryLayout<Int32>.size
            return sysctlbyname(n, &v, &size, nil, 0) == 0 ? Int(v) : nil
        }
        cpuName = str("machdep.cpu.brand_string")
        model = str("hw.model")
        let phys = int("hw.physicalcpu") ?? 0
        let logical = int("hw.logicalcpu") ?? ProcessInfo.processInfo.activeProcessorCount
        if let p = int("hw.perflevel0.logicalcpu"), let e = int("hw.perflevel1.logicalcpu") {
            coresText = "\(p + e) (\(p) " + T("производительных") + " + \(e) " + T("энергоэффективных") + ")"
        } else if phys > 0 && phys != logical {
            coresText = "\(phys) / \(logical)"
        } else {
            coresText = "\(logical)"
        }
    }
}

// MARK: - Окно

final class TMWindowController: NSObject, NSWindowDelegate {
    static let shared = TMWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 620),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable],
                             backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 880, height: 460)
            w.contentView = NSHostingView(rootView: LangRefresh { TMRootView() })
            w.delegate = self
            if !w.setFrameUsingName("TMWindow") { w.center() }
            w.setFrameAutosaveName("TMWindow")
            window = w
            NotificationCenter.default.addObserver(self, selector: #selector(languageChanged), name: .languageChanged, object: nil)
        }
        window?.title = T("Диспетчер задач")
        TMSampler.shared.windowVisible = true
        TMSampler.shared.start()
        window?.level = UserDefaults.standard.bool(forKey: "tm.onTop") ? .floating : .normal
        NSApp.windows.compactMap { $0 as? PopupWindow }.forEach { $0.orderOut(nil) }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func languageChanged() {
        window?.title = T("Диспетчер задач")
    }

    func setOnTop(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: "tm.onTop")
        window?.level = on ? .floating : .normal
    }

    func windowWillClose(_ notification: Notification) {
        TMSampler.shared.windowVisible = false
        TMJournal.shared.save()
        if !TMExtras.keepRunning { TMSampler.shared.stop() }
    }
}
