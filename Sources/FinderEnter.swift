import Cocoa

// MARK: - Enter в Finder открывает файл
//
// В Finder Enter включает переименование. Здесь, пока Finder активен, Enter (и Enter на цифровой клавиатуре)
// превращается в «Файл → Открыть» (⌘O): файлы запускаются, папки открываются, как в Windows.
// ⇧Enter пропускается как обычный Enter, то есть включает переименование. Поля ввода (переименование, поиск),
// диалоги и листы Finder («Заменить?», «Подключение к серверу»…) не затрагиваются: там Enter остаётся обычным.
// Для перехвата клавиш нужен доступ «Управление устройством и доступ к данным» (в ранних версиях macOS: «Универсальный доступ»).

final class FinderEnter {
    static let shared = FinderEnter()
    private static let marker: Int64 = 0x53464D45          // метка своих событий, чтобы не перехватывать их же

    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "finder.enter") as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: "finder.enter") }
    }

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    func setEnabled(_ on: Bool) {
        on ? start() : stop()
    }

    func start() {
        guard tap == nil else { return }
        guard AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) else { return }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: mask,
                                        callback: { _, type, event, _ in FinderEnter.shared.handle(type, event) },
                                        userInfo: nil) else { return }
        tap = t
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
    }

    func stop() {
        if let t = tap { CGEvent.tapEnable(tap: t, enable: false) }
        if let s = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
        tap = nil
        source = nil
    }

    /// Курсор в текстовом поле (переименование, поиск): тогда Enter обычный
    private func editingText() -> Bool {
        let sys = AXUIElementCreateSystemWide()
        guard let el = WindowFinder.attr(sys, kAXFocusedUIElementAttribute) else { return false }
        let role = WindowFinder.attr(el as! AXUIElement, kAXRoleAttribute) as? String
        return role == kAXTextFieldRole || role == kAXTextAreaRole || role == kAXComboBoxRole || role == "AXSearchField"
    }

    /// Окно Finder обычное (или это рабочий стол): без диалогов и листов, где Enter нажимает кнопку по умолчанию
    private func ordinaryWindow(_ pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        guard let w = WindowFinder.attr(app, kAXFocusedWindowAttribute) else { return true }     // рабочий стол
        let win = w as! AXUIElement
        if let sub = WindowFinder.attr(win, kAXSubroleAttribute) as? String, sub != "AXStandardWindow" { return false }
        if let kids = WindowFinder.attr(win, kAXChildrenAttribute) as? [AXUIElement],
           kids.contains(where: { (WindowFinder.attr($0, kAXRoleAttribute) as? String) == "AXSheet" }) { return false }
        return true
    }

    private func post(_ key: CGKeyCode, _ flags: CGEventFlags) {
        let src = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: down) else { continue }
            e.flags = flags
            e.setIntegerValueField(.eventSourceUserData, value: FinderEnter.marker)
            e.post(tap: .cghidEventTap)
        }
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
            return pass
        }
        guard type == .keyDown,
              event.getIntegerValueField(.eventSourceUserData) != FinderEnter.marker else { return pass }
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        guard key == 36 || key == 76 else { return pass }                    // Return или Enter на цифровой клавиатуре
        let mods = event.flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl])
        guard mods.isEmpty || mods == .maskShift else { return pass }
        guard let front = NSWorkspace.shared.frontmostApplication, front.bundleIdentifier == "com.apple.finder" else { return pass }
        if editingText() || !ordinaryWindow(front.processIdentifier) { return pass }
        if mods == .maskShift {
            post(36, [])                                                     // ⇧Enter — обычный Enter: переименование
        } else {
            post(31, .maskCommand)                                           // ⌘O — «Открыть»
        }
        return nil
    }
}
