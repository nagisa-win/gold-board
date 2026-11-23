import AppKit

/** 图标按钮：hover 底、选中金底、可选外环进度（唤醒计时用）。 */
final class IconButton: NSView {
    var symbol: String {
        didSet { needsDisplay = true }
    }
    var tint: NSColor = Tokens.muted(0.45) {
        didSet { needsDisplay = true }
    }
    var activeTint: NSColor = Tokens.gold
    var isActive = false {
        didSet { needsDisplay = true }
    }
    var isSelected = false {
        didSet { needsDisplay = true }
    }
    var iconSize: CGFloat = 15
    var onClick: (() -> Void)?
    var onRightClick: (() -> Void)?

    private var hovering = false

    init(symbol: String, tooltip: String? = nil) {
        self.symbol = symbol
        super.init(frame: .zero)
        toolTip = tooltip
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("unsupported") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        needsDisplay = true
    }

    /** 消费按下事件，避免落到父视图触发拖窗。 */
    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) { onClick?() }

    override func rightMouseUp(with event: NSEvent) { onRightClick?() }

    override func draw(_ dirtyRect: NSRect) {
        if isSelected {
            Tokens.gold.withAlphaComponent(0.14).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).fill()
        } else if hovering {
            NSColor.white.withAlphaComponent(0.06).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).fill()
        }

        let color = isActive ? activeTint : (hovering ? Tokens.muted(0.88) : tint)
        if let image = symbolImage(symbol, size: iconSize, weight: .medium, color: color) {
            let size = image.size
            image.draw(in: NSRect(x: bounds.midX - size.width / 2,
                                  y: bounds.midY - size.height / 2,
                                  width: size.width, height: size.height))
        }
    }

}

/** 可多选的小参数 chip（caffeinate 的 -i -d -m -s -u）。 */
final class Chip: NSView {
    private let title: String
    var isOn = false {
        didSet { needsDisplay = true }
    }
    var onClick: (() -> Void)?

    init(title: String) {
        self.title = title
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("unsupported") }

    override var intrinsicContentSize: NSSize { NSSize(width: 26, height: 20) }

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) { onClick?() }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.25, dy: 0.25), xRadius: 6, yRadius: 6)
        (isOn ? Tokens.gold.withAlphaComponent(0.20) : NSColor.white.withAlphaComponent(0.06)).setFill()
        path.fill()
        (isOn ? Tokens.gold.withAlphaComponent(0.55) : NSColor.white.withAlphaComponent(0.10)).setStroke()
        path.lineWidth = 0.5
        path.stroke()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: Tokens.text(10.5, .semibold),
            .foregroundColor: isOn ? Tokens.gold : Tokens.muted(0.62),
        ]
        let size = (title as NSString).size(withAttributes: attrs)
        (title as NSString).draw(at: NSPoint(x: bounds.midX - size.width / 2,
                                            y: bounds.midY - size.height / 2), withAttributes: attrs)
    }
}

/** 两段式分段控件（时间段 / 倒计时）。 */
final class Segmented: NSView {
    private let items: [String]
    private(set) var selected = 0
    var onSelect: ((Int) -> Void)?

    init(items: [String]) {
        self.items = items
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("unsupported") }

    override var intrinsicContentSize: NSSize { NSSize(width: 168, height: 24) }

    func select(_ index: Int, notify: Bool) {
        guard index >= 0, index < items.count else { return }
        selected = index
        needsDisplay = true
        if notify { onSelect?(index) }
    }

    override func mouseDown(with event: NSEvent) {
        let segment = bounds.width / CGFloat(max(1, items.count))
        let x = convert(event.locationInWindow, from: nil).x
        let picked = min(items.count - 1, max(0, Int(x / segment)))
        select(picked, notify: true)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.withAlphaComponent(0.06).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()

        let segment = bounds.width / CGFloat(max(1, items.count))
        let thumb = NSRect(x: CGFloat(selected) * segment + 2, y: 2, width: segment - 4, height: bounds.height - 4)
        NSColor.white.withAlphaComponent(0.12).setFill()
        NSBezierPath(roundedRect: thumb, xRadius: 5, yRadius: 5).fill()

        for (index, title) in items.enumerated() {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: Tokens.text(11, index == selected ? .semibold : .regular),
                .foregroundColor: index == selected ? Tokens.paper : Tokens.muted(0.55),
            ]
            let size = (title as NSString).size(withAttributes: attrs)
            let centerX = CGFloat(index) * segment + segment / 2
            (title as NSString).draw(at: NSPoint(x: centerX - size.width / 2,
                                                 y: bounds.midY - size.height / 2),
                                     withAttributes: attrs)
        }
    }
}
