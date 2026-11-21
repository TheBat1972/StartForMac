import Cocoa

/// Таблица рекордов игры (12 строк в настройках приложения) и ввод имени — как в «Тетрисе»
final class GameRecordsPanel: NSObject, NSTextFieldDelegate {
    static let limit = 12
    private let key: String
    private weak var host: NSView?
    private let field = NSTextField(frame: .zero)
    private(set) var records: [RestRecord] = []
    private(set) var entering = false
    private var pendingScore = 0
    /// Вызывается после сохранения результата или отмены ввода (Esc)
    var onFinish: (() -> Void)?

    init(key: String, host: NSView) {
        self.key = key
        self.host = host
        super.init()
        field.delegate = self
        field.isHidden = true
        field.font = NSFont.systemFont(ofSize: 15)
        field.placeholderString = T("Ваше имя")
        host.addSubview(field)
        reload()
    }

    private func reload() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([RestRecord].self, from: data) else { records = []; return }
        records = list
    }

    /// Показывает поле для имени; rect — область таблицы рекордов
    func beginEntry(score: Int, in rect: NSRect) {
        pendingScore = score
        entering = true
        field.stringValue = ""
        field.frame = NSRect(x: rect.minX, y: rect.minY + 52, width: rect.width, height: 24)
        field.isHidden = false
        host?.window?.makeFirstResponder(field)
        host?.needsDisplay = true
    }

    /// Прячет поле без сохранения и без вызова onFinish
    func cancel() {
        guard entering else { return }
        entering = false
        field.isHidden = true
        host?.window?.makeFirstResponder(host)
        host?.needsDisplay = true
    }

    private func save() {
        let raw = field.stringValue.replacingOccurrences(of: " ", with: "")
        let name = raw.prefix(1).uppercased() + raw.dropFirst().lowercased()
        var list = records
        list.append(RestRecord(name: name, score: pendingScore))
        list.sort { $0.score > $1.score }
        list = Array(list.prefix(GameRecordsPanel.limit))
        if let data = try? JSONEncoder().encode(list) { UserDefaults.standard.set(data, forKey: key) }
        records = list
        entering = false
        field.isHidden = true
        host?.window?.makeFirstResponder(host)
        host?.needsDisplay = true
        onFinish?()
    }

    func controlTextDidChange(_ obj: Notification) {
        if field.stringValue.count > 15 { field.stringValue = String(field.stringValue.prefix(15)) }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            save()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            cancel()
            onFinish?()
            return true
        }
        return false
    }

    func draw(in rect: NSRect) {
        let head: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 15), .foregroundColor: NSColor.white]
        (T("Рекорды") as NSString).draw(at: NSPoint(x: rect.minX, y: rect.minY), withAttributes: head)
        var y = rect.minY + 30
        if entering {
            let p: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor(white: 1, alpha: 0.85)]
            (T("Запишем результат?") as NSString).draw(at: NSPoint(x: rect.minX, y: y), withAttributes: p)
            y = rect.minY + 90
        }
        let mono = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [.font: mono, .foregroundColor: NSColor.white]
        let shown = records.prefix(GameRecordsPanel.limit)
        let numWidth = max(4, shown.map { String($0.score).count }.max() ?? 4)
        for r in shown {
            let num = String(r.score)
            let line = num + String(repeating: " ", count: numWidth - num.count + 1) + r.name
            (line as NSString).draw(at: NSPoint(x: rect.minX, y: y), withAttributes: attrs)
            y += 20
        }
    }
}
