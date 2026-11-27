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
        // 频率抬到 240–360Hz：低于 100Hz 只能感到震动、听不到声音
        "tap": [Pulse(delay: 0, hz: 320, ms: 12)],
        "double": [Pulse(delay: 0, hz: 320, ms: 10),
                   Pulse(delay: 0.11, hz: 320, ms: 10)],
        "triple": [Pulse(delay: 0, hz: 360, ms: 9),
                   Pulse(delay: 0.09, hz: 360, ms: 9),
                   Pulse(delay: 0.18, hz: 360, ms: 9)],
        "long": [Pulse(delay: 0, hz: 260, ms: 240)],
        "heart": [Pulse(delay: 0, hz: 240, ms: 60),
                  Pulse(delay: 0.18, hz: 240, ms: 60),
                  Pulse(delay: 0.76, hz: 240, ms: 60),
                  Pulse(delay: 0.94, hz: 240, ms: 60),
                  Pulse(delay: 1.52, hz: 240, ms: 60),
                  Pulse(delay: 1.70, hz: 240, ms: 60)],
    ]

    /// 节奏型：脉宽的疏密变化，比单纯拍击更有辨识度。
    private let rhythms: [String: [Pulse]] = [
        // 雨点：六下快速连击
        "rain": (0..<6).map { Pulse(delay: Double($0) * 0.055, hz: 380, ms: 8) },
        // 敲门：两长一短
        "knock": [Pulse(delay: 0, hz: 280, ms: 70), Pulse(delay: 0.20, hz: 280, ms: 70),
                  Pulse(delay: 0.42, hz: 460, ms: 22)],
        // SOS：三短三长三短
        "sos": [Pulse(delay: 0, hz: 420, ms: 45), Pulse(delay: 0.09, hz: 420, ms: 45),
                Pulse(delay: 0.18, hz: 420, ms: 45),
                Pulse(delay: 0.42, hz: 420, ms: 150), Pulse(delay: 0.64, hz: 420, ms: 150),
                Pulse(delay: 0.86, hz: 420, ms: 150),
                Pulse(delay: 1.32, hz: 420, ms: 45), Pulse(delay: 1.41, hz: 420, ms: 45),
                Pulse(delay: 1.50, hz: 420, ms: 45)],
        // 警报：高低交替
        "alarm": [Pulse(delay: 0, hz: 700, ms: 80), Pulse(delay: 0.14, hz: 500, ms: 80),
                  Pulse(delay: 0.28, hz: 700, ms: 80), Pulse(delay: 0.42, hz: 500, ms: 80),
                  Pulse(delay: 0.56, hz: 700, ms: 80)],
        // 上升：频率逐级抬高
        "rise": (0..<5).map { Pulse(delay: Double($0) * 0.09, hz: 240 + Double($0) * 90, ms: 60) },
        // 下降：与上升相反的坠落感
        "fall": (0..<5).map { Pulse(delay: Double($0) * 0.09, hz: 600 - Double($0) * 90, ms: 60) },
        // 打字机：不规则的短促敲击
        "type": [Pulse(delay: 0, hz: 480, ms: 10), Pulse(delay: 0.06, hz: 440, ms: 9),
                 Pulse(delay: 0.15, hz: 500, ms: 10), Pulse(delay: 0.21, hz: 420, ms: 8),
                 Pulse(delay: 0.33, hz: 470, ms: 10), Pulse(delay: 0.40, hz: 450, ms: 9)],
    ]

    /// 旋律：(起始毫秒, 频率 Hz, 时长毫秒)。
    private static let melodies: [String: [(Double, Double, Double)]] = [
        "dingdong": [(0, 784, 130), (160, 659, 180)],
        "coin": [(0, 988, 60), (80, 1319, 110)],
        "victory": [(0, 523, 100), (120, 659, 100), (240, 784, 100), (360, 1047, 220)],
        "fail": [(0, 392, 150), (190, 330, 150), (380, 262, 320)],
        "canon": [(0, 523, 200), (220, 659, 200), (440, 784, 200), (660, 880, 200), (880, 1047, 300)],
        "star": [(0, 523, 220), (250, 523, 220), (500, 784, 220), (750, 784, 220),
                 (1000, 880, 220), (1250, 880, 220), (1500, 784, 380)],
    ]

    /// 提醒方式分组：简单震动 / 节奏 / 旋律。
    static let presetSections: [(title: String, items: [(id: String, title: String)])] = [
        ("简单震动", [("tap", "轻点"), ("double", "双击"), ("triple", "三连"),
                  ("long", "长震"), ("heart", "心跳")]),
        ("节奏", [("rhythm:rain", "雨点"), ("rhythm:knock", "敲门"), ("rhythm:sos", "SOS"),
                ("rhythm:alarm", "警报"), ("rhythm:rise", "上升"), ("rhythm:fall", "下降"),
                ("rhythm:type", "打字机")]),
        ("旋律", [("melody:dingdong", "叮咚"), ("melody:coin", "金币"), ("melody:victory", "胜利"),
                ("melody:fail", "失败"), ("melody:canon", "卡农"), ("melody:star", "小星星")]),
    ]

    /// 扁平化后的全部提醒方式，供查找与校验。
    static var presetNames: [(id: String, title: String)] {
        presetSections.flatMap(\.items)
    }

    /// 五档强度映射到驱动层的 level（0…1）。
    static let strengthLevels: [Float] = [0.35, 0.5, 0.65, 0.8, 1.0]

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

    // MARK: - 播放入口

    /// 各组增益：旋律频段高、本身更响，压到 0.7；节奏 0.9；简单震动满幅。
    private func gain(for preset: String) -> Float {
        if preset.hasPrefix("melody:") { return 0.7 }
        if preset.hasPrefix("rhythm:") { return 0.9 }
        return 1.0
    }

    /// 统一入口：简单震动 / 节奏 / 旋律；strength 为 1…5 档。
    func play(_ preset: String, strength: Int) {
        let level = Self.strengthLevels[max(0, min(4, strength - 1))] * gain(for: preset)
        if preset.hasPrefix("melody:") {
            playMelody(String(preset.dropFirst("melody:".count)), level: level)
            return
        }
        let id = preset.hasPrefix("rhythm:") ? String(preset.dropFirst("rhythm:".count)) : preset
        guard let pulses = rhythms[id] ?? presets[id] ?? presets["double"] else { return }
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

    /// 播放一段旋律：每个音符一次拍击。
    func playMelody(_ id: String, level: Float) {
        guard let notes = Self.melodies[id] else { return }
        guard isAvailable else {
            fallback()
            return
        }
        for note in notes {
            DispatchQueue.main.asyncAfter(deadline: .now() + note.0 / 1000) { [weak self] in
                self?.pulse(hz: note.1, ms: note.2, level: level)
            }
        }
    }

    // MARK: - 驱动层

    /// 单次波形：Gaussian 底 + 一个正弦音，交给马达驱动。
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

