import SwiftUI
import AppKit
import CoreWLAN
import CoreLocation

// MARK: - Wi-Fi: поиск свободного канала
//
// Сканирует эфир встроенным Wi-Fi (CoreWLAN) и показывает сети, их каналы и уровень сигнала, а ещё загрузку каждого канала
// и подсказку, какой канал свободнее. В 2,4 ГГц соседние каналы перекрываются, поэтому нагрузка считается с учётом
// перекрытия, а лучшим предлагается один из непересекающихся 1, 6, 11. macOS без доступа к геолокации прячет названия сетей
// и может не отдавать каналы вовсе, поэтому программа просит этот доступ (только для сканирования, место не определяется).

struct WiFiNet: Identifiable {
    let id = UUID()
    let ssid: String
    let bssid: String
    let channel: Int
    let band: Int          // 2, 5 или 6 (ГГц)
    let width: Int         // МГц
    let rssi: Int
    let secured: Bool
    let current: Bool
}

final class WiFiScanner: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var nets: [WiFiNet] = []
    @Published var scanning = false
    @Published var message = ""
    @Published var locationDenied = false
    @Published var scanned = false
    /// Название вашей сети: её сигнал не считается помехой (иначе после переезда на «свободный» канал самым выгодным стал бы прежний)
    @Published var ownSSID: String = UserDefaults.standard.string(forKey: "wifi.own") ?? "" {
        didSet { UserDefaults.standard.set(ownSSID, forKey: "wifi.own") }
    }
    private let lm = CLLocationManager()

    override init() {
        super.init()
        lm.delegate = self
    }

    func start() {
        let st = lm.authorizationStatus
        if st == .notDetermined { lm.requestWhenInUseAuthorization() }
        locationDenied = (st == .denied || st == .restricted)
        scan()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        locationDenied = (manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted)
        if manager.authorizationStatus == .authorizedAlways { scan() }
    }

    func scan() {
        guard !scanning else { return }
        scanning = true
        message = ""
        DispatchQueue.global(qos: .userInitiated).async {
            var out: [WiFiNet] = []
            var msg = ""
            if let iface = CWWiFiClient.shared().interface() {
                let curSSID = iface.ssid(), curBSSID = iface.bssid()
                do {
                    let set = try iface.scanForNetworks(withSSID: nil)
                    for n in set {
                        guard let ch = n.wlanChannel else { continue }
                        let band: Int
                        switch ch.channelBand {
                        case .band2GHz: band = 2
                        case .band5GHz: band = 5
                        case .band6GHz: band = 6
                        default: band = ch.channelNumber <= 14 ? 2 : 5
                        }
                        let w: Int
                        switch ch.channelWidth {
                        case .width40MHz: w = 40
                        case .width80MHz: w = 80
                        case .width160MHz: w = 160
                        default: w = 20
                        }
                        let isCur = (n.bssid != nil && n.bssid == curBSSID) || (n.bssid == nil && n.ssid != nil && n.ssid == curSSID)
                        out.append(WiFiNet(ssid: n.ssid ?? "", bssid: n.bssid ?? "", channel: ch.channelNumber, band: band,
                                           width: w, rssi: n.rssiValue, secured: !n.supportsSecurity(.none), current: isCur))
                    }
                    if out.isEmpty { msg = T("Сети не найдены. Если Wi-Fi включён, проверьте доступ к геолокации: без него macOS не отдаёт результаты сканирования.") }
                } catch {
                    msg = T("Не удалось просканировать эфир") + ": \(error.localizedDescription)"
                }
            } else {
                msg = T("На этом Mac нет Wi-Fi или он выключен.")
            }
            DispatchQueue.main.async {
                self.nets = out.sorted { $0.rssi > $1.rssi }
                // по умолчанию своя сеть — та, к которой подключён этот Mac
                if self.ownSSID.isEmpty || !out.contains(where: { $0.ssid == self.ownSSID }),
                   let cur = out.first(where: { $0.current && !$0.ssid.isEmpty }) { self.ownSSID = cur.ssid }
                self.message = msg
                self.scanning = false
                self.scanned = true
            }
        }
    }

    // MARK: загрузка каналов

    func isOwn(_ n: WiFiNet) -> Bool { n.current || (!ownSSID.isEmpty && n.ssid == ownSSID) }
    var ownNets: [WiFiNet] { nets.filter { isOwn($0) } }

    static let channels24 = Array(1...13)
    static let channels5 = [36, 40, 44, 48, 52, 56, 60, 64, 100, 104, 108, 112, 116, 120, 124, 128, 132, 136, 140, 144, 149, 153, 157, 161, 165]

    /// Блоки каналов 5 ГГц по ширине: широкая сеть занимает сразу несколько каналов по 20 МГц
    static func blocks5(width: Int) -> [[Int]] {
        switch width {
        case 40: return [[36, 40], [44, 48], [52, 56], [60, 64], [100, 104], [108, 112], [116, 120], [124, 128], [132, 136], [140, 144], [149, 153], [157, 161]]
        case 80: return [[36, 40, 44, 48], [52, 56, 60, 64], [100, 104, 108, 112], [116, 120, 124, 128], [132, 136, 140, 144], [149, 153, 157, 161]]
        case 160: return [[36, 40, 44, 48, 52, 56, 60, 64], [100, 104, 108, 112, 116, 120, 124, 128]]
        default: return channels5.map { [$0] }
        }
    }

    /// Какие каналы по 20 МГц занимает чужая сеть
    private func covered(_ n: WiFiNet) -> [Int] {
        if n.band == 2 { return [n.channel] }
        return WiFiScanner.blocks5(width: n.width).first(where: { $0.contains(n.channel) }) ?? [n.channel]
    }

    /// Нагрузка канала по 20 МГц только от чужих сетей (своя не считается), с учётом перекрытия каналов 2,4 ГГц
    func load(channel c: Int, band: Int) -> Double {
        var sum = 0.0
        for n in nets where n.band == band && !isOwn(n) && n.rssi > -92 {
            let loud = Double(max(0, 100 + n.rssi))          // −40 дБм → 60, −90 дБм → 10
            if band == 2 {
                let d = abs(n.channel - c)
                if d < 5 { sum += loud * (1 - Double(d) / 5) }
            } else if covered(n).contains(c) {
                sum += loud
            }
        }
        return sum
    }

    private func score(_ block: [Int], band: Int) -> Double { block.reduce(0) { $0 + load(channel: $1, band: band) } }
    private func usesDFS(_ block: [Int]) -> Bool { block.contains { $0 >= 52 && $0 <= 144 } }

    struct Advice {
        let best: [Int]          // каналы лучшего блока
        let bestScore: Double
        let current: [Int]?      // каналы вашей сети в этом диапазоне
        let currentScore: Double
        let width: Int
        var keep: Bool { current != nil && (current! == best || currentScore <= bestScore + 20) }
    }

    func advice(band: Int) -> Advice? {
        guard nets.contains(where: { $0.band == band }) else { return nil }
        let own = ownNets.filter { $0.band == band }.max(by: { $0.rssi < $1.rssi })
        let width = band == 2 ? 20 : (own?.width ?? 40)
        let blocks: [[Int]] = band == 2 ? [[1], [6], [11]] : WiFiScanner.blocks5(width: width)
        let best = blocks.min { a, b in
            let sa = score(a, band: band), sb = score(b, band: band)
            if abs(sa - sb) > 0.001 { return sa < sb }
            return !usesDFS(a) && usesDFS(b)       // при равной нагрузке каналы без DFS (36–48 и 149+) предпочтительнее
        }
        guard let b = best else { return nil }
        let cur: [Int]? = own.map { o in
            band == 2 ? [o.channel] : (WiFiScanner.blocks5(width: width).first(where: { $0.contains(o.channel) }) ?? [o.channel])
        }
        return Advice(best: b, bestScore: score(b, band: band), current: cur, currentScore: cur.map { score($0, band: band) } ?? 0, width: width)
    }
}

struct WiFiView: View {
    @StateObject private var w = WiFiScanner()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button { w.start() } label: { Label(w.scanning ? T("Сканирую…") : T("Сканировать"), systemImage: "wifi") }
                    .disabled(w.scanning)
                if w.locationDenied {
                    Button(T("Открыть настройки геолокации")) {
                        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") { NSWorkspace.shared.open(u) }
                    }
                }
                Spacer()
                if w.scanned && !w.nets.isEmpty {
                    Text(T("Моя сеть")).foregroundColor(.secondary)
                    Picker("", selection: $w.ownSSID) {
                        Text(T("не выбрана")).tag("")
                        ForEach(Array(Set(w.nets.map { $0.ssid }.filter { !$0.isEmpty })).sorted(), id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                    .help(T("Сигнал вашей сети не считается помехой: рекомендация не изменится после того, как вы переведёте роутер на выбранный канал."))
                }
            }
            if w.locationDenied {
                Text(T("Доступ к геолокации выключен: macOS скрывает названия сетей и каналы. Включите «Пуск» в «Службах геолокации». Место программа не определяет."))
                    .font(.caption).foregroundColor(.red).fixedSize(horizontal: false, vertical: true)
            }
            if !w.message.isEmpty {
                Text(w.message).font(.caption).foregroundColor(.red).fixedSize(horizontal: false, vertical: true)
            }
            if w.scanned && !w.nets.isEmpty {
                recommendation
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        chart(T("2,4 ГГц: помехи от соседей по каналам"), band: 2, channels: WiFiScanner.channels24)
                        if w.nets.contains(where: { $0.band == 5 }) {
                            chart(T("5 ГГц: помехи от соседей по каналам"), band: 5, channels: WiFiScanner.channels5)
                        }
                        netList
                    }
                    .padding(.trailing, 6)
                }
            } else if !w.scanned {
                Text(T("Нажмите «Сканировать»: программа посмотрит, какие сети и на каких каналах работают рядом, и подскажет свободный канал для вашего роутера."))
                    .foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onAppear { w.start() }
    }

    private func chanText(_ c: [Int]) -> String { c.count == 1 ? "\(c[0])" : "\(c.first!)–\(c.last!)" }

    /// Зелёный — всё хорошо, оранжевый — стоит поменять, красный — помех много; значок дублирует цвет
    private func adviceLine(_ title: String, band: Int) -> some View {
        Group {
            if let a = w.advice(band: band) {
                let gain: Int = {
                    guard let _ = a.current, a.currentScore > 0 else { return 0 }
                    return Int(round((a.currentScore - a.bestScore) / a.currentScore * 100))
                }()
                let level: (Color, String) = a.keep ? (.green, "checkmark.circle.fill")
                    : (gain >= 40 ? (.red, "xmark.octagon.fill") : (.orange, "exclamationmark.triangle.fill"))
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: level.1).foregroundColor(level.0).font(.system(size: 16))
                    VStack(alignment: .leading, spacing: 2) {
                        if a.keep, let cur = a.current {
                            Text(title + ": " + T("оставайтесь на канале") + " \(chanText(cur))").font(.headline).foregroundColor(level.0)
                            Text(T("Это уже один из самых свободных вариантов, менять не нужно."))
                                .font(.caption).foregroundColor(.green)
                        } else {
                            Text(title + ": " + T("переведите роутер на канал") + " \(chanText(a.best))"
                                 + (band == 5 ? " (\(a.width) " + T("МГц") + ")" : "")).font(.headline).foregroundColor(level.0)
                            if let cur = a.current, a.currentScore > 0 {
                                Text(T("Сейчас у вас канал") + " \(chanText(cur)); " + T("помех от соседей станет меньше примерно на") + " \(gain) %.")
                                    .font(.caption).foregroundColor(level.0)
                            }
                        }
                    }
                }
            }
        }
    }

    private var recommendation: some View {
        VStack(alignment: .leading, spacing: 8) {
            adviceLine(T("2,4 ГГц"), band: 2)
            if w.nets.contains(where: { $0.band == 5 }) { adviceLine(T("5 ГГц"), band: 5) }
            if w.ownNets.isEmpty {
                Label(T("Выберите свою сеть справа вверху. Без этого программа посчитает и ваш роутер помехой, и рекомендация будет прыгать."),
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundColor(.orange).fixedSize(horizontal: false, vertical: true)
            } else {
                Text(T("Расчёт сделан без вашей сети: после переключения на подсказанный канал рекомендация не изменится. В 2,4 ГГц предлагаются 1, 6 и 11 (они не пересекаются), в 5 ГГц учитывается ширина вашего канала. Каналы 52–144 могут отключаться, если рядом радар (DFS)."))
                    .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.12)))
    }

    private func chart(_ title: String, band: Int, channels: [Int]) -> some View {
        let loads = channels.map { w.load(channel: $0, band: band) }
        let mx = max(loads.max() ?? 1, 1)
        let a = w.advice(band: band)
        let best = Set(a?.best ?? [])
        let own = Set(a?.current ?? [])
        return VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline).foregroundColor(.secondary)
            HStack(alignment: .bottom, spacing: band == 2 ? 6 : 3) {
                ForEach(Array(channels.enumerated()), id: \.offset) { i, c in
                    VStack(spacing: 2) {
                        ZStack(alignment: .bottom) {
                            Color.clear.frame(height: 70)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(best.contains(c) ? Color.green : (own.contains(c) ? Color.accentColor : Color.gray.opacity(0.55)))
                                .frame(height: max(2, CGFloat(loads[i] / mx) * 70))
                        }
                        Text("\(c)").font(.system(size: band == 2 ? 11 : 9)).foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Text(T("Высота — помехи от чужих сетей (ваша не считается). Зелёный — куда стоит перейти, синий — где вы сейчас.")).font(.caption2).foregroundColor(.secondary)
        }
    }

    private var netList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(T("Сети рядом") + " (\(w.nets.count))").font(.subheadline).foregroundColor(.secondary).padding(.bottom, 4)
            ForEach(w.nets) { n in
                HStack(spacing: 8) {
                    Image(systemName: n.secured ? "lock.fill" : "lock.open").font(.caption).foregroundColor(.secondary).frame(width: 16)
                    Text(n.ssid.isEmpty ? T("(скрыта)") : n.ssid).fontWeight(w.isOwn(n) ? .semibold : .regular).lineLimit(1)
                    if w.isOwn(n) { Text(T("ваша")).font(.caption2).padding(.horizontal, 5).background(Capsule().fill(Color.accentColor.opacity(0.25))) }
                    Spacer()
                    Text("\(n.band == 2 ? "2,4" : String(n.band)) " + T("ГГц") + " · " + T("канал") + " \(n.channel) · \(n.width) " + T("МГц"))
                        .font(.system(size: 12, design: .monospaced)).foregroundColor(.secondary)
                    Text("\(n.rssi) " + T("дБм")).font(.system(size: 12, design: .monospaced)).frame(width: 74, alignment: .trailing)
                        .foregroundColor(w.isOwn(n) ? (n.rssi >= -67 ? .green : (n.rssi >= -75 ? .orange : .red)) : .primary)
                }
                .padding(.vertical, 3)
                Divider()
            }
        }
    }
}
