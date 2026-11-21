import Cocoa
import Carbon

// MARK: - Автоматический переключатель раскладки
//
// Автоматически: слово, набранное не в той раскладке («ghbdtn»), после пробела / Tab / Enter заменяется на правильное
// («привет») и раскладка переключается. Решение принимает системная проверка орфографии: слово исправляется, только если
// набранный вариант не слово, а вариант в другой раскладке — слово.
// Вручную (по горячей клавише): исправляет слово, которое набирается сейчас, выделенный текст или последнее слово.
// В программах из списка исключений не работает. Всё вычисляется на этом Mac, набранный текст нигде не хранится
// (в памяти только текущее слово) и не передаётся.
// Нужен доступ «Управление устройством и доступ к данным» (в ранних версиях macOS: «Универсальный доступ»).

final class LayoutSwitcher {
    static let shared = LayoutSwitcher()
    private static let marker: Int64 = 0x53464D43          // метка своих событий, чтобы не разбирать их же

    // MARK: Настройки

    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "layout.enabled") as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: "layout.enabled") }
    }
    /// Исправлять слова автоматически (иначе только по горячей клавише)
    static var autoFix: Bool {
        get { UserDefaults.standard.object(forKey: "layout.auto") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "layout.auto") }
    }
    static let defaultExcluded = ["com.apple.Terminal", "com.googlecode.iterm2", "com.apple.dt.Xcode",
                                  "com.microsoft.VSCode", "dev.warp.Warp-Stable"]
    /// Программы (bundle id), в которых переключатель не работает
    static var excluded: [String] {
        get { UserDefaults.standard.stringArray(forKey: "layout.excluded") ?? defaultExcluded }
        set { UserDefaults.standard.set(newValue, forKey: "layout.excluded") }
    }
    static let comboFallback = Combo(keyCode: 49, mods: UInt32(controlKey | optionKey), keyTitle: "Space")
    static func loadCombo() -> Combo { Combo.load(prefix: "layout.hk", fallback: comboFallback) }


    // MARK: Состояние

    private struct Stroke { let code: CGKeyCode; let shift: Bool; let caps: Bool }
    private struct Lay { let id: String; let ru: Bool; let data: CFData; let src: TISInputSource }
    private struct LastWord { let strokes: [Stroke]; let layID: String; let boundary: CGKeyCode; let pid: pid_t }

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var retry: Timer?
    private var clickMonitor: Any?
    private var layouts: [Lay] = []
    private var layoutsStamp = Date.distantPast

    private var keys: [Stroke] = []                         // слово, которое набирается сейчас
    private var wordLayID = ""
    private var poison = false                              // в слове цифра или знак — слово не трогаем
    private var last: LastWord?                             // последнее законченное слово (для горячей клавиши)
    private var busy = false                                // идёт исправление: новые нажатия ждут
    private var deferred: [CGEvent] = []
    private let work = DispatchQueue(label: "layoutswitcher.work", qos: .userInteractive)

    private static let letterCodes: Set<CGKeyCode> = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 12, 13, 14, 15, 16, 17,
                                                      31, 32, 34, 35, 37, 38, 40, 45, 46]
    /// Клавиши знаков, которые в русской раскладке дают буквы: х ъ э ж б ю ё
    private static let punctCodes: Set<CGKeyCode> = [33, 30, 39, 41, 43, 47, 50]
    private static let digitCodes: Set<CGKeyCode> = [18, 19, 20, 21, 22, 23, 25, 26, 28, 29, 27, 24, 44, 42]

    // MARK: Включение и выключение

    func setEnabled(_ on: Bool) { on ? start() : stop() }

    func start() {
        guard tap == nil else { return }
        // доступ нужен, чтобы видеть нажатия и вносить исправления: просим сразу
        guard AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) else {
            // пользователь ещё не выдал доступ: ждём, пока выдаст, и тогда включаемся сами
            retry?.invalidate()
            var tries = 0
            retry = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] t in
                tries += 1
                if AXIsProcessTrusted() { t.invalidate(); self?.retry = nil; if LayoutSwitcher.enabled { self?.start() } }
                else if tries > 200 { t.invalidate(); self?.retry = nil }
            }
            return
        }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: mask,
                                        callback: { _, type, event, _ in LayoutSwitcher.shared.handle(type, event) },
                                        userInfo: nil) else { return }
        tap = t
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        // щелчок мышью переносит курсор в другое место: слово, которое набиралось, больше не актуально
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.resetWord()
        }
        HotKeyCenter.shared.register(LayoutSwitcher.loadCombo(), id: 16) { [weak self] in self?.manual() }
    }

    func stop() {
        retry?.invalidate()
        retry = nil
        if let t = tap { CGEvent.tapEnable(tap: t, enable: false) }
        if let s = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
        if let m = clickMonitor { NSEvent.removeMonitor(m) }
        clickMonitor = nil
        tap = nil
        source = nil
        HotKeyCenter.shared.unregister(id: 16)
        resetWord()
        last = nil
        busy = false
        deferred = []
    }

    /// Сочетание для ручного исправления изменили в настройках
    func reregisterHotkey() {
        guard tap != nil else { return }
        HotKeyCenter.shared.register(LayoutSwitcher.loadCombo(), id: 16) { [weak self] in self?.manual() }
    }

    private func resetWord() {
        keys = []
        poison = false
        last = nil
    }

    // MARK: Раскладки

    private func loadLayouts() -> [Lay] {
        if Date().timeIntervalSince(layoutsStamp) < 3, !layouts.isEmpty { return layouts }
        var out: [Lay] = []
        for s in Kb.selectable() {
            guard let p = TISGetInputSourceProperty(s, kTISPropertyUnicodeKeyLayoutData) else { continue }
            let data = Unmanaged<CFData>.fromOpaque(p).takeUnretainedValue()
            let lang = Kb.lang(s)
            let id = Kb.string(s, kTISPropertyInputSourceID) ?? ""
            if lang == "ru" { out.append(Lay(id: id, ru: true, data: data, src: s)) }
            else if lang.hasPrefix("en") { out.append(Lay(id: id, ru: false, data: data, src: s)) }
        }
        layouts = out
        layoutsStamp = Date()
        return out
    }

    private func lay(_ id: String) -> Lay? { loadLayouts().first { $0.id == id } }
    /// Раскладка «с другой стороны»: для русской — английская, для английской — русская
    private func other(_ l: Lay) -> Lay? { loadLayouts().first { $0.ru != l.ru } }
    private func hasPair() -> Bool { let l = loadLayouts(); return l.contains { $0.ru } && l.contains { !$0.ru } }

    private func translate(_ s: Stroke, _ l: Lay) -> String? { translate(s.code, shift: s.shift, caps: s.caps, l) }

    private func translate(_ code: CGKeyCode, shift: Bool, caps: Bool, _ l: Lay) -> String? {
        guard let ptr = CFDataGetBytePtr(l.data) else { return nil }
        let kbd = UnsafeRawPointer(ptr).assumingMemoryBound(to: UCKeyboardLayout.self)
        var dead: UInt32 = 0
        var len = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var mods: UInt32 = 0
        if shift { mods |= UInt32(shiftKey >> 8) }
        if caps { mods |= UInt32(alphaLock >> 8) }
        let r = UCKeyTranslate(kbd, UInt16(code), UInt16(kUCKeyActionDown), mods, UInt32(LMGetKbdType()),
                               OptionBits(kUCKeyTranslateNoDeadKeysMask), &dead, 4, &len, &chars)
        guard r == noErr, len > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: len)
    }

    private func string(_ strokes: [Stroke], _ l: Lay) -> String {
        strokes.compactMap { translate($0, l) }.joined()
    }

    // MARK: Проверка слова

    private func spellLang(ru: Bool) -> String? {
        let langs = NSSpellChecker.shared.availableLanguages
        if ru { return langs.first { $0.hasPrefix("ru") } }
        return langs.first { $0 == "en_US" } ?? langs.first { $0.hasPrefix("en") }
    }

    private func isWord(_ s: String, ru: Bool) -> Bool {
        guard let lang = spellLang(ru: ru) else { return false }
        func ok(_ w: String) -> Bool {
            NSSpellChecker.shared.checkSpelling(of: w, startingAt: 0, language: lang, wrap: false,
                                                inSpellDocumentWithTag: 0, wordCount: nil).location == NSNotFound
        }
        return ok(s) || ok(s.lowercased())
    }

    /// Что напечатать вместо слова, набранного не в той раскладке; nil — слово трогать не нужно
    private func decide(_ k: [Stroke], from: Lay, to: Lay) -> String? {
        guard spellLang(ru: from.ru) != nil, spellLang(ru: to.ru) != nil else { return nil }
        // внутренние заглавные (camelCase) и короткие слова не трогаем
        if k.dropFirst().contains(where: { $0.shift != k[0].shift && !$0.caps && !k[0].caps && !$0.shift }) == false,
           k.dropFirst().filter({ $0.shift }).count > 0, k.count != k.filter({ $0.shift }).count { return nil }
        var tailMax = 0
        for s in k.reversed() { if LayoutSwitcher.punctCodes.contains(s.code) { tailMax += 1 } else { break } }
        tailMax = min(tailMax, 3)
        for t in 0...tailMax {
            let part = Array(k.dropLast(t))
            guard part.count >= 3 else { break }
            let typed = string(part, from), conv = string(part, to)
            guard !conv.isEmpty, conv.allSatisfy({ $0.isLetter }) else { continue }
            if t == 0, typed.allSatisfy({ $0.isLetter }), isWord(typed, ru: from.ru) { return nil }   // слово набрано верно
            if isWord(conv, ru: to.ru) { return conv + string(Array(k.suffix(t)), from) }
        }
        return nil
    }

    // MARK: Перехват клавиш

    private func frontExcluded() -> Bool {
        guard let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
        return LayoutSwitcher.excluded.contains(id)
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
            return pass
        }
        guard type == .keyDown, event.getIntegerValueField(.eventSourceUserData) != LayoutSwitcher.marker else { return pass }
        if busy {                                           // идёт исправление: нажатия ждут своей очереди
            if let c = event.copy() { deferred.append(c) }
            return nil
        }
        let code = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        return process(code, event.flags, allowFix: true) ? nil : pass
    }

    /// Разбор нажатия. Возвращает true, если нажатие поглощено (слово исправляется)
    private func process(_ code: CGKeyCode, _ flags: CGEventFlags, allowFix: Bool) -> Bool {
        if flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate) {
            resetWord(); return false
        }
        if frontExcluded() || IsSecureEventInputEnabled() || !hasPair() { resetWord(); return false }
        let shift = flags.contains(.maskShift), caps = flags.contains(.maskAlphaShift)

        switch code {
        case 51:                                            // ⌫ — убираем последнюю букву слова
            if !keys.isEmpty { keys.removeLast() }
            last = nil
            return false
        case 49, 36, 76, 48:                                // пробел, Enter, Tab — конец слова
            let k = keys, wl = wordLayID, poisoned = poison
            keys = []
            poison = false
            if allowFix, LayoutSwitcher.autoFix, !poisoned, k.count >= 3, let from = lay(wl), let to = other(from),
               let text = decide(k, from: from, to: to) {
                last = nil
                fix(text, delete: k.count, target: to, boundary: (code, flags.intersection(.maskShift)))
                return true
            }
            if (code == 49 || code == 48), !poisoned, !k.isEmpty {
                last = LastWord(strokes: k, layID: wl, boundary: code, pid: NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0)
            } else {
                last = nil
            }
            return false
        default:
            break
        }
        if LayoutSwitcher.letterCodes.contains(code) || LayoutSwitcher.punctCodes.contains(code) {
            let cur = Kb.current().id
            guard lay(cur) != nil else { resetWord(); return false }
            if keys.isEmpty || wordLayID != cur { keys = []; wordLayID = cur; poison = false }
            keys.append(Stroke(code: code, shift: shift, caps: caps))
            last = nil
        } else if LayoutSwitcher.digitCodes.contains(code) {
            poison = true
            last = nil
        } else {
            resetWord()                                     // стрелки, Esc и прочие клавиши
        }
        return false
    }

    // MARK: Исправление

    /// Стирает `delete` символов, печатает `text`, переключает раскладку и (если нужно) повторяет клавишу конца слова
    private func fix(_ text: String, delete n: Int, target: Lay, boundary: (CGKeyCode, CGEventFlags)?) {
        busy = true
        deferred = []
        DispatchQueue.main.async { Kb.select(target.src) }       // с проверкой и повтором, если macOS «потеряла» переключение
        work.async { [weak self] in
            guard let self = self else { return }
            for _ in 0..<n { self.post(51, []); usleep(4000) }
            usleep(10000)
            self.type(text)
            if let b = boundary { usleep(8000); self.post(b.0, b.1) }
            usleep(40000)
            DispatchQueue.main.async { self.finishFix() }
        }
    }

    private func finishFix() {
        busy = false
        let pending = deferred
        deferred = []
        for e in pending {                                  // нажатия, пришедшие во время исправления
            let code = CGKeyCode(e.getIntegerValueField(.keyboardEventKeycode))
            _ = process(code, e.flags, allowFix: false)
            e.setIntegerValueField(.eventSourceUserData, value: LayoutSwitcher.marker)
            e.post(tap: .cghidEventTap)
            if let up = CGEvent(keyboardEventSource: CGEventSource(stateID: .hidSystemState), virtualKey: code, keyDown: false) {
                up.flags = e.flags
                up.setIntegerValueField(.eventSourceUserData, value: LayoutSwitcher.marker)
                up.post(tap: .cghidEventTap)
            }
        }
    }

    private func post(_ code: CGKeyCode, _ flags: CGEventFlags) {
        let src = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down) else { continue }
            e.flags = flags
            e.setIntegerValueField(.eventSourceUserData, value: LayoutSwitcher.marker)
            e.post(tap: .cghidEventTap)
        }
    }

    /// Печатает текст как символы (не зависит от текущей раскладки)
    private func type(_ text: String) {
        let units = Array(text.utf16)
        let src = CGEventSource(stateID: .hidSystemState)
        var i = 0
        while i < units.count {
            let chunk = Array(units[i..<min(i + 16, units.count)])
            i += 16
            for down in [true, false] {
                guard let e = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: down) else { continue }
                e.flags = []
                e.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
                e.setIntegerValueField(.eventSourceUserData, value: LayoutSwitcher.marker)
                e.post(tap: .cghidEventTap)
            }
            usleep(3000)
        }
    }

    // MARK: Горячая клавиша

    /// Слово, которое набирается сейчас → выделенный текст → последнее слово
    private func manual() {
        guard tap != nil, !busy, !frontExcluded(), hasPair() else { return }
        if !keys.isEmpty, !poison, let from = lay(wordLayID), let to = other(from) {
            let text = string(keys, to)
            let n = keys.count
            keys = []
            fix(text, delete: n, target: to, boundary: nil)
            return
        }
        convertSelection { [weak self] done in
            guard let self = self, !done else { return }
            guard let l = self.last, l.pid == NSWorkspace.shared.frontmostApplication?.processIdentifier,
                  let from = self.lay(l.layID), let to = self.other(from) else { NSSound.beep(); return }
            let text = self.string(l.strokes, to)
            self.last = nil
            self.fix(text, delete: l.strokes.count + 1, target: to, boundary: (l.boundary, []))
        }
    }

    /// Исправляет выделенный текст: копирует, переводит символы в другую раскладку, вставляет, возвращает буфер обмена
    private func convertSelection(_ done: @escaping (Bool) -> Void) {
        let pb = NSPasteboard.general
        let saved = snapshot(pb)
        let before = pb.changeCount
        ClipboardHistory.shared.suppress(for: 2)
        post(8, .maskCommand)                               // ⌘C
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
            guard let self = self else { return }
            guard pb.changeCount != before, let s = pb.string(forType: .string), !s.isEmpty else { done(false); return }
            let cyr = s.unicodeScalars.filter { (0x0400...0x04FF).contains($0.value) }.count
            let lat = s.unicodeScalars.filter { $0.isASCII && CharacterSet.letters.contains($0) }.count
            let toEnglish = cyr > lat
            let ls = self.loadLayouts()
            guard let en = ls.first(where: { !$0.ru }), let ru = ls.first(where: { $0.ru }) else { done(false); return }
            let map = self.charMap(from: toEnglish ? ru : en, to: toEnglish ? en : ru)
            let out = String(s.map { map[$0] ?? $0 })
            pb.clearContents()
            pb.setString(out, forType: .string)
            self.post(9, .maskCommand)                      // ⌘V
            let dst = (toEnglish ? en : ru).src
            DispatchQueue.main.async { Kb.select(dst) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.restore(saved, pb) }
            done(true)
        }
    }

    /// Какой символ получится на тех же клавишах в другой раскладке
    private func charMap(from a: Lay, to b: Lay) -> [Character: Character] {
        var m: [Character: Character] = [:]
        for code in 0...50 {
            for shift in [false, true] {
                guard let x = translate(CGKeyCode(code), shift: shift, caps: false, a), x.count == 1,
                      let y = translate(CGKeyCode(code), shift: shift, caps: false, b), y.count == 1,
                      let cx = x.first, let cy = y.first, !cx.isNewline, cx != "\t" else { continue }
                if m[cx] == nil { m[cx] = cy }
            }
        }
        return m
    }

    private func snapshot(_ pb: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (pb.pasteboardItems ?? []).map { item in
            var d: [NSPasteboard.PasteboardType: Data] = [:]
            for t in item.types { if let x = item.data(forType: t) { d[t] = x } }
            return d
        }
    }

    private func restore(_ items: [[NSPasteboard.PasteboardType: Data]], _ pb: NSPasteboard) {
        ClipboardHistory.shared.suppress(for: 1)
        pb.clearContents()
        guard !items.isEmpty else { return }
        pb.writeObjects(items.map { d in
            let it = NSPasteboardItem()
            for (t, x) in d { it.setData(x, forType: t) }
            return it
        })
    }
}
