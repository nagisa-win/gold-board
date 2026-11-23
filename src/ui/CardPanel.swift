import AppKit

/** 浮卡：左侧三图标 rail + 内容区；外观抽屉挂在 rail 底部齿轮上。 */
final class CardPanel: NSPanel {
    let pricePage = PricePage()
    let wakePage = WakePage()
    let notifyPage = NotifyPage()
    let appearancePage = AppearancePage()

    private let backdrop = GlassView(radius: Tokens.Metric.cardRadius, borderAlpha: 0.10, shadowOpacity: 0)
    private let tint = SolidBackdrop(radius: Tokens.Metric.cardRadius,
                                     fill: Tokens.graphite.withAlphaComponent(0.78))
    private let rail = RailView()
    private let content = NSView()
    private var navButtons: [IconButton] = []
    private let gear = IconButton(symbol: "gearshape", tooltip: "外观设置")
    private var pages: [NSView] = []

    /// 0 走势 / 1 唤醒 / 2 通知 / 3 外观
    private(set) var selected = 0
    /// 单击锁定的浮卡不随鼠标移出收起。
    private(set) var locked = false

    private let navSymbols = [
        ("chart.line.uptrend.xyaxis", "金价走势"),
        ("timer", "唤醒定时器"),
        ("bell.badge", "通知与震动"),
    ]

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0,
                                       width: Tokens.Metric.cardWidth,
                                       height: Tokens.Metric.cardHeight),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        appearance = NSAppearance(named: .darkAqua)
        level = .statusBar
        hidesOnDeactivate = false
        isFloatingPanel = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let root = NSView(frame: NSRect(x: 0, y: 0,
                                        width: Tokens.Metric.cardWidth,
                                        height: Tokens.Metric.cardHeight))
        // 整层裁圆角：rail 的直角背景会被裁掉，左侧圆角才干净。
        root.wantsLayer = true
        root.layer?.cornerRadius = Tokens.Metric.cardRadius
        root.layer?.masksToBounds = true
        contentView = root
        root.addSubview(backdrop)
        root.addSubview(tint)
        root.addSubview(rail)
        root.addSubview(content)
        rail.addSubview(gear)

        for (index, item) in navSymbols.enumerated() {
            let button = IconButton(symbol: item.0, tooltip: item.1)
            button.iconSize = 16
            button.onClick = { [weak self] in self?.select(index) }
            navButtons.append(button)
            rail.addSubview(button)
        }

        gear.iconSize = 14
        gear.onClick = { [weak self] in
            guard let self else { return }
            self.select(self.selected == 3 ? 0 : 3)
        }

        pages = [pricePage, wakePage, notifyPage, appearancePage]
        for page in pages {
            page.isHidden = true
            content.addSubview(page)
        }
        relayout()
        select(0)
    }

    /** 手写布局：rail 固定 48pt，其余给内容区。 */
    private func relayout() {
        guard let root = contentView else { return }
        backdrop.frame = root.bounds
        tint.frame = root.bounds
        rail.frame = NSRect(x: 0, y: 0, width: Tokens.Metric.railWidth, height: root.bounds.height)

        // rail 坐标是翻转的：y 越大越靠下，导航自上而下，齿轮贴底。
        for (index, button) in navButtons.enumerated() {
            button.frame = NSRect(x: 6, y: 14 + CGFloat(index) * 44, width: 36, height: 36)
        }
        gear.frame = NSRect(x: 6, y: root.bounds.height - 48, width: 36, height: 36)

        let inset = Tokens.Metric.cardInset
        content.frame = NSRect(x: Tokens.Metric.railWidth,
                               y: 0,
                               width: root.bounds.width - Tokens.Metric.railWidth,
                               height: root.bounds.height)
        for page in pages {
            page.frame = NSRect(x: inset, y: inset,
                                width: content.bounds.width - inset * 2,
                                height: content.bounds.height - inset * 2)
        }
    }

    /** 切换页面；外观页不占 rail 选中态。 */
    func select(_ index: Int) {
        guard index >= 0, index < pages.count else { return }
        selected = index
        for (offset, button) in navButtons.enumerated() {
            button.isSelected = offset == index
        }
        gear.isSelected = index == 3

        let target = pages[index]
        for page in pages where page !== target {
            page.isHidden = true
            page.alphaValue = 0
        }
        target.isHidden = false
        target.alphaValue = 1
        target.needsLayout = true
        target.layoutSubtreeIfNeeded()

        switch index {
        case 0: pricePage.reloadChart(force: false)
        case 1: wakePage.refresh()
        case 2: notifyPage.refresh()
        default: appearancePage.refresh()
        }
    }

    /// 浮窗被拖动时同步挪动浮卡，避免两者脱节。
    func follow(_ capsuleFrame: NSRect) {
        guard isVisible else { return }
        setFrameOrigin(anchorOrigin(for: capsuleFrame))
    }

    /** 从设置同步整体不透明度。 */
    func applySettings() {
        alphaValue = SettingsStore.shared.value.cardOpacity / 100
        appearancePage.refresh()
    }

    // MARK: - 显隐

    /** 相对胶囊浮窗定位并展开；locked 表示单击锁定。 */
    func show(anchoredTo capsuleFrame: NSRect, locked: Bool) {
        self.locked = locked
        if !isVisible {
            setFrameOrigin(anchorOrigin(for: capsuleFrame))
            // 窗口 alpha 直接置位：动画交给页面淡入，避免动画被打断后停在 0。
            alphaValue = SettingsStore.shared.value.cardOpacity / 100
            orderFrontRegardless()
        }
        select(selected)
    }

    /// 输入等交互期间锁定，避免鼠标离开自动收起。
    func lockOpen() {
        locked = true
    }

    func hide() {
        guard isVisible else { return }
        locked = false
        orderOut(nil)
        alphaValue = SettingsStore.shared.value.cardOpacity / 100
    }

    /** 优先贴在胶囊下方，右边缘对齐；空间不足时翻到上方。 */
    private func anchorOrigin(for capsuleFrame: NSRect) -> NSPoint {
        let size = frame.size
        let screen = NSScreen.screens.first { $0.visibleFrame.intersects(capsuleFrame) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        var x = capsuleFrame.maxX - size.width
        x = min(max(visible.minX + 8, x), visible.maxX - size.width - 8)

        let below = capsuleFrame.minY - Tokens.Metric.cardGap - size.height
        let above = capsuleFrame.maxY + Tokens.Metric.cardGap
        let y = below >= visible.minY + 8 ? below : min(above, visible.maxY - size.height - 8)
        return NSPoint(x: x, y: y)
    }
}

/** 侧栏：更深底色 + 右侧 0.5pt 分隔线。 */
final class RailView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(srgbRed: 0.055, green: 0.063, blue: 0.071, alpha: 0.55).setFill()
        NSBezierPath(rect: bounds).fill()
        Tokens.hairline(0.08).setStroke()
        let line = NSBezierPath()
        line.move(to: NSPoint(x: bounds.maxX - 0.25, y: 0))
        line.line(to: NSPoint(x: bounds.maxX - 0.25, y: bounds.height))
        line.lineWidth = 0.5
        line.stroke()
    }
}
