import AppKit
import UserNotifications

/** 系统通知：首次使用时申请授权，投递失败只记录不打扰用户。 */
final class Notifier {
    static let shared = Notifier()

    private var requested = false

    /// 可选的系统提示音（NSSound 名字）。
    static let soundNames = ["", "Tink", "Pop", "Ping", "Glass", "Basso", "Blow", "Funk", "Morse", "Sosumi"]

    private init() {}

    /** 申请一次通知授权；没有 bundle id 时直接跳过（例如命令行模式）。 */
    func prepare() {
        guard !requested else { return }
        requested = true
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /** 投递一条系统通知；sound 为空时静音。 */
    func post(title: String, body: String, sound: String?) {
        prepare()
        if Bundle.main.bundleIdentifier != nil {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            if let sound, !sound.isEmpty {
                content.sound = UNNotificationSound(named: UNNotificationSoundName(sound))
            }
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
        // 通知中心被关闭时，至少把声音放出来。
        if let sound, !sound.isEmpty, let player = NSSound(named: sound) {
            player.play()
        }
    }
}
