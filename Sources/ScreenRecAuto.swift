import Foundation
import AppKit

// MARK: - Автоконвертация записей экрана
//
// По умолчанию выключено (Настройки → «Запись экрана»). Пока «Пуск» запущен, он раз в три секунды смотрит в папку, куда стандартная
// утилита (⇧⌘5) сохраняет записи: рабочий стол или папка, выбранная в её параметрах. Новая запись («Запись экрана … .mov»), которая
// перестала расти, отправляется в «Загрузку и конвертацию» (раздел «Видео») с теми настройками, что там стоят сейчас. Результат
// ложится в «Загрузки», оригинал остаётся на месте. Записи, которые уже лежали в папке, не трогаются.

final class ScreenRecAuto {
    static let shared = ScreenRecAuto()

    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "screenrec.auto") as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: "screenrec.auto") }
    }

    /// Начинать конвертацию сразу, без кнопки «Старт» (по умолчанию да) или только ставить запись в очередь
    static var startNow: Bool {
        get { UserDefaults.standard.object(forKey: "screenrec.start") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "screenrec.start") }
    }

    private static let prefixes = ["Screen Recording", "Запись экрана", "Bildschirmaufnahme", "Grabación de pantalla", "Enregistrement de l’écran"]

    private var timer: Timer?
    private var seen = Set<String>()
    private var sizes: [String: Int64] = [:]      // размер на прошлом опросе: запись готова, когда он перестал меняться

    func setEnabled(_ on: Bool) { on ? start() : stop() }

    /// Папка записей: настройка стандартной утилиты, а по умолчанию рабочий стол
    static func folder() -> URL {
        let p = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location") ?? "~/Desktop"
        return URL(fileURLWithPath: (p as NSString).expandingTildeInPath, isDirectory: true)
    }

    func start() {
        guard timer == nil else { return }
        seen = Set(recordings().map { $0.path })
        sizes = [:]
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.poll() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        sizes = [:]
    }

    private func recordings() -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(at: Self.folder(), includingPropertiesForKeys: nil,
                                                                   options: [.skipsHiddenFiles])) ?? []
        return items.filter { u in
            u.pathExtension.lowercased() == "mov" && Self.prefixes.contains { u.lastPathComponent.hasPrefix($0) }
        }
    }

    /// Настоящий QuickTime: в байтах 4–8 стоит название первого блока контейнера (ftyp, moov, mdat, wide, free, skip),
    /// а не просто файл с расширением .mov
    private static func isQuickTime(_ u: URL) -> Bool {
        guard let h = try? FileHandle(forReadingFrom: u) else { return false }
        defer { try? h.close() }
        guard let d = try? h.read(upToCount: 12), d.count >= 8 else { return false }
        let tag = String(decoding: d[d.startIndex + 4 ..< d.startIndex + 8], as: UTF8.self)
        return ["ftyp", "moov", "mdat", "wide", "free", "skip"].contains(tag)
    }

    private func poll() {
        // папку могли сменить в параметрах утилиты: то, что уже лежит там, считаем старым
        for u in recordings() where !seen.contains(u.path) {
            let size = Int64((try? u.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            if size > 0, sizes[u.path] == size {
                seen.insert(u.path)
                sizes[u.path] = nil
                if Self.isQuickTime(u) { handle(u) }
            } else {
                sizes[u.path] = size
            }
        }
    }

    private func handle(_ url: URL) {
        let conv = VideoConverter.shared
        conv.add([url])
        let ready = ToolsManager.shared.tools != nil
        let title: String, sub: String
        if !ready {
            title = Tf("В очередь: «%@»", url.lastPathComponent)
            sub = T("Нужны компоненты ffmpeg")
        } else if !Self.startNow {
            title = Tf("В очередь: «%@»", url.lastPathComponent)
            sub = T("Запустите конвертацию сами")
        } else {
            if !conv.isRunning { conv.start() }
            title = Tf("В конвертацию: «%@»", url.lastPathComponent)
            sub = T("Результат — в «Загрузках»")
        }
        FinderCut.shared.present(icon: "film", title: title, subtitle: sub)
    }
}
