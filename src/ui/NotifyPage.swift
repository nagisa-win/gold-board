import AppKit

/** 浮卡第三页：触控板震动 + 系统通知 + 本地 Agent 接入。 */
final class NotifyPage: NSView {
    private let title = NSTextField(labelWithString: "通知与震动")
    private let hapticRow: SwitchRow
    private let notifyRow: SwitchRow
    private let strengthLabel = NSTextField(labelWithString: "强度")
    private let strength = StrengthDots(value: SettingsStore.shared.value.hapticStrength)
    private let soundLabel = NSTextField(labelWithString: "声音")
    private let soundPopup = NSPopUpButton()
    private let eventSection = sectionLabel("事件")
    private let toolSection = sectionLabel("本地 Agent 接入")
    private var eventRows: [EventRow] = []
    private var toolRows: [ToolRow] = []
    private let status = NSTextField(labelWithString: "")
    private let speechLabel = NSTextField(labelWithString: "Turn 语音")
    private let speechField = NSTextField()

    private let eventTitles: [(key: String, title: String)] = [
        ("turn", "Turn 完成"), ("surge", "金价急涨"), ("plunge", "金价急跌"), ("timer", "定时器结束"),
    ]

    init() {
        let settings = SettingsStore.shared.value
        hapticRow = SwitchRow(title: "触控板震动", value: settings.hapticEnabled)
        notifyRow = SwitchRow(title: "系统通知", value: settings.systemNotifyEnabled)
        super.init(frame: .zero)

        title.font = Tokens.text(12, .semibold)
        title.textColor = Tokens.muted(0.78)

        hapticRow.onChange = { value in
            SettingsStore.shared.update { $0.hapticEnabled = value }
        }
        notifyRow.onChange = { value in
            SettingsStore.shared.update { $0.systemNotifyEnabled = value }
            if value { Notifier.shared.prepare() }
        }

        strengthLabel.font = Tokens.text(10.5)
        strengthLabel.textColor = Tokens.muted(0.45)
        strength.onChange = { value in
            SettingsStore.shared.update { $0.hapticStrength = value }
        }

        soundLabel.font = Tokens.text(10.5)
        soundLabel.textColor = Tokens.muted(0.45)
        soundPopup.controlSize = .mini
        soundPopup.font = Tokens.text(11)
        soundPopup.isBordered = false
        soundPopup.focusRingType = .none
        soundPopup.addItems(withTitles: Notifier.soundNames.map { $0.isEmpty ? "静音" : $0 })
        if let index = Notifier.soundNames.firstIndex(of: settings.soundName) {
            soundPopup.selectItem(at: index)
        }
        soundPopup.target = self
        soundPopup.action = #selector(changeSound)

        for item in eventTitles {
            let row = EventRow(key: item.key, title: item.title)
            row.onChange = { [weak self] in self?.reloadEvents() }
            eventRows.append(row)
        }
        for tool in HookTool.allCases {
            let row = ToolRow(tool: tool)
            row.onMessage = { [weak self] text in self?.status.stringValue = text }
            toolRows.append(row)
        }

        speechLabel.font = Tokens.text(11.5)
        speechLabel.textColor = Tokens.muted(0.72)
        speechField.font = Tokens.text(11)
        speechField.textColor = Tokens.paper
        speechField.isBordered = false
        speechField.focusRingType = .none
        speechField.drawsBackground = false
        speechField.placeholderString = EventConfig.defaultSpeech(for: "turn")
        speechField.stringValue = settings.event("turn").speech
        speechField.target = self
        speechField.action = #selector(changeSpeech)

        status.font = Tokens.text(9.5)
        status.textColor = Tokens.muted(0.4)
        status.lineBreakMode = .byTruncatingTail
        status.maximumNumberOfLines = 1

        [title, hapticRow, strengthLabel, strength, notifyRow, soundLabel, soundPopup,
         eventSection, toolSection, status, speechLabel, speechField].forEach(addSubview)
        eventRows.forEach(addSubview)
        toolRows.forEach(addSubview)
    }

    required init?(coder: NSCoder) { fatalError("unsupported") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let width = bounds.width
        title.frame = NSRect(x: 0, y: 0, width: 160, height: 16)

        hapticRow.frame = NSRect(x: 0, y: 24, width: 110, height: 20)
        strengthLabel.frame = NSRect(x: 126, y: 27, width: 26, height: 14)
        strength.frame = NSRect(x: 156, y: 26, width: 80, height: 16)

        notifyRow.frame = NSRect(x: 0, y: 48, width: 110, height: 20)
        soundLabel.frame = NSRect(x: 126, y: 51, width: 26, height: 14)
        soundPopup.frame = NSRect(x: 156, y: 47, width: 70, height: 22)

        eventSection.frame = NSRect(x: 0, y: 76, width: 120, height: 12)
        for (index, row) in eventRows.enumerated() {
            row.frame = NSRect(x: 0, y: 90 + CGFloat(index) * 22, width: width, height: 20)
        }

        speechLabel.frame = NSRect(x: 0, y: 183, width: 60, height: 16)
        speechField.frame = NSRect(x: 64, y: 182, width: width - 64, height: 20)

        toolSection.frame = NSRect(x: 0, y: 210, width: 160, height: 12)
        for (index, row) in toolRows.enumerated() {
            row.frame = NSRect(x: 0, y: 224 + CGFloat(index) * 22, width: width, height: 20)
        }
        status.frame = NSRect(x: 0, y: bounds.height - 12, width: width, height: 12)
    }

    /** 从设置同步界面。 */
    func refresh() {
        let settings = SettingsStore.shared.value
        hapticRow.setValue(settings.hapticEnabled)
        notifyRow.setValue(settings.systemNotifyEnabled)
        strength.value = settings.hapticStrength
        if let index = Notifier.soundNames.firstIndex(of: settings.soundName) {
            soundPopup.selectItem(at: index)
        }
        if speechField.currentEditor() == nil {
            speechField.stringValue = settings.event("turn").speech
        }
        eventRows.forEach { $0.refresh() }
        toolRows.forEach { $0.refresh() }
    }

    private func reloadEvents() {
        eventRows.forEach { $0.refresh() }
        StatusHUD.say("已保存")
    }

    @objc private func changeSpeech() {
        let text = speechField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        SettingsStore.shared.update { $0.events["turn", default: EventConfig()].speech = text }
    }

    @objc private func changeSound() {
        let index = max(0, soundPopup.indexOfSelectedItem)
        let name = Notifier.soundNames[min(index, Notifier.soundNames.count - 1)]
        SettingsStore.shared.update { $0.soundName = name }
    }
}

/** 事件行：标题 + 预设下拉 + 试听 + 开关。 */
final class EventRow: NSView {
    private let key: String
    private let label: NSTextField
    private let popup = NSPopUpButton()
    private let play = IconButton(symbol: "play.circle", tooltip: "试听")
    private let toggle = Toggle(isOn: true)
    var onChange: (() -> Void)?

    init(key: String, title: String) {
        self.key = key
        label = NSTextField(labelWithString: title)
        super.init(frame: .zero)
        label.font = Tokens.text(11.5)
        label.textColor = Tokens.muted(0.72)
        addSubview(label)

        popup.controlSize = .mini
        popup.font = Tokens.text(11)
        popup.isBordered = false
        popup.focusRingType = .none
        popup.addItems(withTitles: Haptics.presetNames.map(\.title))
        popup.target = self
        popup.action = #selector(changed)
        addSubview(popup)

        play.iconSize = 13
        play.onClick = { [weak self] in
            guard let self else { return }
            let settings = SettingsStore.shared.value
            let config = settings.event(self.key)
            let text = config.speech.isEmpty ? EventConfig.defaultSpeech(for: self.key) : config.speech
            Haptics.shared.play(config.preset, strength: settings.hapticStrength, speech: text)
        }
        addSubview(play)

        toggle.onChange = { [weak self] _ in self?.toggled() }
        addSubview(toggle)

        refresh()
    }

    required init?(coder: NSCoder) { fatalError("unsupported") }

    override func layout() {
        super.layout()
        label.frame = NSRect(x: 0, y: (bounds.height - 16) / 2, width: 80, height: 16)
        popup.frame = NSRect(x: 84, y: (bounds.height - 20) / 2, width: 68, height: 20)
        play.frame = NSRect(x: 174, y: (bounds.height - 18) / 2, width: 18, height: 18)
        toggle.frame = NSRect(x: bounds.width - 28, y: (bounds.height - 16) / 2, width: 28, height: 16)
    }

    func refresh() {
        let config = SettingsStore.shared.value.event(key)
        toggle.isOn = config.haptic
        if let index = Haptics.presetNames.firstIndex(where: { $0.id == config.preset }) {
            popup.selectItem(at: index)
        }
    }

    private func toggled() {
        let value = toggle.isOn
        SettingsStore.shared.update { $0.events[key, default: EventConfig()].haptic = value }
        onChange?()
    }

    @objc private func changed() {
        let index = max(0, popup.indexOfSelectedItem)
        let preset = Haptics.presetNames[min(index, Haptics.presetNames.count - 1)].id
        SettingsStore.shared.update { $0.events[key, default: EventConfig()].preset = preset }
        onChange?()
    }
}

/** 接入行：工具名 + 状态 + 一键配置/回滚。 */
final class ToolRow: NSView {
    private let tool: HookTool
    private let label: NSTextField
    private let badge = NSTextField(labelWithString: "")
    private let button = PillButton(title: "一键配置")
    var onMessage: ((String) -> Void)?

    init(tool: HookTool) {
        self.tool = tool
        label = NSTextField(labelWithString: tool.rawValue)
        super.init(frame: .zero)
        label.font = Tokens.text(11.5)
        label.textColor = Tokens.muted(0.72)
        addSubview(label)

        badge.font = Tokens.text(10)
        badge.textColor = Tokens.muted(0.4)
        addSubview(badge)

        button.frame.size = NSSize(width: 74, height: 20)
        button.onClick = { [weak self] in self?.toggle() }
        addSubview(button)

        refresh()
    }

    required init?(coder: NSCoder) { fatalError("unsupported") }

    override func layout() {
        super.layout()
        label.frame = NSRect(x: 0, y: (bounds.height - 16) / 2, width: 90, height: 16)
        badge.frame = NSRect(x: 92, y: (bounds.height - 14) / 2, width: 60, height: 14)
        button.frame = NSRect(x: bounds.width - 74, y: (bounds.height - 20) / 2, width: 74, height: 20)
    }

    func refresh() {
        let installed = HookInstaller.shared.isInstalled(tool)
        if tool == .dsh {
            badge.stringValue = "插件接入"
            badge.textColor = Tokens.muted(0.4)
            button.title = "复制命令"
            button.tint = Tokens.muted(0.6)
            return
        }
        badge.stringValue = installed ? "● 已接入" : "○ 未接入"
        badge.textColor = installed ? Tokens.down : Tokens.muted(0.4)
        button.title = installed ? "回滚" : "一键配置"
        button.tint = installed ? Tokens.muted(0.6) : Tokens.gold
    }

    private func toggle() {
        if tool == .dsh {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(HookInstaller.shared.commandLine, forType: .string)
            onMessage?("已复制：\(HookInstaller.shared.commandLine)")
            return
        }
        do {
            let installed = HookInstaller.shared.isInstalled(tool)
            let message = installed
                ? try HookInstaller.shared.uninstall(tool)
                : try HookInstaller.shared.install(tool)
            onMessage?(message)
        } catch {
            onMessage?("失败：\(error.localizedDescription)")
        }
        refresh()
    }
}

/** 极轻量的即时反馈文字，用于「已保存」「已写入」这类一次性提示。 */
enum StatusHUD {
    static func say(_ text: String) {
        NotificationCenter.default.post(name: .goldFloatStatus, object: text)
    }
}

extension Notification.Name {
    static let goldFloatStatus = Notification.Name("GoldFloat.status")
}
