import Cocoa

// MARK: - Проверка и установка обновлений
//
// Раз в 6 часов «Пуск» спрашивает у GitHub последний релиз репозитория (TheBat1972/StartForMac, можно переопределить
// ключом update.repo) и сравнивает его номер со своей версией. Если вышла новая, в настройках появляется сообщение
// с описанием и кнопкой «Обновить» (на значке настроек — точка); окон сам по себе «Пуск» не показывает.
// «Обновить» скачивает StartForMac.zip из релиза, проверяет подпись и идентификатор, подменяет программу в её папке
// и запускает заново. Релиз: тег вида 9.2 или v9.2, в файлах — StartForMac.zip (его собирает build.sh), в описании — что нового.

final class AppUpdater: ObservableObject {
    static let shared = AppUpdater()

    @Published var status = ""
    @Published var busy = false
    /// Найденная новая версия: номер, описание из релиза (показываются в настройках с кнопкой «Обновить»)
    @Published var availableVersion: String?
    @Published var availableNotes = ""
    private var availableURL: URL?

    static var auto: Bool {
        get { UserDefaults.standard.object(forKey: "update.auto") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "update.auto") }
    }
    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    private var repo: String { UserDefaults.standard.string(forKey: "update.repo") ?? "TheBat1972/StartForMac" }
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    /// Как часто спрашивать GitHub (таймер смотрит раз в час и проверяет, прошло ли это время)
    private static let interval: Double = 6 * 3600

    // MARK: расписание

    func start() {
        restoreFound()
        guard AppUpdater.auto, timer == nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in self?.checkIfDue() }
        let t = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in self?.checkIfDue() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        // после пробуждения Mac не ждать следующего часового тика
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) { self?.checkIfDue() }
        }
    }

    func setAuto(_ on: Bool) {
        AppUpdater.auto = on
        if on { start() } else {
            timer?.invalidate(); timer = nil
            if let o = wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(o); wakeObserver = nil }
        }
    }

    /// Проверка нужна, если с прошлой прошло достаточно времени (таймер смотрит раз в час, так что Mac может спать и включаться когда угодно)
    private func checkIfDue() {
        guard AppUpdater.auto, !busy else { return }
        let last = UserDefaults.standard.double(forKey: "update.last")
        if Date().timeIntervalSince1970 - last >= AppUpdater.interval - 300 { check(manual: false) }
    }

    // MARK: проверка

    func check(manual: Bool) {
        guard !busy else { return }
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return }
        busy = true
        if manual { status = T("Проверяю…") }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("StartForMac", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { [weak self] data, resp, err in
            DispatchQueue.main.async { self?.handle(data, resp, err, manual: manual) }
        }.resume()
    }

    /// Номер «8.10.1» в числа; сравнение по частям
    /// ВРЕМЕННО для проверки установки: считать «новой» любую версию, отличную от текущей (в том числе более старую).
    /// После проверки поставить false.
    static let allowDowngrade = false

    static func isNewer(_ a: String, than b: String) -> Bool {
        if allowDowngrade { return a != b }
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    private func handle(_ data: Data?, _ resp: URLResponse?, _ err: Error?, manual: Bool) {
        busy = false
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        // время проверки запоминаем только при настоящем ответе; сбой сети, лимит GitHub (403) или 5xx не откладывают следующую попытку
        if code == 200 || code == 404 { UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "update.last") }
        guard err == nil, code == 200, let data = data,
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = j["tag_name"] as? String else {
            status = code == 404 ? T("Релизов не найдено: репозиторий закрыт или в нём ещё нет релизов.") : T("Не удалось проверить обновления.")
            if manual { info(status) }
            return
        }
        let ver = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard AppUpdater.isNewer(ver, than: AppUpdater.currentVersion) else {
            availableVersion = nil
            UserDefaults.standard.removeObject(forKey: "update.found")
            status = T("Установлена последняя версия")
            if manual { info(status) }
            return
        }
        let assets = (j["assets"] as? [[String: Any]]) ?? []
        let zips = assets.filter { ($0["name"] as? String)?.lowercased().hasSuffix(".zip") == true }
        let asset = zips.first { ($0["name"] as? String)?.hasPrefix("StartForMac") == true } ?? zips.first
        guard let link = asset?["browser_download_url"] as? String, let dl = URL(string: link) else {
            status = Tf("Вышла версия %@, но в релизе нет архива .zip.", ver)
            if manual { info(status) }
            return
        }
        availableVersion = ver
        availableURL = dl
        availableNotes = (j["body"] as? String) ?? ""
        UserDefaults.standard.set(["ver": ver, "url": link, "notes": availableNotes], forKey: "update.found")
        status = Tf("Доступна версия %@.", ver)
        if manual { (NSApp.delegate as? AppDelegate)?.openSettings() }
    }

    /// Найденная ранее новая версия переживает перезапуск «Пуска»: сообщение не пропадает до следующей проверки
    private func restoreFound() {
        guard availableVersion == nil, let d = UserDefaults.standard.dictionary(forKey: "update.found"),
              let v = d["ver"] as? String, let l = d["url"] as? String, let u = URL(string: l),
              AppUpdater.isNewer(v, than: AppUpdater.currentVersion) else {
            UserDefaults.standard.removeObject(forKey: "update.found"); return
        }
        availableVersion = v; availableURL = u
        availableNotes = d["notes"] as? String ?? ""
        status = Tf("Доступна версия %@.", v)
    }

    /// Ставит найденную версию (кнопка «Обновить»)
    func installAvailable() {
        guard !busy, let url = availableURL, let v = availableVersion else { return }
        install(url, version: v)
    }

    // MARK: окно и установка

    private func info(_ text: String) {
        let a = NSAlert()
        a.messageText = text
        NSApp.activate(ignoringOtherApps: true)
        // если открыты настройки, сообщение по центру окна настроек (по умолчанию оно выскакивало правее и выше)
        if let host = SettingsWindowController.shared.visibleWindow {
            a.layout()
            let place = {
                let f = a.window.frame
                a.window.setFrameOrigin(NSPoint(x: host.frame.midX - f.width / 2, y: host.frame.midY - f.height / 2))
            }
            place()
            RunLoop.main.perform(inModes: [.modalPanel, .common]) { place() }      // runModal ставит окно по-своему: поправляем в начале модального цикла
        }
        a.runModal()
    }

    private func fail(_ msg: String) {
        DispatchQueue.main.async {
            self.busy = false
            self.status = msg
            self.info(msg)
        }
    }

    @discardableResult
    private static func run(_ tool: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }

    private func install(_ url: URL, version: String) {
        busy = true
        status = T("Скачиваю обновление…")
        URLSession.shared.downloadTask(with: url) { [weak self] tmp, resp, err in
            guard let self = self else { return }
            guard let tmp = tmp, err == nil, (resp as? HTTPURLResponse)?.statusCode == 200 else {
                self.fail(T("Не удалось скачать обновление.")); return
            }
            let fm = FileManager.default
            let work = fm.temporaryDirectory.appendingPathComponent("StartForMacUpdate-\(UUID().uuidString)")
            let out = work.appendingPathComponent("x")
            let zip = work.appendingPathComponent("u.zip")
            do {
                try fm.createDirectory(at: out, withIntermediateDirectories: true)
                try fm.moveItem(at: tmp, to: zip)
            } catch { self.fail(T("Не удалось скачать обновление.")); return }
            DispatchQueue.main.async { self.status = T("Устанавливаю…") }

            guard AppUpdater.run("/usr/bin/ditto", ["-x", "-k", zip.path, out.path]) == 0 else {
                self.fail(T("Не удалось распаковать обновление.")); return
            }
            let app = out.appendingPathComponent("StartForMac.app")
            let plist = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
            guard let id = plist?["CFBundleIdentifier"] as? String, id == Bundle.main.bundleIdentifier,
                  let v = plist?["CFBundleShortVersionString"] as? String, AppUpdater.isNewer(v, than: AppUpdater.currentVersion),
                  AppUpdater.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path]) == 0 else {
                self.fail(T("Скачанный архив не прошёл проверку: обновление не установлено.")); return
            }
            let dst = Bundle.main.bundleURL
            guard fm.isWritableFile(atPath: dst.deletingLastPathComponent().path) else {
                DispatchQueue.main.async {
                    NSWorkspace.shared.activateFileViewerSelecting([app])
                    self.fail(T("Нет прав на замену программы в её папке. Новая версия показана в Finder: перенесите её в «Программы» вручную."))
                }
                return
            }
            // замену делает отдельный процесс: ждёт выхода «Пуска», подменяет программу (при сбое возвращает старую) и запускает новую
            let script = """
            PID="$1"; NEW="$2"; DST="$3"; WORK="$4"
            while kill -0 "$PID" 2>/dev/null; do sleep 0.3; done
            rm -rf "$DST.old"
            if mv "$DST" "$DST.old" && ditto "$NEW" "$DST"; then rm -rf "$DST.old"; else rm -rf "$DST"; mv "$DST.old" "$DST"; fi
            xattr -dr com.apple.quarantine "$DST" 2>/dev/null
            rm -rf "$WORK"
            open "$DST"
            """
            let sh = work.appendingPathComponent("replace.sh")
            do { try script.write(to: sh, atomically: true, encoding: .utf8) } catch { self.fail(T("Не удалось установить обновление.")); return }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = ["-c", "nohup /bin/sh \"$0\" \"$1\" \"$2\" \"$3\" \"$4\" >/dev/null 2>&1 &", sh.path,
                           String(ProcessInfo.processInfo.processIdentifier), app.path, dst.path, work.path]
            guard (try? p.run()) != nil else { self.fail(T("Не удалось установить обновление.")); return }
            p.waitUntilExit()
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }.resume()
    }
}
