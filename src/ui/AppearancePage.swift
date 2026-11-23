import AppKit

/** 外观抽屉：浮窗透明度、浮卡不透明度、按钮图标。 */
final class AppearancePage: NSView {
    private let title = NSTextField(labelWithString: "外观")
    private let capsuleRow: SliderRow
    private let cardRow: SliderRow
    private let iconSection = sectionLabel("按钮图标")
    private let hint = NSTextField(labelWithString: "开启唤醒时自动使用填充变体；点一下即保存。")
    private let reset = PillButton(title: "恢复默认", tint: Tokens.muted(0.6), filled: false)
    private var iconButtons: [IconButton] = []

    private let symbols = [
        "cup.and.saucer", "moon.zzz", "bolt", "eye",
        "lock", "flame", "leaf", "waveform",
        "cpu", "timer", "coffee", "bed.double",
    ]

    init() {
        let settings = SettingsStore.shared.value
        capsuleRow = SliderRow(title: "浮窗背景", value: settings.capsuleOpacity, range: 0...100)
        cardRow = SliderRow(title: "浮卡不透明度", value: settings.cardOpacity, range: 50...100)
        super.init(frame: .zero)

        title.font = Tokens.text(12, .semibold)
        title.textColor = Tokens.muted(0.78)

        capsuleRow.onChange = { value in
            SettingsStore.shared.update { $0.capsuleOpacity = value }
        }
        cardRow.onChange = { value in
            SettingsStore.shared.update { $0.cardOpacity = value }
        }

        hint.font = Tokens.text(10)
        hint.textColor = Tokens.muted(0.35)

        for symbol in symbols {
            let button = IconButton(symbol: symbol, tooltip: symbol)
            button.iconSize = 14
            button.onClick = { [weak self] in
                SettingsStore.shared.update { $0.buttonSymbol = symbol }
                self?.refresh()
            }
            iconButtons.append(button)
            addSubview(button)
        }

        reset.onClick = { [weak self] in
            SettingsStore.shared.reset()
            self?.refresh()
        }

        [title, capsuleRow, cardRow, iconSection, hint, reset].forEach(addSubview)
    }

    required init?(coder: NSCoder) { fatalError("unsupported") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        title.frame = NSRect(x: 0, y: 0, width: 120, height: 16)
        capsuleRow.frame = NSRect(x: 0, y: 26, width: bounds.width, height: 22)
        cardRow.frame = NSRect(x: 0, y: 54, width: bounds.width, height: 22)
        iconSection.frame = NSRect(x: 0, y: 88, width: 120, height: 12)

        let cell: CGFloat = 38
        for (index, button) in iconButtons.enumerated() {
            let column = index % 6
            let row = index / 6
            button.frame = NSRect(x: CGFloat(column) * (cell + 6), y: 106 + CGFloat(row) * (cell + 6),
                                  width: cell, height: cell)
        }
        hint.frame = NSRect(x: 0, y: 200, width: bounds.width, height: 14)
        reset.frame = NSRect(x: 0, y: 224, width: 90, height: 24)
    }

    func refresh() {
        let settings = SettingsStore.shared.value
        capsuleRow.setValue(settings.capsuleOpacity)
        cardRow.setValue(settings.cardOpacity)
        for button in iconButtons {
            button.isSelected = button.symbol == settings.buttonSymbol
        }
    }
}
