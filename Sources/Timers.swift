import SwiftUI
import AppKit
import UserNotifications

// MARK: - Таймер, секундомер и напоминания
//
// По умолчанию выключено (Настройки → «Интерфейс» → «Таймер, секундомер и напоминания»). Включённая настройка добавляет
// кнопку рядом с чашкой («Не давать уснуть») в верхней строке «Пуска»; вторая настройка добавляет ещё и значок в верхнюю панель
// со временем, оставшимся до сигнала. Напоминания срабатывают, пока «Пуск» запущен; при сигнале звучит «Glass» и приходит
// уведомление (если оно разрешено в системе).

struct TimerReminder: Identifiable, Codable, Equatable {
    var id = UUID()
    var text: String
    var date: Date
    var fired = false
    /// Сработало, но пользователь ещё не принял (значок в верхней панели красный, пока не примет)
    var acked: Bool? = nil
    /// Стикер, который нужно показать на экране, когда напоминание сработает
    var sticker: UUID? = nil
    /// Создано колокольчиком на самом стикере (дата хранится и на стикере)
    var own: Bool? = nil
}

final class TimerHub: ObservableObject {
    static let shared = TimerHub()

    @Published var enabled = UserDefaults.standard.object(forKey: "timers.enabled") as? Bool ?? false
    @Published var inMenuBar = UserDefaults.standard.object(forKey: "timers.menubar") as? Bool ?? false
    /// Нужен для перерисовки секунд: обновляется только пока идёт таймер или секундомер
    @Published var now = Date()

    // таймер обратного отсчёта
    @Published var timerEnd: Date? = nil          // идёт: когда прозвенит
    @Published var timerPausedLeft: TimeInterval? = nil
    @Published var timerTotal: TimeInterval = 0
    /// Время вышло: звучит сигнал, значок красный, таймер ждёт кнопку «Сбросить»
    @Published var timerFinished = false
    /// Значок в верхней панели появился (таймер, секундомер или напоминание запускались) и остаётся, пока не нажато «Закрыть»; «Сбросить» его не убирает
    @Published var iconOpen = false
    private var lastBeep = Date.distantPast
    private var beeps = 0

    // секундомер
    @Published var swStart: Date? = nil
    @Published var swAccum: TimeInterval = 0
    @Published var laps: [TimeInterval] = []

    @Published var reminders: [TimerReminder] = []

    // действие по окончании таймера (сон, выключение, закрыть программу): выполняется через 10 секунд, пока можно отменить
    @Published var pendingTitle: String? = nil
    @Published var pendingAt: Date? = nil
    private var pendingRun: (() -> Void)?

    private var ticker: Timer?
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var iconWasRed = false
    private static let popoverHeight: CGFloat = 420

    init() {
        if let d = UserDefaults.standard.data(forKey: "timers.reminders"),
           let r = try? JSONDecoder().decode([TimerReminder].self, from: d) {
            // то, что сработало до этого запуска и уже сохранено, считается принятым
            reminders = r.map { var x = $0; if x.fired && x.acked == nil { x.acked = true }; return x }
        }
        if enabled { DispatchQueue.main.async { self.activate() } }
    }

    // MARK: настройки

    func setEnabled(_ on: Bool) {
        enabled = on
        UserDefaults.standard.set(on, forKey: "timers.enabled")
        if on { activate() } else { deactivate() }
    }

    func setInMenuBar(_ on: Bool) {
        inMenuBar = on
        UserDefaults.standard.set(on, forKey: "timers.menubar")
        applyMenuBar()
    }

    private func activate() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
        syncAllStickers()
        applyMenuBar()
        tick()
    }

    private func deactivate() {
        ticker?.invalidate(); ticker = nil
        resetTimer(); resetStopwatch(); cancelPending()
        iconOpen = false
        applyMenuBar()
    }

    // MARK: таймер

    var timerRunning: Bool { timerEnd != nil }
    var timerLeft: TimeInterval {
        if let e = timerEnd { return max(0, e.timeIntervalSince(now)) }
        return timerPausedLeft ?? 0
    }

    func startTimer(minutes: Double) {
        let sec = max(1, minutes * 60)
        timerTotal = sec
        timerPausedLeft = nil
        timerFinished = false
        iconOpen = true
        now = Date()
        timerEnd = now.addingTimeInterval(sec)
    }

    func pauseTimer() {
        guard let e = timerEnd else { return }
        timerPausedLeft = max(0, e.timeIntervalSince(Date()))
        timerEnd = nil
    }

    func resumeTimer() {
        guard let left = timerPausedLeft else { return }
        timerEnd = Date().addingTimeInterval(left)
        timerPausedLeft = nil
    }

    /// «Закрыть» у значка: останавливает и сбрасывает всё и убирает значок из верхней панели
    func closeAll() {
        resetTimer(); resetStopwatch(); cancelPending()
        iconOpen = false
        for i in reminders.indices where reminders[i].fired { reminders[i].acked = true }
        saveReminders()
        updateStatusTitle()
    }

    func resetTimer() { timerEnd = nil; timerPausedLeft = nil; timerTotal = 0; timerFinished = false; beeps = 0 }

    // MARK: секундомер

    var swRunning: Bool { swStart != nil }
    var swElapsed: TimeInterval { swAccum + (swStart.map { max(0, now.timeIntervalSince($0)) } ?? 0) }

    func toggleStopwatch() {
        if let s = swStart { swAccum += Date().timeIntervalSince(s); swStart = nil }
        else { now = Date(); swStart = now; iconOpen = true }
    }
    func lap() { if swRunning { laps.insert(swElapsed, at: 0) } }
    func resetStopwatch() { swStart = nil; swAccum = 0; laps = [] }

    // MARK: напоминания

    func addReminder(_ text: String, at date: Date, sticker: UUID? = nil) {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty, let sid = sticker, let s = StickerStore.shared.sticker(sid) { t = s.title }
        reminders.append(TimerReminder(text: t.isEmpty ? T("Напоминание") : t, date: date, sticker: sticker))
        reminders.sort { $0.date < $1.date }
        saveReminders()
    }

    /// Сработавшие и ещё не принятые напоминания
    var reminderAlerts: [TimerReminder] { reminders.filter { $0.fired && $0.acked != true } }
    var reminderAlert: Bool { !reminderAlerts.isEmpty }

    /// Напоминание принято (в списке, на стикере или в значке): если больше ничего не идёт, значок из верхней панели убирается, как по «Закрыть»
    private func closeIconIfIdle() {
        if !timerRunning && timerPausedLeft == nil && !timerFinished && !swRunning && swAccum == 0 && !reminderAlert { iconOpen = false }
        updateStatusTitle()
    }

    func ackReminder(_ id: UUID) {
        if let i = reminders.firstIndex(where: { $0.id == id }) {
            reminders[i].acked = true
            let own = reminders[i].own == true
            if let sid = reminders[i].sticker, StickerStore.shared.sticker(sid)?.alertActive == true {
                StickerManager.shared.acceptAlert(sid)      // принято в таймере — стикер тоже перестаёт мигать
            }
            if own { reminders.removeAll { $0.id == id } }     // напоминание со стикера после приёма из списка пропадает
        }
        saveReminders(); closeIconIfIdle()
    }

    func ackAllReminders() {
        for i in reminders.indices where reminders[i].fired { reminders[i].acked = true }
        saveReminders(); closeIconIfIdle()
    }

    func removeReminder(_ id: UUID) {
        // удалили во вкладке напоминание, поставленное со стикера: дата на самом стикере тоже снимается
        if let r = reminders.first(where: { $0.id == id }), r.own == true, !r.fired, let sid = r.sticker {
            StickerStore.shared.update(sid) { $0.remindAt = nil }
        }
        reminders.removeAll { $0.id == id }; saveReminders(); updateStatusTitle()
    }

    // MARK: стикеры

    func hasOwnReminder(_ sticker: UUID) -> Bool { reminders.contains { $0.sticker == sticker && $0.own == true } }

    /// Напоминание, поставленное колокольчиком на стикере, видно и во вкладке «Напоминания»; nil — убрать несработавшее
    func syncStickerReminder(_ id: UUID, at date: Date?) {
        reminders.removeAll { $0.sticker == id && $0.own == true && !$0.fired }
        if let d = date, enabled, let s = StickerStore.shared.sticker(id) {
            reminders.append(TimerReminder(text: s.title, date: d, sticker: id, own: true))
            reminders.sort { $0.date < $1.date }
        }
        saveReminders()
    }

    /// При включении таймера: уже заданные на стикерах даты попадают в его список
    private func syncAllStickers() {
        for s in StickerStore.shared.list {
            guard let d = s.remindAt, d > Date(), !s.alertActive, !hasOwnReminder(s.id) else { continue }
            syncStickerReminder(s.id, at: d)
        }
    }

    /// Стикер принят: сработавшие напоминания этого стикера в списке принимаются, а поставленные со стикера убираются
    func ackSticker(_ id: UUID) {
        for i in reminders.indices where reminders[i].sticker == id && reminders[i].fired && reminders[i].acked != true { reminders[i].acked = true }
        reminders.removeAll { $0.sticker == id && $0.own == true && $0.fired }     // принято на стикере: из списка таймера оно уходит
        saveReminders(); closeIconIfIdle()
    }
    func clearFired() { reminders.removeAll { $0.fired }; saveReminders(); updateStatusTitle() }

    /// Сработало напоминание самого стикера: то же красное предупреждение в верхней панели, пока не принято
    func stickerFired(_ title: String) {
        reminders.append(TimerReminder(text: Tf("Стикер: %@", title), date: Date(), fired: true, acked: false))
        iconOpen = true
        saveReminders()
        alert(T("Напоминание"), Tf("Стикер: %@", title))
        updateStatusTitle()
    }

    private func saveReminders() {
        if let d = try? JSONEncoder().encode(reminders) { UserDefaults.standard.set(d, forKey: "timers.reminders") }
    }

    // MARK: ход времени

    private func tick() {
        let n = Date()
        if timerEnd != nil || swStart != nil || pendingAt != nil { now = n }
        if let at = pendingAt, at <= n {
            let run = pendingRun
            cancelPending()
            run?()
        }
        if let e = timerEnd, e <= n {
            timerEnd = nil; timerPausedLeft = nil
            timerFinished = true
            beeps = 1; lastBeep = n
            alert(T("Таймер"), T("Время вышло"))
            scheduleAction()
        }
        // пока таймер не сброшен, сигнал повторяется (раз в 4 секунды, не больше 12 раз)
        if timerFinished, beeps < 12, n.timeIntervalSince(lastBeep) >= 4 {
            beeps += 1; lastBeep = n
            NSSound(named: NSSound.Name("Glass"))?.play()
        }
        var changed = false
        for i in reminders.indices where !reminders[i].fired && reminders[i].date <= n {
            reminders[i].fired = true
            iconOpen = true
            reminders[i].acked = false
            changed = true
            let late = n.timeIntervalSince(reminders[i].date) > 120
            alert(T("Напоминание"), reminders[i].text + (late ? " (" + T("пропущено, пока «Пуск» был закрыт") + ")" : ""))
            if let sid = reminders[i].sticker { StickerManager.shared.reveal(sid) }      // стикер сам появляется на экране
        }
        if changed { saveReminders() }
        updateStatusTitle()
    }

    /// Что сделать по окончании таймера: настройка лежит в «timers.action» (0 — ничего, 1 — сон, 2 — выключение, 3 — закрыть программу)
    private func scheduleAction() {
        let d = UserDefaults.standard
        var title = ""
        var run: (() -> Void)?
        switch d.integer(forKey: "timers.action") {
        case 1:
            title = T("Сон")
            run = { PowerMenu.send("sleep") }
        case 2:
            title = T("Выключение")
            run = { PowerMenu.send("rsdn") }
        case 3:
            let bid = d.string(forKey: "timers.quitApp") ?? ""
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bid).first else { return }
            title = T("Закрыть") + " " + (app.localizedName ?? bid)
            run = { app.terminate() }
        default:
            return
        }
        pendingTitle = title
        pendingRun = run
        now = Date()
        pendingAt = now.addingTimeInterval(10)
        alert(T("Таймер"), title + " — " + T("через 10 секунд, можно отменить в окне таймера"))
    }

    func cancelPending() { pendingTitle = nil; pendingAt = nil; pendingRun = nil }

    private func alert(_ title: String, _ body: String) {
        NSSound(named: NSSound.Name("Glass"))?.play()
        NSApp.requestUserAttention(.informationalRequest)
        let c = UNMutableNotificationContent()
        c.title = title; c.body = body; c.sound = nil
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }

    static func format(_ t: TimeInterval, tenths: Bool = false) -> String {
        let total = Int(t)
        let h = total / 3600, m = total % 3600 / 60, s = total % 60
        var out = h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
        if tenths { out += String(format: ".%d", Int((t - Double(total)) * 10)) }
        return out
    }

    // MARK: значок в строке меню

    /// Значок нужен, только пока идёт таймер (в том числе на паузе) или секундомер
    private var wantIcon: Bool {
        enabled && inMenuBar && (iconOpen || timerRunning || timerPausedLeft != nil || timerFinished || reminderAlert || swRunning || swAccum > 0)
    }

    private func applyMenuBar() {
        if wantIcon {
            if statusItem == nil {
                let it = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                it.autosaveName = "StartTimerIcon"      // система запоминает место значка в строке меню
                it.button?.image = NSImage(systemSymbolName: "timer", accessibilityDescription: T("Таймер"))
                it.button?.image?.isTemplate = true
                it.button?.imagePosition = .imageLeading
                it.button?.target = self
                it.button?.action = #selector(statusClicked)
                it.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
                it.button?.toolTip = T("Таймер, секундомер и напоминания")
                statusItem = it
            }
            updateStatusTitle()
        } else {
            popover?.close(); popover = nil
            if let it = statusItem { NSStatusBar.system.removeStatusItem(it) }
            statusItem = nil
            iconWasRed = false
        }
    }

    private func updateStatusTitle() {
        if wantIcon != (statusItem != nil) { applyMenuBar(); if statusItem == nil { return } }
        guard let b = statusItem?.button else { return }
        let s: String
        if timerFinished { s = " " + Self.format(timerLeft) }
        else if let r = reminderAlerts.first { s = " " + String(r.text.prefix(24)) + (reminderAlerts.count > 1 ? " +\(reminderAlerts.count - 1)" : "") }
        else if timerRunning || timerPausedLeft != nil { s = " " + Self.format(timerLeft) }
        else if swRunning || swAccum > 0 { s = " " + Self.format(swElapsed) }      // остановленный секундомер тоже виден, пока не нажали «Закрыть»
        else { s = "" }
        if timerFinished || reminderAlert {
            // красный значок и время; пока не нажата «Сбросить»
            if !iconWasRed { b.image = StatusIcon.colored("timer", .systemRed, T("Таймер")) ?? b.image }
            b.attributedTitle = NSAttributedString(string: s, attributes: [.foregroundColor: NSColor.systemRed, .font: NSFont.menuBarFont(ofSize: 0)])
            iconWasRed = true
        } else {
            if iconWasRed {
                let img = NSImage(systemSymbolName: "timer", accessibilityDescription: T("Таймер"))
                img?.isTemplate = true
                b.image = img
                b.title = ""
                iconWasRed = false
            }
            if b.title != s { b.title = s }
        }
    }

    @objc private func closeFromMenu() { closeAll() }
    @objc private func removeFromMenuBar() { setInMenuBar(false) }
    @objc private func openSettingsItem() { (NSApp.delegate as? AppDelegate)?.openSettings() }

    @objc private func statusClicked() {
        // правый клик (или ⌃-клик): меню с пунктом «Убрать из верхней панели»
        if let e = NSApp.currentEvent, e.type == .rightMouseUp || e.modifierFlags.contains(.control) {
            popover?.close()
            let m = NSMenu()
            m.addItem(withTitle: T("Закрыть"), action: #selector(closeFromMenu), keyEquivalent: "").target = self
            m.addItem(.separator())
            m.addItem(withTitle: T("Убрать из верхней панели"), action: #selector(removeFromMenuBar), keyEquivalent: "").target = self
            m.addItem(withTitle: T("Настройки…"), action: #selector(openSettingsItem), keyEquivalent: "").target = self
            statusItem?.menu = m
            statusItem?.button?.performClick(nil)
            statusItem?.menu = nil
            return
        }
        if let p = popover, p.isShown { p.close(); return }
        if reminderAlert && !timerFinished { UserDefaults.standard.set(2, forKey: "timers.tab") }      // сразу к напоминаниям
        let p = NSPopover()
        p.behavior = .transient
        let hub = self
        let close: () -> Void = { [weak p] in p?.close() }
        let host = NSHostingController(rootView: LangRefresh {
            TimerPanelView(hub: hub, onClose: close, onCloseAll: { close(); hub.closeAll() }, fixedHeight: Self.popoverHeight)
        })
        host.view.frame = NSRect(x: 0, y: 0, width: 400, height: Self.popoverHeight)
        p.contentViewController = host
        p.contentSize = NSSize(width: 400, height: Self.popoverHeight)
        popover = p
        if let b = statusItem?.button { p.show(relativeTo: b.bounds, of: b, preferredEdge: .minY) }
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Интерфейс

struct TimerPanelView: View {
    @ObservedObject var hub: TimerHub
    var onClose: (() -> Void)? = nil
    /// Только у окна от значка в верхней панели: останавливает всё и убирает значок
    var onCloseAll: (() -> Void)? = nil
    /// Для всплывающего окна у значка: размер задан заранее, иначе окно считает его по первому кадру и содержимое съезжает
    var fixedHeight: CGFloat? = nil
    @AppStorage("timers.tab") private var tab = 0
    @AppStorage("timers.action") private var action = 0
    @AppStorage("timers.quitApp") private var quitApp = ""
    @State private var customMin = ""
    @State private var text = ""
    @State private var when = Date().addingTimeInterval(600)
    @State private var stickerID: UUID? = nil

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Picker("", selection: $tab) {
                    Text(T("Таймер")).tag(0)
                    Text(T("Секундомер")).tag(1)
                    Text(T("Напоминания")).tag(2)
                }
                .pickerStyle(.segmented).labelsHidden()
                .frame(maxWidth: .infinity)
                if let close = onClose {
                    Button(action: close) {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain).help(T("Закрыть"))
                }
            }
            switch tab {
            case 0: timer
            case 1: stopwatch
            default: reminders
            }
            if let closeAll = onCloseAll {
                Spacer(minLength: 0)
                Divider()
                HStack {
                    Text(T("Остановить всё и убрать значок из верхней панели")).font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Button(T("Закрыть")) { closeAll() }
                }
            }
        }
        .padding(14)
        .frame(width: 400)
        .frame(height: fixedHeight, alignment: .top)
    }

    private var runningApps: [(id: String, name: String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .map { ($0.bundleIdentifier ?? "", $0.localizedName ?? ($0.bundleIdentifier ?? "")) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var afterAction: some View {
        VStack(spacing: 6) {
            HStack {
                Text(T("По окончании")).foregroundColor(.secondary)
                Picker("", selection: $action) {
                    Text(T("Ничего")).tag(0)
                    Text(T("Сон")).tag(1)
                    Text(T("Выключить компьютер")).tag(2)
                    Text(T("Закрыть программу")).tag(3)
                }
                .labelsHidden().frame(maxWidth: .infinity)
            }
            if action == 3 {
                Picker("", selection: $quitApp) {
                    Text("—").tag("")
                    ForEach(runningApps, id: \.id) { Text($0.name).tag($0.id) }
                }
                .labelsHidden().frame(maxWidth: .infinity)
            }
            if let t = hub.pendingTitle, let at = hub.pendingAt {
                HStack {
                    Text(t + ": " + T("через") + " \(Int(max(0, at.timeIntervalSince(hub.now)).rounded(.up))) " + T("сек."))
                        .foregroundColor(.orange)
                    Spacer()
                    Button(T("Отмена")) { hub.cancelPending() }
                }
            }
        }
    }

    private var timer: some View {
        VStack(spacing: 12) {
            let active = hub.timerRunning || hub.timerPausedLeft != nil || hub.timerFinished
            Text(TimerHub.format(active ? hub.timerLeft : (Double(customMin.replacingOccurrences(of: ",", with: ".")) ?? 0) * 60))
                .font(.system(size: 44, weight: .light, design: .monospaced))
                .foregroundColor(hub.timerFinished ? .red : (hub.timerPausedLeft != nil ? .secondary : .primary))
            if active {
                if hub.timerFinished {
                    Text(T("Время вышло")).foregroundColor(.red)
                } else if hub.timerTotal > 0 { ProgressView(value: 1 - hub.timerLeft / hub.timerTotal) }
                HStack {
                    if !hub.timerFinished {
                        if hub.timerRunning { Button(T("Пауза")) { hub.pauseTimer() } }
                        else { Button(T("Продолжить")) { hub.resumeTimer() } }
                    }
                    if !hub.timerFinished || onCloseAll == nil { Button(T("Сбросить")) { hub.resetTimer() } }
                }
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                    ForEach([1, 5, 10, 15, 30, 60], id: \.self) { m in
                        Button(m < 60 ? "\(m) " + T("мин") : "1 " + T("час")) { hub.startTimer(minutes: Double(m)) }
                            .frame(maxWidth: .infinity)
                    }
                }
                HStack {
                    TextField(T("Минут"), text: $customMin).textFieldStyle(.roundedBorder).frame(width: 90)
                        .onSubmit { startCustom() }
                    Button(T("Старт")) { startCustom() }
                        .disabled((Double(customMin.replacingOccurrences(of: ",", with: ".")) ?? 0) <= 0)
                }
            }
            afterAction
        }
    }

    private func startCustom() {
        if let v = Double(customMin.replacingOccurrences(of: ",", with: ".")), v > 0 { hub.startTimer(minutes: v); customMin = "" }
    }

    private var stopwatch: some View {
        VStack(spacing: 12) {
            Text(TimerHub.format(hub.swElapsed, tenths: true))
                .font(.system(size: 44, weight: .light, design: .monospaced))
            HStack {
                Button(hub.swRunning ? T("Стоп") : T("Старт")) { hub.toggleStopwatch() }
                Button(T("Круг")) { hub.lap() }.disabled(!hub.swRunning)
                Button(T("Сбросить")) { hub.resetStopwatch() }.disabled(hub.swElapsed == 0)
            }
            if !hub.laps.isEmpty {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(hub.laps.enumerated()), id: \.offset) { i, t in
                            HStack {
                                Text("\(hub.laps.count - i)").foregroundColor(.secondary)
                                Spacer()
                                Text(TimerHub.format(t, tenths: true)).font(.system(.body, design: .monospaced))
                            }
                        }
                    }
                }
                .frame(maxHeight: 110)
            }
        }
    }

    private var reminders: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(T("О чём напомнить"), text: $text).textFieldStyle(.roundedBorder)
                .onSubmit { add() }
            HStack {
                DatePicker("", selection: $when, displayedComponents: [.date, .hourAndMinute]).labelsHidden()
                Spacer()
                Button(T("Добавить")) { add() }
            }
            HStack {
                Text(T("Показать стикер")).font(.caption).foregroundColor(.secondary)
                Picker("", selection: $stickerID) {
                    Text(T("Без стикера")).tag(UUID?.none)
                    ForEach(StickerStore.shared.list) { s in Text(s.title).tag(Optional(s.id)) }
                }
                .labelsHidden()
            }
            HStack(spacing: 6) {
                ForEach([(10, T("через 10 мин")), (60, T("через час")), (180, T("через 3 часа"))], id: \.0) { m, title in
                    Button(title) { when = Date().addingTimeInterval(Double(m) * 60) }.controlSize(.small)
                }
            }
            if hub.reminders.isEmpty {
                Text(T("Напоминаний нет. Они срабатывают, пока «Пуск» запущен.")).font(.caption).foregroundColor(.secondary)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(hub.reminders) { r in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 1) {
                                    HStack(spacing: 4) {
                                        if r.sticker != nil { Image(systemName: "note.text").foregroundColor(.secondary) }
                                        Text(r.text).lineLimit(2)
                                    }
                                    Text(r.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                if r.fired && r.acked != true { Button(T("Принять")) { hub.ackReminder(r.id) }.controlSize(.small) }
                                else if r.fired { Image(systemName: "checkmark").foregroundColor(.secondary) }
                                Button { hub.removeReminder(r.id) } label: { Image(systemName: "xmark.circle") }
                                    .buttonStyle(.borderless).help(T("Удалить"))
                            }
                            .opacity(r.fired && r.acked == true ? 0.5 : 1)
                            .foregroundColor(r.fired && r.acked != true ? .red : nil)
                        }
                    }
                }
                .frame(maxHeight: 150)
                if hub.reminders.contains(where: { $0.fired }) {
                    Button(T("Убрать сработавшие")) { hub.clearFired() }.buttonStyle(.link).font(.caption)
                }
            }
        }
    }

    private func add() {
        guard when > Date() else { NSSound.beep(); return }
        hub.addReminder(text, at: when, sticker: stickerID)
        text = ""
        stickerID = nil
        when = Date().addingTimeInterval(600)
    }
}

/// Кнопка рядом с чашкой; показывается, только когда функция включена в настройках
struct TimersHeaderButton: View {
    @ObservedObject var hub = TimerHub.shared
    @Binding var open: Bool

    var body: some View {
        if hub.enabled {
            Button { open.toggle() } label: {
                HStack(spacing: 3) {
                    Image(systemName: "timer")
                    if hub.timerRunning || hub.timerPausedLeft != nil || hub.timerFinished {
                        Text(TimerHub.format(hub.timerLeft)).font(.system(size: 11, design: .monospaced))
                    } else if hub.swRunning || hub.swAccum > 0 {
                        Text(TimerHub.format(hub.swElapsed)).font(.system(size: 11, design: .monospaced))
                    }
                }
                .padding(5).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverHighlight(6)
            .foregroundColor(hub.timerFinished || hub.reminderAlert ? .red : (open || hub.timerRunning || hub.swRunning ? .accentColor : .secondary))
            .help(T("Таймер, секундомер и напоминания"))
        }
    }
}

/// Панель под кнопкой внутри окна «Пуска» (как умный буфер обмена)
struct TimersOverlay: View {
    @ObservedObject var hub = TimerHub.shared
    let close: () -> Void

    var body: some View {
        if hub.enabled {
            ZStack(alignment: .topTrailing) {
                Color.clear.contentShape(Rectangle()).onTapGesture { close() }
                TimerPanelView(hub: hub, onClose: close)
                    .background(VisualEffect())
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(radius: 12)
                    .padding(.top, 90).padding(.trailing, 14)
            }
        }
    }
}
