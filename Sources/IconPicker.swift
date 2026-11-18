// Окно выбора иконки приложения: банк готовых иконок (для веб-приложений и просто для оформления)
// или картинка с диска. Иконка меняется только внутри «Пуска».
import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum IconBank {
    /// Символы на разные случаи: интернет, общение, работа, медиа, игры, разработка, покупки, жизнь
    static let symbols: [String] = [
        // интернет
        "globe", "safari.fill", "network", "link", "antenna.radiowaves.left.and.right", "wifi",
        // общение
        "message.fill", "bubble.left.and.bubble.right.fill", "envelope.fill", "phone.fill", "video.fill", "person.2.fill", "at", "megaphone.fill",
        // работа
        "briefcase.fill", "doc.text.fill", "tablecells", "chart.bar.fill", "calendar", "checklist", "folder.fill", "tray.full.fill", "paperplane.fill", "pencil.and.outline",
        // медиа
        "play.rectangle.fill", "music.note", "headphones", "mic.fill", "photo.fill", "camera.fill", "film", "tv.fill",
        // игры
        "gamecontroller.fill", "die.face.5.fill", "trophy.fill", "puzzlepiece.fill",
        // разработка
        "terminal.fill", "chevron.left.forwardslash.chevron.right", "hammer.fill", "cpu", "externaldrive.fill", "ladybug.fill",
        // покупки и деньги
        "cart.fill", "creditcard.fill", "banknote.fill", "bag.fill", "building.columns.fill",
        // жизнь
        "heart.fill", "house.fill", "map.fill", "airplane", "car.fill", "fork.knife", "cross.case.fill", "graduationcap.fill",
        "book.fill", "newspaper.fill", "sun.max.fill", "bolt.fill", "star.fill", "lock.fill", "shield.fill", "bell.fill",
        "bookmark.fill", "flag.fill", "lightbulb.fill", "leaf.fill", "pawprint.fill", "gearshape.fill", "wrench.and.screwdriver.fill",
    ]

    static let palette: [NSColor] = [
        NSColor(srgbRed: 0.20, green: 0.48, blue: 0.96, alpha: 1),   // синий
        NSColor(srgbRed: 0.35, green: 0.34, blue: 0.84, alpha: 1),   // индиго
        NSColor(srgbRed: 0.69, green: 0.32, blue: 0.87, alpha: 1),   // фиолетовый
        NSColor(srgbRed: 0.95, green: 0.31, blue: 0.55, alpha: 1),   // розовый
        NSColor(srgbRed: 0.92, green: 0.26, blue: 0.24, alpha: 1),   // красный
        NSColor(srgbRed: 0.98, green: 0.58, blue: 0.10, alpha: 1),   // оранжевый
        NSColor(srgbRed: 0.97, green: 0.78, blue: 0.10, alpha: 1),   // жёлтый
        NSColor(srgbRed: 0.20, green: 0.74, blue: 0.35, alpha: 1),   // зелёный
        NSColor(srgbRed: 0.16, green: 0.70, blue: 0.74, alpha: 1),   // бирюзовый
        NSColor(srgbRed: 0.40, green: 0.42, blue: 0.47, alpha: 1),   // графит
    ]

    /// Скруглённый квадрат с градиентом и белым символом
    static func render(_ symbol: String, color: NSColor, side: CGFloat) -> NSImage? {
        guard let base = NSImage(systemSymbolName: symbol, accessibilityDescription: nil),
              let sym = base.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 100, weight: .semibold)),
              sym.size.width > 0, sym.size.height > 0 else { return nil }
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let tile = rect.insetBy(dx: side * 0.05, dy: side * 0.05)
            let path = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)
            let top = color.blended(withFraction: 0.30, of: .white) ?? color
            NSGradient(starting: top, ending: color)?.draw(in: path, angle: -90)

            // белый символ по центру: сначала рисуем его чёрным, потом закрашиваем белым по его форме
            let k = min(tile.width * 0.54 / sym.size.width, tile.height * 0.54 / sym.size.height)
            let w = sym.size.width * k, h = sym.size.height * k
            let tinted = NSImage(size: NSSize(width: w, height: h), flipped: false) { r in
                sym.draw(in: r)
                NSColor.white.set()
                r.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: NSRect(x: (side - w) / 2, y: (side - h) / 2, width: w, height: h))
            return true
        }
    }
}

struct IconPickerView: View {
    let name: String
    let icon: () -> NSImage
    let hasCustom: () -> Bool
    let apply: (NSImage) -> Void
    let reset: () -> Void
    @ObservedObject var store: Store
    let pickFile: () -> Void
    let close: () -> Void
    @State private var colorIndex = 0

    private let columns = Array(repeating: GridItem(.fixed(56), spacing: 12), count: 8)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(nsImage: icon()).resizable().scaledToFit().frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.headline).lineLimit(1)
                    Text(T("Выберите готовую иконку или картинку с диска")).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 8) {
                Text(T("Цвет:")).foregroundColor(.secondary)
                ForEach(0..<IconBank.palette.count, id: \.self) { i in
                    Circle()
                        .fill(Color(IconBank.palette[i]))
                        .frame(width: 20, height: 20)
                        .overlay(Circle().stroke(Color.primary.opacity(colorIndex == i ? 0.9 : 0), lineWidth: 2).padding(-3))
                        .contentShape(Circle())
                        .onTapGesture { colorIndex = i }
                }
                Spacer()
            }

            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(IconBank.symbols, id: \.self) { sym in
                        if let img = IconBank.render(sym, color: IconBank.palette[colorIndex], side: 112) {
                            Button {
                                if let full = IconBank.render(sym, color: IconBank.palette[colorIndex], side: 512) {
                                    apply(full)
                                }
                                close()
                            } label: {
                                Image(nsImage: img).resizable().frame(width: 56, height: 56)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(4)
            }

            Divider()
            HStack {
                Button(T("Выбрать файл…")) { pickFile() }
                if hasCustom() {
                    Button(T("Вернуть исходную иконку")) { reset(); close() }
                }
                Spacer()
                Button(T("Закрыть")) { close() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(width: 560, height: 520)
    }
}

final class IconPickerController: NSObject, NSWindowDelegate {
    static let shared = IconPickerController()
    private var window: NSWindow?

    func show(name: String, icon: @escaping () -> NSImage, hasCustom: @escaping () -> Bool,
              apply: @escaping (NSImage) -> Void, reset: @escaping () -> Void, store: Store) {
        window?.close()
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
                         styleMask: [.titled, .closable],
                         backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.title = Tf("Иконка для «%@»", name)
        let view = IconPickerView(name: name, icon: icon, hasCustom: hasCustom, apply: apply, reset: reset, store: store,
                                  pickFile: { [weak self] in self?.pickFile(apply: apply) },
                                  close: { [weak self] in DispatchQueue.main.async { self?.window?.close() } })
        w.contentView = NSHostingView(rootView: LangRefresh { view })
        w.center()
        w.delegate = self
        window = w
        // «Пуск» прячем, как при открытии инструментов: окно выбора должно быть сверху
        NSApp.windows.compactMap { $0 as? PopupWindow }.forEach { $0.orderOut(nil) }
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    /// Окно выбора файла открывается листом на окне иконок, поэтому всегда сверху
    private func pickFile(apply: @escaping (NSImage) -> Void) {
        guard let w = window else { return }
        let panel = NSOpenPanel()
        panel.message = T("Выберите картинку (PNG, JPEG, ICNS…)")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.png, .jpeg, .icns, .tiff, .gif, .heic, .bmp]
        panel.beginSheetModal(for: w) { response in
            guard response == .OK, let url = panel.url else { return }
            if let img = NSImage(contentsOf: url) { apply(img) }
            DispatchQueue.main.async { w.close() }
        }
    }

    func windowWillClose(_ notification: Notification) { window = nil }
}
