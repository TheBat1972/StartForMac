import SwiftUI
import AppKit

// MARK: - Сведения о системе
//
// Одно окно со сведениями о компьютере: модель, серийный номер, процессор, память, диск, версия macOS,
// время работы и состояние батареи. «Скопировать для поддержки» кладёт всё это текстом в буфер обмена.
// Данные берутся у системы (system_profiler, sysctl); ничего не отправляется.

struct SysInfoRow: Identifiable {
    let id = UUID()
    let title: String
    let value: String
}

final class SysInfoModel: ObservableObject {
    @Published var rows: [SysInfoRow] = []
    @Published var loading = false

    func reload() {
        guard !loading else { return }
        loading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let r = SysInfoModel.collect()
            DispatchQueue.main.async { self.rows = r; self.loading = false }
        }
    }

    var asText: String { rows.map { $0.title + ": " + $0.value }.joined(separator: "\n") }

    private static func profiler(_ type: String) -> [String: Any] {
        let t = NetSpeed.capture("/usr/sbin/system_profiler", ["-json", type])
        guard let d = t.data(using: .utf8),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return [:] }
        return j
    }

    private static func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }

    static func collect() -> [SysInfoRow] {
        var out: [SysInfoRow] = []
        func add(_ title: String, _ value: String?) {
            if let v = value?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty { out.append(SysInfoRow(title: title, value: v)) }
        }

        let hw = profiler("SPHardwareDataType")
        let h = (hw["SPHardwareDataType"] as? [[String: Any]])?.first ?? [:]

        add(T("Компьютер"), Host.current().localizedName)
        let model = [h["machine_name"] as? String, h["machine_model"] as? String].compactMap { $0 }.joined(separator: ", ")
        add(T("Модель"), model)
        add(T("Серийный номер"), h["serial_number"] as? String)
        let chip = (h["chip_type"] as? String) ?? (h["cpu_type"] as? String) ?? ""
        add(T("Процессор"), chip + (chip.isEmpty ? "" : ", ") + "\(ProcessInfo.processInfo.processorCount) " + T("ядер"))
        let mem = (h["physical_memory"] as? String) ?? bytes(Int64(ProcessInfo.processInfo.physicalMemory))
        add(T("Память"), mem)

        let ver = NetSpeed.capture("/usr/bin/sw_vers", ["-productVersion"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let build = NetSpeed.capture("/usr/bin/sw_vers", ["-buildVersion"]).trimmingCharacters(in: .whitespacesAndNewlines)
        add("macOS", ver + (build.isEmpty ? "" : " (" + build + ")"))

        if let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
           let total = v.volumeTotalCapacity, let free = v.volumeAvailableCapacityForImportantUsage {
            add(T("Диск"), T("свободно") + " " + bytes(free) + " " + T("из") + " " + bytes(Int64(total)))
        }

        var tv = timeval()
        var size = MemoryLayout<timeval>.stride
        if sysctlbyname("kern.boottime", &tv, &size, nil, 0) == 0 {
            let sec = Int(Date().timeIntervalSince1970) - Int(tv.tv_sec)
            let d = sec / 86400, hr = sec % 86400 / 3600, mn = sec % 3600 / 60
            add(T("Время работы"), (d > 0 ? "\(d) " + T("дн.") + " " : "") + "\(hr) " + T("ч") + " \(mn) " + T("мин"))
        }

        add(T("Пользователь"), NSFullUserName() + " (" + NSUserName() + ")")

        let pw = profiler("SPPowerDataType")
        if let items = pw["SPPowerDataType"] as? [[String: Any]],
           let info = items.compactMap({ $0["sppower_battery_health_info"] as? [String: Any] }).first {
            if let c = info["sppower_battery_cycle_count"] { add(T("Батарея: циклы зарядки"), "\(c)") }
            if let s = info["sppower_battery_health"] { add(T("Батарея: состояние"), "\(s)") }
            if let m = info["sppower_battery_health_maximum_capacity"] { add(T("Батарея: ёмкость"), "\(m)") }
        }
        return out
    }
}

struct SysInfoView: View {
    @StateObject private var m = SysInfoModel()
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if m.rows.isEmpty {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text(T("Собираю сведения…")).foregroundColor(.secondary) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(m.rows) { r in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(r.title).foregroundColor(.secondary).frame(width: 170, alignment: .leading)
                                Text(r.value).textSelection(.enabled)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 6)
                            Divider()
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
            HStack {
                Button(T("Скопировать для поддержки")) {
                    copyToPasteboard(m.asText)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                }
                .disabled(m.rows.isEmpty)
                Button(T("Обновить")) { m.reload() }
                if copied { Text(T("Скопировано")).font(.caption).foregroundColor(.green) }
                Spacer()
            }
        }
        .padding(16)
        .onAppear { if m.rows.isEmpty { m.reload() } }
    }
}

final class SysInfoController: NSObject, NSWindowDelegate {
    static let shared = SysInfoController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 460, height: 360)
            w.contentView = NSHostingView(rootView: LangRefresh { SysInfoView() })
            w.delegate = self
            if !w.setFrameUsingName("SysInfoWindow") { w.center() }
            w.setFrameAutosaveName("SysInfoWindow")
            window = w
            NotificationCenter.default.addObserver(self, selector: #selector(languageChanged), name: .languageChanged, object: nil)
        }
        window?.title = T("Сведения о системе")
        NSApp.windows.compactMap { $0 as? PopupWindow }.forEach { $0.orderOut(nil) }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func languageChanged() { window?.title = T("Сведения о системе") }
}
