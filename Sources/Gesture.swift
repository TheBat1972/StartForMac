// Жест «щипок большим и тремя пальцами» на трекпаде — открыть/скрыть «Пуск».
// Использует системную библиотеку MultitouchSupport (она не документирована Apple), поэтому код защитный:
// если библиотека или функции недоступны, жест просто не работает.

import AppKit

private typealias MTDeviceRef = UnsafeMutableRawPointer
private typealias MTContactCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32
private typealias MTCreateListFn = @convention(c) () -> Unmanaged<CFArray>?
private typealias MTRegisterFn = @convention(c) (MTDeviceRef, MTContactCallback) -> Void
private typealias MTStartFn = @convention(c) (MTDeviceRef, Int32) -> Void

/// Состояние жеста (колбэк вызывается из системного потока, без захвата переменных)
private enum PinchState {
    static var maxSpread: Float = 0
    static var fired = false
    static var lastFire: Double = 0
    static var enabled = true
    static var onPinch: (() -> Void)?
}

private let fingerStride = 96   // размер структуры Finger в MultitouchSupport

private func contactCallback(_ device: UnsafeMutableRawPointer?, _ data: UnsafeMutableRawPointer?,
                             _ count: Int32, _ time: Double, _ frame: Int32) -> Int32 {
    let n = Int(count)
    if n == 0 {
        PinchState.maxSpread = 0
        PinchState.fired = false
        return 0
    }
    guard PinchState.enabled, n >= 4, let base = data, !PinchState.fired else { return 0 }

    var xs = [Float](), ys = [Float]()
    for i in 0..<n {
        let p = base + i * fingerStride
        xs.append(p.load(fromByteOffset: 32, as: Float.self))
        ys.append(p.load(fromByteOffset: 36, as: Float.self))
    }
    let cx = xs.reduce(0, +) / Float(n)
    let cy = ys.reduce(0, +) / Float(n)
    var spread: Float = 0
    for i in 0..<n {
        let dx = (xs[i] - cx) * 1.6          // трекпад шире, чем выше
        let dy = ys[i] - cy
        spread += (dx * dx + dy * dy).squareRoot()
    }
    spread /= Float(n)

    PinchState.maxSpread = max(PinchState.maxSpread, spread)
    // пальцы заметно сошлись относительно самого широкого положения
    if PinchState.maxSpread > 0.18, spread < PinchState.maxSpread * 0.62, time - PinchState.lastFire > 0.8 {
        PinchState.fired = true
        PinchState.lastFire = time
        DispatchQueue.main.async { PinchState.onPinch?() }
    }
    return 0
}

final class PinchGesture {
    static let enabledKey = "pinch.enabled"

    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: PinchGesture.enabledKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: PinchGesture.enabledKey); PinchState.enabled = newValue }
    }

    var onPinch: (() -> Void)? {
        get { PinchState.onPinch }
        set { PinchState.onPinch = newValue }
    }

    private(set) var available = false

    func start() {
        PinchState.enabled = enabled
        guard let h = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_LAZY),
              let c = dlsym(h, "MTDeviceCreateList"),
              let r = dlsym(h, "MTRegisterContactFrameCallback"),
              let s = dlsym(h, "MTDeviceStart") else { return }
        let create = unsafeBitCast(c, to: MTCreateListFn.self)
        let register = unsafeBitCast(r, to: MTRegisterFn.self)
        let startDev = unsafeBitCast(s, to: MTStartFn.self)
        guard let list = create()?.takeRetainedValue() else { return }
        for i in 0..<CFArrayGetCount(list) {
            guard let raw = CFArrayGetValueAtIndex(list, i) else { continue }
            let dev = UnsafeMutableRawPointer(mutating: raw)
            register(dev, contactCallback)
            startDev(dev, 0)
            available = true
        }
    }
}
