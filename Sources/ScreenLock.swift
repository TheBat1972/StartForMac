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
