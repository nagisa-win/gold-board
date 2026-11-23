import AppKit
import AVFoundation
import Accelerate

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

    /// 旋律：(起始毫秒, 频率 Hz, 时长毫秒)。
    private static let melodies: [String: [(Double, Double, Double)]] = [
        "dingdong": [(0, 784, 130), (160, 659, 180)],
        "coin": [(0, 988, 60), (80, 1319, 110)],
        "victory": [(0, 523, 100), (120, 659, 100), (240, 784, 100), (360, 1047, 220)],
        "fail": [(0, 392, 150), (190, 330, 150), (380, 262, 320)],
        "canon": [(0, 523, 200), (220, 659, 200), (440, 784, 200), (660, 880, 200), (880, 1047, 300)],
    ]

    /// 预设名与中文名：前五项是简约震动，其余是旋律与语音播报。
    static let presetNames: [(id: String, title: String)] = [
        ("tap", "轻点"), ("double", "双击"), ("triple", "三连"), ("long", "长震"), ("heart", "心跳"),
        ("melody:dingdong", "叮咚"), ("melody:coin", "金币"), ("melody:victory", "胜利"),
        ("melody:fail", "失败"), ("melody:canon", "卡农"), ("speech", "语音播报"),
    ]

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

    /// 统一入口：预设 / 旋律 / 语音；strength 为 1…5 档。
    func play(_ preset: String, strength: Int, speech text: String = "") {
        let level = Self.strengthLevels[max(0, min(4, strength - 1))]
        if preset.hasPrefix("melody:") {
            playMelody(String(preset.dropFirst("melody:".count)), level: level)
            return
        }
        if preset == "speech" {
            speak(text, level: level)
            return
        }
        guard let pulses = presets[preset] ?? presets["double"] else { return }
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

    /// 语音：用 say 合成到临时音频，再按 10ms 一帧取主频与能量，映射成马达音。
    func speak(_ text: String, level: Float) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard isAvailable else {
            fallback()
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let notes = SpeechAnalyzer.notes(for: trimmed)
            DispatchQueue.main.async {
                guard let self else { return }
                guard !notes.isEmpty else { self.fallback(); return }
                self.schedule(notes: notes, level: level)
            }
        }
    }

    /// 把音列切成 300ms 的块，每块一次驱动调用，块内用 DelayMS 排程。
    private func schedule(notes: [(Double, Double, Double)], level: Float) {
        let window: Double = 300
        var index = 0
        while index < notes.count {
            let base = notes[index].0
            let chunk = Array(notes[index...].prefix { $0.0 - base < window })
            index += chunk.count
            let tones: [(Double, Double, Double, Float)] = chunk.map {
                ($0.0 - base, $0.1, 12, max(0.2, min(1, Float($0.2))))
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + base / 1000) { [weak self] in
                self?.playTones(tones, window: window, level: level)
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

    /// 一次驱动调用里排多个音（DelayMS 毫秒级错开），用于旋律与语音。
    private func playTones(_ tones: [(Double, Double, Double, Float)], window: Double, level: Float) {
        guard let motorPointer, let actuationCreate, let actuationPlay, !tones.isEmpty else { return }
        let list: [[String: Any]] = tones.map { tone in
            [
                "Type": "Sine",
                "Amplitude": Double(tone.3),
                "DurationMS": tone.2,
                "DelayMS": tone.0,
                "FrequencykHz": tone.1 / 1000,
            ]
        }
        let shape: [String: Any] = [
            "BaseWaveform": ["Type": "Gaussian", "Amplitude": 0.0, "DurationMS": window],
            "Tones": list,
        ]
        guard let actuation = actuationCreate(shape as CFDictionary, 0) else { return }
        _ = actuationPlay(actuation, motorPointer, 0, level, 0)
        Unmanaged<AnyObject>.fromOpaque(actuation).release()
    }

    private func fallback() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }
}

/// 把一段文字变成马达音列：say 合成 → 逐帧 FFT 取主频与能量。
enum SpeechAnalyzer {
    /// 返回 (起始毫秒, 频率 Hz, 幅度 0…1)。
    static func notes(for text: String) -> [(Double, Double, Double)] {
        let path = NSTemporaryDirectory() + "goldfloat-speech-\(UUID().uuidString).wav"
        defer { try? FileManager.default.removeItem(atPath: path) }

        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-o", path, "--file-format=WAVE", "--data-format=LEF32@22050", text]
        do { try say.run() } catch { return [] }
        say.waitUntilExit()
        guard say.terminationStatus == 0 else { return [] }

        guard let file = try? AVAudioFile(forReading: URL(fileURLWithPath: path)) else { return [] }
        let frameCount = AVAudioFrameCount(min(file.length, 22_050 * 8))   // 最多 8 秒
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount),
              (try? file.read(into: buffer)) != nil,
              let channel = buffer.floatChannelData?[0] else { return [] }

        let sampleRate = Double(file.processingFormat.sampleRate)
        let total = Int(buffer.frameLength)
        let windowSize = 512
        let hop = 256
        guard total > windowSize else { return [] }

        var window = [Float](repeating: 0, count: windowSize)
        vDSP_hann_window(&window, vDSP_Length(windowSize), Int32(vDSP_HANN_NORM))
        let log2n = vDSP_Length(round(log2(Double(windowSize))))
        guard let fft = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return [] }
        defer { vDSP_destroy_fftsetup(fft) }

        var real = [Float](repeating: 0, count: windowSize / 2)
        var imag = [Float](repeating: 0, count: windowSize / 2)
        var notes: [(Double, Double, Double)] = []

        var offset = 0
        while offset + windowSize <= total {
            var frame = Array(UnsafeBufferPointer(start: channel + offset, count: windowSize))
            vDSP_vmul(frame, 1, window, 1, &frame, 1, vDSP_Length(windowSize))

            var rms: Float = 0
            vDSP_rmsqv(frame, 1, &rms, vDSP_Length(windowSize))

            var magnitudes = [Float](repeating: 0, count: windowSize / 2)
            real.withUnsafeMutableBufferPointer { realPtr in
                imag.withUnsafeMutableBufferPointer { imagPtr in
                    var split = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                    frame.withUnsafeBufferPointer { framePtr in
                        framePtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: windowSize / 2) { complexPtr in
                            vDSP_ctoz(complexPtr, 2, &split, 1, vDSP_Length(windowSize / 2))
                        }
                    }
                    vDSP_fft_zrip(fft, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                    vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(windowSize / 2))
                }
            }

            if rms > 0.006, let peak = magnitudes.enumerated().max(by: { $0.element < $1.element }), peak.element > 0 {
                let start = Double(offset) / sampleRate * 1000
                let amp = min(1.0, Double(rms) * 6)
                // 主峰 = 第一共振峰
                let f1 = Double(peak.offset) * sampleRate / Double(windowSize)
                notes.append((start, min(3900, max(110, f1)), amp))

                // 距离主峰 200Hz 以上再找次峰，作为第二共振峰一起发声
                var bestIndex = -1
                var bestValue: Float = 0
                for (bin, value) in magnitudes.enumerated() where abs(bin - peak.offset) > 4 {
                    let hz = Double(bin) * sampleRate / Double(windowSize)
                    if hz < 300 || hz > 3900 { continue }
                    if value > bestValue { bestValue = value; bestIndex = bin }
                }
                if bestIndex >= 0, bestValue > peak.element * 0.2 {
                    let f2 = Double(bestIndex) * sampleRate / Double(windowSize)
                    notes.append((start, min(3900, max(300, f2)), amp * 0.55))
                }
            }
            offset += hop
        }
        return notes
    }
}
