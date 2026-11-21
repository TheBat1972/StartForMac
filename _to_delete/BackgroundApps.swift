import Cocoa
import SwiftUI
import Darwin

// MARK: - Диспетчер задач: вкладка «Фоновые приложения»
// Программы без окон: значки в строке меню, агенты и фоновые службы с оболочкой .app.

struct TMBackgroundView: View {
    @ObservedObject var s: TMSampler
    @ObservedObject private var st = TMStartupStore.shared
    @State private var selected: String? = nil
    @State private var sortKey = "name"
    @State private var asc = true
    @State private var query = ""
    @State private var showSystem = false

    struct BG: Identifiable {
        let id: String              // путь к .app
        var name: String
        var kind: String
        var row: TMRow
        var system: Bool
        var autostart: Bool
    }

    private func items() -> [BG] {
        var rows: [String: TMRow] = [:]
        for r in s.apps + s.background where rows[r.id] == nil { rows[r.id] = r }
        var seen = Set<String>()
        var out: [BG] = []
        for a in NSWorkspace.shared.runningApplications where a.activationPolicy != .regular && !a.isTerminated {
            guard let url = a.bundleURL, a.processIdentifier != getpid() else { continue }
            let id = url.path
            guard !seen.contains(id) else { continue }
            seen.insert(id)
            var row = rows[id] ?? TMRow(id: id, name: a.localizedName ?? url.deletingPathExtension().lastPathComponent,
                                        pids: [a.processIdentifier], cpu: 0, mem: 0, isApp: true, icon: nil, path: id)
            if row.icon == nil { row.icon = a.icon }
            let sys = id.hasPrefix("/System/") || id.hasPrefix("/usr/") || id.hasPrefix("/Library/Apple/")
            let auto = st.items.contains { $0.kind == .login && $0.enabled && $0.path == id }
            out.append(BG(id: id, name: row.name,
                          kind: a.activationPolicy == .accessory ? T("Значок в строке меню") : T("Фоновая служба"),
                          row: row, system: sys, autostart: auto))
        }
        let f = out.filter { (showSystem || !$0.system) && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)) }
        return f.sorted { x, y in
            switch sortKey {
            case "cpu": return asc ? x.row.cpu < y.row.cpu : x.row.cpu > y.row.cpu
            case "mem": return asc ? x.row.mem < y.row.mem : x.row.mem > y.row.mem
            default:
                let r = x.name.localizedCaseInsensitiveCompare(y.name)
                return asc ? r == .orderedAscending : r == .orderedDescending
            }
        }
    }

    private func header(_ title: String, _ key: String, width: CGFloat?, leading: Bool) -> some View {
        Button {
            if sortKey == key { asc.toggle() } else { sortKey = key; asc = key == "name" }
        } label: {
            HStack(spacing: 3) {
                Text(title)
                if sortKey == key { Image(systemName: asc ? "chevron.up" : "chevron.down").font(.system(size: 8, weight: .bold)) }
            }
            .font(.caption).foregroundColor(.secondary)
            .frame(maxWidth: width ?? .infinity, alignment: leading ? .leading : .trailing)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func heat(_ v: Double) -> Color { Color.orange.opacity(min(0.55, max(0, v))) }

    private func restart(_ b: BG) {
        s.end(b.row, force: false)
        let url = URL(fileURLWithPath: b.id)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        }
    }

    private func toggleAutostart(_ b: BG) {
        if b.autostart {
            if let it = st.items.first(where: { $0.kind == .login && $0.path == b.id }) { st.remove(it) }
        } else {
            st.add(URL(fileURLWithPath: b.id))
        }
    }

    private func rowView(_ b: BG) -> some View {
        let sel = selected == b.id
        return HStack(spacing: 0) {
            HStack(spacing: 8) {
                if let i = b.row.icon {
                    Image(nsImage: i).resizable().frame(width: 16, height: 16)
                } else {
                    Image(systemName: "app").frame(width: 16, height: 16).foregroundColor(.secondary)
                }
                Text(b.name).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(b.kind).foregroundColor(.secondary).lineLimit(1)
                .frame(width: 150, alignment: .leading)
            Text(String(format: "%.1f%%", b.row.cpu))
                .frame(width: 70, alignment: .trailing).padding(.vertical, 5).padding(.trailing, 6)
                .background(heat(b.row.cpu / 40))
            Text(tmBytes(Double(b.row.mem)))
                .frame(width: 100, alignment: .trailing).padding(.vertical, 5).padding(.trailing, 6)
                .background(heat(Double(b.row.mem) / 3e9))
            Text(b.autostart ? T("Да") : T("Нет"))
                .foregroundColor(b.autostart ? .primary : .secondary)
                .frame(width: 90, alignment: .trailing).padding(.trailing, 6)
        }
        .font(.system(size: 13))
        .padding(.leading, 12).padding(.trailing, 6)
        .background(sel ? Color.accentColor.opacity(0.28) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { selected = b.id }
        .contextMenu {
            Button(T("Завершить")) { s.end(b.row, force: false) }
            Button(T("Принудительно завершить")) { s.end(b.row, force: true) }
            Button(T("Перезапустить")) { restart(b) }
            Divider()
            Button(b.autostart ? T("Убрать из автозагрузки") : T("Добавить в автозагрузку")) { toggleAutostart(b) }
            Button(T("Показать в Finder")) { s.reveal(b.row) }
        }
    }

    var body: some View {
        let list = items()
        let cur = list.first { $0.id == selected }
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                header(T("Имя"), "name", width: nil, leading: true)
                Text(T("Тип")).font(.caption).foregroundColor(.secondary).frame(width: 150, alignment: .leading)
                header(T("ЦП"), "cpu", width: 76, leading: false)
                header(T("Память"), "mem", width: 106, leading: false)
                Text(T("Автозагрузка")).font(.caption).foregroundColor(.secondary).frame(width: 96, alignment: .trailing)
            }
            .padding(.leading, 12).padding(.trailing, 6).padding(.vertical, 6)
            Divider()
            if list.isEmpty {
                Text(T("Нет фоновых приложений"))
                    .foregroundColor(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) { ForEach(list) { rowView($0) } }
                        .padding(.bottom, 8)
                }
            }
            Divider()
            HStack(spacing: 10) {
                TextField(T("Поиск"), text: $query).textFieldStyle(.roundedBorder).frame(width: 180)
                Toggle(T("Системные"), isOn: $showSystem)
                Spacer()
                Button(T("Перезапустить")) { if let c = cur { restart(c) } }.disabled(cur == nil)
                if let c = cur, c.autostart {
                    Button(T("Убрать из автозагрузки")) { toggleAutostart(c) }
                } else {
                    Button(T("Добавить в автозагрузку")) { if let c = cur { toggleAutostart(c) } }.disabled(cur == nil)
                }
                Button(T("Завершить")) { if let c = cur { s.end(c.row, force: false) } }.disabled(cur == nil)
                Button(T("Принудительно")) { if let c = cur { s.end(c.row, force: true) } }.disabled(cur == nil)
            }
            .padding(10)
        }
        .onAppear { st.reload() }
    }
}
