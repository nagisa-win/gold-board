import AppKit

/** 价格文字层：单独放在毛玻璃之上，保证悬停时数字不被玻璃盖住。 */
final class CapsuleNumberView: NSView {
    var number = "--.--" {
        didSet { needsDisplay = true }
    }
    var signal: PriceSignal = .normal {
        didSet { needsDisplay = true }
    }
    /// 悬停/拖动时底色变深，文字一律转成浅色，避免黑字压黑底。
    var prefersLightText = false {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let opacity = SettingsStore.shared.value.capsuleOpacity / 100
        let light = prefersLightText || opacity >= 0.24
        let color = Self.color(opacity: opacity, signal: signal, light: light)

        let numberFont = Tokens.number(17, .semibold)
        let labelFont = Tokens.cjk(11, .medium)
        // 浮窗文字统一带一层柔和阴影：浅色字用黑色投影，深色字用白色柔光，任何壁纸上都更立体。
        let shadow = Self.textShadow(lightText: light)
        let numberAttrs: [NSAttributedString.Key: Any] = [
            .font: numberFont,
            .foregroundColor: color,
            .shadow: shadow,
        ]
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: color.withAlphaComponent(0.45),
            .shadow: shadow,
        ]

        // 两段共用一条基线：以数字行盒居中为准。
        let lineHeight = numberFont.ascender - numberFont.descender
        let baseline = (bounds.height - lineHeight) / 2 - numberFont.descender

        ("金" as NSString).draw(at: NSPoint(x: 0, y: baseline + labelFont.descender),
                                withAttributes: labelAttrs)

        let text = NSAttributedString(string: number, attributes: numberAttrs)
        let size = text.size()
        text.draw(at: NSPoint(x: bounds.width - size.width,
                              y: baseline + numberFont.descender))
    }

    /// 浮窗文字阴影：白字用黑色投影，黑字用白色柔光。
    static func textShadow(lightText: Bool) -> NSShadow {
        let shadow = NSShadow()
        // 偏移保持 0,0：只要一圈均匀的柔光，不要投影的「立体感」。
        shadow.shadowOffset = .zero
        if lightText {
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.38)
            shadow.shadowBlurRadius = 2.2
        } else {
            shadow.shadowColor = NSColor.white.withAlphaComponent(0.55)
            shadow.shadowBlurRadius = 1.8
        }
        return shadow
    }

    /// 透明态黑字，深底态白字；涨跌色跟随同一规则。
    static func color(opacity: Double, signal: PriceSignal, light: Bool) -> NSColor {
        if signal == .rising || signal == .falling || signal == .stale {
            return light ? signal.color : brighter(signal.color)
        }
        return light ? Tokens.paper : Tokens.ink
    }

    /// 透明态下提亮涨跌色，补偿没有底色时的感知压暗。
    static func brighter(_ color: NSColor) -> NSColor {
        guard let srgb = color.usingColorSpace(.sRGB) else { return color }
        return NSColor(srgbRed: min(1, srgb.redComponent * 1.12),
                       green: min(1, srgb.greenComponent * 1.12),
                       blue: min(1, srgb.blueComponent * 1.12),
                       alpha: srgb.alphaComponent)
    }
}

/** 胶囊浮窗：左侧金价数字、右侧唤醒开关按钮；悬停时浮出毛玻璃底。 */
final class CapsuleView: NSView {
    private let backdrop = SolidBackdrop(radius: Tokens.Metric.capsuleRadius, fill: .clear)
    private let glass = GlassView(radius: Tokens.Metric.capsuleRadius, borderAlpha: 0.14, shadowOpacity: 0.28)
    private let hoverTint = SolidBackdrop(radius: Tokens.Metric.capsuleRadius,
                                         fill: Tokens.graphite.withAlphaComponent(0.55))
    private let numberView = CapsuleNumberView()
    let button = IconButton(symbol: "cup.and.saucer", tooltip: "保持系统唤醒")

    private var hovered = false
    private var dragging = false
    private var pressLocation = NSPoint.zero

    /// 单击数字：打开浮卡。
    var onClickNumber: (() -> Void)?
    /// 悬停变化：驱动毛玻璃与浮卡自动展开。
    var onHoverChange: ((Bool) -> Void)?
    /// 拖动中：把胶囊 frame 广播出去，让浮卡跟随。
    var onMove: ((NSRect) -> Void)?

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        glass.alphaValue = 0
        hoverTint.alphaValue = 0
        addSubview(backdrop)
        addSubview(glass)
        addSubview(hoverTint)
        addSubview(numberView)
        addSubview(button)
    }

    required init?(coder: NSCoder) { fatalError("unsupported") }

    override var isFlipped: Bool { false }

    override func layout() {
        super.layout()
        backdrop.frame = bounds
        glass.frame = bounds
        hoverTint.frame = bounds
        let contentRight = bounds.width - Tokens.Metric.buttonSize
            - Tokens.Metric.capsulePadRight - Tokens.Metric.buttonGap
        numberView.frame = NSRect(x: Tokens.Metric.capsulePadLeft, y: 0,
                                  width: max(0, contentRight - Tokens.Metric.capsulePadLeft),
                                  height: bounds.height)
        let size = Tokens.Metric.buttonSize
        button.frame = NSRect(x: bounds.width - size - Tokens.Metric.capsulePadRight,
                              y: (bounds.height - size) / 2, width: size, height: size)
    }

    // MARK: - 内容

    /// 宽度固定，避免数字位数变化时窗口跳动或位置漂移。
    var preferredWidth: CGFloat {
        Tokens.Metric.capsuleWidth
    }

    func update(number: String, signal: PriceSignal) {
        numberView.number = number
        numberView.signal = signal
    }

    func apply(settings: AppSettings, running: Bool) {
        let opacity = settings.capsuleOpacity / 100
        // 底色比滑杆更快变实：t=62% 时约 0.67，t=100% 时 0.94，避免半透明时发灰。
        backdrop.fillColor = opacity > 0.01
            ? Tokens.graphite.withAlphaComponent(0.94 * pow(opacity, 0.7))
            : .clear
        button.symbol = settings.buttonSymbol
        // 运行中只把图标点亮成金色，不再在按钮上叠进度环。
        button.isActive = running
        button.tint = opacity < 0.24 ? Tokens.ink.withAlphaComponent(0.55) : Tokens.muted(0.55)
        numberView.needsDisplay = true
        backdrop.needsDisplay = true
    }

    // MARK: - 悬停与拖动

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { setHover(true) }

    override func mouseExited(with event: NSEvent) { if !dragging { setHover(false) } }

    func setHover(_ value: Bool) {
        guard hovered != value else { return }
        hovered = value
        numberView.prefersLightText = value || dragging
        onHoverChange?(value)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = value ? Tokens.Motion.hoverIn : Tokens.Motion.hoverOut
            glass.animator().alphaValue = value ? 1 : 0
            hoverTint.animator().alphaValue = value ? 1 : 0
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        pressLocation = NSEvent.mouseLocation
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        let current = NSEvent.mouseLocation
        let dx = current.x - pressLocation.x
        let dy = current.y - pressLocation.y
        if !dragging && hypot(dx, dy) < 3 { return }
        dragging = true
        numberView.prefersLightText = true
        glass.alphaValue = 1
        hoverTint.alphaValue = 1
        guard let window else { return }
        window.setFrameOrigin(NSPoint(x: window.frame.origin.x + dx, y: window.frame.origin.y + dy))
        pressLocation = current
        onMove?(window.frame)
    }

    override func mouseUp(with event: NSEvent) {
        let wasDragging = dragging
        dragging = false
        numberView.prefersLightText = hovered
        if !wasDragging { onClickNumber?() }
        setHover(bounds.contains(convert(event.locationInWindow, from: nil)))
    }
}

/** 无边框、不抢焦点的浮窗容器。 */
final class CapsulePanel: NSPanel {
    let capsule = CapsuleView()

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0,
                                       width: Tokens.Metric.capsuleMinWidth,
                                       height: Tokens.Metric.capsuleHeight),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        hidesOnDeactivate = false
        isFloatingPanel = true
        isMovableByWindowBackground = false
        appearance = NSAppearance(named: .darkAqua)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = capsule
    }
}
