import Cocoa

// MARK: - Delete в Finder отправляет файлы в Корзину
//
// В Finder в Корзину файлы отправляет только ⌘⌫. Здесь, пока Finder активен, обычный Delete (⌫ и ⌦) превращается в ⌘⌫,
// как в Windows. Поля ввода (переименование, поиск), диалоги и листы Finder не затрагиваются: там Delete остаётся обычным.
// Файлы не удаляются насовсем: они попадают в Корзину, как при ⌘⌫. Для перехвата клавиш нужен доступ
// «Управление устройством и доступ к данным» (в ранних версиях macOS: «Универсальный доступ»).

final class FinderDelete {
    static let shared = FinderDelete()
    private static let marker: Int64 = 0x53464D44          // метка своих событий, чтобы не перехватывать их же

    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "finder.delete") as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: "finder.delete") }
    }

    /// ⇧Delete — удалить мимо Корзины (⌥⌘⌫; Finder сам спросит подтверждение)
    static var shiftEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "finder.deleteNow") as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: "finder.deleteNow") }
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
                                        callback: { _, type, event, _ in FinderDelete.shared.handle(type, event) },
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
            e.setIntegerValueField(.eventSourceUserData, value: FinderDelete.marker)
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
              event.getIntegerValueField(.eventSourceUserData) != FinderDelete.marker else { return pass }
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        guard key == 51 || key == 117 else { return pass }                   // ⌫ или ⌦
        let mods = event.flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl])
        guard mods.isEmpty || mods == .maskShift else { return pass }
        if mods.isEmpty && !FinderDelete.enabled { return pass }
        if mods == .maskShift && !FinderDelete.shiftEnabled { return pass }
        guard let front = NSWorkspace.shared.frontmostApplication, front.bundleIdentifier == "com.apple.finder" else { return pass }
        if editingText() || !ordinaryWindow(front.processIdentifier) { return pass }
        if mods == .maskShift {
            post(51, [.maskCommand, .maskAlternate])                         // ⌥⌘⌫ — «Удалить немедленно» (с вопросом Finder)
        } else {
            post(51, .maskCommand)                                           // ⌘⌫ — «Переместить в Корзину»
        }
        return nil
    }
}
