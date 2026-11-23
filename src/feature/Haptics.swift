import AppKit

/** 触控板马达：优先私有 MultitouchSupport（与 os6/nospeaker 同一路径），失败降级系统反馈，再失败静默。 */
final class Haptics {
    static let shared = Haptics()

    private typealias CreateList = @convention(c) () -> Unmanaged<CFArray>?
    private typealias GetID = @convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<UInt64>) -> Int32
    private typealias ActuatorCreate = @convention(c) (UInt64) -> Unmanaged<CFTypeRef>?
    private typealias ActuatorOpen = @convention(c) (CFTypeRef) -> Int32
    private typealias ActuationCreate = @convention(c) (CFDictionary, Int32) -> UnsafeMutableRawPointer?
    private typealias ActuationPlay = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer, UInt32, Float, Float) -> Int32

    private var actuationCreate: ActuationCreate?
    private var actuationPlay: ActuationPlay?
    private var motor: CFTypeRef?
    private var motorPointer: UnsafeMutableRawPointer?

    /// 私有框架是否可用；不可用时界面标注「系统反馈」。
    private(set) var isAvailable = false

    /// 一次拍击：延迟（秒）、频率（Hz）、时长（毫秒）。
    private struct Pulse {
        let delay: Double
        let hz: Double
        let ms: Double
    }

    private let presets: [String: [Pulse]] = [
        "tap": [Pulse(delay: 0, hz: 70, ms: 12)],
        "double": [Pulse(delay: 0, hz: 70, ms: 10),
                   Pulse(delay: 0.11, hz: 70, ms: 10)],
        "triple": [Pulse(delay: 0, hz: 70, ms: 9),
                   Pulse(delay: 0.09, hz: 70, ms: 9),
                   Pulse(delay: 0.18, hz: 70, ms: 9)],
        "long": [Pulse(delay: 0, hz: 45, ms: 240)],
        "heart": [Pulse(delay: 0, hz: 45, ms: 60),
                  Pulse(delay: 0.18, hz: 45, ms: 60),
                  Pulse(delay: 0.76, hz: 45, ms: 60),
                  Pulse(delay: 0.94, hz: 45, ms: 60),
                  Pulse(delay: 1.52, hz: 45, ms: 60),
                  Pulse(delay: 1.70, hz: 45, ms: 60)],
    ]

    /// 五档强度映射到驱动层的 level（0…1）。
    static let strengthLevels: [Float] = [0.35, 0.5, 0.65, 0.8, 1.0]

    /// 预设名与中文名，供界面下拉使用。
    static let presetNames: [(id: String, title: String)] = [
        ("tap", "轻点"), ("double", "双击"), ("triple", "三连"), ("long", "长震"), ("heart", "心跳"),
    ]

    private init() {
        openMotor()
    }

    /** 找到第一块可用触控板并打开它的马达。 */
    private func openMotor() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport",
                                  RTLD_NOW) else { return }
        func load<T>(_ name: String, _ type: T.Type) -> T? {
            guard let symbol = dlsym(handle, name) else { return nil }
            return unsafeBitCast(symbol, to: T.self)
        }
        guard let createList = load("MTDeviceCreateList", CreateList.self),
              let getID = load("MTDeviceGetDeviceID", GetID.self),
              let actuatorCreate = load("MTActuatorCreateFromDeviceID", ActuatorCreate.self),
              let actuatorOpen = load("MTActuatorOpen", ActuatorOpen.self),
              let createActuation = load("MTActuationCreateFromDictionary", ActuationCreate.self),
              let play = load("MTActuationActuate", ActuationPlay.self),
              let list = createList()?.takeRetainedValue() else { return }

        actuationCreate = createActuation
        actuationPlay = play

        for index in 0..<CFArrayGetCount(list) {
            guard let raw = CFArrayGetValueAtIndex(list, index) else { continue }
            let device = UnsafeMutableRawPointer(mutating: raw)
            var deviceID: UInt64 = 0
            guard getID(device, &deviceID) == 0 else { continue }
            guard let ref = actuatorCreate(deviceID)?.takeRetainedValue(), actuatorOpen(ref) == 0 else { continue }
            motor = ref
            motorPointer = Unmanaged.passUnretained(ref as AnyObject).toOpaque()
            isAvailable = true
            break
        }
    }

    /** 按预设播放一段震动；strength 为 1…5 档。 */
    func play(_ preset: String, strength: Int) {
        guard let pulses = presets[preset] ?? presets["double"] else { return }
        let level = Self.strengthLevels[max(0, min(4, strength - 1))]
        guard isAvailable else {
            fallback()
            return
        }
        for pulse in pulses {
            DispatchQueue.main.asyncAfter(deadline: .now() + pulse.delay) { [weak self] in
                self?.pulse(hz: pulse.hz, ms: pulse.ms, level: level)
            }
        }
    }

    /** 单次波形：Gaussian 底 + 一个正弦音，交给马达驱动。 */
    private func pulse(hz: Double, ms: Double, level: Float) {
        guard let motorPointer, let actuationCreate, let actuationPlay else { return }
        let shape: [String: Any] = [
            "BaseWaveform": ["Type": "Gaussian", "Amplitude": 0.0, "DurationMS": ms],
            "Tones": [["Type": "Sine", "Amplitude": 1.0, "DurationMS": ms,
                       "DelayMS": 0.0, "FrequencykHz": hz / 1000]],
        ]
        guard let actuation = actuationCreate(shape as CFDictionary, 0) else { return }
        _ = actuationPlay(actuation, motorPointer, 0, level, 0)
        Unmanaged<AnyObject>.fromOpaque(actuation).release()
    }

    private func fallback() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }
}
