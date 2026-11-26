import SwiftUI
import AppKit

// MARK: - Сведения о внешнем диске: формат, разделы, подключение, производитель

struct DiskInfoSection: Identifiable {
    let id = UUID()
    let title: String
    let rows: [(String, String)]
}

extension FormatModel {
    /// Понятное название файловой системы раздела; если том не читается, показываем тип раздела из таблицы
    static func fsName(_ info: [String: Any], content: String) -> String {
        for k in ["FilesystemUserVisibleName", "FilesystemName"] {
            if let v = info[k] as? String, !v.isEmpty { return v }
        }
        switch content {
        case "DOS_FAT_32": return "FAT32"
        case "DOS_FAT_16": return "FAT16"
        case "DOS_FAT_12": return "FAT12"
        case "Windows_NTFS": return "NTFS / exFAT"
        case "Apple_HFS": return "Mac OS Extended (HFS+)"
        case "Apple_APFS": return "APFS"
        case "EFI": return "EFI"
        default: return content
        }
    }

    private static func bytesText(_ n: Int64) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        let exact = f.string(from: NSNumber(value: n)) ?? "\(n)"
        return ByteCountFormatter.string(fromByteCount: n, countStyle: .file) + " (" + exact + " " + T("байт") + ")"
    }

    private static func yesNo(_ v: Any?) -> String? {
        guard let b = v as? Bool else { return nil }
        return b ? T("да") : T("нет")
    }

    private static func str(_ d: [String: Any], _ k: String) -> String? {
        if let v = d[k] as? String, !v.isEmpty { return v }
        return nil
    }

    private static func int(_ d: [String: Any], _ k: String) -> Int64? {
        (d[k] as? NSNumber)?.int64Value
    }

    /// Узел системного профиля USB, у которого среди носителей есть нужный диск
    private static func findUSB(_ node: Any, _ disk: String) -> [String: Any]? {
        if let arr = node as? [Any] {
            for x in arr { if let r = findUSB(x, disk) { return r } }
            return nil
        }
        guard let d = node as? [String: Any] else { return nil }
        if let media = d["Media"] as? [[String: Any]],
           media.contains(where: { ($0["bsd_name"] as? String).map { wholeDisk($0) == disk } ?? false }) { return d }
        for (_, v) in d where v is [Any] || v is [String: Any] {
            if let r = findUSB(v, disk) { return r }
        }
        return nil
    }

    private static func usbDevice(for disk: String) -> [String: Any]? {
        for type in ["SPUSBDataType", "SPUSBHostDataType"] {
            let (code, data) = runTool("/usr/sbin/system_profiler", [type, "-json"], mergeErrors: false, timeout: 40)
            if code == 0, let root = try? JSONSerialization.jsonObject(with: data), let r = findUSB(root, disk) { return r }
        }
        return nil
    }

    static func collectInfo(_ disk: String) -> [DiskInfoSection] {
        var out: [DiskInfoSection] = []
        guard let info = plist(["info", "-plist", disk]) else { return out }
        let top = (plist(["list", "-plist", disk])?["AllDisksAndPartitions"] as? [[String: Any]])?.first

        // — устройство —
        var rows: [(String, String)] = []
        func add(_ k: String, _ v: String?) { if let v = v, !v.isEmpty { rows.append((k, v)) } }
        add(T("Модель"), str(info, "MediaName"))
        if let n = int(info, "TotalSize") ?? int(info, "Size") { add(T("Объём"), bytesText(n)) }
        add(T("Идентификатор"), disk + "  (/dev/" + disk + ")")
        add(T("Интерфейс"), str(info, "BusProtocol"))
        let content = (top?["Content"] as? String) ?? str(info, "Content") ?? ""
        switch content {
        case "GUID_partition_scheme": add(T("Схема разделов"), "GPT")
        case "FDisk_partition_scheme": add(T("Схема разделов"), "MBR")
        case "Apple_partition_scheme": add(T("Схема разделов"), "APM")
        case "": break
        default: add(T("Схема разделов"), T("Нет (весь диск — один том)") + ", " + fsName(info, content: content))
        }
        add(T("Твердотельный (SSD)"), yesNo(info["SolidState"]))
        add(T("Сменный носитель"), yesNo(info["RemovableMediaOrExternalDevice"]) ?? yesNo(info["Removable"]))
        add(T("Можно извлечь"), yesNo(info["Ejectable"]))
        add(T("Запись разрешена"), yesNo(info["WritableMedia"]) ?? yesNo(info["Writable"]))
        if let b = int(info, "DeviceBlockSize") { add(T("Размер сектора"), "\(b) " + T("байт")) }
        add(T("Состояние SMART"), str(info, "SMARTStatus"))
        add(T("Устройство в системе"), str(info, "DeviceTreePath") ?? str(info, "IORegistryEntryName"))
        out.append(DiskInfoSection(title: T("Устройство"), rows: rows))

        // — подключение и производитель (системный профиль USB) —
        rows = []
        if let u = usbDevice(for: disk) {
            add(T("Название USB-устройства"), str(u, "_name"))
            add(T("Производитель"), str(u, "manufacturer"))
            add(T("Серийный номер"), str(u, "serial_num"))
            add(T("Код производителя (VID)"), str(u, "vendor_id"))
            add(T("Код устройства (PID)"), str(u, "product_id"))
            add(T("Версия устройства"), str(u, "bcd_device"))
            if let sp = str(u, "device_speed") {
                if let c = SpeedModel.classify(sp) {
                    let rate = c.1 >= 1000 ? "\(Int(c.1 / 1000)) " + T("Гбит/с") : "\(Int(c.1)) " + T("Мбит/с")
                    add(T("Скорость подключения"), c.0 + " · " + rate)
                } else { add(T("Скорость подключения"), sp) }
            }
            add(T("Потребление"), str(u, "bus_power").map { $0 + " " + T("мА") })
        }
        if !rows.isEmpty { out.append(DiskInfoSection(title: T("Подключение"), rows: rows)) }

        // — разделы —
        for p in top?["Partitions"] as? [[String: Any]] ?? [] {
            guard let pid = p["DeviceIdentifier"] as? String else { continue }
            let pinfo = plist(["info", "-plist", pid]) ?? [:]
            let pcontent = (p["Content"] as? String) ?? str(pinfo, "Content") ?? ""
            rows = []
            add(T("Файловая система"), fsName(pinfo, content: pcontent))
            add(T("Тип раздела"), pcontent)
            add(T("Имя тома"), str(pinfo, "VolumeName") ?? (p["VolumeName"] as? String))
            let mp = (p["MountPoint"] as? String) ?? str(pinfo, "MountPoint") ?? ""
            add(T("Смонтирован"), mp.isEmpty ? T("нет") : mp)
            if let n = (p["Size"] as? NSNumber)?.int64Value ?? int(pinfo, "TotalSize") ?? int(pinfo, "Size") {
                add(T("Размер"), bytesText(n))
                if !mp.isEmpty {
                    var st = statfs()
                    if statfs(mp, &st) == 0 {
                        let free = Int64(st.f_bavail) * Int64(st.f_bsize)
                        let total = Int64(st.f_blocks) * Int64(st.f_bsize)
                        add(T("Свободно"), ByteCountFormatter.string(fromByteCount: free, countStyle: .file))
                        add(T("Занято"), ByteCountFormatter.string(fromByteCount: max(0, total - free), countStyle: .file))
                    }
                }
            }
            if let b = int(pinfo, "VolumeAllocationBlockSize") { add(T("Размер кластера"), "\(b) " + T("байт")) }
            add(T("Запись в том"), yesNo(pinfo["WritableVolume"]) ?? yesNo(pinfo["Writable"]))
            add(T("Журналирование"), yesNo(pinfo["Journaled"]))
            add(T("Шифрование"), yesNo(pinfo["Encryption"]) ?? yesNo(pinfo["FileVault"]))
            add(T("UUID тома"), str(pinfo, "VolumeUUID"))
            let title = pid + (str(pinfo, "VolumeName").map { " — " + $0 } ?? "")
            out.append(DiskInfoSection(title: title, rows: rows))
        }
        return out
    }

    func loadInfo() {
        guard let id = selectedID else { info = []; infoLoading = false; return }
        infoLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let s = FormatModel.collectInfo(id)
            DispatchQueue.main.async {
                guard self.selectedID == id else { return }
                self.info = s
                self.infoLoading = false
            }
        }
    }

    var infoText: String {
        info.map { sec in
            sec.title + "\n" + sec.rows.map { "  " + $0.0 + ": " + $0.1 }.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }
}

struct DiskInfoPanel: View {
    @ObservedObject var model: FormatModel
    let store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.selected == nil {
                Text(T("Выберите диск, чтобы увидеть сведения")).font(.callout).foregroundColor(.secondary)
                Spacer(minLength: 0)
            } else if model.infoLoading && model.info.isEmpty {
                Text(T("Собираю сведения…")).font(.callout).foregroundColor(.secondary)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(model.info) { sec in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(sec.title).font(.subheadline.bold())
                                ForEach(Array(sec.rows.enumerated()), id: \.offset) { _, r in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text(r.0).font(.caption).foregroundColor(.secondary)
                                            .frame(width: 190, alignment: .leading)
                                        Text(r.1).font(.caption).fixedSize(horizontal: false, vertical: true)
                                        Spacer(minLength: 0)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack {
                if model.infoLoading && !model.info.isEmpty { Text(T("Обновляю…")).font(.caption).foregroundColor(.secondary) }
                Spacer()
                Button(T("Закрыть")) { store.fmt = nil }
                Button(T("Обновить")) { model.loadInfo() }.disabled(model.selected == nil)
                Button(T("Скопировать")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.infoText, forType: .string)
                }.disabled(model.info.isEmpty)
            }
        }
    }
}
