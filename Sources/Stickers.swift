import SwiftUI
import AppKit

// MARK: - Стикеры
//
// Цветные стикеры-самоклейки: карточка с короткими строками-напоминаниями, которую можно «наклеить» на рабочий стол.
// Наклеенный стикер лежит поверх обоев и значков рабочего стола, но под окнами программ, на всех рабочих столах (Spaces),
// и остаётся там, куда его поставили, пока запущен «Пуск». Строку можно зачеркнуть кнопкой-кружком рядом с ней.
// «×» на стикере убирает его с экрана (с подтверждением), но в инструменте «Стикеры» он сохраняется, пока не удалишь его там.
// К стикеру можно привязать дату и время (колокольчик): в этот момент стикер сам появится на экране, если его там нет.
// Всё хранится только на этом Mac, в настройках программы.

// MARK: Модель

struct StickerItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var text = ""
    var done = false
    /// Самая длинная строка стикера (символов); вставленное из буфера обмена обрезается
    static let maxLength = 200
}

struct Sticker: Identifiable, Codable, Equatable {
    var id = UUID()
    var color = 0
    var items: [StickerItem] = [StickerItem()]
    /// Когда напомнить об этом стикере
    var remindAt: Date? = nil
    /// Напоминание сработало и ещё не принято: стикер подсвечен
    var alertActive = false
    /// Наклеен ли сейчас на экран
    var onScreen = true
    var x: Double = 0
    var y: Double = 0
    var w: Double = 240
    var h: Double = 250
    /// Положение уже задано (иначе при первом показе ставится в угол экрана)
    var placed = false
    /// Записи размыты, чтобы подошедший не прочитал (кнопка-глаз); по умолчанию выключено
    var blurred: Bool? = nil
    var created = Date()

    var title: String { items.first(where: { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty })?.text ?? T("Пустой стикер") }
}

enum StickerPalette {
    static let count = 6
    // бумага и более тёмная полоска сверху
    private static let paper: [(Double, Double, Double)] = [(1.00, 0.92, 0.35), (1.00, 0.72, 0.84), (0.70, 0.94, 0.55),
                                                           (0.60, 0.86, 1.00), (1.00, 0.76, 0.42), (0.80, 0.72, 1.00)]
    private static let strip: [(Double, Double, Double)] = [(0.97, 0.80, 0.10), (0.96, 0.52, 0.70), (0.45, 0.80, 0.30),
                                                           (0.30, 0.68, 0.95), (0.97, 0.60, 0.15), (0.62, 0.50, 0.92)]
    static func paperColor(_ i: Int) -> Color { let c = paper[abs(i) % count]; return Color(red: c.0, green: c.1, blue: c.2) }
    static func stripColor(_ i: Int) -> Color { let c = strip[abs(i) % count]; return Color(red: c.0, green: c.1, blue: c.2) }
    static func name(_ i: Int) -> String {
        [T("Жёлтый"), T("Розовый"), T("Зелёный"), T("Голубой"), T("Оранжевый"), T("Сиреневый")][abs(i) % count]
    }
}

// MARK: Хранилище

final class StickerStore: ObservableObject {
    static let shared = StickerStore()
    private static let key = "stickers.data"
    @Published var list: [Sticker] = []
    private var saveWork: DispatchWorkItem?

    init() {
        if let d = UserDefaults.standard.data(forKey: StickerStore.key),
           let l = try? JSONDecoder().decode([Sticker].self, from: d) { list = l }
    }

    func sticker(_ id: UUID) -> Sticker? { list.first { $0.id == id } }

    func update(_ id: UUID, _ change: (inout Sticker) -> Void) {
        guard let i = list.firstIndex(where: { $0.id == id }) else { return }
        change(&list[i])
        scheduleSave()
    }

    func scheduleSave() {
        saveWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: w)
    }

    func saveNow() {
        saveWork?.cancel()
        if let d = try? JSONEncoder().encode(list) { UserDefaults.standard.set(d, forKey: StickerStore.key) }
    }
}

// MARK: Окна на экране

/// Первое нажатие по неактивному окну сразу попадает в стикер (без «холостого» щелчка), поэтому перетаскивать можно с первого раза
private final class FirstMouseHost<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private final class StickerPanel: NSPanel {
    var stickerID: UUID?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// ⌘V / ⌃V (и с ⇧) на стикере, когда строка не правится: из буфера обмена создаётся новая строка
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let f = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if event.keyCode == 9, !f.contains(.option), f.contains(.command) || f.contains(.control),
           !(firstResponder is NSText), let id = stickerID {
            StickerManager.shared.pasteLine(id)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

final class StickerManager: NSObject, NSWindowDelegate {
    static let shared = StickerManager()
    private let store = StickerStore.shared
    private var panels: [UUID: StickerPanel] = [:]
    private var timer: Timer?
    private var beepsLeft: [UUID: Int] = [:]
    private static let minSize = NSSize(width: 180, height: 120)

    /// Уровень «над значками рабочего стола, под окнами программ»
    private static var level: NSWindow.Level { NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1) }

    /// При запуске: наклеить всё, что было наклеено, и начать следить за напоминаниями
    func start() {
        for s in store.list where s.onScreen { showPanel(s.id) }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.applyCleanSpace()
            self?.checkReminders()
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.cleanSpaceSoon()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.checkReminders() }
    }

    // MARK: действия

    func newSticker(color: Int? = nil) {
        var s = Sticker()
        // без выбора цвета берётся следующий по кругу после последнего созданного: стикеры получаются разноцветными
        s.color = color ?? ((store.list.last?.color ?? -1) + 1) % StickerPalette.count
        store.list.append(s)
        store.saveNow()
        showPanel(s.id, focusFirst: true)
    }

    func stick(_ id: UUID) {
        store.update(id) { $0.onScreen = true }
        showPanel(id)
    }

    /// Убирает стикер с экрана (он остаётся в инструменте); спрашивает подтверждение
    func unstick(_ id: UUID, confirm: Bool = true) {
        if confirm {
            NSApp.activate(ignoringOtherApps: true)
            let a = NSAlert()
            a.messageText = T("Убрать стикер с экрана?")
            a.informativeText = T("Он останется в списке инструмента «Стикеры», его можно наклеить снова.")
            a.addButton(withTitle: T("Убрать"))
            a.addButton(withTitle: T("Отмена"))
            guard a.runModal() == .alertFirstButtonReturn else { return }
        }
        store.update(id) { $0.onScreen = false }
        closePanel(id)
        store.saveNow()
    }

    /// Удаляет стикер совсем; спрашивает подтверждение
    func delete(_ id: UUID) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = T("Удалить стикер?")
        a.informativeText = T("Стикер и его записи будут удалены без возможности восстановления.")
        a.alertStyle = .warning
        a.addButton(withTitle: T("Удалить"))
        a.addButton(withTitle: T("Отмена"))
        guard a.runModal() == .alertFirstButtonReturn else { return }
        closePanel(id)
        TimerHub.shared.syncStickerReminder(id, at: nil)
        store.list.removeAll { $0.id == id }
        store.saveNow()
    }

    /// Показывает стикер на экране (если его там нет — наклеивает) и подсвечивает его; вызывается и таймером
    func reveal(_ id: UUID) {
        guard store.sticker(id) != nil else { return }
        store.update(id) { $0.onScreen = true; $0.alertActive = true }
        showPanel(id)
        panels[id]?.orderFrontRegardless()
        beepsLeft[id] = 2
        NSSound(named: NSSound.Name("Glass"))?.play()
    }

    func acceptAlert(_ id: UUID) {
        store.update(id) { $0.alertActive = false; $0.remindAt = nil }
        beepsLeft[id] = nil
        store.saveNow()
        TimerHub.shared.syncStickerReminder(id, at: nil)
        TimerHub.shared.ackSticker(id)
        applyCleanSpace()
    }

    func resize(_ id: UUID, to size: NSSize) {
        guard let p = panels[id] else { return }
        let w = min(max(size.width, StickerManager.minSize.width), 600)
        let h = min(max(size.height, StickerManager.minSize.height), 800)
        let top = p.frame.maxY
        p.setFrame(NSRect(x: p.frame.minX, y: top - h, width: w, height: h), display: true)
    }

    func panelSize(_ id: UUID) -> NSSize? { panels[id]?.frame.size }

    /// Стикер, который сейчас принимает клавиши (по нему щёлкнули мышью)
    func keyStickerID() -> UUID? { panels.first { $0.value.isKeyWindow }?.key }

    /// Вставка из буфера обмена в стикер напрямую (из списка истории): в правящуюся строку — текстом, иначе новой строкой
    func insertFromClipboard(_ id: UUID) {
        guard let p = panels[id] else { return }
        p.makeKey()
        if let t = p.firstResponder as? NSText { t.paste(nil) } else { pasteLine(id) }
    }

    /// Новая строка стикера из буфера обмена: переводы строк и повторные пробелы сжимаются, длинное обрезается (до 200 символов, в конце «…»)
    func pasteLine(_ id: UUID) {
        let raw = NSPasteboard.general.string(forType: .string) ?? ""
        var t = raw.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        if t.isEmpty { NSSound.beep(); return }
        if t.count > StickerItem.maxLength { t = String(t.prefix(StickerItem.maxLength - 1)) + "…" }
        store.update(id) { s in
            if let last = s.items.last, last.text.trimmingCharacters(in: .whitespaces).isEmpty { s.items[s.items.count - 1].text = t }
            else { s.items.append(StickerItem(text: t)) }
        }
    }

    // MARK: напоминания

    private func checkReminders() {
        let now = Date()
        for s in store.list {
            // если напоминание ведёт таймер (оно есть в его списке), сигнал даёт он
            if TimerHub.shared.enabled && TimerHub.shared.hasOwnReminder(s.id) { continue }
            if let at = s.remindAt, at <= now, !s.alertActive {
                reveal(s.id)
                if TimerHub.shared.enabled { TimerHub.shared.stickerFired(s.title) }
            } else if s.alertActive, let n = beepsLeft[s.id], n > 0 {
                beepsLeft[s.id] = n - 1
                NSSound(named: NSSound.Name("Glass"))?.play()
            }
        }
    }

    // MARK: окна

    private func defaultOrigin(_ size: NSSize) -> NSPoint {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let n = CGFloat(panels.count % 8)
        return NSPoint(x: screen.visibleFrame.maxX - size.width - 24 - n * 26,
                       y: screen.visibleFrame.maxY - size.height - 24 - n * 26)
    }

    private func showPanel(_ id: UUID, focusFirst: Bool = false) {
        guard let s = store.sticker(id) else { return }
        if let p = panels[id] { p.orderFrontRegardless(); return }
        var frame = NSRect(x: s.x, y: s.y, width: s.w, height: s.h)
        let visible = NSScreen.screens.contains { $0.visibleFrame.intersects(frame.insetBy(dx: 30, dy: 30)) }
        if !s.placed || !visible { frame.origin = defaultOrigin(frame.size) }
        let p = StickerPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = StickerManager.level
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]       // на всех рабочих столах, кроме «чистых»
        p.isMovableByWindowBackground = false          // двигается за шапку и фон стикера (жест в карточке)
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.delegate = self
        p.stickerID = id
        p.contentView = FirstMouseHost(rootView: LangRefresh { StickerCardView(id: id, startEditing: focusFirst) })
        p.setFrame(frame, display: false)
        panels[id] = p
        store.update(id) { $0.x = frame.minX; $0.y = frame.minY; $0.placed = true }
        p.orderFrontRegardless()
        if !focusFirst { applyCleanSpace() }
        if focusFirst { p.makeKey() }
    }

    // MARK: «чистые» рабочие столы

    private static let cleanKey = "stickers.cleanSpaces"
    /// Рабочие столы (постоянные uuid), на которых стикеры не показываются
    static var cleanSpaces: [String] {
        get { UserDefaults.standard.stringArray(forKey: cleanKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: cleanKey) }
    }

    /// На «чистом» столе стикеры прячутся (кроме сработавшего напоминания), на остальных показываются
    func applyCleanSpace() {
        guard Spaces.available else { return }
        let clean = Spaces.currentUUID().map { StickerManager.cleanSpaces.contains($0) } ?? false
        for (id, p) in panels {
            let alert = store.sticker(id)?.alertActive == true
            if clean && !alert { if p.isVisible { p.orderOut(nil) } }
            else if !p.isVisible { p.orderFrontRegardless() }
        }
    }

    private func cleanSpaceSoon() {
        for d in [0.2, 0.8] { DispatchQueue.main.asyncAfter(deadline: .now() + d) { [weak self] in self?.applyCleanSpace() } }
    }

    // MARK: движение

    func panelOrigin(_ id: UUID) -> NSPoint? { panels[id]?.frame.origin }
    func setOrigin(_ id: UUID, _ o: NSPoint) { panels[id]?.setFrameOrigin(o) }

    private func closePanel(_ id: UUID) {
        guard let p = panels.removeValue(forKey: id) else { return }
        p.delegate = nil
        p.orderOut(nil)
    }

    private func id(of window: NSWindow?) -> UUID? { panels.first { $0.value === window }?.key }

    func windowDidMove(_ n: Notification) { remember(n.object as? NSWindow) }
    func windowDidResize(_ n: Notification) { remember(n.object as? NSWindow) }
    private func remember(_ w: NSWindow?) {
        guard let w = w, let id = id(of: w) else { return }
        store.update(id) { $0.x = w.frame.minX; $0.y = w.frame.minY; $0.w = w.frame.width; $0.h = w.frame.height; $0.placed = true }
    }
}

// MARK: Стикер на экране

struct StickerCardView: View {
    let id: UUID
    var startEditing = false
    @ObservedObject private var store = StickerStore.shared
    @State private var editing: UUID? = nil
    @FocusState private var focus: UUID?
    @State private var showRemind = false
    @State private var remindDate = Date().addingTimeInterval(3600)
    @State private var hover: UUID? = nil
    @State private var resizeStart: (mouse: NSPoint, size: NSSize)? = nil
    @State private var pulse = false
    @State private var dragStart: (mouse: NSPoint, origin: NSPoint)? = nil

    private let ink = Color.black.opacity(0.85)

    var body: some View {
        Group {
            if let s = store.sticker(id) { card(s) } else { Color.clear }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if startEditing, let s = store.sticker(id), let f = s.items.first { startEdit(f.id) }
        }
    }

    private func card(_ s: Sticker) -> some View {
        VStack(spacing: 0) {
            header(s)
            if s.alertActive { banner }
            if showRemind { remindPanel(s) } else { lines(s) }
        }
        .background(StickerPalette.paperColor(s.color).contentShape(Rectangle()).gesture(moveGesture))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.red, lineWidth: s.alertActive ? 3 : 0)
                .opacity(pulse ? 0.25 : 1)
        )
        .overlay(grip, alignment: .bottomTrailing)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .environment(\.colorScheme, .light)
        .onChange(of: s.alertActive) { on in
            if on { withAnimation(Animation.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { pulse = true } }
            else { withAnimation(.default) { pulse = false } }
        }
        .onAppear {
            if s.alertActive { withAnimation(Animation.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { pulse = true } }
        }
    }

    // MARK: шапка

    private func header(_ s: Sticker) -> some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(0..<StickerPalette.count, id: \.self) { i in
                    Button(StickerPalette.name(i)) { store.update(id) { $0.color = i } }
                }
            } label: {
                Image(systemName: "paintpalette").font(.system(size: 11))
            }
            .menuStyle(BorderlessButtonMenuStyle())
            .fixedSize()
            .help(T("Цвет стикера"))
            Button {
                let on = s.blurred != true
                if on { editing = nil; focus = nil; showRemind = false }
                withAnimation(.easeInOut(duration: 0.2)) { store.update(id) { $0.blurred = on } }
            } label: {
                Image(systemName: s.blurred == true ? "eye.slash" : "eye").font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .help(s.blurred == true ? T("Показать записи") : T("Скрыть записи (размыть)"))
            Spacer()
            Button {
                remindDate = s.remindAt.flatMap { $0 > Date() ? $0 : nil } ?? Date().addingTimeInterval(3600)
                showRemind.toggle()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: s.remindAt != nil ? "bell.fill" : "bell").font(.system(size: 11))
                    if let at = s.remindAt {
                        Text(at.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 10))
                    }
                }
                .foregroundColor(s.alertActive ? .red : ink)
            }
            .buttonStyle(.plain)
            .help(T("Напомнить об этом стикере"))
            Button { StickerManager.shared.unstick(id) } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .help(T("Убрать с экрана"))
        }
        .foregroundColor(ink)
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(StickerPalette.stripColor(s.color).contentShape(Rectangle()).gesture(moveGesture))
    }

    private var banner: some View {
        HStack {
            Image(systemName: "bell.fill").foregroundColor(.red)
            Text(T("Напоминание")).font(.system(size: 12, weight: .semibold)).foregroundColor(ink)
            Spacer()
            Button(T("Принять")) { StickerManager.shared.acceptAlert(id) }.controlSize(.small)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.red.opacity(0.15))
    }

    // MARK: напоминание

    private func remindPanel(_ s: Sticker) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(T("Напомнить о стикере")).font(.system(size: 12, weight: .semibold)).foregroundColor(ink)
            DatePicker("", selection: $remindDate, displayedComponents: [.date, .hourAndMinute]).labelsHidden()
            HStack(spacing: 6) {
                Button(T("через час")) { remindDate = Date().addingTimeInterval(3600) }
                Button(T("завтра в 9:00")) {
                    let cal = Calendar.current
                    let tomorrow = cal.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                    remindDate = cal.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
                }
            }
            .controlSize(.small)
            Text(T("В это время стикер сам появится на экране, если его там нет.")).font(.system(size: 10)).foregroundColor(ink.opacity(0.7))
            HStack {
                Button(T("Установить")) {
                    guard remindDate > Date() else { NSSound.beep(); return }
                    store.update(id) { $0.remindAt = remindDate; $0.alertActive = false }
                    TimerHub.shared.syncStickerReminder(id, at: remindDate)       // то же напоминание видно во вкладке таймера
                    showRemind = false
                }
                if s.remindAt != nil {
                    Button(T("Убрать")) { StickerManager.shared.acceptAlert(id); showRemind = false }
                }
                Spacer()
                Button(T("Закрыть")) { showRemind = false }
            }
            .controlSize(.small)
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: строки

    private func lines(_ s: Sticker) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(s.items) { it in row(it) }
                Button {
                    addLine(after: s.items.last?.id)
                } label: {
                    Label(T("Строка"), systemImage: "plus").font(.system(size: 11)).foregroundColor(ink.opacity(0.55))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
            .padding(.horizontal, 9).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // «глаз»: записи размазаны и недоступны, пока их не покажут той же кнопкой
        .blur(radius: s.blurred == true ? 7 : 0)
        .allowsHitTesting(s.blurred != true)
        .clipped()
    }

    private func row(_ it: StickerItem) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Button { toggle(it.id) } label: {
                Image(systemName: it.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12))
                    .foregroundColor(ink.opacity(it.done ? 0.5 : 0.7))
            }
            .buttonStyle(.plain)
            .padding(.top, 1)
            .help(it.done ? T("Вернуть строку") : T("Зачеркнуть"))
            if editing == it.id {
                TextField("", text: textBinding(it.id), onCommit: { commit(it.id) })
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 13))
                    .foregroundColor(ink)
                    .focused($focus, equals: it.id)
            } else {
                Text(it.text.isEmpty ? " " : it.text)
                    .font(.system(size: 13))
                    .strikethrough(it.done)
                    .foregroundColor(it.done ? ink.opacity(0.4) : ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentShape(Rectangle())
                    .onTapGesture { startEdit(it.id) }
            }
            Button { removeLine(it.id) } label: {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundColor(ink.opacity(0.45))
            }
            .buttonStyle(.plain)
            .opacity(hover == it.id ? 1 : 0)
            .padding(.top, 3)
            .help(T("Удалить строку"))
        }
        .onHover { inside in hover = inside ? it.id : (hover == it.id ? nil : hover) }
    }

    // MARK: правка

    private func textBinding(_ iid: UUID) -> Binding<String> {
        Binding(get: { store.sticker(id)?.items.first { $0.id == iid }?.text ?? "" },
                set: { v in store.update(id) { s in if let k = s.items.firstIndex(where: { $0.id == iid }) { s.items[k].text = String(v.prefix(StickerItem.maxLength)) } } })
    }

    private func startEdit(_ iid: UUID) {
        editing = iid
        DispatchQueue.main.async { focus = iid }
    }

    private func toggle(_ iid: UUID) {
        store.update(id) { s in if let k = s.items.firstIndex(where: { $0.id == iid }) { s.items[k].done.toggle() } }
    }

    private func addLine(after iid: UUID?) {
        let n = StickerItem()
        store.update(id) { s in
            if let iid = iid, let k = s.items.firstIndex(where: { $0.id == iid }) { s.items.insert(n, at: k + 1) }
            else { s.items.append(n) }
        }
        startEdit(n.id)
    }

    /// Enter заканчивает правку строки (новая строка добавляется кнопкой «+ Строка»)
    private func commit(_ iid: UUID) {
        editing = nil
        focus = nil
        prune()
    }

    private func removeLine(_ iid: UUID) {
        store.update(id) { s in
            s.items.removeAll { $0.id == iid }
            if s.items.isEmpty { s.items = [StickerItem()] }
        }
        if editing == iid { editing = nil }
    }

    /// Пустые строки, кроме последней единственной и той, что сейчас правится, убираются
    private func prune() {
        let keep = editing
        store.update(id) { s in
            let kept = s.items.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty || $0.id == keep }
            s.items = kept.isEmpty ? [s.items.first ?? StickerItem()] : kept
        }
    }

    // MARK: перемещение

    /// Стикер двигается, если потянуть за шапку или за свободное место на бумаге
    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { _ in
                let m = NSEvent.mouseLocation
                if dragStart == nil, let o = StickerManager.shared.panelOrigin(id) { dragStart = (m, o) }
                guard let st = dragStart else { return }
                StickerManager.shared.setOrigin(id, NSPoint(x: st.origin.x + (m.x - st.mouse.x), y: st.origin.y + (m.y - st.mouse.y)))
            }
            .onEnded { _ in dragStart = nil }
    }

    // MARK: размер

    private var grip: some View {
        Image(systemName: "chevron.down.right")
            .font(.system(size: 8, weight: .bold))
            .foregroundColor(ink.opacity(0.35))
            .padding(4)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    let m = NSEvent.mouseLocation
                    if resizeStart == nil, let sz = StickerManager.shared.panelSize(id) { resizeStart = (m, sz) }
                    guard let st = resizeStart else { return }
                    StickerManager.shared.resize(id, to: NSSize(width: st.size.width + (m.x - st.mouse.x),
                                                                height: st.size.height - (m.y - st.mouse.y)))
                }
                .onEnded { _ in resizeStart = nil })
            .help(T("Потяните, чтобы изменить размер"))
    }
}

// MARK: - Инструмент «Стикеры»

final class StickersController: NSObject, NSWindowDelegate {
    static let shared = StickersController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 520),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 400, height: 380)
            w.contentView = NSHostingView(rootView: LangRefresh { StickersListView() })
            w.delegate = self
            if !w.setFrameUsingName("StickersWindow") { w.center() }
            w.setFrameAutosaveName("StickersWindow")
            window = w
            NotificationCenter.default.addObserver(self, selector: #selector(languageChanged), name: .languageChanged, object: nil)
        }
        window?.title = T("Стикеры")
        NSApp.windows.compactMap { $0 as? PopupWindow }.forEach { $0.orderOut(nil) }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func languageChanged() { window?.title = T("Стикеры") }
}

struct StickersListView: View {
    @ObservedObject private var store = StickerStore.shared
    @State private var spaceTick = 0

    private func cleanBinding(_ uuid: String) -> Binding<Bool> {
        Binding(get: { StickerManager.cleanSpaces.contains(uuid) },
                set: { on in
                    var a = StickerManager.cleanSpaces.filter { $0 != uuid }
                    if on { a.append(uuid) }
                    StickerManager.cleanSpaces = a
                    StickerManager.shared.applyCleanSpace()
                    spaceTick += 1
                })
    }

    /// Рабочие столы, на которых стикеров быть не должно (например, пустой)
    private var cleanSpacesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(T("Чистые рабочие столы")).fontWeight(.semibold)
            Text(T("На отмеченных столах стикеры не показываются; на остальных видны. Сработавшее напоминание всё равно покажет свой стикер."))
                .font(.caption).foregroundColor(.secondary)
            ForEach(Spaces.list(), id: \.uuid) { sp in
                Toggle(sp.title + (sp.uuid == Spaces.currentUUID() ? " — " + T("текущий") : ""), isOn: cleanBinding(sp.uuid))
            }
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)) { _ in spaceTick += 1 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Menu {
                    Button(T("Любого цвета")) { StickerManager.shared.newSticker() }
                    Divider()
                    ForEach(0..<StickerPalette.count, id: \.self) { i in
                        Button(StickerPalette.name(i)) { StickerManager.shared.newSticker(color: i) }
                    }
                } label: {
                    Label(T("Новый стикер"), systemImage: "plus")
                }
                .fixedSize()
                Spacer()
                Text(Tf("Всего стикеров: %@", "\(store.list.count)")).font(.caption).foregroundColor(.secondary)
            }
            Text(T("Наклеенный стикер лежит на рабочем столе там, куда вы его поставили, пока запущен «Пуск», и виден на всех рабочих столах. Потяните за шапку или за свободное место, чтобы передвинуть его. «×» на стикере убирает его с экрана, а здесь он сохраняется, пока вы его не удалите. Колокольчик на стикере — напомнить в нужное время: стикер сам появится на экране."))
                .font(.caption).foregroundColor(.secondary)
            if Spaces.available { cleanSpacesSection.id(spaceTick) }
            if store.list.isEmpty {
                Spacer()
                Text(T("Стикеров пока нет. Нажмите «Новый стикер»."))
                    .foregroundColor(.secondary).frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(store.list.sorted { $0.created > $1.created }) { s in row(s) }
                    }
                }
            }
        }
        .padding(16)
    }

    private func row(_ s: Sticker) -> some View {
        let done = s.items.filter { $0.done }.count
        let filled = s.items.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }.count
        return HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 3).fill(StickerPalette.paperColor(s.color))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.black.opacity(0.15)))
                .frame(width: 22, height: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.title).lineLimit(2)
                HStack(spacing: 8) {
                    Text(Tf("Строк: %@, зачёркнуто: %@", "\(filled)", "\(done)"))
                    if let at = s.remindAt {
                        Label(at.formatted(date: .abbreviated, time: .shortened), systemImage: "bell")
                            .foregroundColor(s.alertActive ? .red : .secondary)
                    }
                    if s.onScreen { Label(T("на экране"), systemImage: "pin") }
                }
                .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Button(s.onScreen ? T("Показать") : T("Наклеить")) { StickerManager.shared.stick(s.id) }
                .controlSize(.small)
            if s.onScreen {
                Button(T("Снять")) { StickerManager.shared.unstick(s.id) }.controlSize(.small)
            }
            Button { StickerManager.shared.delete(s.id) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless).help(T("Удалить"))
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
    }
}


// MARK: - Рабочие столы (Spaces)
//
// Публичного способа узнать, какой рабочий стол сейчас открыт, в macOS нет, поэтому используются системные функции SkyLight.
// Они нужны только для «чистых» рабочих столов; если их нет в этой версии macOS, стикеры показываются на всех столах.

struct DesktopSpace {
    let id: Int
    let uuid: String
    let number: Int
    let display: Int
    let displayCount: Int
    var title: String {
        displayCount > 1 ? Tf("Экран %@, рабочий стол %@", "\(display)", "\(number)") : Tf("Рабочий стол %@", "\(number)")
    }
}

enum Spaces {
    private typealias MainConn = @convention(c) () -> Int32
    private typealias ActiveSpace = @convention(c) (Int32) -> Int
    private typealias CopyDisplays = @convention(c) (Int32) -> Unmanaged<CFArray>?

    private static let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

    private static func find(_ names: [String]) -> UnsafeMutableRawPointer? {
        for n in names {
            if let h = handle, let p = dlsym(h, n) { return p }
            if let p = dlsym(UnsafeMutableRawPointer(bitPattern: -2), n) { return p }      // RTLD_DEFAULT
        }
        return nil
    }

    private static let mainConn: MainConn? = find(["SLSMainConnectionID", "CGSMainConnectionID"]).map { unsafeBitCast($0, to: MainConn.self) }
    private static let activeSpace: ActiveSpace? = find(["SLSGetActiveSpace", "CGSGetActiveSpace"]).map { unsafeBitCast($0, to: ActiveSpace.self) }
    private static let copyDisplays: CopyDisplays? = find(["SLSCopyManagedDisplaySpaces", "CGSCopyManagedDisplaySpaces"]).map { unsafeBitCast($0, to: CopyDisplays.self) }

    static var available: Bool {
        mainConn != nil && activeSpace != nil && copyDisplays != nil && !list().isEmpty
    }

    private static var cid: Int32 { mainConn?() ?? 0 }

    /// Обычные рабочие столы (полноэкранные программы не считаются) по порядку, по каждому экрану
    static func list() -> [DesktopSpace] {
        guard let copy = copyDisplays, let arr = copy(cid)?.takeRetainedValue() as? [[String: Any]] else { return [] }
        var out: [DesktopSpace] = []
        for (di, d) in arr.enumerated() {
            var n = 0
            for sp in (d["Spaces"] as? [[String: Any]]) ?? [] {
                guard (sp["type"] as? Int ?? 0) == 0, let id = (sp["ManagedSpaceID"] as? Int) ?? (sp["id64"] as? Int) else { continue }
                n += 1
                let raw = sp["uuid"] as? String ?? ""
                out.append(DesktopSpace(id: id, uuid: raw.isEmpty ? "pos-\(di + 1)-\(n)" : raw, number: n, display: di + 1, displayCount: arr.count))
            }
        }
        return out
    }

    static func currentUUID() -> String? {
        guard let a = activeSpace else { return nil }
        let id = a(cid)
        return list().first { $0.id == id }?.uuid
    }


}
