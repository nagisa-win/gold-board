import AppKit

/** caffeinate 子进程与倒计时状态：浮窗按钮与唤醒页共用同一份状态。 */
final class WakeController {
    static let shared = WakeController()

    /// 当前可选参数，界面 chip 用同一份定义。
    static let flagOrder = ["i", "d", "m", "s", "u"]
    static let flagTitles: [String: String] = [
        "i": "闲置不睡", "d": "屏幕不睡", "m": "磁盘不睡", "s": "系统不睡", "u": "声明用户活动",
    ]

    private var process: Process?
    private var adoptedPid: pid_t?
    private(set) var startedAt: Date?
    private(set) var endsAt: Date?
    private(set) var lastError: String?

    var onChange: (() -> Void)?
    /// 自然到点时回调一次；手动停止不会触发。
    var onExpire: (() -> Void)?
    /// 结束前 3 分钟回调一次，用于短促预告。
    var onNearlyExpired: (() -> Void)?
    /// 到点后待播报的时刻，跨过该时刻即提醒一次（countdown 由 caffeinate 自己退出也覆盖）。
    private var pendingExpiry: Date?
    /// 结束前 3 分钟的预告提醒时刻；短定时器不会登记。
    private var pendingPreAlert: Date?
    /// 提前预告的提前量；调试入口可临时改小以便验证。
    var preAlertLead: TimeInterval = 180

    private let stateURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GoldFloat", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("wake.json")
    }()

    private struct Persisted: Codable {
        let pid: Int32
        let startedAt: Date?
        let endsAt: Date?
        let args: String
    }

    var isRunning: Bool {
        if let process, process.isRunning { return true }
        if let pid = adoptedPid, kill(pid, 0) == 0 { return true }
        return false
    }

    /// 剩余秒数；无到期时间（无限唤醒）返回 nil。
    var remaining: TimeInterval? {
        guard isRunning, let endsAt else { return nil }
        return max(0, endsAt.timeIntervalSinceNow)
    }

    /// 本次唤醒总时长，用于环形进度。
    var total: TimeInterval? {
        guard let startedAt, let endsAt else { return nil }
        let value = endsAt.timeIntervalSince(startedAt)
        return value > 0 ? value : nil
    }

    private init() {}

    /** 启动唤醒；seconds 为倒计时，until 为时间段结束时刻，两者可只给一个。 */
    func start(flags: [String], seconds: TimeInterval?, until: Date?) {
        stop()
        lastError = nil
        var args: [String] = []
        if !flags.isEmpty { args.append("-" + flags.joined()) }
        if let seconds {
            args.append("-t")
            args.append(String(Int(seconds.rounded())))
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        task.arguments = args
        task.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.process = nil
                self?.startedAt = nil
                self?.endsAt = nil
                self?.clearState()
                self?.onChange?()
            }
        }
        do {
            try task.run()
        } catch {
            lastError = "无法启动 caffeinate：\(error.localizedDescription)"
            onChange?()
            return
        }

        process = task
        startedAt = Date()
        endsAt = until ?? seconds.map { Date().addingTimeInterval($0) }
        // 有结束时刻才需要提醒；无限唤醒不会触发
        pendingExpiry = endsAt
        // 只有长于预告量的定时才登记预告
        if let endsAt, endsAt.timeIntervalSinceNow > preAlertLead {
            pendingPreAlert = endsAt.addingTimeInterval(-preAlertLead)
        }
        persist(pid: task.processIdentifier, args: args.joined(separator: " "))
        onChange?()
    }

    /** 停止唤醒并清理状态文件。 */
    /// 手动停止：清掉待提醒标记，不会播报。
    func stop() {
        pendingExpiry = nil
        pendingPreAlert = nil
        if let process, process.isRunning { process.terminate() }
        process = nil
        if let pid = adoptedPid, kill(pid, 0) == 0 { kill(pid, SIGTERM) }
        adoptedPid = nil
        startedAt = nil
        endsAt = nil
        clearState()
        onChange?()
    }

    /** 秒级推进：到点自动停止，并发现被外部结束的进程。 */
    func tick() {
        // 接管的旧进程消失：只有确实跨过结束时刻才算自然到时
        if let pid = adoptedPid, kill(pid, 0) != 0 {
            let expired = endsAt.map { Date() >= $0 } ?? false
            adoptedPid = nil
            startedAt = nil
            endsAt = nil
            pendingExpiry = nil
            pendingPreAlert = nil
            clearState()
            onChange?()
            if expired { onExpire?() }
            return
        }

        // 结束前 3 分钟的短促预告
        if let lead = pendingPreAlert, Date() >= lead {
            pendingPreAlert = nil
            onNearlyExpired?()
        }

        // 到点提醒：caffeinate 自己退出（-t）与时间段模式都由这里统一处理
        guard let due = pendingExpiry, Date() >= due else { return }
        pendingExpiry = nil
        if let endsAt, Date() >= endsAt, isRunning { stop() }
        onExpire?()
    }

    /** App 启动时接管上一次遗留的唤醒，避免残留进程让 Mac 一直不睡。 */
    func recover() {
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(Persisted.self, from: data) else { return }
        if kill(state.pid, 0) == 0 {
            adoptedPid = state.pid
            endsAt = state.endsAt
            // 重启接管后如果还没到点，到点时仍然要提醒
            pendingExpiry = state.endsAt
            if let endsAt, endsAt.timeIntervalSinceNow > preAlertLead {
                pendingPreAlert = endsAt.addingTimeInterval(-preAlertLead)
            }
            // 恢复真实的开始时间，环形进度才不会在重启后归零；
            // 旧版本没存 startedAt 时，用 -t 秒数从 endsAt 反推。
            startedAt = state.startedAt ?? Self.inferStart(endsAt: state.endsAt, args: state.args) ?? Date()
        } else {
            clearState()
        }
    }

    /// 旧状态文件里的 startedAt 缺失时，按 `-t N` 反推开始时刻。
    private static func inferStart(endsAt: Date?, args: String) -> Date? {
        guard let endsAt else { return nil }
        let tokens = args.split(separator: " ")
        guard let flagIndex = tokens.firstIndex(of: "-t"),
              flagIndex + 1 < tokens.count,
              let seconds = Double(tokens[flagIndex + 1]) else { return nil }
        return endsAt.addingTimeInterval(-seconds)
    }

    private func persist(pid: Int32, args: String) {
        let state = Persisted(pid: pid, startedAt: startedAt, endsAt: endsAt, args: args)
        if let data = try? JSONEncoder().encode(state) { try? data.write(to: stateURL) }
    }

    private func clearState() {
        try? FileManager.default.removeItem(at: stateURL)
    }
}
