import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Полная копия «Пуска»
//
// Всё, что «Пуск» хранит у себя, собирается в один файл «.startbackup» (XML property list): все настройки программы,
// стикеры, оба словаря раскладки, категории, ссылки и папки меню, «чистые» рабочие столы.
// В копию не входят история буфера обмена, скачанные программы, кэши и системные настройки (автозапуск, перезапуск, разрешения).
// Восстановление идёт в два шага: выбранный файл откладывается рядом с данными, «Пуск» перезапускается и при следующем запуске,
// пока ничего ещё не прочитано, подменяет настройки и файлы. Так старые значения не успевают перезаписать новые при выходе.

enum FullBackup {
    private static let format = "StartFullBackup"
    /// Файлы внутри ~/Library/Application Support, которые входят в копию (других путей из файла копии не читается)
    private static let files = ["StartMenu/config.json", "StartForMac/desktops.json"]
    private static let skipPrefixes = ["NSWindow Frame"]

    private static var support: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0] }
    private static var pendingURL: URL { support.appendingPathComponent("StartMenu/restore-pending.startbackup") }
    private static var backupsDir: URL { support.appendingPathComponent("StartMenu/Backups", isDirectory: true) }
    private static var fileType: UTType { UTType(filenameExtension: "startbackup", conformingTo: .data) ?? .data }
    private static var bundleID: String { Bundle.main.bundleIdentifier ?? "ru.local.StartMenu" }

    private static func skip(_ key: String) -> Bool { skipPrefixes.contains { key.hasPrefix($0) } }

    /// Текущее состояние «Пуска» одним файлом
    static func snapshot() -> Data? {
        StickerStore.shared.saveNow()
        UserDefaults.standard.synchronize()
        var defs = UserDefaults.standard.persistentDomain(forName: bundleID) ?? [:]
        for k in Array(defs.keys) where skip(k) { defs[k] = nil }
        var fs: [String: Data] = [:]
        for rel in files { if let d = try? Data(contentsOf: support.appendingPathComponent(rel)) { fs[rel] = d } }
        let obj: [String: Any] = ["format": format, "version": 1, "date": Date(),
                                  "app": AppUpdater.currentVersion, "bundle": bundleID,
                                  "defaults": defs, "files": fs]
        return try? PropertyListSerialization.data(fromPropertyList: obj, format: .xml, options: 0)
    }

    private static func parse(_ data: Data) -> [String: Any]? {
        guard let obj = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any],
              obj["format"] as? String == format, obj["defaults"] is [String: Any] else { return nil }
        return obj
    }

    /// Сохраняет копию в выбранный файл; возвращает сообщение (nil — отменено)
    static func save() -> String? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let p = NSSavePanel()
        p.title = T("Полная копия «Пуска»")
        p.nameFieldStringValue = "Start-" + f.string(from: Date()) + ".startbackup"
        p.allowedContentTypes = [fileType]
        NSApp.activate(ignoringOtherApps: true)
        guard p.runModal() == .OK, let url = p.url else { return nil }
        guard let data = snapshot() else { return T("Не удалось собрать копию.") }
        do {
            try data.write(to: url, options: .atomic)
            return Tf("Сохранено: %@ КБ", "\(max(1, data.count / 1024))")
        } catch {
            return Tf("Не удалось сохранить: %@", error.localizedDescription)
        }
    }

    /// Восстановление из файла: после подтверждения «Пуск» перезапускается и применяет копию; возвращает сообщение об ошибке (nil — отменено или пошло на перезапуск)
    static func restore() -> String? {
        let p = NSOpenPanel()
        p.title = T("Восстановить «Пуск» из полной копии")
        p.allowedContentTypes = [fileType]
        p.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard p.runModal() == .OK, let url = p.url else { return nil }
        guard let data = try? Data(contentsOf: url), let obj = parse(data) else { return T("Это не полная копия «Пуска».") }
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        let when = (obj["date"] as? Date).map { df.string(from: $0) } ?? "?"
        let a = NSAlert()
        a.messageText = T("Восстановить «Пуск» из копии?")
        a.informativeText = Tf("Копия от %@ (версия %@). Все текущие настройки, стикеры, словари, категории и ссылки будут заменены данными из копии, «Пуск» перезапустится. Перед этим текущие данные сохраняются отдельным файлом.",
                               when, (obj["app"] as? String) ?? "?")
        a.alertStyle = .warning
        a.addButton(withTitle: T("Восстановить"))
        a.addButton(withTitle: T("Отмена"))
        guard a.runModal() == .alertFirstButtonReturn else { return nil }
        saveSafetyCopy()
        do {
            try FileManager.default.createDirectory(at: pendingURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: pendingURL, options: .atomic)
        } catch {
            return Tf("Не удалось сохранить: %@", error.localizedDescription)
        }
        Watchdog.relaunch()
        return nil
    }

    /// Копия текущих данных перед заменой (последние пять хранятся в ~/Library/Application Support/StartMenu/Backups)
    private static func saveSafetyCopy() {
        guard let data = snapshot() else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: backupsDir, withIntermediateDirectories: true)
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        try? data.write(to: backupsDir.appendingPathComponent("before-restore-" + f.string(from: Date()) + ".startbackup"), options: .atomic)
        let old = ((try? fm.contentsOfDirectory(at: backupsDir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("before-restore-") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for u in old.dropFirst(5) { try? fm.removeItem(at: u) }
    }

    /// В самом начале запуска: если есть отложенная копия, подменяет настройки и файлы
    static func applyPending() {
        guard let data = try? Data(contentsOf: pendingURL) else { return }
        try? FileManager.default.removeItem(at: pendingURL)         // применяется один раз
        guard let obj = parse(data), let defs = obj["defaults"] as? [String: Any] else { return }
        let d = UserDefaults.standard
        for k in Array((d.persistentDomain(forName: bundleID) ?? [:]).keys) where !skip(k) { d.removeObject(forKey: k) }
        for (k, v) in defs where !skip(k) { d.set(v, forKey: k) }
        d.synchronize()
        let fs = obj["files"] as? [String: Data] ?? [:]
        for rel in files {
            let u = support.appendingPathComponent(rel)
            if let content = fs[rel] {
                try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? content.write(to: u, options: .atomic)
            } else {
                try? FileManager.default.removeItem(at: u)
            }
        }
    }
}

/// Кнопки полной копии во вкладке «О программе»
struct FullBackupSection: View {
    @State private var note = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button(T("Сохранить полную копию…")) { if let m = FullBackup.save() { note = m } }
                Button(T("Восстановить из полной копии…")) { if let m = FullBackup.restore() { note = m } }
                Spacer()
            }
            Text(T("В копию входят все настройки «Пуска», стикеры, словари раскладки, категории, ссылки и «чистые» рабочие столы. Не входят история буфера обмена, скачанные программы, кэши и системные настройки (автозапуск, перезапуск, разрешения): их при необходимости нужно включить заново. Копия словарей отдельно остаётся во вкладке «Раскладка»."))
                .font(.caption).foregroundColor(.secondary)
            if !note.isEmpty { Text(note).font(.caption) }
        }
    }
}
