import SwiftUI
import AppKit

// MARK: - README внутри программы
//
// build.sh кладёт README.md и README.ru.md в Resources; вкладка «О программе» в настройках показывает тот,
// что соответствует языку программы, в прокручиваемом поле (только разделы «Возможности» и «Приватность и безопасность»). Разметка простая: заголовки, списки, таблицы, код, ссылки.

struct ReadmeView: View {
    private struct Row: Identifiable {
        enum Kind { case h1, h2, h3, bullet(Int), table, code, text, gap }
        let id: Int
        let kind: Kind
        let text: String
    }

    private static func load() -> String {
        let name = Loc.english ? "README" : "README.ru"
        guard let u = Bundle.main.url(forResource: name, withExtension: "md"),
              let s = try? String(contentsOf: u, encoding: .utf8) else { return "" }
        // из README показываем только два раздела: возможности и приватность
        let wanted: Set<String> = ["## Возможности", "## Приватность и безопасность", "## Features", "## Privacy and security"]
        var keep = false
        var out: [String] = []
        for line in s.components(separatedBy: "\n") {
            if line.hasPrefix("# ") && !line.hasPrefix("## ") { keep = false; continue }
            if line.hasPrefix("## ") { keep = wanted.contains(line.trimmingCharacters(in: .whitespaces)) }
            if keep { out.append(line) }
        }
        return out.joined(separator: "\n")
    }

    private static func parse(_ text: String) -> [Row] {
        var rows: [Row] = []
        var inCode = false
        for raw in text.components(separatedBy: "\n") {
            let line = raw.replacingOccurrences(of: "\r", with: "")
            let id = rows.count
            if line.hasPrefix("```") { inCode.toggle(); continue }
            if inCode { rows.append(Row(id: id, kind: .code, text: line)); continue }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { if case .gap? = rows.last?.kind {} else { rows.append(Row(id: id, kind: .gap, text: "")) }; continue }
            if line.hasPrefix("### ") { rows.append(Row(id: id, kind: .h3, text: String(line.dropFirst(4)))); continue }
            if line.hasPrefix("## ") { rows.append(Row(id: id, kind: .h2, text: String(line.dropFirst(3)))); continue }
            if line.hasPrefix("# ") { rows.append(Row(id: id, kind: .h1, text: String(line.dropFirst(2)))); continue }
            if trimmed.hasPrefix("|") {
                let cells = trimmed.split(separator: "|", omittingEmptySubsequences: true).map { $0.trimmingCharacters(in: .whitespaces) }
                if cells.allSatisfy({ $0.allSatisfy { "-: ".contains($0) } }) { continue }      // строка «---|---»
                rows.append(Row(id: id, kind: .table, text: cells.joined(separator: "  —  ")))
                continue
            }
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                let indent = line.prefix(while: { $0 == " " }).count / 2
                rows.append(Row(id: id, kind: .bullet(indent), text: String(trimmed.dropFirst(2))))
                continue
            }
            rows.append(Row(id: id, kind: .text, text: trimmed))
        }
        return rows
    }

    private static func inline(_ s: String) -> Text {
        if let a = try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) { return Text(a) }
        return Text(s)
    }

    @State private var rows: [Row] = ReadmeView.parse(ReadmeView.load())

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 3) {
                ForEach(rows) { r in
                    switch r.kind {
                    case .h1: ReadmeView.inline(r.text).font(.title2).fontWeight(.bold).padding(.top, 6)
                    case .h2: ReadmeView.inline(r.text).font(.title3).fontWeight(.semibold).padding(.top, 8)
                    case .h3: ReadmeView.inline(r.text).font(.headline).padding(.top, 4)
                    case .bullet(let n): HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•")
                        ReadmeView.inline(r.text).fixedSize(horizontal: false, vertical: true)
                    }.padding(.leading, CGFloat(n) * 16)
                    case .table: ReadmeView.inline(r.text).font(.callout).foregroundColor(.secondary)
                    case .code: Text(r.text).font(.system(.caption, design: .monospaced))
                    case .text: ReadmeView.inline(r.text).fixedSize(horizontal: false, vertical: true)
                    case .gap: Color.clear.frame(height: 4)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .textSelection(.enabled)
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
        .onReceive(NotificationCenter.default.publisher(for: .languageChanged)) { _ in
            rows = ReadmeView.parse(ReadmeView.load())
        }
    }
}
