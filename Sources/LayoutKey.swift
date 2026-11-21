import Cocoa
import Carbon

/// Своя клавиша переключения раскладки (Globe/fn): работает независимо от автоматического переключателя
final class LayoutKey {
    static let shared = LayoutKey()

    /// "off" — системная, "fn" — Globe/fn
    static var kind: String {
        get { UserDefaults.standard.string(forKey: "layout.sw.kind") ?? "off" }
        set { UserDefaults.standard.set(newValue, forKey: "layout.sw.kind") }
    }

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var retry: Timer?
    private var fnDown = false
    private var fnUsed = false

    /// Применить текущие настройки (при запуске и при любом изменении)
    func apply() {
        if LayoutKey.kind == "fn" { startTap() } else { stopTap() }
    }

    private func startTap() {
        guard tap == nil else { return }
        // чтобы видеть нажатие Globe/fn, нужен доступ «Управление устройством и доступ к данным»: просим сразу
        guard AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) else {
            retry?.invalidate()
            var tries = 0
            retry = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] t in
                tries += 1
                if AXIsProcessTrusted() { t.invalidate(); self?.retry = nil; if LayoutKey.kind == "fn" { self?.startTap() } }
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
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
            return pass
        }
        if type == .keyDown {
            if fnDown { fnUsed = true }                     // fn + другая клавиша — это не переключение
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
