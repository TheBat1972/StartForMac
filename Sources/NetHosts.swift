import SwiftUI
import AppKit

// MARK: - Файл hosts (вкладка «Сетевых инструментов»)
//
// Показывает /etc/hosts построчно. Строки, которые «гасят» имена (адрес 0.0.0.0 или 127.x для имени, кроме localhost),
// выделены красным; у них есть кнопка «Убрать». Убирает строку системная команда с запросом пароля администратора
// (стандартное окно macOS), перед этим копия файла кладётся в /etc/hosts.startbak, а после — сбрасывается кэш DNS.

struct HostsLine: Identifiable {
    let id: Int
    let text: String
    var isComment: Bool { text.trimmingCharacters(in: .whitespaces).hasPrefix("#") || text.trimmingCharacters(in: .whitespaces).isEmpty }
    var fields: [String] {
        text.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map {
            $0.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        } ?? []
    }
    /// Блокирующая запись: имя направлено на 0.0.0.0 или на локальный адрес, и это не обычные служебные имена
    var blocks: Bool {
        guard !isComment, fields.count >= 2 else { return false }
        let ip = fields[0]
        guard ip == "0.0.0.0" || ip.hasPrefix("127.") || ip == "::1" || ip == "::" else { return false }
        let names = fields.dropFirst().map { $0.lowercased() }
        return names.contains { !["localhost", "broadcasthost", "localhost.localdomain", "ip6-localhost", "ip6-loopback"].contains($0) }
    }
}

final class HostsModel: ObservableObject {
    @Published var lines: [HostsLine] = []
    @Published var message = ""
    @Published var messageColor: Color = .secondary

    init() { reload() }

    func reload() {
        let t = (try? String(contentsOfFile: "/etc/hosts", encoding: .utf8)) ?? ""
        var parts = t.components(separatedBy: "\n")
        if parts.last == "" { parts.removeLast() }
        lines = parts.enumerated().map { HostsLine(id: $0.offset, text: $0.element) }
    }

    /// Убирает строку с запросом пароля администратора; перед этим делает копию, после — сбрасывает кэш DNS
    func remove(_ line: HostsLine) {
        let a = NSAlert()
        a.messageText = T("Убрать строку из файла hosts?")
        a.informativeText = line.text + "\n\n" + T("Копия файла сохранится как /etc/hosts.startbak. macOS попросит пароль администратора.")
        a.addButton(withTitle: T("Убрать"))
        a.addButton(withTitle: T("Отмена"))
        NSApp.activate(ignoringOtherApps: true)
        guard a.runModal() == .alertFirstButtonReturn else { return }
        var all = lines.map { $0.text }
        guard all.indices.contains(line.id), all[line.id] == line.text else { reload(); return }
        all.remove(at: line.id)
        let tmp = NSTemporaryDirectory() + "startformac-hosts.new"
        do { try (all.joined(separator: "\n") + "\n").write(toFile: tmp, atomically: true, encoding: .utf8) }
        catch { fail(error.localizedDescription); return }
        let cmd = "cp /etc/hosts /etc/hosts.startbak && cp '\(tmp)' /etc/hosts && dscacheutil -flushcache && killall -HUP mDNSResponder"
        var err: NSDictionary?
        NSAppleScript(source: "do shell script \"\(cmd)\" with administrator privileges")?.executeAndReturnError(&err)
        try? FileManager.default.removeItem(atPath: tmp)
        if let e = err {
            let n = e[NSAppleScript.errorNumber] as? Int ?? 0
            fail(n == -128 ? T("Отменено") : (e[NSAppleScript.errorMessage] as? String ?? T("Не удалось записать файл")))
        } else {
            message = T("Строка убрана, кэш DNS сброшен.")
            messageColor = .green
        }
        reload()
    }

    private func fail(_ s: String) { message = s; messageColor = .red }
}

struct HostsView: View {
    @StateObject private var m = HostsModel()
    @State private var filter = ""

    private var shown: [HostsLine] {
        let f = filter.trimmingCharacters(in: .whitespaces).lowercased()
        return f.isEmpty ? m.lines : m.lines.filter { $0.text.lowercased().contains(f) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TextField(T("Поиск по файлу"), text: $filter).textFieldStyle(.roundedBorder).frame(maxWidth: 260)
                Button(T("Обновить")) { m.reload() }
                Button(T("Показать в Finder")) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: "/etc/hosts")]) }
                Button(T("Копировать")) { copyToPasteboard(m.lines.map { $0.text }.joined(separator: "\n")) }
                Spacer()
            }
            let blocked = m.lines.filter { $0.blocks }.count
            Label(blocked == 0 ? T("Блокирующих записей нет.") : T("Блокирующих записей") + ": \(blocked)",
                  systemImage: blocked == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.callout).foregroundColor(blocked == 0 ? .green : .red)
            if !m.message.isEmpty { Text(m.message).font(.caption).foregroundColor(m.messageColor) }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(shown) { l in
                        HStack(spacing: 8) {
                            Text("\(l.id + 1)").font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary)
                                .frame(width: 32, alignment: .trailing)
                            Text(l.text.isEmpty ? " " : l.text)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(l.blocks ? .red : (l.isComment ? .secondary : .primary))
                                .textSelection(.enabled)
                            Spacer(minLength: 8)
                            if l.blocks { Button(T("Убрать")) { m.remove(l) }.controlSize(.small) }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(8).frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.15)))
            Text(T("Файл hosts сопоставляет имена сайтов с адресами раньше любого DNS. Запись с адресом 0.0.0.0 или 127.0.0.1 «гасит» сайт: он не открывается. Обычные строки (localhost, broadcasthost) не трогаем."))
                .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { m.reload() }
    }
}
