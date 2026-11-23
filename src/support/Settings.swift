import AppKit

/** 单个事件的提醒方式。 */
struct EventConfig: Codable {
    var haptic = true
    var notify = false
    /** 震动预设：tap / double / triple / long / heart。 */
    var preset = "double"
}

/** 所有可持久化的偏好。字段名即存储键，新增字段必须给默认值。 */
struct AppSettings: Codable {
    /// 浮窗背景透明度 0…100（0 = 完全透明浮字）。
    var capsuleOpacity: Double = 0
    /// 浮卡不透明度 50…100。
    var cardOpacity: Double = 100
    /// 浮窗按钮的 SF Symbol 名。
    var buttonSymbol: String = "cup.and.saucer"
    /// 上次使用过的 caffeinate 参数（单字母集合，如 ["i"]）。
    var wakeFlags: [String] = ["i"]
    /// countdown | range
    var wakeMode: String = "countdown"
    /// 倒计时秒数。
    var wakeSeconds: Double = 3600
    /// 时间段模式：当日分钟数。
    var wakeStartMinute: Int = 0
    var wakeEndMinute: Int = 120

    /// 触控板震动总开关。
    var hapticEnabled: Bool = true
    /// 系统通知总开关。
    var systemNotifyEnabled: Bool = false
    /// 震动强度 1…5。
    var hapticStrength: Int = 3
    /// 提示音名（NSSound 系统音，空 = 静音）。
    var soundName: String = ""

    /// 事件键：turn / surge / plunge / timer。
    var events: [String: EventConfig] = [
        "turn": EventConfig(haptic: true, notify: true, preset: "double"),
        "surge": EventConfig(haptic: true, notify: false, preset: "triple"),
        "plunge": EventConfig(haptic: true, notify: false, preset: "triple"),
        "timer": EventConfig(haptic: true, notify: true, preset: "long"),
    ]

    func event(_ key: String) -> EventConfig {
        events[key] ?? EventConfig()
    }
}

/** 设置读写与变更广播：所有界面共用同一份，避免各存一份互相覆盖。 */
final class SettingsStore {
    static let shared = SettingsStore()

    private let key = "GoldFloat.settings.v2"
    private(set) var value: AppSettings
    /// 设置变化后通知所有界面重绘。
    var onChange: (() -> Void)?

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            value = decoded
        } else {
            value = AppSettings()
        }
    }

    /** 以闭包方式修改并立即落盘。 */
    func update(_ mutate: (inout AppSettings) -> Void) {
        mutate(&value)
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
        onChange?()
    }

    func reset() {
        value = AppSettings()
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
        onChange?()
    }
}
