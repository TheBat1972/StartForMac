// Калькулятор в стиле старого CalcNew (оранжевые клавиши действий, мятные клавиши памяти и функций, зелёные — степени и факториал)
// и конвертер единиц и валют. Единицы, валюты и разбор запросов — те же, что в быстром ответе строки поиска.
import SwiftUI
import AppKit

// MARK: - Дисплей

struct DigitalDisplay: View {
    let text: String
    let expression: String
    let m1: Bool
    let m2: Bool
    var m1Text: String = ""
    var m2Text: String = ""

    private func memCell(_ name: String, on: Bool, value: String) -> some View {
        HStack(spacing: 5) {
            Text(name).font(.system(size: 11, weight: .bold)).opacity(on ? 1 : 0.15)
            Text(on ? value : "").font(.system(size: 9).monospacedDigit()).foregroundColor(.secondary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
        .foregroundColor(.accentColor)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor))
            RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.55), lineWidth: 1)
            VStack(alignment: .trailing, spacing: 0) {
                // ячейки памяти: M1 слева, M2 справа, рядом мелко — содержимое
                HStack(spacing: 0) {
                    memCell("M1", on: m1, value: m1Text)
                    memCell("M2", on: m2, value: m2Text)
                }
                Text(expression.isEmpty ? " " : expression)
                    .font(.system(size: 13).monospacedDigit()).foregroundColor(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: 0)
                // число уменьшается, чтобы поместиться при любом количестве цифр
                Text(text == "Err" ? T("Ошибка") : text)
                    .font(.system(size: 54, weight: .light).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.2)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
        }
        .frame(height: 112)
    }
}

// MARK: - Состояние калькулятора

final class CalcModel: ObservableObject {
    enum Op {
        case add, sub, mul, div, pow, root
        var symbol: String {
            switch self {
            case .add: return "+"
            case .sub: return "−"
            case .mul: return "×"
            case .div: return "÷"
            case .pow: return "^"
            case .root: return "ʸ√"
            }
        }
    }

    @Published private(set) var text = "0"            // что на дисплее
    @Published private(set) var expression = ""       // первое число и выбранное действие
    @Published private(set) var hasM1 = false
    @Published private(set) var hasM2 = false
    @Published private(set) var memText1 = ""         // содержимое ячеек для информационной строки
    @Published private(set) var memText2 = ""

    /// Компактная запись для ячейки памяти: если не помещается — «× 10ⁿ»
    static func memoryText(_ v: Double) -> String {
        guard var s = formatValue(v) else { return "" }
        if s.count > 11 { s = formatValue(v, forceSci: true) ?? s }
        return s
    }

    private var first = 0.0, second = 0.0
    private var oper: Op?
    private var buffer = ""           // число, которое сейчас набирают
    private var m1 = 0.0, m2 = 0.0
    private var failed = false

    private var current: Double {
        get { oper == nil ? first : second }
        set { if oper == nil { first = newValue } else { second = newValue } }
    }

    // MARK: показ чисел

    private static var decimalSeparator: String { Locale.current.decimalSeparator ?? "," }
    private static var groupingSeparator: String { Locale.current.groupingSeparator ?? " " }

    /// Набираемое число с разделением на разряды
    static func formatBuffer(_ b: String) -> String {
        var s = b
        var neg = false
        if s.hasPrefix("-") { neg = true; s.removeFirst() }
        let parts = s.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let intPart = parts.isEmpty ? "0" : String(parts[0])
        var out = ""
        for (i, c) in intPart.enumerated() {
            if i > 0 && (intPart.count - i) % 3 == 0 { out += groupingSeparator }
            out.append(c)
        }
        if parts.count > 1 { out += decimalSeparator + String(parts[1]) }
        return (neg ? "-" : "") + out
    }

    /// Результат для дисплея: до 12 значащих цифр; очень большие и очень малые — с порядком (E)
    static func formatValue(_ v: Double, forceSci: Bool = false) -> String? {
        guard v.isFinite else { return nil }
        if v == 0 { return "0" }
        let a = abs(v)
        if forceSci || a >= 1e15 || a < 1e-9 {
            // порядок записываем как «10 в степени»: 1,2345 × 10²⁵
            let parts = String(format: "%.9e", v).components(separatedBy: "e")
            var mant = parts[0]
            if mant.contains(".") {
                while mant.hasSuffix("0") { mant.removeLast() }
                if mant.hasSuffix(".") { mant.removeLast() }
            }
            let sup: [Character: Character] = ["0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹", "-": "⁻"]
            var e = parts.count > 1 ? parts[1] : "0"
            if e.hasPrefix("+") { e.removeFirst() }
            let exp = Int(e) ?? 0
            let expStr = String(String(exp).map { sup[$0] ?? $0 })
            return mant.replacingOccurrences(of: ".", with: decimalSeparator) + " × 10" + expStr
        }
        let intDigits = a < 1 ? 1 : Int(floor(log10(a))) + 1
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale.current
        f.usesGroupingSeparator = true
        f.maximumFractionDigits = max(0, min(10, 12 - intDigits))
        f.minimumFractionDigits = 0
        return f.string(from: NSNumber(value: v))
    }

    private func show(_ v: Double) {
        if let s = CalcModel.formatValue(v) { text = s } else { fail() }
    }

    private func fail() {
        failed = true
        text = "Err"
        expression = ""
        first = 0; second = 0; oper = nil; buffer = ""
    }

    private func prepare() { if failed { allClear() } }

    func allClear() {
        first = 0; second = 0; oper = nil; buffer = ""; failed = false
        text = "0"
        expression = ""
    }

    // MARK: ввод

    func digit(_ d: Int) {
        prepare()
        if buffer == "0" {
            if d == 0 { return }
            buffer = ""
        }
        buffer += String(d)
        commitBuffer()
    }

    func dot() {
        prepare()
        if buffer.contains(".") { return }
        if buffer.isEmpty { buffer = "0" }
        buffer += "."
        commitBuffer()
    }

    private func commitBuffer() {
        current = Double(buffer) ?? 0
        // после 15 цифр число показывается как «× 10ⁿ», чтобы шрифт не мельчал
        if buffer.filter({ $0.isNumber }).count > 15, let sci = CalcModel.formatValue(current, forceSci: true) {
            text = sci
        } else {
            text = CalcModel.formatBuffer(buffer)
        }
    }

    func backspace() {
        prepare()
        guard !buffer.isEmpty else { return }
        buffer.removeLast()
        if buffer.isEmpty || buffer == "-" {
            buffer = ""
            current = 0
            text = "0"
        } else {
            commitBuffer()
        }
    }

    // MARK: действия

    func op(_ o: Op) {
        prepare()
        if oper != nil {
            equals()
            if failed { return }
        }
        oper = o
        buffer = ""
        second = 0
        expression = (CalcModel.formatValue(first) ?? "") + " " + o.symbol
    }

    func equals() {
        if failed { allClear(); return }
        guard let o = oper else { return }
        let r: Double
        switch o {
        case .add: r = first + second
        case .sub: r = first - second
        case .mul: r = first * second
        case .div: r = first / second
        case .pow: r = Foundation.pow(first, second)
        case .root: r = CalcModel.root(first, second)
        }
        first = r; second = 0; oper = nil; buffer = ""
        expression = ""
        show(first)
    }

    /// Процент, как в обычных калькуляторах:
    /// после «+» и «−» это доля от первого числа (200 + 10% → 200 + 20), после «×» и «÷» — сотая часть (50 × 10% → 50 × 0,1),
    /// без действия — число, делённое на 100
    func percent() {
        prepare()
        var c = current
        if oper != nil, buffer.isEmpty, second == 0 { c = first }      // «50 + %» берёт 50
        let r: Double
        switch oper {
        case .some(.add), .some(.sub): r = first * c / 100
        default: r = c / 100
        }
        current = r
        buffer = ""
        show(r)
    }

    private func unary(_ f: (Double) -> Double) {
        prepare()
        buffer = ""
        let r = f(current)
        current = r
        show(r)
    }

    func negate() { unary { -$0 } }
    func square() { unary { $0 * $0 } }
    func cube() { unary { $0 * $0 * $0 } }
    func sqrt() { unary { $0 < 0 ? Double.nan : $0.squareRoot() } }
    func inverse() { unary { $0 == 0 ? Double.nan : 1 / $0 } }
    func pi() { unary { _ in Double.pi } }
    func factorial() { unary { CalcModel.factorial($0) } }
    func expX() { unary { Foundation.exp($0) } }

    private static func factorial(_ v: Double) -> Double {
        guard v >= 0, v == v.rounded(), v <= 170 else { return Double.nan }
        var r = 1.0
        if v >= 2 { for i in 2...Int(v) { r *= Double(i) } }
        return r
    }

    /// Корень степени y из x; для отрицательного x — только при нечётном целом y
    private static func root(_ x: Double, _ y: Double) -> Double {
        guard y != 0 else { return Double.nan }
        if x >= 0 { return Foundation.pow(x, 1 / y) }
        if y == y.rounded(), abs(y) < 1e9, Int(y) % 2 != 0 { return -Foundation.pow(-x, 1 / y) }
        return Double.nan
    }

    // MARK: память

    func store(_ n: Int) {
        prepare()
        buffer = ""
        if n == 1 { m1 = current; hasM1 = true; memText1 = CalcModel.memoryText(m1) } else { m2 = current; hasM2 = true; memText2 = CalcModel.memoryText(m2) }
    }

    func recall(_ n: Int) {
        prepare()
        buffer = ""
        current = (n == 1) ? m1 : m2
        show(current)
    }

    func clearMemory(_ n: Int) {
        if n == 1 { m1 = 0; hasM1 = false; memText1 = "" } else { m2 = 0; hasM2 = false; memText2 = "" }
    }

    // MARK: буфер обмена

    func copy() {
        copyToPasteboard(QuickCalc.format(current, maxFrac: 10, grouping: false))
    }

    func paste() {
        prepare()
        guard let t = NSPasteboard.general.string(forType: .string) else { return }
        let s = t.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: ".")
        guard let v = Double(s) else { return }
        buffer = ""
        current = v
        show(v)
    }
}

// MARK: - Клавиши

enum CalcKeyKind { case digit, orange, mint, green }

struct CalcKeyStyle: ButtonStyle {
    let kind: CalcKeyKind

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        // цвета как во всём «Пуске»: системный акцент, нейтральный фон, красный для стирания
        let fill: Color
        let text: Color
        switch kind {
        case .orange: fill = Color.accentColor.opacity(pressed ? 0.75 : 1); text = .white
        case .mint:   fill = Color.accentColor.opacity(pressed ? 0.32 : 0.15); text = .accentColor
        case .green:  fill = Color.red.opacity(pressed ? 0.32 : 0.15); text = .red
        case .digit:  fill = pressed ? Color.primary.opacity(0.20) : Color(NSColor.controlBackgroundColor); text = .primary
        }
        return configuration.label
            .foregroundColor(text)
            .background(RoundedRectangle(cornerRadius: 10).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.4), lineWidth: 1))
            .scaleEffect(pressed ? 0.97 : 1)
    }
}

struct CalcKey: View {
    let title: String
    var symbol: String? = nil
    var hint: String? = nil
    let kind: CalcKeyKind
    var fontSize: CGFloat = 20
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                label.frame(maxWidth: .infinity, maxHeight: .infinity)
                if let h = hint {
                    Text(h).font(.system(size: 8, weight: .medium)).opacity(0.55)
                        .padding(.trailing, 6).padding(.top, 3)
                }
            }
        }
        .buttonStyle(CalcKeyStyle(kind: kind))
    }

    @ViewBuilder private var label: some View {
        if let s = symbol {
            Image(systemName: s).font(.system(size: fontSize, weight: .medium))
        } else {
            Text(title).font(.system(size: fontSize, weight: .medium))
        }
    }
}

struct CalculatorPad: View {
    @ObservedObject var calc: CalcModel

    private let w: CGFloat = 76
    private let gap: CGFloat = 8

    var body: some View {
        VStack(spacing: gap) {
            DigitalDisplay(text: calc.text, expression: calc.expression, m1: calc.hasM1, m2: calc.hasM2, m1Text: calc.memText1, m2Text: calc.memText2)
            small {
                mint("→M1") { calc.store(1) }
                mint("M1→") { calc.recall(1) }
                CalcKey(title: "", symbol: "doc.on.doc", kind: .digit, fontSize: 15) { calc.copy() }.frame(width: w, height: 38)
                CalcKey(title: "", symbol: "doc.on.clipboard", kind: .digit, fontSize: 15) { calc.paste() }.frame(width: w, height: 38)
            }
            small {
                mint("→M2") { calc.store(2) }
                mint("M2→") { calc.recall(2) }
                mint("xʸ") { calc.op(.pow) }
                mint("ʸ√x") { calc.op(.root) }
            }
            HStack(spacing: gap) {
                // стирание памяти: две вытянутые зелёные кнопки в одной клетке
                VStack(spacing: 4) {
                    CalcKey(title: "См1", kind: .mint, fontSize: 11) { calc.clearMemory(1) }.frame(width: w, height: 20)
                    CalcKey(title: "См2", kind: .mint, fontSize: 11) { calc.clearMemory(2) }.frame(width: w, height: 20)
                }
                mint("π", 44) { calc.pi() }
                mint("x!", 44) { calc.factorial() }
                mint("eˣ", 44) { calc.expX() }
            }
            small {
                mint("x²") { calc.square() }
                mint("x³") { calc.cube() }
                mint("√") { calc.sqrt() }
                mint("1/x") { calc.inverse() }
            }
            row {
                key("AC", .orange) { calc.allClear() }
                key("±", .orange) { calc.negate() }
                key("%", .orange) { calc.percent() }
                key("÷", .orange, 24) { calc.op(.div) }
            }
            row { num(1); num(2); num(3); key("×", .orange, 24) { calc.op(.mul) } }
            row { num(4); num(5); num(6); key("−", .orange, 24) { calc.op(.sub) } }
            row { num(7); num(8); num(9); key("+", .orange, 24) { calc.op(.add) } }
            HStack(spacing: gap) {
                CalcKey(title: "0", kind: .digit) { calc.digit(0) }
                    .frame(width: w * 2 + gap, height: 58)
                CalcKey(title: ",", kind: .digit, fontSize: 26) { calc.dot() }
                    .frame(width: w, height: 58)
                CalcKey(title: "=", kind: .orange, fontSize: 24) { calc.equals() }
                    .frame(width: w, height: 58)
            }
        }
    }

    private func key(_ t: String, _ k: CalcKeyKind, _ size: CGFloat = 20, _ a: @escaping () -> Void) -> some View {
        CalcKey(title: t, kind: k, fontSize: size, action: a).frame(width: w, height: 58)
    }

    private func num(_ d: Int) -> some View {
        CalcKey(title: String(d), kind: .digit, fontSize: 22) { calc.digit(d) }.frame(width: w, height: 58)
    }

    private func mint(_ t: String, _ h: CGFloat = 38, _ a: @escaping () -> Void) -> some View {
        CalcKey(title: t, kind: .mint, fontSize: 15, action: a).frame(width: w, height: h)
    }

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: gap) { content() }
    }

    private func small<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: gap) { content() }
    }
}

// MARK: - Конвертер

enum ConvCategory: String, CaseIterable, Identifiable {
    case length, mass, volume, temperature, speed, time, data, area, currency
    var id: String { rawValue }

    var title: String {
        switch self {
        case .length: return T("Длина")
        case .mass: return T("Масса")
        case .volume: return T("Объём")
        case .temperature: return T("Температура")
        case .speed: return T("Скорость")
        case .time: return T("Время")
        case .data: return T("Данные")
        case .area: return T("Площадь")
        case .currency: return T("Валюты")
        }
    }

    var symbol: String {
        switch self {
        case .length: return "ruler"
        case .mass: return "scalemass"
        case .volume: return "drop"
        case .temperature: return "thermometer"
        case .speed: return "speedometer"
        case .time: return "clock"
        case .data: return "internaldrive"
        case .area: return "square.dashed"
        case .currency: return "dollarsign.circle"
        }
    }

    /// (подпись, имя в таблице единиц быстрого ответа поиска)
    var units: [(String, String)] {
        switch self {
        case .length: return [("mm", "mm"), ("cm", "cm"), ("m", "m"), ("km", "km"), ("in", "in"), ("ft", "ft"), ("yd", "yd"), ("mi", "mi")]
        case .mass: return [("mg", "mg"), ("g", "g"), ("kg", "kg"), ("t", "tonne"), ("lb", "lb"), ("oz", "oz")]
        case .volume: return [("ml", "ml"), ("l", "l"), ("gal", "gal"), ("pt", "pint")]
        case .temperature: return [("°C", "°c"), ("°F", "°f"), ("K", "k")]
        case .speed: return [("km/h", "km/h"), ("m/s", "m/s"), ("mph", "mph"), ("kn", "kn")]
        case .time: return [("s", "s"), ("min", "min"), ("h", "h"), ("d", "d"), ("wk", "week")]
        case .data: return [("B", "byte"), ("KB", "kb"), ("MB", "mb"), ("GB", "gb"), ("TB", "tb"), ("KiB", "kib"), ("MiB", "mib"), ("GiB", "gib")]
        case .area: return [("m²", "m2"), ("km²", "km2"), ("ha", "ha"), ("acre", "acre")]
        case .currency: return []
        }
    }

    static let currencyCodes = ["USD", "EUR", "RUB", "GBP", "CNY", "JPY", "TRY", "KZT", "UAH", "BYN", "CHF", "AED",
                                "THB", "INR", "KRW", "GEL", "AMD", "AZN", "UZS", "KGS", "PLN"]

    var unitIDs: [String] { self == .currency ? ConvCategory.currencyCodes : units.map { $0.0 } }
}

final class ConverterModel: ObservableObject {
    @Published var category: ConvCategory = .length {
        didSet {
            guard oldValue != category else { return }
            let ids = category.unitIDs
            from = ids.first ?? ""
            to = ids.count > 1 ? ids[1] : (ids.first ?? "")
            if category == .currency {
                from = "USD"; to = "RUB"
                loadRates()
            }
        }
    }
    @Published var from = "mm"
    @Published var to = "cm"
    @Published var text = "1"
    @Published private(set) var note: String?
    @Published private(set) var ratesTick = 0

    func label(_ id: String) -> String {
        guard category == .currency else { return id }
        let name = Locale.current.localizedString(forCurrencyCode: id) ?? ""
        return name.isEmpty ? id : id + " · " + name
    }

    func loadRates() {
        Rates.shared.ensure { [weak self] has, fresh in
            guard let self = self else { return }
            if has, let d = Rates.shared.date {
                let f = DateFormatter()
                f.dateStyle = .medium
                f.timeStyle = .short
                let ds = f.string(from: d)
                self.note = fresh ? Tf("Курс на %@", ds) : Tf("Нет связи — последний сохранённый курс на %@", ds)
            }
            self.ratesTick += 1
        }
    }

    private var value: Double? {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: "."))
    }

    /// Результат для показа и для буфера обмена
    var result: (shown: String, copy: String)? {
        guard let v = value else { return nil }
        let out: Double
        let frac: Int
        if category == .currency {
            let r = Rates.shared.rates
            guard let rf = r[from], let rt = r[to], rf > 0 else { return nil }
            out = v * rt / rf
            frac = abs(out) < 1 ? 4 : 2
        } else {
            guard let key1 = category.units.first(where: { $0.0 == from })?.1,
                  let key2 = category.units.first(where: { $0.0 == to })?.1,
                  let uf = QuickUnits.table[key1], let ut = QuickUnits.table[key2],
                  let r = QuickUnits.convert(v, from: uf, to: ut) else { return nil }
            out = r
            frac = abs(r) >= 1000 ? 2 : (abs(r) >= 1 ? 4 : 6)
        }
        return (QuickCalc.format(out, maxFrac: frac), QuickCalc.format(out, maxFrac: frac, grouping: false))
    }

    func swap() {
        let t = from
        from = to
        to = t
    }
}

struct UnitMenu: View {
    @Binding var selection: String
    let ids: [String]
    let title: (String) -> String

    var body: some View {
        Menu {
            ForEach(ids, id: \.self) { id in
                Button(title(id)) { selection = id }
            }
        } label: {
            Text(selection).font(.system(size: 15, weight: .medium)).frame(minWidth: 60)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

struct ConverterPane: View {
    @ObservedObject var conv: ConverterModel
    @StateObject private var quick = QuickAnswer()
    @State private var query = ""
    @State private var copied = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            quickInput
            Divider()
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(ConvCategory.allCases) { c in
                    Button { conv.category = c } label: {
                        VStack(spacing: 3) {
                            Image(systemName: c.symbol).font(.system(size: 17))
                            Text(c.title).font(.system(size: 11)).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(RoundedRectangle(cornerRadius: 9)
                            .fill(conv.category == c ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.06)))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            converterBox
            Spacer(minLength: 0)
        }
        .onAppear { if conv.category == .currency { conv.loadRates() } }
    }

    private var quickInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(T("15% от 8400, 5 миль в км, 100 usd в руб"), text: $query)
                .textFieldStyle(.roundedBorder)
                .onChange(of: query) { quick.update($0) }
            Group {
                if let item = quick.item {
                    QuickAnswerCard(item: item) { }
                } else {
                    Text(T("Любое выражение или конвертация, как в строке поиска"))
                        .font(.caption).foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.horizontal, 4)
                }
            }
            .frame(height: 74)
        }
    }

    private var converterBox: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                TextField("", text: $conv.text)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 22, weight: .medium))
                UnitMenu(selection: $conv.from, ids: conv.category.unitIDs, title: conv.label)
            }
            HStack {
                Spacer()
                Button { conv.swap() } label: {
                    Image(systemName: "arrow.up.arrow.down").font(.system(size: 15, weight: .medium))
                        .frame(width: 34, height: 26)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.08)))
                }
                .buttonStyle(.plain)
                Spacer()
            }
            HStack(spacing: 10) {
                Text(conv.result?.shown ?? "—")
                    .font(.system(size: 26, weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                UnitMenu(selection: $conv.to, ids: conv.category.unitIDs, title: conv.label)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.07)))
            .contentShape(Rectangle())
            .onTapGesture {
                guard let r = conv.result else { return }
                copyToPasteboard(r.copy)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
            }
            HStack {
                if conv.category == .currency, let n = conv.note {
                    Text(n).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Text(copied ? T("Скопировано") : T("Нажмите, чтобы скопировать результат"))
                    .font(.caption).foregroundColor(copied ? .green : .secondary)
            }
        }
    }
}

// MARK: - Окно

enum CalcTab { case calculator, converter }

final class CalcWindowState: ObservableObject {
    @Published var tab: CalcTab = .calculator
    @Published var langTick = 0
}

struct CalcRootView: View {
    @ObservedObject var state: CalcWindowState
    @ObservedObject var calc: CalcModel
    @ObservedObject var conv: ConverterModel

    var body: some View {
        VStack(spacing: 12) {
            Picker("", selection: $state.tab) {
                Text(T("Калькулятор")).tag(CalcTab.calculator)
                Text(T("Конвертер")).tag(CalcTab.converter)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if state.tab == .calculator {
                CalculatorPad(calc: calc)
                Spacer(minLength: 0)
            } else {
                ConverterPane(conv: conv)
            }
        }
        .padding(16)
        .frame(width: 360, height: 700)
        .id(state.langTick)
    }
}

final class CalcWindowController: NSObject, NSWindowDelegate {
    static let shared = CalcWindowController()
    private var window: NSWindow?
    private let calc = CalcModel()
    private let conv = ConverterModel()
    private let state = CalcWindowState()
    private var monitor: Any?

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 700),
                             styleMask: [.titled, .closable, .miniaturizable],
                             backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            let st = state, cl = calc, cv = conv
            w.contentView = NSHostingView(rootView: LangRefresh { CalcRootView(state: st, calc: cl, conv: cv) })
            w.delegate = self
            if !w.setFrameUsingName("CalcWindow") { w.center() }
            w.setFrameAutosaveName("CalcWindow")
            window = w
            NotificationCenter.default.addObserver(self, selector: #selector(languageChanged), name: .languageChanged, object: nil)
        }
        window?.title = T("Калькулятор")
        installMonitor()
        NSApp.windows.compactMap { $0 as? PopupWindow }.forEach { $0.orderOut(nil) }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func languageChanged() {
        window?.title = T("Калькулятор")
        state.langTick += 1
    }

    func windowWillClose(_ notification: Notification) {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }

    // MARK: клавиатура: цифры, действия, Enter, Esc, Backspace, ⌘C / ⌘V

    private func installMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self = self, let w = self.window, NSApp.keyWindow === w,
                  self.state.tab == .calculator, !(w.firstResponder is NSTextView) else { return e }
            return self.handle(e) ? nil : e
        }
    }

    private func handle(_ e: NSEvent) -> Bool {
        if e.modifierFlags.contains(.command) {
            switch e.charactersIgnoringModifiers?.lowercased() {
            case "c": calc.copy(); return true
            case "v": calc.paste(); return true
            default: return false
            }
        }
        switch e.keyCode {
        case 36, 76: calc.equals(); return true
        case 53: calc.allClear(); return true
        case 51: calc.backspace(); return true
        default: break
        }
        guard let ch = e.characters, ch.count == 1, let c = ch.first else { return false }
        if let d = c.wholeNumberValue, c.isASCII { calc.digit(d); return true }
        switch c {
        case "+": calc.op(.add)
        case "-": calc.op(.sub)
        case "*": calc.op(.mul)
        case "/": calc.op(.div)
        case "=": calc.equals()
        case ".", ",": calc.dot()
        case "%": calc.percent()
        default: return false
        }
        return true
    }
}
