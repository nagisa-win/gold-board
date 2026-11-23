import AppKit
import CoreGraphics

/** 内置屏亮度读写：DisplayServices 私有框架，外接屏不支持（需 DDC）。 */
enum BuiltinBrightness {
    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
                                       RTLD_NOW)
    private static let getSymbol: GetBrightness? = handle.flatMap { dlsym($0, "DisplayServicesGetBrightness") }
        .map { unsafeBitCast($0, to: GetBrightness.self) }
    private static let setSymbol: SetBrightness? = handle.flatMap { dlsym($0, "DisplayServicesSetBrightness") }
        .map { unsafeBitCast($0, to: SetBrightness.self) }

    /// 内置屏的 displayID；没有内置屏（如纯外接）时返回 nil。
    static var builtinDisplay: CGDirectDisplayID? {
        var displays = [CGDirectDisplayID](repeating: 0, count: 8)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(8, &displays, &count) == .success else { return nil }
        for index in 0..<Int(count) where CGDisplayIsBuiltin(displays[index]) != 0 {
            return displays[index]
        }
        return nil
    }

    static func read() -> Float? {
        guard let display = builtinDisplay, let getSymbol else { return nil }
        var level: Float = -1
        guard getSymbol(display, &level) == 0 else { return nil }
        return level
    }

    @discardableResult
    static func write(_ level: Float) -> Bool {
        guard let display = builtinDisplay, let setSymbol else { return false }
        return setSymbol(display, max(0, min(1, level))) == 0
    }
}

/** 锁屏后延时熄屏：监听系统锁屏通知，10 秒后把内置屏亮度降到 0，解锁时恢复。 */
final class ScreenLockWatcher: NSObject {
    static let shared = ScreenLockWatcher()

    /// 锁屏后等待多久再熄屏，留出解锁反悔的余地。
    private let delay: TimeInterval = 10
    /// 上次熄屏前记下的亮度，用于解锁恢复。
    private var savedLevel: Float?
    private var pendingDim: DispatchWorkItem?

    private let store = SettingsStore.shared
    private let savedKey = "GoldFloat.brightnessBeforeDim"

    private override init() {
        super.init()
    }

    /// 开始监听；启动时若发现上次异常退出遗留的「已熄屏」状态，先恢复亮度。
    func start() {
        restoreIfLeftDimmed()
        let center = DistributedNotificationCenter.default
        let pairs: [(String, Selector)] = [
            ("com.apple.screenIsLocked", #selector(handleLocked)),
            ("com.apple.screenIsUnlocked", #selector(handleUnlocked)),
        ]
        for (name, selector) in pairs {
            center.addObserver(self, selector: selector, name: NSNotification.Name(name), object: nil)
        }

        // 兜底：锁屏通知偶发丢失时，用状态轮询校正。
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in self?.syncState() }
        RunLoop.main.add(timer, forMode: .common)
        clock = timer
    }

    private var clock: Timer?

    /// 立即恢复亮度并停止监听（应用退出时调用）。
    func stop() {
        pendingDim?.cancel()
        pendingDim = nil
        restoreIfNeeded()
        clock?.invalidate()
        DistributedNotificationCenter.default.removeObserver(self)
    }

    /// 功能被关闭时也要把亮度还回去。
    func applyEnabledState() {
        if !store.value.dimOnLock {
            pendingDim?.cancel()
            pendingDim = nil
            restoreIfNeeded()
        }
    }

    @objc private func handleLocked() {
        guard store.value.dimOnLock else { return }
        scheduleDim()
    }

    @objc private func handleUnlocked() {
        pendingDim?.cancel()
        pendingDim = nil
        restoreIfNeeded()
    }

    /// 锁屏 10 秒后再熄屏；期间解锁则取消。
    private func scheduleDim() {
        guard pendingDim == nil, savedLevel == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.store.value.dimOnLock, Self.isLocked else { return }
            guard let current = BuiltinBrightness.read() else { return }
            self.savedLevel = current
            UserDefaults.standard.set(Double(current), forKey: self.savedKey)
            BuiltinBrightness.write(0)
            self.pendingDim = nil
        }
        pendingDim = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// 把亮度还原到熄屏前的值（内存或上次遗留的持久化值）。
    private func restoreIfNeeded() {
        let persisted = (UserDefaults.standard.object(forKey: savedKey) as? Double).map(Float.init)
        guard let level = savedLevel ?? persisted else { return }
        BuiltinBrightness.write(level)
        savedLevel = nil
        UserDefaults.standard.removeObject(forKey: savedKey)
    }

    /// 上次异常退出时亮度还压着，但当前并未锁屏，直接恢复。
    private func restoreIfLeftDimmed() {
        guard UserDefaults.standard.object(forKey: savedKey) != nil, !Self.isLocked else { return }
        restoreIfNeeded()
    }

    /// 轮询校正：锁屏却没安排熄屏、或已解锁却还压着亮度。
    private func syncState() {
        guard store.value.dimOnLock else { return }
        if Self.isLocked {
            if savedLevel == nil && pendingDim == nil { scheduleDim() }
        } else {
            pendingDim?.cancel()
            pendingDim = nil
            restoreIfNeeded()
        }
    }

    /// 当前会话是否处于锁屏。
    static var isLocked: Bool {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (dict["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }
}
