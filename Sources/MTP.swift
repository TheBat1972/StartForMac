// Работа с Android-телефонами по протоколу MTP напрямую через USB (IOUSBHost), без сторонних библиотек.
// Принцип тот же, что в OpenMTP: macOS сама захватывает телефон службой ptpcamera, поэтому перед открытием
// USB-интерфейса эта служба завершается, дальше «Пуск» сам говорит с телефоном по MTP.

import Foundation
import IOKit
import IOUSBHost

// MARK: - Журнал для отладки (~/Library/Logs/Pusk-MTP.log)

enum MTPLog {
    static let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Pusk-MTP.log")
    private static let q = DispatchQueue(label: "ru.local.StartMenu.mtplog")
    private static let df: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func log(_ s: String) {
        let line = df.string(from: Date()) + " " + s + "\n"
        q.async {
            let fm = FileManager.default
            if let a = try? fm.attributesOfItem(atPath: url.path), (a[.size] as? NSNumber)?.intValue ?? 0 > 1_000_000 {
                try? fm.removeItem(at: url)
            }
            if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
            if let h = try? FileHandle(forWritingTo: url) {
                _ = try? h.seekToEnd()
                try? h.write(contentsOf: Data(line.utf8))
                try? h.close()
            }
        }
    }
}

// MARK: - Модели

struct MTPDeviceInfo: Identifiable {
    let id: UInt64          // номер записи в реестре IOKit
    let name: String
}

struct MTPEntry {
    let handle: UInt32
    let storage: UInt32
    let name: String
    let isDir: Bool
    let size: Int64
    let modified: Date?
}

struct MTPStorageInfo {
    let id: UInt32
    let name: String
    let free: Int64
    let total: Int64
}

enum MTPError: LocalizedError {
    case usb(String)
    case response(UInt16)
    case noStorage
    case protocolError(String)

    var errorDescription: String? {
        switch self {
        case .usb(let s): return s
        case .noStorage:
            return T("Телефон не отдал хранилища. Разблокируйте экран и разрешите доступ к данным на телефоне.")
        case .protocolError(let s): return s
        case .response(let c):
            switch c {
            case 0x2002: return T("Телефон сообщил об общей ошибке")
            case 0x2005: return T("Телефон не поддерживает эту операцию")
            case 0x2009: return T("Объект не найден на телефоне")
            case 0x200C: return T("На телефоне нет места")
            case 0x200D: return T("Объект защищён от записи")
            case 0x200F: return T("Доступ запрещён")
            case 0x2019: return T("Телефон занят, повторите позже")
            default: return Tf("Ответ телефона: код %@", String(format: "0x%04X", c))
            }
        }
    }
}

// MARK: - Вспомогательное чтение и запись данных MTP (little-endian)

fileprivate extension Data {
    mutating func putU16(_ v: UInt16) { append(UInt8(v & 0xFF)); append(UInt8(v >> 8)) }
    mutating func putU32(_ v: UInt32) { for i in 0..<4 { append(UInt8((v >> UInt32(8 * i)) & 0xFF)) } }
    mutating func putU64(_ v: UInt64) { for i in 0..<8 { append(UInt8((v >> UInt64(8 * i)) & 0xFF)) } }
    /// Строка MTP: число символов (с нулевым), затем UTF-16LE
    mutating func putStr(_ s: String) {
        let units = Array(s.utf16.prefix(250))
        if units.isEmpty { append(0); return }
        append(UInt8(units.count + 1))
        for u in units { putU16(u) }
        putU16(0)
    }
    func mtpU16(_ o: Int) -> UInt16 { UInt16(self[startIndex + o]) | (UInt16(self[startIndex + o + 1]) << 8) }
    func mtpU32(_ o: Int) -> UInt32 {
        var v: UInt32 = 0
        for i in 0..<4 { v |= UInt32(self[startIndex + o + i]) << UInt32(8 * i) }
        return v
    }
}

fileprivate struct MTPReader {
    let d: Data
    var o = 0
    var ok = true
    init(_ data: Data) { d = Data(data) }

    mutating func u8() -> UInt8 {
        guard o + 1 <= d.count else { ok = false; return 0 }
        defer { o += 1 }
        return d[o]
    }
    mutating func u16() -> UInt16 {
        guard o + 2 <= d.count else { ok = false; o = d.count; return 0 }
        defer { o += 2 }
        return d.mtpU16(o)
    }
    mutating func u32() -> UInt32 {
        guard o + 4 <= d.count else { ok = false; o = d.count; return 0 }
        defer { o += 4 }
        return d.mtpU32(o)
    }
    mutating func u64() -> UInt64 {
        let lo = UInt64(u32()), hi = UInt64(u32())
        return lo | (hi << 32)
    }
    mutating func str() -> String {
        let n = Int(u8())
        if n == 0 { return "" }
        var units: [UInt16] = []
        for _ in 0..<n { units.append(u16()) }
        if units.last == 0 { units.removeLast() }
        return String(decoding: units, as: UTF16.self)
    }
    mutating func u32Array() -> [UInt32] {
        let n = Int(u32())
        guard ok, n >= 0, n < 5_000_000, o + 4 * n <= d.count else { ok = false; return [] }
        var r: [UInt32] = []
        r.reserveCapacity(n)
        for _ in 0..<n { r.append(u32()) }
        return r
    }
}

private let mtpDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyyMMdd'T'HHmmss"
    return f
}()

private func mtpParseDate(_ s: String) -> Date? {
    guard s.count >= 15 else { return nil }
    return mtpDateFormatter.date(from: String(s.prefix(15)))
}

// MARK: - Поиск телефонов

enum MTPScanner {
    private static func intProp(_ svc: io_registry_entry_t, _ key: String) -> Int? {
        (IORegistryEntryCreateCFProperty(svc, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber)?.intValue
    }

    private static func searchString(_ svc: io_registry_entry_t, _ key: String) -> String? {
        let opts = IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
        return IORegistryEntrySearchCFProperty(svc, kIOServicePlane, key as CFString, kCFAllocatorDefault, opts) as? String
    }

    private static func strProp(_ svc: io_registry_entry_t, _ key: String) -> String? {
        IORegistryEntryCreateCFProperty(svc, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
    }

    private static var lastSignature = ""

    /// Устройства с интерфейсом «Still Image / MTP» (так Android показывает режим «Передача файлов»)
    /// или с интерфейсом, в названии которого есть MTP (так делают некоторые производители)
    static func scan() -> [MTPDeviceInfo] {
        var result: [MTPDeviceInfo] = []
        var dump: [String] = []
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUSBHostInterface"), &it) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(it) }
        var svc = IOIteratorNext(it)
        while svc != 0 {
            let cls = intProp(svc, "bInterfaceClass") ?? -1
            let sub = intProp(svc, "bInterfaceSubClass") ?? -1
            let pro = intProp(svc, "bInterfaceProtocol") ?? -1
            let ifName = strProp(svc, "USB Interface Name") ?? ""
            dump.append("iface class=\(cls) sub=\(sub) proto=\(pro) name=\"\(ifName)\" product=\"\(searchString(svc, "USB Product Name") ?? "")\"")
            let prod = searchString(svc, "USB Product Name") ?? searchString(svc, "kUSBProductString") ?? ""
            // стандартный интерфейс MTP/PTP, либо «производительский» (255/255/0 — так MTP показывают Samsung и ридеры)
            let isMTP = (cls == 6 && sub == 1 && pro == 1)
                || ifName.uppercased().contains("MTP")
                || (cls == 255 && prod.uppercased().contains("MTP"))
                || (cls == 255 && sub == 255 && pro == 0)
            if isMTP {
                var rid: UInt64 = 0
                if IORegistryEntryGetRegistryEntryID(svc, &rid) == KERN_SUCCESS {
                    let product = searchString(svc, "USB Product Name") ?? searchString(svc, "kUSBProductString") ?? "Android"
                    let vendor = searchString(svc, "USB Vendor Name") ?? searchString(svc, "kUSBVendorString") ?? ""
                    let name = (vendor.isEmpty || product.lowercased().contains(vendor.lowercased())) ? product : vendor + " " + product
                    result.append(MTPDeviceInfo(id: rid, name: name))
                }
            }
            IOObjectRelease(svc)
            svc = IOIteratorNext(it)
        }
        let sig = dump.sorted().joined(separator: "\n") + "\nfound=\(result.count)"
        if sig != lastSignature {
            lastSignature = sig
            MTPLog.log("USB-интерфейсы:\n" + sig)
        }
        return result
    }
}

// MARK: - Сеанс MTP

final class MTPSession {
    let id: UInt64
    let name: String
    private let lock = NSRecursiveLock()
    private var iface: IOUSBHostInterface?
    private var seizedDevice: IOUSBHostDevice?
    private var inPipe: IOUSBHostPipe?
    private var outPipe: IOUSBHostPipe?
    private var maxIn = 512
    private var maxOut = 512
    private var tid: UInt32 = 0
    private(set) var dead = false

    private static var cache: [UInt64: MTPSession] = [:]
    private static let cacheLock = NSLock()

    static func session(for info: MTPDeviceInfo) throws -> MTPSession {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let s = cache[info.id], !s.dead { return s }
        let s = try MTPSession(info: info)
        cache[info.id] = s
        return s
    }

    deinit {
        iface?.destroy()
        seizedDevice?.destroy()
    }

    /// Интерфейс с нужным номером среди потомков устройства (после захвата записи реестра могут создаться заново)
    private static func findInterface(parent: io_service_t, number: Int) -> io_service_t {
        var it: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(parent, kIOServicePlane, &it) == KERN_SUCCESS else { return 0 }
        defer { IOObjectRelease(it) }
        var c = IOIteratorNext(it)
        while c != 0 {
            let n = (IORegistryEntryCreateCFProperty(c, "bInterfaceNumber" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? NSNumber)?.intValue
            if n == number { return c }
            IOObjectRelease(c)
            c = IOIteratorNext(it)
        }
        return 0
    }

    /// Службы macOS, которые держат телефон (как делает OpenMTP)
    private static func killCameraAgents() {
        // ptpcamerad (новые macOS) и ptpcamera (старые): ищем по части имени; launchd тут же запускает службу заново,
        // поэтому вызывается перед каждой попыткой
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        p.arguments = ["-9", "-f", "ptpcamera|Android File Transfer"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
    }

    /// Адреса bulk-конечных точек и размеры пакетов: разбираем дескриптор конфигурации
    private static func endpoints(_ iface: IOUSBHostInterface) -> (bulkIn: Int, bulkOut: Int, maxIn: Int, maxOut: Int)? {
        let cfg = UnsafeRawPointer(iface.configurationDescriptor)
        let ifd = UnsafeRawPointer(iface.interfaceDescriptor)
        func b(_ o: Int) -> Int { Int(cfg.load(fromByteOffset: o, as: UInt8.self)) }
        let total = b(2) | (b(3) << 8)
        let ifnum = Int(ifd.load(fromByteOffset: 2, as: UInt8.self))
        var off = 0
        var inIface = false
        var bi = -1, bo = -1, mi = 512, mo = 512
        while off + 2 <= total {
            let len = b(off), type = b(off + 1)
            if len < 2 { break }
            if type == 4 {
                inIface = (b(off + 2) == ifnum && b(off + 3) == 0)
            } else if type == 5, inIface, len >= 7 {
                let addr = b(off + 2), attr = b(off + 3)
                let mps = (b(off + 4) | (b(off + 5) << 8)) & 0x7FF
                if attr & 3 == 2 {
                    if addr & 0x80 != 0 { bi = addr; mi = max(mps, 64) } else { bo = addr; mo = max(mps, 64) }
                }
            }
            off += len
        }
        guard bi >= 0, bo >= 0 else { return nil }
        return (bi, bo, mi, mo)
    }

    private init(info: MTPDeviceInfo) throws {
        id = info.id
        name = info.name
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(info.id))
        guard svc != 0 else { throw MTPError.usb(T("Устройство не найдено")) }
        defer { IOObjectRelease(svc) }

        var opened: IOUSBHostInterface?
        var lastError: Error?
        var target = svc
        var retargeted: io_service_t = 0
        defer { if retargeted != 0 { IOObjectRelease(retargeted) } }
        var parentSvc: io_service_t = 0
        _ = IORegistryEntryGetParentEntry(svc, kIOServicePlane, &parentSvc)
        defer { if parentSvc != 0 { IOObjectRelease(parentSvc) } }
        let ifNum = (IORegistryEntryCreateCFProperty(svc, "bInterfaceNumber" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? NSNumber)?.intValue ?? 0
        var seized: IOUSBHostDevice?

        for attempt in 0..<10 {
            MTPSession.killCameraAgents()
            // после нескольких неудач захватываем устройство целиком: прочие владельцы отключаются
            if attempt >= 4, seized == nil, parentSvc != 0 {
                seized = try? IOUSBHostDevice(__ioService: parentSvc, options: .deviceSeize, queue: nil, interestHandler: nil)
                MTPLog.log("захват устройства: " + (seized != nil ? "удался" : "не удался"))
                if seized != nil {
                    let again = MTPSession.findInterface(parent: parentSvc, number: ifNum)
                    if again != 0 { retargeted = again; target = again }
                }
            }
            let opts: IOUSBHostObjectInitOptions = (attempt == 2 || attempt == 3) ? .deviceSeize : []
            MTPLog.log("открываю интерфейс (попытка \(attempt + 1)), параметры: \(opts.rawValue)")
            do {
                opened = try IOUSBHostInterface(__ioService: target, options: opts, queue: nil, interestHandler: nil)
                break
            } catch {
                lastError = error
                MTPLog.log("не открылся: \(error)")
                Thread.sleep(forTimeInterval: 0.25)
            }
        }
        seizedDevice = seized
        guard let ifc = opened else {
            throw MTPError.usb(T("Не удалось открыть телефон по USB. Закройте Android File Transfer, OpenMTP и «Захват изображений», переподключите кабель.")
                               + (lastError.map { " (" + $0.localizedDescription + ")" } ?? ""))
        }
        guard let ep = MTPSession.endpoints(ifc) else {
            MTPLog.log("каналы bulk не найдены")
            ifc.destroy()
            throw MTPError.usb(T("У телефона не найдены каналы передачи данных"))
        }
        do {
            inPipe = try ifc.copyPipe(withAddress: ep.bulkIn)
            outPipe = try ifc.copyPipe(withAddress: ep.bulkOut)
        } catch {
            ifc.destroy()
            throw MTPError.usb(error.localizedDescription)
        }
        maxIn = ep.maxIn
        maxOut = ep.maxOut
        MTPLog.log("каналы: in=0x\(String(ep.bulkIn, radix: 16)) (пакет \(ep.maxIn)), out=0x\(String(ep.bulkOut, radix: 16)) (пакет \(ep.maxOut))")
        iface = ifc

        do {
            try run(0x1002, [1])                       // OpenSession
        } catch MTPError.response(0x201E) {             // сеанс уже открыт
            _ = try? run(0x1003)
            try run(0x1002, [1])
        }
    }

    // MARK: транспорт

    private func fail(_ error: Error, _ pipe: IOUSBHostPipe?) -> MTPError {
        MTPLog.log("ошибка USB: \(error)")
        try? pipe?.clearStall()
        dead = true
        return MTPError.usb(error.localizedDescription)
    }

    /// Синхронная передача по bulk-каналу: ставим запрос в очередь и ждём завершения
    private func io(_ pipe: IOUSBHostPipe, _ data: NSMutableData?) throws -> Int {
        let sem = DispatchSemaphore(value: 0)
        var status: IOReturn = kIOReturnSuccess
        var count = 0
        try pipe.enqueueIORequest(with: data, completionTimeout: 30) { st, n in
            status = st
            count = n
            sem.signal()
        }
        sem.wait()
        if status != kIOReturnSuccess {
            throw MTPError.usb(Tf("Ошибка USB: %@", String(format: "0x%08X", UInt32(bitPattern: status))))
        }
        return count
    }

    private func writeBulk(_ d: Data) throws {
        guard let pipe = outPipe else { throw MTPError.usb(T("Устройство не подключено")) }
        do { _ = try io(pipe, d.isEmpty ? nil : NSMutableData(data: d)) }     // nil — пустой пакет
        catch { throw fail(error, pipe) }
    }

    private func readBulk(_ size: Int) throws -> Data {
        guard let pipe = inPipe, let m = NSMutableData(length: size) else { throw MTPError.usb(T("Устройство не подключено")) }
        var n = 0
        do { n = try io(pipe, m) }
        catch { throw fail(error, pipe) }
        return Data(bytes: m.bytes, count: n)
    }

    private func header(len: Int, type: UInt16, code: UInt16, tid: UInt32) -> Data {
        var d = Data()
        d.putU32(UInt32(truncatingIfNeeded: len))
        d.putU16(type)
        d.putU16(code)
        d.putU32(tid)
        return d
    }

    /// Одна транзакция MTP: команда, при необходимости данные туда, данные обратно, ответ
    @discardableResult
    private func run(_ op: UInt16, _ params: [UInt32] = [], sendSize: Int? = nil,
                     sendChunk: ((Int) throws -> Data)? = nil,
                     sink: ((Data) throws -> Void)? = nil) throws -> (code: UInt16, params: [UInt32]) {
        lock.lock()
        defer { lock.unlock() }
        tid &+= 1
        let t = tid

        var cmd = header(len: 12 + 4 * params.count, type: 1, code: op, tid: t)
        for p in params { cmd.putU32(p) }
        try writeBulk(cmd)

        if let size = sendSize, let provider = sendChunk {
            let total = 12 + size
            let chunkMax = 524_288
            var sent = 0
            var first = true
            while true {
                var buf = Data()
                if first { buf = header(len: total, type: 2, code: op, tid: t); first = false }
                buf.append(try provider(chunkMax - buf.count))
                if buf.isEmpty { break }
                try writeBulk(buf)
                sent += buf.count
                if sent >= total { break }
            }
            if sent > 0, sent % maxOut == 0 { try writeBulk(Data()) }   // завершающий пустой пакет
        }

        var zeroReads = 0
        while true {
            let first = try readBulk(maxIn)
            if first.isEmpty {
                zeroReads += 1
                if zeroReads > 4 { throw MTPError.protocolError(T("Телефон не ответил")) }
                continue
            }
            guard first.count >= 12 else { throw MTPError.protocolError(T("Неверный ответ телефона")) }
            let len = Int(first.mtpU32(0))
            let type = first.mtpU16(4)
            let code = first.mtpU16(6)

            if type == 2 {                                   // данные
                try sink?(first.subdata(in: first.startIndex + 12..<first.endIndex))
                var got = first.count
                if len == 0xFFFF_FFFF {
                    while true {
                        let chunk = try readBulk(262_144)
                        if chunk.isEmpty { break }
                        try sink?(chunk)
                        if chunk.count < 262_144 { break }
                    }
                } else {
                    while got < len {
                        let remaining = len - got
                        var req = min(remaining, 262_144)
                        if req == remaining, req % maxIn != 0 { req = ((req + maxIn - 1) / maxIn) * maxIn }
                        let chunk = try readBulk(req)
                        if chunk.isEmpty { throw MTPError.protocolError(T("Передача данных прервана")) }
                        got += chunk.count
                        try sink?(chunk)
                    }
                }
                continue
            }
            if type == 3 {                                   // ответ
                var ps: [UInt32] = []
                let n = (min(len, first.count) - 12) / 4
                if n > 0 { for i in 0..<n { ps.append(first.mtpU32(12 + 4 * i)) } }
                if op != 0x1008 || code != 0x2001 { MTPLog.log(String(format: "op 0x%04X %@ -> 0x%04X %@", op, params.map { String($0, radix: 16) }.joined(separator: ","), code, ps.map { String($0, radix: 16) }.joined(separator: ","))) }
                if code != 0x2001 { throw MTPError.response(code) }
                return (code, ps)
            }
            // события и прочее пропускаем
        }
    }

    // MARK: операции

    func storages() throws -> [MTPStorageInfo] {
        lock.lock(); defer { lock.unlock() }
        var d = Data()
        try run(0x1004, sink: { d.append($0) })
        var r = MTPReader(d)
        let ids = r.u32Array()
        var out: [MTPStorageInfo] = []
        for sid in ids {
            if let s = try? storageInfo(sid) { out.append(s) }
        }
        if out.isEmpty { throw MTPError.noStorage }
        return out
    }

    func storageInfo(_ sid: UInt32) throws -> MTPStorageInfo {
        lock.lock(); defer { lock.unlock() }
        var d = Data()
        try run(0x1005, [sid], sink: { d.append($0) })
        var r = MTPReader(d)
        _ = r.u16(); _ = r.u16(); _ = r.u16()
        let total = r.u64()
        let free = r.u64()
        _ = r.u32()
        let desc = r.str()
        let label = r.str()
        var nm = desc.isEmpty ? label : desc
        if nm.isEmpty { nm = Tf("Хранилище %@", "\(sid)") }
        return MTPStorageInfo(id: sid, name: nm, free: Int64(truncatingIfNeeded: free), total: Int64(truncatingIfNeeded: total))
    }

    func list(storage: UInt32, parent: UInt32) throws -> [MTPEntry] {
        lock.lock(); defer { lock.unlock() }
        var d = Data()
        try run(0x1007, [storage, 0, parent], sink: { d.append($0) })
        var r = MTPReader(d)
        let handles = r.u32Array()
        var out: [MTPEntry] = []
        for h in handles {
            var od = Data()
            do { try run(0x1008, [h], sink: { od.append($0) }) } catch MTPError.response { continue }
            var o = MTPReader(od)
            _ = o.u32()                         // StorageID
            let format = o.u16()
            _ = o.u16()                         // защита
            let size = o.u32()
            _ = o.u16(); _ = o.u32(); _ = o.u32(); _ = o.u32()   // миниатюра
            _ = o.u32(); _ = o.u32(); _ = o.u32()                // размеры картинки
            _ = o.u32()                         // родитель
            _ = o.u16(); _ = o.u32(); _ = o.u32()
            let fname = o.str()
            let created = o.str()
            let modified = o.str()
            guard o.ok, !fname.isEmpty else { continue }
            out.append(MTPEntry(handle: h, storage: storage, name: fname, isDir: format == 0x3001,
                                size: Int64(size), modified: mtpParseDate(modified) ?? mtpParseDate(created)))
        }
        return out
    }

    func download(handle: UInt32, to url: URL) throws {
        lock.lock(); defer { lock.unlock() }
        let fm = FileManager.default
        guard fm.createFile(atPath: url.path, contents: nil) else { throw MTPError.usb(T("Не удалось создать файл") + ": " + url.lastPathComponent) }
        let fh = try FileHandle(forWritingTo: url)
        do {
            try run(0x1009, [handle], sink: { try fh.write(contentsOf: $0) })
            try fh.close()
        } catch {
            try? fh.close()
            try? fm.removeItem(at: url)
            throw error
        }
    }

    private func objectInfo(name: String, format: UInt16, size: UInt32, assoc: UInt16, date: Date) -> Data {
        var d = Data()
        d.putU32(0)                 // хранилище (задаётся командой)
        d.putU16(format)
        d.putU16(0)                 // защита
        d.putU32(size)
        d.putU16(0); d.putU32(0); d.putU32(0); d.putU32(0)      // миниатюра
        d.putU32(0); d.putU32(0); d.putU32(0)                   // картинка
        d.putU32(0)                 // родитель
        d.putU16(assoc)
        d.putU32(0); d.putU32(0)
        d.putStr(name)
        let ds = mtpDateFormatter.string(from: date)
        d.putStr(ds)
        d.putStr(ds)
        d.putStr("")
        return d
    }

    private func oneShot(_ data: Data) -> (Int) throws -> Data {
        var given = false
        return { _ in
            if given { return Data() }
            given = true
            return data
        }
    }

    @discardableResult
    func upload(file url: URL, storage: UInt32, parent: UInt32) throws -> UInt32 {
        lock.lock(); defer { lock.unlock() }
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        guard size < 0xFFFF_FF00 else { throw MTPError.protocolError(T("Файл больше 4 ГБ: пока не поддерживается") + ": " + url.lastPathComponent) }
        let date = (attrs[.modificationDate] as? Date) ?? Date()
        let p: UInt32 = parent == 0xFFFF_FFFF ? 0 : parent
        let info = objectInfo(name: url.lastPathComponent, format: 0x3000, size: UInt32(size), assoc: 0, date: date)
        let r = try run(0x100C, [storage, p], sendSize: info.count, sendChunk: oneShot(info))
        let handle = r.params.count >= 3 ? r.params[2] : 0
        let fh = try FileHandle(forReadingFrom: url)
        defer { try? fh.close() }
        do {
            try run(0x100D, [], sendSize: Int(size), sendChunk: { max in try fh.read(upToCount: max) ?? Data() })
        } catch {
            if handle != 0 { _ = try? run(0x100B, [handle, 0]) }
            throw error
        }
        return handle
    }

    func makeFolder(name: String, storage: UInt32, parent: UInt32) throws -> UInt32 {
        lock.lock(); defer { lock.unlock() }
        let p: UInt32 = parent == 0xFFFF_FFFF ? 0 : parent
        let info = objectInfo(name: name, format: 0x3001, size: 0, assoc: 1, date: Date())
        let r = try run(0x100C, [storage, p], sendSize: info.count, sendChunk: oneShot(info))
        return r.params.count >= 3 ? r.params[2] : 0
    }

    func delete(handle: UInt32) throws {
        lock.lock(); defer { lock.unlock() }
        try run(0x100B, [handle, 0])
    }

    func deleteRecursive(_ e: MTPEntry) throws {
        lock.lock(); defer { lock.unlock() }
        if e.isDir {
            for c in try list(storage: e.storage, parent: e.handle) { try deleteRecursive(c) }
        }
        try delete(handle: e.handle)
    }

    func rename(handle: UInt32, to newName: String) throws {
        lock.lock(); defer { lock.unlock() }
        var d = Data()
        d.putStr(newName)
        try run(0x9804, [handle, 0xDC07], sendSize: d.count, sendChunk: oneShot(d))
    }
}
