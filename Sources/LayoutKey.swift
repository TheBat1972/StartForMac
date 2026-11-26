import Cocoa
import Carbon

/// Своя клавиша переключения раскладки (Globe/fn или Control+Shift): работает независимо от автоматического переключателя
final class LayoutKey {
    static let shared = LayoutKey()

    /// "off" — системная, "fn" — Globe/fn, "ctrlshift" — Control+Shift, нажатые вместе и отпущенные без других клавиш
    static var kind: String {
        get { UserDefaults.standard.string(forKey: "layout.sw.kind") ?? "off" }
        set { UserDefaults.standard.set(newValue, forKey: "layout.sw.kind") }
    }

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var retry: Timer?
    private var fnDown = false
    private var fnUsed = false
    private var csDown = false                             // Control и Shift зажаты вместе
    private var csUsed = false                             // пока они зажаты, нажато что-то ещё

    /// Применить текущие настройки (при запуске и при любом изменении)
    func apply() {
        if LayoutKey.kind == "fn" || LayoutKey.kind == "ctrlshift" { startTap() } else { stopTap() }
    }

    private func startTap() {
        guard tap == nil else { return }
        // чтобы видеть нажатие Globe/fn, нужен доступ «Управление устройством и доступ к данным»: просим сразу
        guard AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) else {
            retry?.invalidate()
            var tries = 0
            retry = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] t in
                tries += 1
                if AXIsProcessTrusted() { t.invalidate(); self?.retry = nil; if LayoutKey.kind == "fn" || LayoutKey.kind == "ctrlshift" { self?.startTap() } }
                else if tries > 200 { t.invalidate(); self?.retry = nil }
            }
            return
        }
        let mask = CGEventMask((1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue))
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: mask,
                                        callback: { _, type, event, _ in LayoutKey.shared.handle(type, event) },
                                        userInfo: nil) else { return }
        tap = t
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
    }

    private func stopTap() {
        retry?.invalidate()
        retry = nil
        if let t = tap { CGEvent.tapEnable(tap: t, enable: false) }
        if let s = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
        tap = nil
        source = nil
        fnDown = false
        csDown = false
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
            return pass
        }
        if type == .keyDown {
            if fnDown { fnUsed = true }                     // fn + другая клавиша — это не переключение
            if csDown { csUsed = true }                     // Control+Shift+буква и т. п. — тоже
            return pass
        }
        if LayoutKey.kind == "ctrlshift" {
            guard type == .flagsChanged else { return pass }
            let f = event.flags
            let both = f.contains(.maskControl) && f.contains(.maskShift)
            let extra = f.contains(.maskCommand) || f.contains(.maskAlternate) || f.contains(.maskSecondaryFn)
            if both && !csDown { csDown = true; csUsed = extra }
            else if csDown && extra { csUsed = true }
            else if csDown && !both {                       // Control+Shift отпущены, ничего больше не нажималось: переключаем
                csDown = false
                if !csUsed && !extra { DispatchQueue.main.async { Kb.selectNext() } }
            }
            return pass
        }
        guard type == .flagsChanged, event.getIntegerValueField(.keyboardEventKeycode) == 63 else { return pass }
        if event.flags.contains(.maskSecondaryFn) {
            fnDown = true
            fnUsed = false
            return nil
        }
        guard fnDown else { return pass }
        fnDown = false
        if !fnUsed { DispatchQueue.main.async { Kb.selectNext() } }
        return nil
    }
}
