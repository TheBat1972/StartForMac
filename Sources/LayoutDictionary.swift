import Cocoa
import SwiftUI
import UniformTypeIdentifiers

extension Notification.Name {
    static let layoutDictChanged = Notification.Name("StartLayoutDictChanged")
}

// MARK: - Свой словарь автоматического переключателя раскладки
//
// Слова и сокращения («OS», «RTSP», «т.д.»), которые переключатель считает правильными в любой раскладке:
// набранное слово из словаря не исправляется, а слово, которое при смене раскладки превращается в слово из словаря,
// исправляется. Хранится на этом Mac в настройках программы, никуда не передаётся.

enum LayoutDictionary {
    private static let key = "layout.dict"
    private static let seedKey = "layout.dict.seed"
    private static let seedVersion = 2

    /// Самые употребимые сокращения, которых нет в системном словаре macOS (русские и английские)
    static let defaultWords: [String] = {
        let ru = """
        т.д. т.п. т.е. т.к. т.н. т.о. т.ч. т.с. и.о. н.э. тыс млн млрд руб коп шт кв мин сек
        др пр см рис табл стр ул пл обл пос прим напр англ рус проф акад доц зам ген гл
        ГОСТ ООО ОАО ЗАО ПАО АО ИП НДС ИНН КПП ОГРН ФИО МВД ФСБ МЧС РФ СССР США ЕС ООН НАТО СНГ
        МГУ РАН ВУЗ ЖКХ ЕГЭ ОГЭ ГИБДД ДТП ЗАГС МФЦ ТЦ ТРЦ ЦБ ФНС ПФР ОМС СНИЛС НИИ КБ ОТК ТСЖ ЖК СМИ ТВ
        ТЗ ТЭО ТЭК ЖД РЖД ЭВМ ПК ПО ОС БД СУБД ЛВС ИБП ИТ ФТ КП ЛК
        СКУД СОТ ОПС АПС ТСО ГРЗ ЦОД АРМ ПАК
        кг мг км мм мл кВт МГц ГГц ГБ МБ КБ ТБ Гбит Мбит
        """
        let en = """
        e.g. i.e. a.m. p.m. N.B. U.S. U.K. Ph.D. etc vs aka asap fyi btw imo imho lol omg brb tbd eta faq
        CEO CTO CFO COO CMO KPI ROI OKR SLA CRM ERP SaaS QA HR PR VIP DIY ATM PIN SMS UTC GMT USA UAE EU UN NATO NASA FBI CIA
        Inc Ltd LLC Corp Dr Mr Mrs Ms Prof Ave Dept approx
        OS PC TV CPU GPU RAM ROM SSD HDD USB HDMI VGA LAN WAN WLAN VPN DNS DHCP HTTP HTTPS FTP SFTP SSH SSL TLS TCP UDP URL URI
        API SDK IDE CLI GUI UI UX HTML CSS JS JSON XML YAML SQL NoSQL PDF PNG JPG JPEG GIF SVG ZIP RAR ISO DMG PKG APK IPA
        iOS macOS iPadOS watchOS tvOS iPhone iPad iMac MacBook AirPods iCloud GitHub YouTube WhatsApp Xcode SwiftUI
        AI ML LLM GPT AR VR QR NFC GPS LED LCD OLED USB-C Wi-Fi CCTV NVR DVR PoE RTSP ONVIF RTMP HLS
        kg km mm cm ml mg kB MB GB TB KB Gbps Mbps kW kWh MHz GHz Hz dB fps dpi ppi rpm
        """
        let split: (String) -> [String] = { $0.split(whereSeparator: { $0 == " " || $0.isNewline }).map(String.init) }
        return split(ru) + split(en)
    }()

    /// Короткие фразы из нескольких слов (добавляются к уже заполненному словарю при обновлении)
    static let defaultPhrases = ["и т.д.", "и т.п.", "и т.е.", "и др.", "и пр.", "т. е.", "т. д.", "т. п.", "и т. д.", "и т. п."]

    /// Слово русское (кириллица) или английское
    static func isCyrillic(_ w: String) -> Bool {
        w.unicodeScalars.first(where: { CharacterSet.letters.contains($0) }).map { (0x0400...0x04FF).contains($0.value) } ?? false
    }

    /// Возвращает в словарь стандартные слова, которых в нём нет (свои слова не трогает); сколько добавлено
    @discardableResult static func restoreDefaults() -> Int {
        let have = Set(words.map { $0.lowercased() })
        let add = (defaultWords + defaultPhrases).filter { !have.contains($0.lowercased()) && validate($0) == nil }
        if !add.isEmpty { words = words + add }
        return add.count
    }
    static let maxWords = 1000
    static let maxLength = 40
    private static var cache: Set<String>?              // записи целиком и отдельные слова фраз
    private static var entryCache: Set<String>?         // только записи целиком

    /// Слова в том виде, как их ввёл пользователь (по порядку добавления)
    static var words: [String] {
        get {
            let seed = UserDefaults.standard.integer(forKey: seedKey)
            if seed < seedVersion {         // первый запуск: стандартный набор; при обновлении только новые фразы (удалённое не возвращается)
                var a = UserDefaults.standard.stringArray(forKey: key) ?? []
                let have = Set(a.map { $0.lowercased() })
                a += ((seed < 1 ? defaultWords : []) + defaultPhrases).filter { !have.contains($0.lowercased()) && validate($0) == nil }
                UserDefaults.standard.set(a, forKey: key)
                UserDefaults.standard.set(seedVersion, forKey: seedKey)
            }
            return UserDefaults.standard.stringArray(forKey: key) ?? []
        }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
            cache = nil
            entryCache = nil
            NotificationCenter.default.post(name: .layoutDictChanged, object: nil)
        }
    }

    private static func buildCaches() {
        var all = Set<String>(), entries = Set<String>()
        for w in words {
            let l = w.lowercased()
            entries.insert(l)
            all.insert(l)
            if l.contains(" ") { for t in l.split(separator: " ") { all.insert(String(t)) } }      // у фразы «и т.д.» известны и «и», и «т.д.»
        }
        cache = all
        entryCache = entries
    }

    /// Известно ли переключателю это слово: запись словаря или слово из фразы (без учёта регистра)
    static func contains(_ s: String) -> Bool {
        if s.isEmpty { return false }
        if cache == nil { buildCaches() }
        return cache!.contains(s.lowercased())
    }

    /// Есть ли в словаре именно такая запись (слово или фраза целиком)
    static func containsEntry(_ s: String) -> Bool {
        if s.isEmpty { return false }
        if entryCache == nil { buildCaches() }
        return entryCache!.contains(s.lowercased())
    }

    /// Убирает знаки вокруг слова («слово,» → «слово»); точка в конце остаётся только у сокращений вроде «т.д.»
    static func clean(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.contains("  ") { s = s.replacingOccurrences(of: "  ", with: " ") }
        let hadDot = s.hasSuffix(".")
        while let f = s.first, !f.isLetter { s.removeFirst() }
        while let l = s.last, !l.isLetter { s.removeLast() }
        if hadDot, s.contains("."), !s.isEmpty { s += "." }
        return s
    }

    /// Проверка формата: nil — запись годится (слово, сокращение или фраза до четырёх слов), иначе текст ошибки
    static func validate(_ s: String) -> String? {
        if s.isEmpty { return T("Введите слово или сокращение.") }
        if s.contains(where: { $0.isNewline || $0 == "\t" }) { return T("Только одна строка.") }
        if s.count > maxLength { return Tf("Не длиннее %@ символов.", "\(maxLength)") }
        if s.contains("  ") { return T("Между словами один пробел.") }
        let tokens = s.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        if tokens.contains("") { return T("Пробелы допустимы только между словами.") }
        if tokens.count > 4 { return T("Не больше четырёх слов.") }
        if s.contains(where: { $0.isNumber }) { return T("Цифры не поддерживаются: слова с цифрами переключатель не трогает.") }
        let allowed = Set<Character>(["-", "'", "’", ".", " "])
        if let bad = s.first(where: { !$0.isLetter && !allowed.contains($0) }) {
            return Tf("Недопустимый символ: «%@». Можно буквы, дефис, апостроф и точку.", String(bad))
        }
        var cyr = false, lat = false
        for u in s.unicodeScalars where CharacterSet.letters.contains(u) {
            if (0x0400...0x04FF).contains(u.value) { cyr = true }
            else if u.isASCII { lat = true }
            else { return Tf("Недопустимый символ: «%@». Можно буквы, дефис, апостроф и точку.", String(u)) }
        }
        if cyr && lat { return T("Нельзя смешивать русские и английские буквы в одной записи.") }
        for t in tokens {
            guard let f = t.first, f.isLetter else { return T("Слово должно начинаться с буквы.") }
            if let l = t.last, !(l.isLetter || l == ".") { return T("Слово должно заканчиваться буквой (или точкой у сокращения).") }
            if t.contains("..") || t.contains("--") || t.contains("''") { return T("Знаки не могут идти подряд.") }
            // у одиночного слова точка в конце — только у сокращений вроде «т.д.»; в фразе («т. е.», «и др.») можно
            if tokens.count == 1, t.hasSuffix("."), !t.dropLast().contains(".") { return T("Точка в конце допустима только у сокращений вроде «т.д.».") }
        }
        return nil
    }

    /// Добавляет слово; nil — готово, иначе текст ошибки
    @discardableResult static func add(_ raw: String) -> String? {
        let w = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let e = validate(w) { return e }
        if containsEntry(w) { return Tf("Уже есть в словаре: «%@»", w) }
        var a = words
        if a.count >= maxWords { return T("Словарь заполнен.") }
        a.append(w)
        words = a
        return nil
    }

    /// Заменяет слово другим (редактирование)
    static func replace(_ old: String, with raw: String) -> String? {
        let w = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let e = validate(w) { return e }
        if w.lowercased() != old.lowercased(), containsEntry(w) { return Tf("Уже есть в словаре: «%@»", w) }
        var a = words
        guard let i = a.firstIndex(of: old) else { return add(w) }
        a[i] = w
        words = a
        return nil
    }

    static func remove(_ w: String) { words = words.filter { $0 != w } }
}

// MARK: - Словарь имён
//
// Имена и фамилии (свои коллеги, клиенты, города), которых нет в системном словаре. Имя из списка считается словом в любой раскладке:
// набранное не в той раскладке исправляется (сразу с заглавной буквы), а набранное правильно, но строчными, получает заглавную
// первую букву. Русские имена узнаются и в склонённом виде («Мурата», «Мурату»).

enum LayoutNames {
    private static let key = "layout.names"
    private static let seedKey = "layout.names.seed"
    private static let seedRuKey = "layout.names.seedRu"
    static let maxNames = 3000
    static let maxLength = 30

    /// Исправлять регистр имён: «андрей» → «Андрей»
    static var capsEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "layout.names.caps") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "layout.names.caps") }
    }
    /// Узнавать русские имена в падежных формах («Мурата», «Мурату»)
    static var declEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "layout.names.decl") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "layout.names.decl") }
    }

    static let defaultRu = """
    Александр Алексей Альберт Анатолий Андрей Антон Аркадий Арсений Артём Артур Борис Вадим Валентин Валерий Василий Виктор Виталий
    Владимир Владислав Всеволод Вячеслав Геннадий Георгий Герман Глеб Григорий Давид Даниил Денис Дмитрий Евгений Егор Захар Иван
    Игорь Илья Кирилл Константин Леонид Лев Максим Марк Матвей Михаил Никита Николай Олег Павел Пётр Роман Ростислав Руслан
    Святослав Семён Сергей Станислав Степан Тимофей Тимур Фёдор Филипп Эдуард Юрий Ярослав Мурат Рустам Ренат Марат Ильдар Айдар
    Азамат Ринат Равиль Тагир Салават Рамиль Булат Эльдар Гусейн Магомед Анвар Заур
    Александра Алина Алиса Алла Анастасия Анна Антонина Валентина Валерия Варвара Вера Вероника Виктория Галина Дарья Диана Евгения
    Екатерина Елена Елизавета Зинаида Зоя Инна Ирина Карина Кира Клавдия Ксения Лариса Лидия Лилия Любовь Людмила Маргарита Марина
    Мария Милана Надежда Наталья Нина Оксана Олеся Ольга Полина Раиса Регина Светлана София Софья Тамара Татьяна Ульяна Элина Юлия Яна
    Альфия Гульнара Динара Земфира Лейла Назира Рузана Салима Эльвира Эльмира Айгуль Айгерим Зарина Камила Малика
    Саша Женя Ваня Дима Коля Миша Паша Лёша Катя Маша Наташа Оля Света Таня Юля Лена Настя Ира Даша
    """
    static let defaultEn = """
    James John Robert Michael William David Richard Joseph Thomas Charles Christopher Daniel Matthew Anthony Mark Donald Steven Paul
    Andrew Joshua Kenneth Kevin Brian George Timothy Ronald Edward Jason Jeffrey Ryan Jacob Gary Nicholas Eric Jonathan Stephen Larry
    Justin Scott Brandon Benjamin Samuel Gregory Alexander Patrick Frank Raymond Jack Dennis Jerry Tyler Aaron Adam Nathan Henry Peter
    Zachary Douglas Harold Kyle Walter Ethan Jeremy Lucas Oliver Noah Liam Mason Logan Elijah
    Mary Patricia Jennifer Linda Elizabeth Barbara Susan Jessica Sarah Karen Lisa Nancy Betty Sandra Margaret Ashley Kimberly Emily Donna
    Michelle Carol Amanda Melissa Deborah Stephanie Rebecca Sharon Laura Cynthia Kathleen Amy Angela Shirley Anna Brenda Pamela Emma
    Nicole Helen Samantha Katherine Christine Debra Rachel Carolyn Janet Maria Heather Diane Olivia Julie Joyce Victoria Kelly Christina
    Lauren Joan Evelyn Judith Megan Cheryl Andrea Hannah Martha Jacqueline Gloria Teresa Sara Madison Frances Kathryn Janice Jean
    Abigail Alice Julia Judy Sophia Grace Denise Amber Doris Marilyn Danielle Beverly Isabella Theresa Diana Natalie Brittany Charlotte
    Marie Kayla Alexis Lori
    """

    private static var exactCache: [String: String]?        // имя строчными → как записано
    private static var stemCache: Set<String>?               // основы русских имён (от четырёх букв)

    private static func spellLangs() -> (ru: String, en: String)? {
        let l = NSSpellChecker.shared.availableLanguages
        guard let ru = l.first(where: { $0.hasPrefix("ru") }), let en = l.first(where: { $0 == "en_US" }) ?? l.first(where: { $0.hasPrefix("en") }) else { return nil }
        return (ru, en)
    }

    /// Русские имена, совпадающие с обычными словами: их заглавная буква в тексте была бы ошибкой («вера», «лев», «роман»)
    private static let notNames: Set<String> = ["лилия", "вера", "надежда", "любовь", "лев", "роман", "булат", "света"]

    private static func splitNames(_ s: String) -> [String] {
        s.split(whereSeparator: { $0 == " " || $0.isNewline }).map(String.init)
    }

    /// Стандартные русские имена (все, кроме совпадающих с обычными словами; системный словарь не учитывается)
    private static func ruDefaults(excluding have: Set<String>) -> [String] {
        splitNames(defaultRu).filter { !have.contains($0.lowercased()) && !notNames.contains($0.lowercased()) && validate($0) == nil }
    }

    /// Стандартные английские имена, которых нет в системном словаре (остальные исправляются и без списка); пусто, если проверка недоступна
    private static func enDefaults(excluding have: Set<String>) -> [String] {
        guard let langs = spellLangs() else { return [] }
        return splitNames(defaultEn).filter { n in
            guard !have.contains(n.lowercased()), validate(n) == nil else { return false }
            return NSSpellChecker.shared.checkSpelling(of: n, startingAt: 0, language: langs.en, wrap: false,
                                                       inSpellDocumentWithTag: 0, wordCount: nil).location != NSNotFound
        }
    }

    /// Имена в том виде, как их ввёл пользователь
    static var names: [String] {
        get {
            let d = UserDefaults.standard
            var a = d.stringArray(forKey: key) ?? []
            var changed = false
            if d.integer(forKey: seedRuKey) < 1 {                       // стандартные русские имена (при обновлении добавляются недостающие)
                a += ruDefaults(excluding: Set(a.map { $0.lowercased() }))
                d.set(1, forKey: seedRuKey)
                changed = true
            }
            if d.integer(forKey: seedKey) < 1, spellLangs() != nil {    // английские, которых нет в системном словаре
                a += enDefaults(excluding: Set(a.map { $0.lowercased() }))
                d.set(1, forKey: seedKey)
                changed = true
            }
            if changed { d.set(a, forKey: key) }
            return a
        }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
            UserDefaults.standard.set(1, forKey: seedKey)
            UserDefaults.standard.set(1, forKey: seedRuKey)
            exactCache = nil
            stemCache = nil
            NotificationCenter.default.post(name: .layoutDictChanged, object: nil)
        }
    }

    /// Возвращает стандартные имена, которых в списке нет; сколько добавлено
    @discardableResult static func restoreDefaults() -> Int {
        let a = names
        let have = Set(a.map { $0.lowercased() })
        let add = ruDefaults(excluding: have) + enDefaults(excluding: have)
        if !add.isEmpty { names = a + add }
        return add.count
    }

    /// «андрей» → «Андрей», «анна-мария» → «Анна-Мария»; записанное с заглавными (McDonald) не меняется
    static func capitalized(_ s: String) -> String {
        var out = "", up = true
        for c in s { out += up ? String(c).uppercased() : String(c); up = (c == "-") }
        return out
    }

    /// Приводит введённое к виду записи: без знаков по краям, строчное — с заглавной буквы
    static func normalize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while let f = s.first, !f.isLetter { s.removeFirst() }
        while let l = s.last, !l.isLetter { s.removeLast() }
        return s == s.lowercased() ? capitalized(s) : s
    }

    /// Проверка формата имени: nil — годится, иначе текст ошибки
    static func validate(_ s: String) -> String? {
        if s.isEmpty { return T("Введите имя.") }
        if s.contains(where: { $0.isNewline || $0 == "\t" }) { return T("Только одна строка.") }
        if s.contains(" ") { return T("Одно имя без пробелов. Двойное пишется через дефис.") }
        if s.count > maxLength { return Tf("Не длиннее %@ символов.", "\(maxLength)") }
        if s.contains(where: { $0.isNumber }) { return T("Цифры не поддерживаются: слова с цифрами переключатель не трогает.") }
        let allowed = Set<Character>(["-", "'", "’"])
        if let bad = s.first(where: { !$0.isLetter && !allowed.contains($0) }) {
            return Tf("Недопустимый символ: «%@». Можно буквы, дефис и апостроф.", String(bad))
        }
        var cyr = false, lat = false
        for u in s.unicodeScalars where CharacterSet.letters.contains(u) {
            if (0x0400...0x04FF).contains(u.value) { cyr = true }
            else if u.isASCII { lat = true }
            else { return Tf("Недопустимый символ: «%@». Можно буквы, дефис и апостроф.", String(u)) }
        }
        if cyr && lat { return T("Нельзя смешивать русские и английские буквы в одной записи.") }
        if s.filter({ $0.isLetter }).count < 2 { return T("Не короче двух букв.") }
        if let f = s.first, !f.isLetter { return T("Слово должно начинаться с буквы.") }
        if let l = s.last, !l.isLetter { return T("Имя должно заканчиваться буквой.") }
        if s.contains("--") || s.contains("''") || s.contains("-'") || s.contains("'-") { return T("Знаки не могут идти подряд.") }
        return nil
    }

    static func has(_ s: String) -> Bool { exact(s.lowercased()) != nil }

    @discardableResult static func add(_ raw: String) -> String? {
        let w = normalize(raw)
        if let e = validate(w) { return e }
        if has(w) { return Tf("Уже есть в списке имён: «%@»", w) }
        var a = names
        if a.count >= maxNames { return T("Список имён заполнен.") }
        a.append(w)
        names = a
        return nil
    }

    static func replace(_ old: String, with raw: String) -> String? {
        let w = normalize(raw)
        if let e = validate(w) { return e }
        if w.lowercased() != old.lowercased(), has(w) { return Tf("Уже есть в списке имён: «%@»", w) }
        var a = names
        guard let i = a.firstIndex(of: old) else { return add(w) }
        a[i] = w
        names = a
        return nil
    }

    static func remove(_ w: String) { names = names.filter { $0 != w } }

    // MARK: Поиск имени

    private static let endings: Set<String> = ["а", "я", "у", "ю", "е", "ы", "и", "й", "ь", "ой", "ей", "ем", "ём", "ом", "ою", "ею", "ью",
        "ов", "ев", "ам", "ям", "ами", "ями", "ах", "ях", "ым", "им", "ых", "ыми", "ого", "его", "ому", "ему", "го", "му",
        "ие", "ия", "ию", "ии", "ией", "ием", "ьи", "ьей"]

    private static func build() {
        var ex: [String: String] = [:], st = Set<String>()
        for n in names {
            let l = n.lowercased()
            ex[l] = n
            if LayoutDictionary.isCyrillic(n), n.count >= 4, !n.contains("-") { st.insert(stem(l)) }
        }
        exactCache = ex
        stemCache = st
    }

    /// Основа русского имени: без одной конечной «а», «я», «й», «ь» (Анна → анн, Дмитрий → дмитри, Игорь → игор)
    private static func stem(_ l: String) -> String {
        if let last = l.last, "аяйь".contains(last) { return String(l.dropLast()) }
        return l
    }

    private static func exact(_ l: String) -> String? {
        if exactCache == nil { build() }
        return exactCache![l]
    }

    /// Имя в правильном написании, если слово — имя из списка (в том числе в падежной форме); иначе nil. Регистр слова не важен
    static func resolve(_ s: String) -> String? {
        let l = s.lowercased()
        guard l.count >= 2 else { return nil }
        if let e = exact(l) { return e }
        guard declEnabled, l.count >= 5, LayoutDictionary.isCyrillic(l) else { return nil }
        if stemCache == nil { build() }
        let c = Array(l)
        for e in 1...3 where c.count - e >= 3 {
            if endings.contains(String(c.suffix(e))), stemCache!.contains(String(c.prefix(c.count - e))) { return capitalized(l) }
        }
        return nil
    }
}

// MARK: - Копия и восстановление словарей (слова и имена одним файлом)

enum DictionaryBackup {
    private static let format = "StartLayoutDictionaries"

    /// Сохраняет оба словаря в один файл; возвращает сообщение для окна настроек (nil — отменено)
    static func save() -> String? {
        let p = NSSavePanel()
        p.title = T("Копия словарей")
        p.nameFieldStringValue = "Start-dictionaries.json"
        p.allowedContentTypes = [UTType.json]
        NSApp.activate(ignoringOtherApps: true)
        guard p.runModal() == .OK, let url = p.url else { return nil }
        let obj: [String: Any] = ["format": format, "version": 1,
                                  "date": ISO8601DateFormatter().string(from: Date()),
                                  "words": LayoutDictionary.words, "names": LayoutNames.names]
        do {
            let data = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url, options: .atomic)
            return Tf("Сохранено: слов %@, имён %@", "\(LayoutDictionary.words.count)", "\(LayoutNames.names.count)")
        } catch {
            return Tf("Не удалось сохранить: %@", error.localizedDescription)
        }
    }

    /// Восстанавливает словари из файла: заменить текущие или добавить к ним; возвращает сообщение (nil — отменено)
    static func restore() -> String? {
        let p = NSOpenPanel()
        p.title = T("Восстановить словари из копии")
        p.allowedContentTypes = [UTType.json]
        p.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard p.runModal() == .OK, let url = p.url else { return nil }
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              obj["format"] as? String == format else { return T("Это не копия словарей «Пуска».") }
        var okWords: [String] = [], okNames: [String] = []
        var seenW = Set<String>(), seenN = Set<String>()
        var skipped = 0
        for w in (obj["words"] as? [String] ?? []) {
            let t = w.trimmingCharacters(in: .whitespacesAndNewlines)
            if LayoutDictionary.validate(t) == nil, seenW.insert(t.lowercased()).inserted { okWords.append(t) } else { skipped += 1 }
        }
        for n in (obj["names"] as? [String] ?? []) {
            let t = LayoutNames.normalize(n)
            if LayoutNames.validate(t) == nil, seenN.insert(t.lowercased()).inserted { okNames.append(t) } else { skipped += 1 }
        }
        let a = NSAlert()
        a.messageText = T("Восстановить словари из копии?")
        a.informativeText = Tf("В копии: слов %@, имён %@. Добавить их к текущим или заменить текущие словари?", "\(okWords.count)", "\(okNames.count)")
        a.addButton(withTitle: T("Добавить к текущим"))
        a.addButton(withTitle: T("Заменить"))
        a.addButton(withTitle: T("Отмена"))
        let r = a.runModal()
        guard r == .alertFirstButtonReturn || r == .alertSecondButtonReturn else { return nil }
        if r == .alertFirstButtonReturn {
            let hw = Set(LayoutDictionary.words.map { $0.lowercased() }), hn = Set(LayoutNames.names.map { $0.lowercased() })
            LayoutDictionary.words = Array((LayoutDictionary.words + okWords.filter { !hw.contains($0.lowercased()) }).prefix(LayoutDictionary.maxWords))
            LayoutNames.names = Array((LayoutNames.names + okNames.filter { !hn.contains($0.lowercased()) }).prefix(LayoutNames.maxNames))
        } else {
            _ = LayoutDictionary.words
            LayoutDictionary.words = Array(okWords.prefix(LayoutDictionary.maxWords))
            LayoutNames.names = Array(okNames.prefix(LayoutNames.maxNames))
        }
        var msg = Tf("Восстановлено: слов %@, имён %@", "\(LayoutDictionary.words.count)", "\(LayoutNames.names.count)")
        if skipped > 0 { msg += Tf(" (пропущено неподходящих записей: %@)", "\(skipped)") }
        return msg
    }
}

// MARK: - Окно настроек: русские и английские слова и имена отдельно, поиск, добавление, правка, удаление, копия

struct LayoutDictionaryEditor: View {
    @State private var list = LayoutDictionary.words
    @State private var names = LayoutNames.names
    @State private var field = ""
    @State private var search = ""
    @State private var editing: String? = nil
    @State private var error: String? = nil
    @State private var info: String? = nil
    @State private var lang = 0                              // 0 — русские слова, 1 — английские, 2 — имена
    @State private var caps = LayoutNames.capsEnabled
    @State private var decl = LayoutNames.declEnabled

    private func inTab(_ w: String) -> Bool { LayoutDictionary.isCyrillic(w) == (lang == 0) }
    private var shown: [String] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let base = lang == 2 ? names : list.filter { inTab($0) }
        return base.filter { q.isEmpty || $0.lowercased().contains(q) }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(T("Мой словарь")).fontWeight(.semibold)
            if lang == 2 {
                Text(T("Имена и фамилии, которых нет в системном словаре (коллеги, клиенты, города). Имя, набранное не в той раскладке, исправляется сразу с заглавной буквы, а набранное строчными получает заглавную первую букву. Русские имена узнаются и в падежах («Мурата», «Мурату»). Сразу заполнено распространёнными русскими именами (кроме совпадающих с обычными словами: «Вера», «Лев», «Роман») и английскими, которых нет в системном словаре; всё можно менять и удалять. Одно слово, двойное имя через дефис. Добавить на лету: ⇧⌃⌥Пробел, затем «Имя»."))
                    .font(.caption).foregroundColor(.secondary)
                Toggle(T("Исправлять регистр имён"), isOn: $caps)
                Toggle(T("Узнавать склонения"), isOn: $decl)
            } else {
                Text(T("Слова, сокращения («OS», «RTSP», «т.д.») и короткие фразы («и т.д.», «т. е.»), которые переключатель не исправляет, а при необходимости подставляет сам. Сразу заполнен самыми употребимыми сокращениями, которых нет в системном словаре; всё можно менять и удалять. До четырёх слов через один пробел, только буквы одного алфавита, можно дефис, апостроф и точку. Регистр не важен. Фраза работает по словам: переключатель знает каждое слово из неё. Слова из своих словарей важнее системного. Добавить можно и на лету: ⇧⌃⌥Пробел — выделенное или предыдущее слово."))
                    .font(.caption).foregroundColor(.secondary)
            }
            Picker("", selection: $lang) {
                Text("\(T("Русские")) (\(list.filter { LayoutDictionary.isCyrillic($0) }.count))").tag(0)
                Text("\(T("Английские")) (\(list.filter { !LayoutDictionary.isCyrillic($0) }.count))").tag(1)
                Text("\(T("Имена")) (\(names.count))").tag(2)
            }
            .pickerStyle(SegmentedPickerStyle()).labelsHidden()
            HStack {
                TextField(lang == 2 ? T("Имя") : T("Слово или сокращение"), text: $field, onCommit: save)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Button(editing == nil ? T("Добавить") : T("Сохранить"), action: save)
                if editing != nil { Button(T("Отмена")) { field = ""; editing = nil; error = nil } }
            }
            if let e = error { Text(e).font(.caption).foregroundColor(.red) }
            if let i = info { Text(i).font(.caption).foregroundColor(.secondary) }
            TextField(T("Поиск"), text: $search).textFieldStyle(RoundedBorderTextFieldStyle())
            if shown.isEmpty {
                Text(search.isEmpty ? T("В этой вкладке записей пока нет.") : T("Ничего не найдено."))
                    .font(.caption).foregroundColor(.secondary)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(shown, id: \.self) { w in
                            HStack {
                                Text(w)
                                Spacer()
                                Button(T("Изменить")) { editing = w; field = w; error = nil; info = nil }
                                Button(T("Удалить")) {
                                    if lang == 2 { LayoutNames.remove(w) } else { LayoutDictionary.remove(w) }
                                    if editing == w { editing = nil; field = "" }
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 170)
            }
            HStack {
                Button(lang == 2 ? T("Вернуть стандартные имена") : T("Вернуть стандартные слова")) {
                    let n = lang == 2 ? LayoutNames.restoreDefaults() : LayoutDictionary.restoreDefaults()
                    error = nil
                    info = Tf("Добавлено записей: %@", "\(n)")
                }
                Text(Tf("Всего записей: %@", "\(lang == 2 ? names.count : list.count)")).font(.caption).foregroundColor(.secondary)
            }
            HStack {
                Button(T("Сохранить копию словарей…")) { error = nil; if let m = DictionaryBackup.save() { info = m } }
                Button(T("Восстановить из копии…")) { error = nil; if let m = DictionaryBackup.restore() { info = m } }
            }
            Text(T("Копия — один файл: слова, сокращения, фразы и имена.")).font(.caption).foregroundColor(.secondary)
        }
        .onReceive(NotificationCenter.default.publisher(for: .layoutDictChanged)) { _ in
            list = LayoutDictionary.words
            names = LayoutNames.names
        }
        .onChange(of: caps) { LayoutNames.capsEnabled = $0 }
        .onChange(of: decl) { LayoutNames.declEnabled = $0 }
        .onChange(of: lang) { _ in field = ""; editing = nil; error = nil; info = nil }
    }

    private func save() {
        info = nil
        let word = field.trimmingCharacters(in: .whitespacesAndNewlines)
        let e: String?
        if lang == 2 { e = editing.map { LayoutNames.replace($0, with: field) } ?? LayoutNames.add(field) }
        else { e = editing.map { LayoutDictionary.replace($0, with: field) } ?? LayoutDictionary.add(field) }
        error = e
        if e == nil {
            if lang != 2 { lang = LayoutDictionary.isCyrillic(word) ? 0 : 1 }      // вкладка, в которую попало слово
            if !search.isEmpty, !word.lowercased().contains(search.lowercased()) { search = "" }
            field = ""
            editing = nil
        }
    }
}

// MARK: - Плашка «Добавить в словарь?»

private final class AskPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private final class AskView: NSView {
    var onAnswer: ((Int) -> Void)?                          // 0 — нет, 1 — как слово, 2 — как имя
    private let title: String
    private let kinds: [Int]
    private let no = NSButton()

    init(title: String, canWord: Bool, canName: Bool) {
        self.title = title
        kinds = canWord && canName ? [1, 2] : [canName ? 2 : 1]
        super.init(frame: NSRect(x: 0, y: 0, width: 320, height: 84))
        var x: CGFloat = 50
        for kind in kinds {
            let b = NSButton()
            b.title = kinds.count == 1 ? T("Да") : (kind == 1 ? T("Слово") : T("Имя"))
            b.bezelStyle = .rounded
            b.keyEquivalent = kind == kinds[0] ? "\r" : ""
            b.frame = NSRect(x: x, y: 10, width: 74, height: 26)
            b.tag = kind
            b.target = self
            b.action = #selector(tap(_:))
            addSubview(b)
            x += 80
        }
        no.title = T("Нет")
        no.bezelStyle = .rounded
        no.keyEquivalent = "\u{1b}"
        no.frame = NSRect(x: x, y: 10, width: 74, height: 26)
        no.tag = 0
        no.target = self
        no.action = #selector(tap(_:))
        addSubview(no)
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func tap(_ b: NSButton) { onAnswer?(b.tag) }

    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        switch (event.charactersIgnoringModifiers ?? "").lowercased() {
        case "y", "д": onAnswer?(kinds[0])
        case "i", "и": if kinds.count > 1 { onAnswer?(2) }
        case "n", "н": onAnswer?(0)
        default: super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: r, xRadius: 12, yRadius: 12)
        NSColor.windowBackgroundColor.setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()
        if let img = NSImage(systemSymbolName: "text.book.closed", accessibilityDescription: nil) {
            let icon = img.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 18, weight: .semibold)) ?? img
            let tinted = NSImage(size: icon.size, flipped: false) { rect in
                icon.draw(in: rect)
                NSColor.controlAccentColor.set()
                rect.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: NSRect(x: 16, y: bounds.height - 16 - tinted.size.height, width: tinted.size.width, height: tinted.size.height))
        }
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byTruncatingMiddle
        (title as NSString).draw(in: NSRect(x: 50, y: 48, width: bounds.width - 64, height: 18),
                                 withAttributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                                                  .foregroundColor: NSColor.labelColor, .paragraphStyle: para])
    }
}

final class DictionaryPrompt {
    static let shared = DictionaryPrompt()
    private var panel: AskPanel?
    private var timeout: DispatchWorkItem?

    /// Спрашивает «Добавить в словарь?» (слово и/или имя); Да — Enter, Y или Д; «Имя» — I или И; Нет — Esc, N или Н;
    /// без ответа через 12 секунд считается «Нет». Ответ: 0 — нет, 1 — слово, 2 — имя
    func ask(word: String, canWord: Bool, canName: Bool, done: @escaping (Int) -> Void) {
        close(animated: false)
        let title = canWord ? Tf("Добавить в словарь?: «%@»", word) : Tf("Добавить в имена?: «%@»", word)
        let view = AskView(title: title, canWord: canWord, canName: canName)
        let size = view.frame.size
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
        let shown = NSPoint(x: screen.visibleFrame.maxX - size.width - 16, y: screen.visibleFrame.minY + 16)
        let hidden = NSPoint(x: shown.x, y: screen.frame.minY - size.height - 8)
        let p = AskPanel(contentRect: NSRect(origin: hidden, size: size), styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .screenSaver
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.contentView = view
        panel = p
        var answered = false
        let answer: (Int) -> Void = { [weak self] kind in
            guard !answered else { return }
            answered = true
            self?.close(animated: true)
            done(kind)
        }
        view.onAnswer = answer
        p.makeKeyAndOrderFront(nil)
        p.makeFirstResponder(view)
        NSAnimationContext.runAnimationGroup { c in
            c.duration = 0.25
            c.timingFunction = CAMediaTimingFunction(name: .easeOut)
            p.animator().setFrame(NSRect(origin: shown, size: size), display: true)
        }
        let t = DispatchWorkItem { answer(0) }
        timeout = t
        DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: t)
    }

    private func close(animated: Bool) {
        timeout?.cancel()
        timeout = nil
        guard let p = panel else { return }
        panel = nil
        if !animated { p.orderOut(nil); return }
        var f = p.frame
        f.origin.y = (p.screen?.frame.minY ?? 0) - f.height - 8
        NSAnimationContext.runAnimationGroup({ c in
            c.duration = 0.25
            c.timingFunction = CAMediaTimingFunction(name: .easeIn)
            p.animator().setFrame(f, display: true)
        }, completionHandler: { p.orderOut(nil) })
    }
}
