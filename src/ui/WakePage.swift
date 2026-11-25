import AppKit

/** 浮卡第二页：caffeinate 唤醒定时器（时间段 / 倒计时）。 */
final class WakePage: NSView {
    private let title = NSTextField(labelWithString: "保持系统唤醒")
    private let state = NSTextField(labelWithString: "未开启")
    private let segmented = Segmented(items: ["时间段", "倒计时"])
    private let remaining = NSTextField(labelWithString: "--:--:--")
    private let ring = RingView()
    private var chips: [Chip] = []
    private let hint = NSTextField(labelWithString: "")
    private let durationRow = NSView()
    private let rangeRow = NSView()
    private var durationButtons: [PillButton] = []
    private let startPopup = NSPopUpButton()
    private let endPopup = NSPopUpButton()
    private let arrow = NSTextField(labelWithString: "→")
    private let action = PillButton(title: "开始唤醒")
    private let command = NSTextField(labelWithString: "")
    private let lockLabel = NSTextField(labelWithString: "锁屏 10 秒后熄屏")
    private let lockToggle = Toggle(isOn: SettingsStore.shared.value.dimOnLock)

    private let durations: [(title: String, seconds: Double)] = [
        ("30 分", 1800), ("1 时", 3600), ("2 时", 7200), ("4 时", 14400), ("8 时", 28800),
    ]

    init() {
        super.init(frame: .zero)
        title.font = Tokens.text(12, .semibold)
        title.textColor = Tokens.muted(0.78)
        state.font = Tokens.text(10.5)
        state.textColor = Tokens.muted(0.42)
        state.alignment = .right

        segmented.select(SettingsStore.shared.value.wakeMode == "range" ? 0 : 1, notify: false)
        segmented.onSelect = { [weak self] index in
            SettingsStore.shared.update { $0.wakeMode = index == 0 ? "range" : "countdown" }
            self?.refresh()
        }

        remaining.font = Tokens.number(20, .medium)
        remaining.textColor = Tokens.paper

        hint.font = Tokens.text(10)
        hint.textColor = Tokens.muted(0.4)

        command.font = Tokens.number(9.5)
        command.textColor = Tokens.muted(0.32)

        arrow.font = Tokens.text(11)
        arrow.textColor = Tokens.muted(0.45)

        for flag in WakeController.flagOrder {
            let chip = Chip(title: flag)
            chip.onClick = { [weak self] in self?.toggleFlag(flag) }
            chips.append(chip)
        }

        for (index, item) in durations.enumerated() {
            let button = PillButton(title: item.title, filled: index == 1)
            button.onClick = { [weak self] in
                SettingsStore.shared.update { $0.wakeSeconds = item.seconds }
                self?.refresh()
            }
            durationButtons.append(button)
            durationRow.addSubview(button)
        }

        for popup in [startPopup, endPopup] {
            popup.controlSize = .mini
            popup.font = Tokens.number(11)
            popup.isBordered = false
            popup.focusRingType = .none
            popup.addItems(withTitles: (0..<48).map { Self.timeTitle($0 * 30) })
            popup.target = self
            popup.action = #selector(changeRange)
        }
        rangeRow.addSubview(startPopup)
        rangeRow.addSubview(arrow)
        rangeRow.addSubview(endPopup)

        action.onClick = { [weak self] in self?.toggle() }

        lockLabel.font = Tokens.text(11.5)
        lockLabel.textColor = Tokens.muted(0.72)
        lockToggle.onChange = { value in
            SettingsStore.shared.update { $0.dimOnLock = value }
            ScreenLockWatcher.shared.applyEnabledState()
        }

        [title, state, segmented, remaining, ring, hint, durationRow, rangeRow, action,
         lockLabel, lockToggle, command].forEach(addSubview)
        chips.forEach(addSubview)

        refresh()
    }

    required init?(coder: NSCoder) { fatalError("unsupported") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        title.frame = NSRect(x: 0, y: 0, width: 120, height: 16)
        state.frame = NSRect(x: bounds.width - 120, y: 1, width: 120, height: 14)
        segmented.frame = NSRect(x: 0, y: 22, width: 168, height: 24)
        remaining.frame = NSRect(x: 0, y: 56, width: 180, height: 26)
        ring.frame = NSRect(x: bounds.width - 30, y: 52, width: 30, height: 30)

        for (index, chip) in chips.enumerated() {
            chip.frame = NSRect(x: CGFloat(index) * 32, y: 96, width: 26, height: 20)
        }
        hint.frame = NSRect(x: 0, y: 120, width: bounds.width, height: 14)

        durationRow.frame = NSRect(x: 0, y: 142, width: bounds.width, height: 24)
        for (index, button) in durationButtons.enumerated() {
            button.frame = NSRect(x: CGFloat(index) * 54, y: 0, width: 50, height: 24)
        }
        rangeRow.frame = NSRect(x: 0, y: 142, width: bounds.width, height: 24)
        startPopup.frame = NSRect(x: 0, y: 0, width: 92, height: 22)
        arrow.frame = NSRect(x: 98, y: 2, width: 16, height: 18)
        endPopup.frame = NSRect(x: 118, y: 0, width: 92, height: 22)

        action.frame = NSRect(x: 0, y: 176, width: 120, height: 26)
        lockLabel.frame = NSRect(x: 0, y: 212, width: 130, height: 16)
        lockToggle.frame = NSRect(x: bounds.width - 28, y: 212, width: 28, height: 16)
        command.frame = NSRect(x: 0, y: 238, width: bounds.width, height: 14)
    }

    // MARK: - 状态

    /** 从设置与 WakeController 同步界面。 */
    func refresh() {
        let settings = SettingsStore.shared.value
        let wake = WakeController.shared
        let rangeMode = settings.wakeMode == "range"
        segmented.select(rangeMode ? 0 : 1, notify: false)
        durationRow.isHidden = rangeMode
        rangeRow.isHidden = !rangeMode

        for (index, chip) in chips.enumerated() {
            chip.isOn = settings.wakeFlags.contains(WakeController.flagOrder[index])
        }
        hint.stringValue = "i 闲置 · d 屏幕 · m 磁盘 · s 系统 · u 活动"
        for (index, button) in durationButtons.enumerated() {
            let selected = abs(settings.wakeSeconds - durations[index].seconds) < 1
            button.filled = selected
            button.tint = selected ? Tokens.gold : Tokens.muted(0.55)
        }

        if rangeMode {
            startPopup.selectItem(at: min(47, max(0, settings.wakeStartMinute / 30)))
            endPopup.selectItem(at: min(47, max(0, settings.wakeEndMinute / 30)))
        }

        let running = wake.isRunning
        action.title = running ? "停止唤醒" : "开始唤醒"
        action.tint = running ? Tokens.warn : Tokens.gold
        state.stringValue = running ? "运行中" : "未开启"
        state.textColor = running ? Tokens.gold : Tokens.muted(0.42)

        if let left = wake.remaining {
            remaining.stringValue = Self.durationText(left)
            remaining.textColor = Tokens.paper
            if let total = wake.total, total > 0 {
                ring.progress = 1 - left / total
                ring.isHidden = false
            }
        } else if running {
            remaining.stringValue = "∞"
            ring.progress = 0
            ring.isHidden = true
        } else {
            remaining.stringValue = rangeMode
                ? String(format: "%@ → %@", Self.timeTitle(settings.wakeStartMinute), Self.timeTitle(settings.wakeEndMinute))
                : Self.durationText(settings.wakeSeconds)
            remaining.textColor = Tokens.muted(0.4)
            ring.isHidden = true
        }

        lockToggle.isOn = settings.dimOnLock
        command.stringValue = "caffeinate -" + settings.wakeFlags.joined()
        if let error = wake.lastError {
            command.stringValue = error
            command.textColor = Tokens.warn
        } else {
            command.textColor = Tokens.muted(0.32)
        }
    }

    // MARK: - 交互

    private func toggleFlag(_ flag: String) {
        SettingsStore.shared.update { settings in
            if let index = settings.wakeFlags.firstIndex(of: flag) {
                settings.wakeFlags.remove(at: index)
            } else {
                settings.wakeFlags.append(flag)
            }
            // 保持 -i -d -m -s -u 的稳定顺序，避免每次拼出来的参数跳来跳去。
            settings.wakeFlags.sort { a, b in
                (WakeController.flagOrder.firstIndex(of: a) ?? 9) < (WakeController.flagOrder.firstIndex(of: b) ?? 9)
            }
            if settings.wakeFlags.isEmpty { settings.wakeFlags = ["i"] }
        }
        refresh()
    }

    @objc private func changeRange() {
        let start = startPopup.indexOfSelectedItem * 30
        let end = endPopup.indexOfSelectedItem * 30
        SettingsStore.shared.update { settings in
            settings.wakeStartMinute = start
            settings.wakeEndMinute = end
        }
        refresh()
    }

    private func toggle() {
        let wake = WakeController.shared
        if wake.isRunning {
            wake.stop()
            refresh()
            return
        }
        let settings = SettingsStore.shared.value
        let flags = settings.wakeFlags
        if settings.wakeMode == "countdown" {
            wake.start(flags: flags, seconds: settings.wakeSeconds, until: nil)
        } else {
            let now = Date()
            var calendar = Calendar.current
            calendar.timeZone = .current
            let startOfDay = calendar.startOfDay(for: now)
            let start = startOfDay.addingTimeInterval(Double(settings.wakeStartMinute) * 60)
            var end = startOfDay.addingTimeInterval(Double(settings.wakeEndMinute) * 60)
            if end <= start { end = end.addingTimeInterval(24 * 3600) }
            let until = end > start ? end : start.addingTimeInterval(3600)
            wake.start(flags: flags, seconds: nil, until: until)
        }
        refresh()
    }

    private static func timeTitle(_ minutes: Int) -> String {
        String(format: "%02d:%02d", (minutes / 60) % 24, minutes % 60)
    }

    private static func durationText(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }
}

/** 细环形进度。 */
final class RingView: NSView {
    var progress: CGFloat = 0 {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let radius = min(bounds.width, bounds.height) / 2 - 2
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        track.lineWidth = 2
        Tokens.gold.withAlphaComponent(0.18).setStroke()
        track.stroke()

        guard progress > 0.001 else { return }
        let arc = NSBezierPath()
        arc.appendArc(withCenter: center, radius: radius,
                      startAngle: 90, endAngle: 90 - 360 * min(1, progress), clockwise: true)
        arc.lineWidth = 2
        arc.lineCapStyle = .round
        Tokens.gold.setStroke()
        arc.stroke()
    }
}
