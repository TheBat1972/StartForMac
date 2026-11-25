import Cocoa

// MARK: - Блокировка экрана
//
// Кнопка «Заблокировать экран» под «Свернуть все окна» на главном экране. Вызывает ту же функцию системы, что и меню
// → «Заблокировать экран»; если её не нашли, нажимает ⌃⌘Q (стандартное сочетание блокировки, нужен Accessibility).

enum ScreenLock {
    static func lock() {
        if let h = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY),
           let f = dlsym(h, "SACLockScreenImmediate") {
            typealias Fn = @convention(c) () -> Int32
            _ = unsafeBitCast(f, to: Fn.self)()
            return
        }
        let src = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: 12, keyDown: down)
            e?.flags = [.maskControl, .maskCommand]
            e?.post(tap: .cghidEventTap)
        }
    }
}

// MARK: - Выключить / Перезагрузить
//
// Кнопка внизу меню открывает меню: перезагрузить, выключить (системные окна, как ⌃⏏) или сон.
// Окно показывает сам macOS: команда «показать диалог выключения» отправляется программе loginwindow.

enum PowerMenu {
    private static let handler = PowerMenuHandler()
    /// Маленькое меню у курсора: перезагрузка / выключение (системные окна с подтверждением) / сон.
    static func show() {
        let m = NSMenu()
        for (title, code) in [(T("Перезагрузить…"), "rrst"), (T("Выключить…"), "rsdn"), (T("Сон"), "sleep")] {
            let it = NSMenuItem(title: title, action: #selector(PowerMenuHandler.pick(_:)), keyEquivalent: "")
            it.target = handler
            it.representedObject = code
            m.addItem(it)
        }
        // меню открывается вверх от курсора: верхний край = курсор + высота меню (координаты экрана, начало внизу слева)
        var pt = NSEvent.mouseLocation
        pt.y += m.size.height + 4
        m.popUp(positioning: nil, at: pt, in: nil)
    }
    static func send(_ code: String) {
        let p = Process()
        if code == "sleep" {
            p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            p.arguments = ["sleepnow"]
        } else {
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", "tell application \"loginwindow\" to «event aevt\(code)»"]
        }
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }
}

final class PowerMenuHandler: NSObject {
    @objc func pick(_ s: NSMenuItem) { if let c = s.representedObject as? String { PowerMenu.send(c) } }
}
