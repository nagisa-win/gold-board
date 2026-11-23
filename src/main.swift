import AppKit

// MARK: - 命令行模式

/// Hook 调用入口：`GoldFloat --haptic turn-done` 播放一次提醒后退出，不启动界面。
enum FireOnce {
    static func run(_ rawName: String) {
        let key = rawName == "turn-done" ? "turn" : rawName
        let settings = SettingsStore.shared.value
        let config = settings.event(key)
        if settings.hapticEnabled && config.haptic {
            Haptics.shared.play(config.preset, strength: settings.hapticStrength)
        }
        if !settings.soundName.isEmpty, let player = NSSound(named: settings.soundName) {
            player.play()
        }
        // 等异步排程的拍击跑完再退出。
        RunLoop.main.run(until: Date().addingTimeInterval(2.2))
    }
}

if let index = CommandLine.arguments.firstIndex(of: "--haptic") {
    let name = index + 1 < CommandLine.arguments.count ? CommandLine.arguments[index + 1] : "turn-done"
    FireOnce.run(name)
    exit(0)
}

// 行情缓存：导出合并 CSV，或打印缓存概况。
if let index = CommandLine.arguments.firstIndex(of: "--export-history") {
    let path = index + 1 < CommandLine.arguments.count
        ? CommandLine.arguments[index + 1]
        : NSHomeDirectory() + "/Desktop/gold-history.csv"
    do {
        let rows = try HistoryStore.shared.export(to: path)
        print("导出 \(rows) 行 → \(path)")
    } catch {
        print("导出失败：\(error.localizedDescription)")
        exit(1)
    }
    exit(0)
}

if CommandLine.arguments.contains("--history-info") {
    let info = HistoryStore.shared.summary()
    print("目录：\(HistoryStore.shared.folderPath)")
    print("已缓存 \(info.days) 天 / \(info.rows) 行（每分钟一行，单位元/克）")
    exit(0)
}

// 自检：打印触控板马达是否可用，便于排查「震动没反应」。
if CommandLine.arguments.contains("--haptic-info") {
    print("private-api:", Haptics.shared.isAvailable ? "available" : "unavailable (fallback: NSHapticFeedbackManager)")
    print("presets:", Haptics.presetNames.map { "\($0.id)=\($0.title)" }.joined(separator: ", "))
    exit(0)
}

/// 启动时直接展开浮卡到指定页：`--page price|wake|notify|appearance`。
let launchPage: Int? = {
    guard let index = CommandLine.arguments.firstIndex(of: "--page"),
          index + 1 < CommandLine.arguments.count else { return nil }
    switch CommandLine.arguments[index + 1] {
    case "price": return 0
    case "wake": return 1
    case "notify": return 2
    case "appearance": return 3
    default: return nil
    }
}()

// MARK: - 界面模式

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = SettingsStore.shared
    private let feed = QuoteFeed()
    private let wake = WakeController.shared
    private let capsule = CapsulePanel()
    private let card = CardPanel()

    private var clock: Timer?
    private var hoveredSince: Date?
    private var leftAt: Date?

    func applicationDidFinishLaunching(_ note: Notification) {
        wake.recover()
        HistoryStore.shared.prune()
        buildCapsule()
        buildMenu()

        feed.onChange = { [weak self] in self?.refreshPrice() }
        feed.onSignalTriggered = { [weak self] signal in
            self?.fire(signal == .rising ? "surge" : "plunge")
        }
        wake.onChange = { [weak self] in self?.refreshWake() }
        store.onChange = { [weak self] in self?.applySettings() }
        card.pricePage.onRefresh = { [weak self] in self?.feed.refresh() }
        card.pricePage.fallbackRate = { [weak self] in self?.feed.fxRate }

        capsule.capsule.onClickNumber = { [weak self] in self?.openCard() }
        capsule.capsule.onHoverChange = { [weak self] hovered in
            guard let self else { return }
            if hovered {
                self.hoveredSince = Date()
            } else {
                self.hoveredSince = nil
                self.leftAt = Date()
            }
        }
        capsule.capsule.onMove = { [weak self] frame in self?.card.follow(frame) }
        capsule.capsule.button.onClick = { [weak self] in self?.toggleWake() }
        capsule.capsule.button.onRightClick = { [weak self] in self?.showFlagMenu() }

        Notifier.shared.prepare()
        applySettings()
        feed.start()
        startClock()

        // --page 指定页时直接展开浮卡（也方便截图与脚本化打开）。
        if let page = launchPage {
            card.select(page)
            card.show(anchoredTo: capsule.frame, locked: true)
        }
    }

    func applicationWillTerminate(_ note: Notification) {
        clock?.invalidate()
        feed.stop()
    }

    // MARK: - 装配

    /** 胶囊按上次位置摆放；位置失效时回到主屏右上角。 */
    private func buildCapsule() {
        let width = capsule.capsule.preferredWidth
        let height = Tokens.Metric.capsuleHeight
        let restored = capsule.setFrameUsingName("GoldCapsule")
        let previous = capsule.frame
        capsule.setContentSize(NSSize(width: width, height: height))
        if restored, NSScreen.screens.contains(where: { $0.visibleFrame.contains(previous) }) {
            capsule.setFrameTopLeftPoint(NSPoint(x: previous.maxX - width, y: previous.maxY))
        } else if let bounds = NSScreen.main?.visibleFrame {
            capsule.setFrameTopLeftPoint(NSPoint(x: bounds.maxX - width - 16, y: bounds.maxY - 16))
        }
        capsule.setFrameAutosaveName("GoldCapsule")
        capsule.orderFrontRegardless()
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "打开浮卡", action: #selector(openCardAction), keyEquivalent: "").target = self
        menu.addItem(withTitle: "立即刷新行情", action: #selector(refreshAction), keyEquivalent: "").target = self
        menu.addItem(withTitle: "切换系统唤醒", action: #selector(toggleWakeAction), keyEquivalent: "").target = self
        menu.addItem(withTitle: "打开行情缓存目录", action: #selector(openHistoryAction), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出金价小窗", action: #selector(quit), keyEquivalent: "").target = self
        capsule.capsule.menu = menu
    }

    // MARK: - 状态同步

    private func applySettings() {
        let settings = store.value
        capsule.capsule.apply(settings: settings, running: wake.isRunning, progress: wakeProgress())
        card.applySettings()
        refreshPrice()
    }

    private func refreshPrice() {
        let number = feed.quote.map { String(format: "%.2f", $0.price) } ?? "--.--"
        capsule.capsule.update(number: number, signal: feed.signal)
        card.pricePage.update(quote: feed.quote, signal: feed.signal, change: feed.changePercent)
        if card.isVisible, card.selected == 1 { card.wakePage.refresh() }
    }

    private func refreshWake() {
        capsule.capsule.button.isActive = wake.isRunning
        capsule.capsule.button.showsRing = wake.isRunning && wakeProgress() > 0
        capsule.capsule.button.ringProgress = wakeProgress()
        if card.isVisible { card.wakePage.refresh() }
    }

    /// 环形进度 = 已用时间 / 总时长。
    private func wakeProgress() -> CGFloat {
        guard let total = wake.total, let left = wake.remaining, total > 0 else { return 0 }
        return CGFloat(max(0, min(1, 1 - left / total)))
    }

    // MARK: - 交互

    private func startClock() {
        let fast = Timer(timeInterval: 0.12, repeats: true) { [weak self] _ in self?.tickHover() }
        fast.tolerance = 0.02
        RunLoop.main.add(fast, forMode: .common)
        clock = fast

        let slow = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.wake.tick()
            self.refreshPrice()
            if self.wake.isRunning { self.refreshWake() }
        }
        RunLoop.main.add(slow, forMode: .common)
    }

    /// 悬停展开、移出收起、点外部关闭。
    private func tickHover() {
        let mouse = NSEvent.mouseLocation
        let overCapsule = capsule.frame.contains(mouse)
        let overCard = card.isVisible && card.frame.contains(mouse)

        if overCapsule, !card.isVisible, let since = hoveredSince,
           Date().timeIntervalSince(since) >= Tokens.Motion.hoverDelay {
            card.show(anchoredTo: capsule.frame, locked: false)
        }
        if card.isVisible, !card.locked, !overCapsule, !overCard {
            if leftAt == nil { leftAt = Date() }
            if let leftAt, Date().timeIntervalSince(leftAt) > Tokens.Motion.hoverLeaveDelay {
                card.hide()
            }
        } else {
            leftAt = nil
        }
        if NSEvent.pressedMouseButtons != 0, card.isVisible, !overCapsule, !overCard {
            card.hide()
        }
    }

    private func openCard() {
        card.show(anchoredTo: capsule.frame, locked: true)
    }

    private func toggleWake() {
        let settings = store.value
        if wake.isRunning {
            wake.stop()
        } else if settings.wakeMode == "countdown" {
            wake.start(flags: settings.wakeFlags, seconds: settings.wakeSeconds, until: nil)
        } else {
            let calendar = Calendar.current
            let startOfDay = calendar.startOfDay(for: Date())
            var end = startOfDay.addingTimeInterval(Double(settings.wakeEndMinute) * 60)
            if end <= Date() { end = end.addingTimeInterval(24 * 3600) }
            wake.start(flags: settings.wakeFlags, seconds: nil, until: end)
        }
        refreshWake()
    }

    /** 右键按钮：勾选本次要用的 caffeinate 参数，勾选即记忆。 */
    private func showFlagMenu() {
        let menu = NSMenu()
        let settings = store.value
        for flag in WakeController.flagOrder {
            let item = NSMenuItem(title: "-\(flag)  \(WakeController.flagTitles[flag] ?? "")",
                                  action: #selector(toggleFlagAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = flag
            item.state = settings.wakeFlags.contains(flag) ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let state = NSMenuItem(title: wake.isRunning ? "停止唤醒" : "开始唤醒",
                               action: #selector(toggleWakeAction), keyEquivalent: "")
        state.target = self
        menu.addItem(state)
        menu.popUp(positioning: nil,
                   at: NSPoint(x: 0, y: capsule.capsule.button.frame.maxY),
                   in: capsule.capsule)
    }

    @objc private func toggleFlagAction(_ sender: NSMenuItem) {
        guard let flag = sender.representedObject as? String else { return }
        store.update { settings in
            if let index = settings.wakeFlags.firstIndex(of: flag) {
                settings.wakeFlags.remove(at: index)
            } else {
                settings.wakeFlags.append(flag)
            }
            settings.wakeFlags.sort { a, b in
                (WakeController.flagOrder.firstIndex(of: a) ?? 9) < (WakeController.flagOrder.firstIndex(of: b) ?? 9)
            }
            if settings.wakeFlags.isEmpty { settings.wakeFlags = ["i"] }
        }
    }

    private func fire(_ key: String) {
        let settings = store.value
        let config = settings.event(key)
        if settings.hapticEnabled && config.haptic {
            Haptics.shared.play(config.preset, strength: settings.hapticStrength)
        }
        if settings.systemNotifyEnabled && config.notify {
            let title = key == "turn" ? "Turn 完成" : key == "surge" ? "金价急涨" : "金价急跌"
            let body = feed.quote.map { String(format: "%.2f 元/克", $0.price) } ?? ""
            Notifier.shared.post(title: title, body: body, sound: settings.soundName)
        }
    }

    // MARK: - 菜单动作

    @objc private func openCardAction() { openCard() }
    @objc private func refreshAction() { feed.refresh(); card.pricePage.reloadChart(force: true) }
    @objc private func toggleWakeAction() { toggleWake() }
    @objc private func openHistoryAction() {
        NSWorkspace.shared.open(URL(fileURLWithPath: HistoryStore.shared.folderPath))
    }
    @objc private func quit() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.appearance = NSAppearance(named: .darkAqua)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
