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
    /// Добавить выделенное или предыдущее слово в свой словарь: ⇧⌃⌥Пробел
    static let dictCombo = Combo(keyCode: 49, mods: UInt32(controlKey | optionKey | shiftKey), keyTitle: "Space")


    // MARK: Состояние

    private struct Stroke { let code: CGKeyCode; let shift: Bool; let caps: Bool }
    private struct Lay { let id: String; let ru: Bool; let data: CFData; let src: TISInputSource }
    private struct LastWord { let strokes: [Stroke]; let layID: String; let boundary: CGKeyCode; let pid: pid_t }
    private struct RunWord { let strokes: [Stroke]; let layID: String }
    /// Последнее исправление: сочетание переключает слово туда и обратно, сколько раз ни нажми
    private struct UndoInfo {
        let now: String                                     // что сейчас на экране
        let other: String                                   // что будет после нажатия
        let layNow: Lay
        let layOther: Lay
        let boundary: (CGKeyCode, CGEventFlags)?            // клавиша после слова (пробел), если она уже набрана
        let never: String?                                  // набранный вид автоисправленного слова
        let isAuto: Bool                                    // на экране результат автоисправления
    }

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
    private var run: [RunWord] = []                         // слова текущей фразы, набранные подряд и не исправленные (для коротких слов «И», «А»)
    private var dictCand: String?                           // слово для словаря, запомненное при нажатии ⇧⌃⌥Пробел
    private var undo: UndoInfo?                             // откат последнего автоисправления (пока ничего не набрано дальше)
    private var pendingUndo: UndoInfo?
    private var appObserver: NSObjectProtocol?
    private var busy = false                                // идёт исправление: новые нажатия ждут
    private var deferred: [CGEvent] = []
    private let work = DispatchQueue(label: "layoutswitcher.work", qos: .userInteractive)

    private static let ruShort: Set<String> = ["а", "в", "и", "к", "о", "с", "у", "я", "во", "на", "не", "ни", "но", "да", "за", "из",
        "по", "от", "до", "он", "мы", "вы", "ты", "то", "ту", "ко", "со", "об", "ли", "же", "бы", "ну", "ей", "им", "их", "её", "ее",
        "уж", "ах", "ох", "эх", "ой", "ай"]
    private static let enShort: Set<String> = ["i", "a", "am", "an", "as", "at", "be", "by", "do", "go", "he", "if", "in", "is", "it",
        "me", "my", "no", "of", "on", "or", "so", "to", "up", "us", "we"]
    private func isShort(_ s: String, ru: Bool) -> Bool {
        (ru ? LayoutSwitcher.ruShort : LayoutSwitcher.enShort).contains(s.lowercased()) || LayoutDictionary.contains(s)
    }

    /// Слова, которые пользователь откатил: их больше не исправляем (набранный вид, строчными)
    static var never: Set<String> { Set(UserDefaults.standard.stringArray(forKey: "layout.never") ?? []) }
    static func addNever(_ w: String) {
        var a = UserDefaults.standard.stringArray(forKey: "layout.never") ?? []
        if !a.contains(w) { a.append(w) }
        if a.count > 500 { a.removeFirst(a.count - 500) }
        UserDefaults.standard.set(a, forKey: "layout.never")
    }
    static func removeNever(_ w: String) {
        var a = UserDefaults.standard.stringArray(forKey: "layout.never") ?? []
        a.removeAll { $0 == w }
        UserDefaults.standard.set(a, forKey: "layout.never")
    }
    static func clearNever() { UserDefaults.standard.removeObject(forKey: "layout.never") }

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
        HotKeyCenter.shared.register(LayoutSwitcher.dictCombo, id: 17) { [weak self] in self?.addToDictionary() }
        // другая программа выходит вперёд: слово, которое набиралось, и память об исправлении больше не актуальны
        appObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                                         object: nil, queue: .main) { [weak self] _ in self?.resetWord() }
    }

    func stop() {
        retry?.invalidate()
        retry = nil
        if let t = tap { CGEvent.tapEnable(tap: t, enable: false) }
        if let s = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
        if let m = clickMonitor { NSEvent.removeMonitor(m) }
        clickMonitor = nil
        if let o = appObserver { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        appObserver = nil
        tap = nil
        source = nil
        HotKeyCenter.shared.unregister(id: 16)
        HotKeyCenter.shared.unregister(id: 17)
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
        run = []
        undo = nil
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
        if LayoutDictionary.contains(s) || LayoutNames.resolve(s) != nil { return true }   // слово из своего словаря или имя
        guard let lang = spellLang(ru: ru) else { return false }
        func ok(_ w: String) -> Bool {
            NSSpellChecker.shared.checkSpelling(of: w, startingAt: 0, language: lang, wrap: false,
                                                inSpellDocumentWithTag: 0, wordCount: nil).location == NSNotFound
        }
        return ok(s) || ok(s.lowercased())
    }

    /// Конец слова: знаки, которые могут стоять после слова и не мешают его исправить
    private static let tailMarks: Set<Character> = [".", ",", "?", "!", ":", ";"]

    /// Знак конца слова в раскладке-цели: берётся из самой раскладки, поэтому годятся и «Русская» (точка на ⇧7, запятая на ⇧6),
    /// и «Русская – ПК» (точка и запятая на клавише «/»)
    private func isMark(_ s: Stroke, in l: Lay) -> Bool {
        guard let t = translate(s, l), t.count == 1, let c = t.first else { return false }
        return LayoutSwitcher.tailMarks.contains(c)
    }

    private func isTail(_ s: Stroke, to: Lay) -> Bool {
        LayoutSwitcher.punctCodes.contains(s.code) || s.code == 44 || (to.ru && s.shift && (s.code == 26 || s.code == 18)) || isMark(s, in: to)
    }

    private func tailText(_ strokes: [Stroke], from: Lay, to: Lay) -> String {
        strokes.map { s -> String in
            if to.ru {
                if isMark(s, in: to) { return translate(s, to) ?? "" }       // знак так, как его даёт сама русская раскладка
                if s.code == 44 { return s.shift ? "," : "." }
                if s.code == 26 && s.shift { return "?" }
                if s.code == 18 && s.shift { return "!" }
                return translate(s, from) ?? ""
            }
            return translate(s, to) ?? ""
        }.joined()
    }

    /// Слово с дефисом («что-то»): каждая часть проверяется отдельно
    private func decideHyphen(_ k: [Stroke], from: Lay, to: Lay) -> String? {
        var segs: [[Stroke]] = [[]]
        for s in k { if s.code == 27 && !s.shift { segs.append([]) } else { segs[segs.count - 1].append(s) } }
        guard segs.count >= 2, segs.allSatisfy({ !$0.isEmpty }) else { return nil }
        let typed = segs.map { string($0, from) }, conv = segs.map { string($0, to) }
        guard conv.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isLetter } }) else { return nil }
        if typed.allSatisfy({ $0.allSatisfy { $0.isLetter } && isWord($0, ru: from.ru) }) { return nil }   // набрано верно
        for (i, c) in conv.enumerated() {
            let ok = segs[i].count <= 2 ? isShort(c, ru: to.ru) : isWord(c, ru: to.ru)
            if !ok { return nil }
        }
        return conv.joined(separator: "-")
    }

    /// Что напечатать вместо слова, набранного не в той раскладке; nil — слово трогать не нужно
    private func decide(_ k: [Stroke], from: Lay, to: Lay) -> String? {
        guard spellLang(ru: from.ru) != nil, spellLang(ru: to.ru) != nil else { return nil }
        let typedAll = string(k, from).lowercased()
        if LayoutSwitcher.never.contains(typedAll) { return nil }                    // слово, которое пользователь откатывал
        if LayoutDictionary.contains(typedAll) || LayoutNames.resolve(typedAll) != nil { return nil }   // слово из своего словаря или имя набрано верно
        // адреса сайтов («github.com») не трогаем
        if !from.ru, typedAll.range(of: "^[a-z0-9-]+\\.(com|ru|org|net|io|dev|app|su|info|biz|edu|gov|me|co|ai|xyz|tv|pro|tech)$",
                                    options: .regularExpression) != nil { return nil }
        if k.contains(where: { $0.code == 27 && !$0.shift }) { return decideHyphen(k, from: from, to: to) }
        // внутренние заглавные (camelCase) и короткие слова не трогаем
        // (⇧ на клавише знака, например ⇧7 = «.», заглавной буквой не считается)
        let body = k.filter { LayoutSwitcher.letterCodes.contains($0.code) || LayoutSwitcher.punctCodes.contains($0.code) }
        if body.dropFirst().contains(where: { $0.shift }), body.count != body.filter({ $0.shift }).count { return nil }
        var tailMax = 0
        for s in k.reversed() { if isTail(s, to: to) { tailMax += 1 } else { break } }
        tailMax = min(tailMax, 3)
        for t in 0...tailMax {
            let part = Array(k.dropLast(t))
            let typed = string(part, from), conv = string(part, to)
            let inDict = LayoutDictionary.contains(conv)                                   // сокращение из словаря («OS» из «щы»)
            let name = LayoutNames.resolve(conv)                                           // имя из списка имён
            let custom = inDict || name != nil                                             // свои словари важнее системного
            guard part.count >= 3 || (inDict && part.count == 2 && (conv.contains(".") || part.allSatisfy { $0.shift || $0.caps })) else { break }   // двухбуквенные — только заглавными («ЩЫ» → «OS») или с точкой («т.»)
            if LayoutDictionary.contains(typed) || LayoutNames.resolve(typed) != nil { return nil }
            guard !conv.isEmpty, conv.allSatisfy({ $0.isLetter }) || inDict else { continue }
            if !custom, typed.allSatisfy({ $0.isLetter }), isWord(typed, ru: from.ru) { return nil }   // слово набрано верно (но слово из своих словарей важнее системного)
            if isWord(conv, ru: to.ru) {
                // имя, набранное строчными, сразу получает заглавную букву
                let out = (name != nil && LayoutNames.capsEnabled && part.allSatisfy { !$0.shift && !$0.caps }) ? name! : conv
                return out + tailText(Array(k.suffix(t)), from: from, to: to)
            }
        }
        return nil
    }

    /// Слово набрано правильно и целиком строчными, но это имя из списка («андрей,» → «Андрей,»): что стоит на экране и что должно быть
    private func nameCase(_ k: [Stroke], from: Lay) -> (old: String, new: String)? {
        var body = k, tail: [Stroke] = []
        while let s = body.last, isMark(s, in: from) { tail.insert(s, at: 0); body.removeLast() }
        guard !body.isEmpty, body.allSatisfy({ !$0.shift && !$0.caps }) else { return nil }     // «Андрей» и «АНДРЕЙ» не трогаем
        let typed = string(body, from)
        guard typed.allSatisfy({ $0.isLetter || $0 == "-" || $0 == "'" || $0 == "’" }) else { return nil }
        if LayoutSwitcher.never.contains(typed.lowercased()) { return nil }                     // пользователь откатил
        guard let name = LayoutNames.resolve(typed), name != typed else { return nil }
        let t = string(tail, from)
        return (typed + t, name + t)
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

    private func isFixCombo(_ code: CGKeyCode, _ flags: CGEventFlags) -> Bool {
        let c = LayoutSwitcher.loadCombo()
        guard UInt32(code) == c.keyCode else { return false }
        var m: UInt32 = 0
        if flags.contains(.maskControl) { m |= UInt32(controlKey) }
        if flags.contains(.maskAlternate) { m |= UInt32(optionKey) }
        if flags.contains(.maskShift) { m |= UInt32(shiftKey) }
        if flags.contains(.maskCommand) { m |= UInt32(cmdKey) }
        return m == c.mods
    }

    private func isDictCombo(_ code: CGKeyCode, _ flags: CGEventFlags) -> Bool {
        let want: CGEventFlags = [.maskControl, .maskAlternate, .maskShift]
        return UInt32(code) == LayoutSwitcher.dictCombo.keyCode && flags.intersection([.maskControl, .maskAlternate, .maskShift, .maskCommand]) == want
    }

    private func captureDictCandidate() {
        dictCand = nil
        if !keys.isEmpty, !poison, let l = lay(wordLayID) { dictCand = string(keys, l) }
        else if let w = last, w.pid == NSWorkspace.shared.frontmostApplication?.processIdentifier, let l = lay(w.layID) {
            dictCand = string(w.strokes, l)
        }
    }

    /// Разбор нажатия. Возвращает true, если нажатие поглощено (слово исправляется)
    private func process(_ code: CGKeyCode, _ flags: CGEventFlags, allowFix: Bool) -> Bool {
        if isDictCombo(code, flags) { captureDictCandidate(); return false }   // ⇧⌃⌥Пробел: запоминаем слово до того, как сочетание сбросит буфер
        let fixCombo = isFixCombo(code, flags)
        if !fixCombo { undo = nil }                         // любое другое нажатие закрывает возможность отката
        if flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate) {
            // само сочетание исправления не должно стирать слово, которое оно собирается исправить
            if fixCombo { return false }
            resetWord(); return false
        }
        if frontExcluded() || IsSecureEventInputEnabled() || !hasPair() { resetWord(); return false }
        let shift = flags.contains(.maskShift), caps = flags.contains(.maskAlphaShift)

        switch code {
        case 51:                                            // ⌫ — убираем последнюю букву слова
            if !keys.isEmpty { keys.removeLast() } else { run = [] }
            last = nil
            return false
        case 49, 36, 76, 48:                                // пробел, Enter, Tab — конец слова
            let k = keys, wl = wordLayID, poisoned = poison
            let before = run
            keys = []
            poison = false
            if allowFix, LayoutSwitcher.autoFix, !poisoned, k.count >= 3, let from = lay(wl), let to = other(from),
               let text = decide(k, from: from, to: to) {
                last = nil
                run = []
                // короткие слова перед ним («И вот»), набранные в той же раскладке, исправляем вместе с ним
                var pre: [RunWord] = []
                for w in before.reversed() {
                    guard w.layID == wl, w.strokes.count <= 2, isShort(string(w.strokes, to), ru: to.ru) else { break }
                    pre.insert(w, at: 0)
                }
                let preTo = pre.map { string($0.strokes, to) + " " }.joined()
                let preFrom = pre.map { string($0.strokes, from) + " " }.joined()
                let full = preTo + text
                let del = k.count + pre.reduce(0) { $0 + $1.strokes.count + 1 }
                let u = UndoInfo(now: full, other: preFrom + string(k, from), layNow: to, layOther: from,
                                 boundary: (code, flags.intersection(.maskShift)), never: string(k, from).lowercased(), isAuto: true)
                fix(full, delete: del, target: to, boundary: (code, flags.intersection(.maskShift)), undo: u)
                return true
            }
            // имя набрано правильно, но строчными: заглавная первая буква
            if allowFix, LayoutNames.capsEnabled, !poisoned, k.count >= 2, let from = lay(wl), let c = nameCase(k, from: from) {
                last = nil
                run = []
                let u = UndoInfo(now: c.new, other: c.old, layNow: from, layOther: from,
                                 boundary: (code, flags.intersection(.maskShift)), never: c.old.lowercased(), isAuto: true)
                fix(c.new, delete: k.count, target: from, boundary: (code, flags.intersection(.maskShift)), undo: u)
                return true
            }
            if code == 49, !poisoned, !k.isEmpty {
                run = Array((before + [RunWord(strokes: k, layID: wl)]).suffix(6))
            } else if !(code == 49 && k.isEmpty && !poisoned) {
                run = []                                    // слово со знаком или цифрой, Enter, Tab — фраза закончилась
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
        var tailExtra = code == 44 || (shift && (code == 26 || code == 18))
        if !tailExtra, shift, LayoutSwitcher.digitCodes.contains(code), let l = lay(Kb.current().id), let o = other(l) {
            tailExtra = isMark(Stroke(code: code, shift: true, caps: caps), in: o)       // «b n&l&» → «и т.д.»
        }
        if LayoutSwitcher.letterCodes.contains(code) || LayoutSwitcher.punctCodes.contains(code) || tailExtra {
            let cur = Kb.current().id
            guard lay(cur) != nil else { resetWord(); return false }
            if keys.isEmpty || wordLayID != cur { keys = []; wordLayID = cur; poison = false }
            keys.append(Stroke(code: code, shift: shift, caps: caps))
            last = nil
        } else if code == 27 && !shift && !keys.isEmpty {         // дефис внутри слова («что-то»)
            keys.append(Stroke(code: code, shift: false, caps: caps))
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
    private func fix(_ text: String, delete n: Int, target: Lay, boundary: (CGKeyCode, CGEventFlags)?, undo u: UndoInfo? = nil) {
        busy = true
        deferred = []
        pendingUndo = u
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
        undo = pending.isEmpty ? pendingUndo : nil          // откат возможен, только пока после исправления ничего не набрано
        pendingUndo = nil
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
        if let u = undo {                                   // повторное нажатие: переключаем слово обратно (и снова вперёд)
            undo = nil
            keys = []
            last = nil
            run = []
            if let w = u.never { if u.isAuto { LayoutSwitcher.addNever(w) } else { LayoutSwitcher.removeNever(w) } }
            let next = UndoInfo(now: u.other, other: u.now, layNow: u.layOther, layOther: u.layNow,
                                boundary: u.boundary, never: u.never, isAuto: !u.isAuto)
            fix(u.other, delete: u.now.count + (u.boundary != nil ? 1 : 0), target: u.layOther, boundary: u.boundary, undo: next)
            return
        }
        if !keys.isEmpty, !poison, let from = lay(wordLayID), let to = other(from) {
            let text = string(keys, to)
            let n = keys.count
            let orig = string(keys, from)
            keys = []
            let u = UndoInfo(now: text, other: orig, layNow: to, layOther: from, boundary: nil, never: nil, isAuto: false)
            fix(text, delete: n, target: to, boundary: nil, undo: u)
            return
        }
        convertSelection { [weak self] done in
            guard let self = self, !done else { return }
            guard let l = self.last, l.pid == NSWorkspace.shared.frontmostApplication?.processIdentifier,
                  let from = self.lay(l.layID), let to = self.other(from) else { NSSound.beep(); return }
            let text = self.string(l.strokes, to)
            self.last = nil
            let u = UndoInfo(now: text, other: self.string(l.strokes, from), layNow: to, layOther: from,
                             boundary: (l.boundary, []), never: nil, isAuto: false)
            self.fix(text, delete: l.strokes.count + 1, target: to, boundary: (l.boundary, []), undo: u)
        }
    }

    // MARK: Свой словарь

    /// ⇧⌃⌥Пробел: выделенное слово (или, если ничего не выделено, предыдущее) → вопрос «Добавить в словарь?»
    private func addToDictionary() {
        guard tap != nil, !busy, !frontExcluded() else { return }
        let cand = dictCand
        dictCand = nil
        readSelection { [weak self] sel in
            guard self != nil else { return }
            let w = LayoutDictionary.clean(sel ?? cand ?? "")
            if w.isEmpty {
                FinderCut.shared.present(icon: "text.book.closed", title: T("Нечего добавлять в словарь"),
                                         subtitle: T("Выделите слово или наберите его"))
                return
            }
            let wordErr = LayoutDictionary.validate(w)
            let nameW = LayoutNames.normalize(w)
            let nameOK = LayoutNames.validate(nameW) == nil && !LayoutNames.has(nameW)
            let wordOK = wordErr == nil && !LayoutDictionary.containsEntry(w)
            if !wordOK && !nameOK {
                if let e = wordErr, LayoutNames.validate(nameW) != nil {
                    FinderCut.shared.present(icon: "exclamationmark.triangle", title: Tf("Не добавлено: «%@»", w), subtitle: e)
                } else {
                    FinderCut.shared.present(icon: "text.book.closed", title: Tf("Уже есть в словаре: «%@»", w), subtitle: "")
                }
                return
            }
            DictionaryPrompt.shared.ask(word: w, canWord: wordOK, canName: nameOK) { kind in
                guard kind != 0 else { return }
                let e = kind == 2 ? LayoutNames.add(nameW) : LayoutDictionary.add(w)
                if let e = e {
                    FinderCut.shared.present(icon: "exclamationmark.triangle", title: Tf("Не добавлено: «%@»", w), subtitle: e)
                } else if kind == 2 {
                    FinderCut.shared.present(icon: "text.book.closed", title: Tf("Добавлено в имена: «%@»", nameW), subtitle: "")
                } else {
                    FinderCut.shared.present(icon: "text.book.closed", title: Tf("Добавлено в словарь: «%@»", w), subtitle: "")
                }
            }
        }
    }

    /// Выделенный текст (nil, если ничего не выделено); буфер обмена возвращается как был
    private func readSelection(_ done: @escaping (String?) -> Void) {
        let pb = NSPasteboard.general
        let saved = snapshot(pb)
        let before = pb.changeCount
        ClipboardHistory.shared.suppress(for: 2)
        post(8, .maskCommand)                               // ⌘C
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
            guard let self = self else { return }
            var s: String? = nil
            if pb.changeCount != before {
                s = pb.string(forType: .string)
                self.restore(saved, pb)
            }
            done(s)
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
            let n = out.count
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
                for _ in 0..<n { self?.post(123, .maskShift) }            // ⇧← : текст снова выделен, повторное нажатие вернёт его обратно
            }
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
