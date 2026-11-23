import AppKit

/** 外观抽屉：浮窗透明度、浮卡不透明度、按钮图标。 */
final class AppearancePage: NSView {
    private let title = NSTextField(labelWithString: "外观")
    private let capsuleRow: SliderRow
    private let cardRow: SliderRow
    private let iconSection = sectionLabel("按钮图标")
    private let hint = NSTextField(labelWithString: "开启唤醒时自动使用填充变体；点一下即保存。")
    private let reset = PillButton(title: "恢复默认", tint: Tokens.muted(0.6), filled: false)
    private let footer = NSTextField(labelWithString: "")
    private let repo = RepoLinkView()
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

        // 页脚：左侧版本号，右侧 GitHub 仓库入口
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        footer.stringValue = "国内金价 v\(short)"
        footer.font = Tokens.number(9.5, .regular)
        footer.textColor = Tokens.muted(0.4)

        [title, capsuleRow, cardRow, iconSection, hint, reset, footer, repo].forEach(addSubview)
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
        reset.frame = NSRect(x: 0, y: 212, width: 90, height: 24)
        footer.frame = NSRect(x: 0, y: bounds.height - 13, width: 120, height: 12)
        repo.frame = NSRect(x: bounds.width - 132, y: bounds.height - 13, width: 132, height: 12)
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


/** 页脚的仓库入口：GitHub 图标 + 仓库名，点击跳转浏览器。 */
final class RepoLinkView: NSView {
    private let url = URL(string: "https://github.com/nagisa-win/gold-board")!
    private let text = "nagisa-win/gold-board"
    private var hovering = false

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) { NSWorkspace.shared.open(url) }

    override func draw(_ dirtyRect: NSRect) {
        let color = hovering ? Tokens.gold : Tokens.muted(0.45)

        // 图标优先用打包的 GitHub 标记，取不到就退化成外链符号。
        if let path = Bundle.main.path(forResource: "github-mark", ofType: "png"),
           let image = NSImage(contentsOfFile: path) {
            image.isTemplate = true
            let size: CGFloat = 11
            let tinted = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
                image.draw(in: rect)
                color.set()
                rect.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: NSRect(x: bounds.width - 132, y: (bounds.height - size) / 2,
                                   width: size, height: size))
        } else if let fallback = symbolImage("arrow.up.right.square", size: 10, color: color) {
            let size = fallback.size
            fallback.draw(in: NSRect(x: bounds.width - 132, y: (bounds.height - size.height) / 2,
                                     width: size.width, height: size.height))
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: Tokens.number(9.5, .regular),
            .foregroundColor: color,
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(at: NSPoint(x: bounds.width - size.width,
                                            y: (bounds.height - size.height) / 2),
                                withAttributes: attrs)
    }
}
