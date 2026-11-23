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

    private let stateURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GoldFloat", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("wake.json")
    }()

    private struct Persisted: Codable {
        let pid: Int32
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
        persist(pid: task.processIdentifier, args: args.joined(separator: " "))
        onChange?()
    }

    /** 停止唤醒并清理状态文件。 */
    func stop() {
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
        if let pid = adoptedPid, kill(pid, 0) != 0 {
            adoptedPid = nil
            startedAt = nil
            endsAt = nil
            clearState()
            onChange?()
            return
        }
        if let endsAt, Date() >= endsAt, isRunning {
            stop()
        }
    }

    /** App 启动时接管上一次遗留的唤醒，避免残留进程让 Mac 一直不睡。 */
    func recover() {
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(Persisted.self, from: data) else { return }
        if kill(state.pid, 0) == 0 {
            adoptedPid = state.pid
            endsAt = state.endsAt
            startedAt = Date()
        } else {
            clearState()
        }
    }

    private func persist(pid: Int32, args: String) {
        let state = Persisted(pid: pid, endsAt: endsAt, args: args)
        if let data = try? JSONEncoder().encode(state) { try? data.write(to: stateURL) }
    }

    private func clearState() {
        try? FileManager.default.removeItem(at: stateURL)
    }
}
