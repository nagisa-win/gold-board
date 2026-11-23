import AppKit

/** 正圆角胶囊按钮，用于「开始唤醒 / 一键配置 / 试听」这类动作。 */
final class PillButton: NSView {
    var title: String {
        didSet { needsDisplay = true }
    }
    var tint: NSColor = Tokens.gold {
        didSet { needsDisplay = true }
    }
    var filled = true {
        didSet { needsDisplay = true }
    }
    var isEnabled = true {
        didSet { needsDisplay = true }
    }
    var onClick: (() -> Void)?

    private var hovering = false

    init(title: String, tint: NSColor = Tokens.gold, filled: Bool = true) {
        self.title = title
        self.tint = tint
        self.filled = filled
        super.init(frame: .zero)
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

    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) { if isEnabled { onClick?() } }

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        let alpha: CGFloat = isEnabled ? (hovering ? 1.0 : 0.86) : 0.35
        if filled {
            tint.withAlphaComponent(0.16 * alpha).setFill()
            path.fill()
        }
        tint.withAlphaComponent(0.5 * alpha).setStroke()
        path.lineWidth = 0.5
        path.stroke()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: Tokens.text(11.5, .semibold),
            .foregroundColor: tint.withAlphaComponent(alpha),
        ]
        let size = (title as NSString).size(withAttributes: attrs)
        (title as NSString).draw(at: NSPoint(x: bounds.midX - size.width / 2,
                                             y: bounds.midY - size.height / 2),
                                 withAttributes: attrs)
    }
}

/** 自绘开关：金色开启态，尺寸比 NSSwitch 更收敛。 */
final class Toggle: NSView {
    var isOn: Bool {
        didSet { needsDisplay = true }
    }
    var onChange: ((Bool) -> Void)?

    init(isOn: Bool) {
        self.isOn = isOn
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("unsupported") }

    override var intrinsicContentSize: NSSize { NSSize(width: 28, height: 16) }

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        isOn.toggle()
        onChange?(isOn)
    }

    override func draw(_ dirtyRect: NSRect) {
        let track = NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        (isOn ? Tokens.gold.withAlphaComponent(0.85) : NSColor.white.withAlphaComponent(0.12)).setFill()
        track.fill()

        let knobSize = bounds.height - 4
        let x = isOn ? bounds.maxX - knobSize - 2 : 2
        let knob = NSBezierPath(ovalIn: NSRect(x: x, y: 2, width: knobSize, height: knobSize))
        (isOn ? Tokens.graphite : NSColor.white.withAlphaComponent(0.72)).setFill()
        knob.fill()
    }
}

/** 一行「标签 + 开关」。 */
final class SwitchRow: NSView {
    private let label: NSTextField
    private let toggle: Toggle
    var onChange: ((Bool) -> Void)?

    init(title: String, value: Bool, labelWidth: CGFloat = 96) {
        label = NSTextField(labelWithString: title)
        toggle = Toggle(isOn: value)
        super.init(frame: .zero)
        label.font = Tokens.text(11.5)
        label.textColor = Tokens.muted(0.72)
        label.frame = NSRect(x: 0, y: 0, width: labelWidth, height: 16)
        addSubview(label)

        toggle.onChange = { [weak self] value in self?.onChange?(value) }
        addSubview(toggle)
    }

    required init?(coder: NSCoder) { fatalError("unsupported") }

    override func layout() {
        super.layout()
        label.frame = NSRect(x: 0, y: (bounds.height - 16) / 2, width: bounds.width - 40, height: 16)
        toggle.frame = NSRect(x: bounds.width - 28, y: (bounds.height - 16) / 2, width: 28, height: 16)
    }

    func setValue(_ value: Bool) { toggle.isOn = value }
}

/** 一行「标签 + 滑块 + 右侧数值」。 */
final class SliderRow: NSView {
    private let label: NSTextField
    private let slider = NSSlider()
    private let valueLabel = NSTextField(labelWithString: "")
    var onChange: ((Double) -> Void)?

    init(title: String, value: Double, range: ClosedRange<Double>, suffix: String = "%") {
        label = NSTextField(labelWithString: title)
        super.init(frame: .zero)
        label.font = Tokens.text(11.5)
        label.textColor = Tokens.muted(0.72)
        addSubview(label)

        slider.minValue = range.lowerBound
        slider.maxValue = range.upperBound
        slider.doubleValue = value
        slider.controlSize = .small
        slider.target = self
        slider.action = #selector(slid)
        addSubview(slider)

        valueLabel.font = Tokens.number(11)
        valueLabel.textColor = Tokens.gold
        valueLabel.alignment = .right
        valueLabel.stringValue = "\(Int(value))\(suffix)"
        addSubview(valueLabel)
    }

    required init?(coder: NSCoder) { fatalError("unsupported") }

    override func layout() {
        super.layout()
        label.frame = NSRect(x: 0, y: (bounds.height - 16) / 2, width: 96, height: 16)
        valueLabel.frame = NSRect(x: bounds.width - 40, y: (bounds.height - 16) / 2, width: 40, height: 16)
        slider.frame = NSRect(x: 100, y: (bounds.height - 18) / 2, width: max(40, bounds.width - 148), height: 18)
    }

    func setValue(_ value: Double) {
        slider.doubleValue = value
        valueLabel.stringValue = "\(Int(value))%"
    }

    @objc private func slid() {
        valueLabel.stringValue = "\(Int(slider.doubleValue))%"
        onChange?(slider.doubleValue)
    }
}

/** 五档强度点选。 */
final class StrengthDots: NSView {
    var value = 3 {
        didSet { needsDisplay = true }
    }
    var onChange: ((Int) -> Void)?

    init(value: Int) {
        self.value = value
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("unsupported") }

    override var intrinsicContentSize: NSSize { NSSize(width: 86, height: 16) }

    override func mouseDown(with event: NSEvent) {
        let x = convert(event.locationInWindow, from: nil).x
        let step = bounds.width / 5
        let picked = min(5, max(1, Int(x / step) + 1))
        value = picked
        onChange?(picked)
    }

    override func draw(_ dirtyRect: NSRect) {
        let step = bounds.width / 5
        for index in 0..<5 {
            let on = index < value
            let radius: CGFloat = 3 + CGFloat(index) * 0.6
            let center = NSPoint(x: step * CGFloat(index) + step / 2, y: bounds.midY)
            let dot = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius,
                                                  width: radius * 2, height: radius * 2))
            (on ? Tokens.gold : NSColor.white.withAlphaComponent(0.16)).setFill()
            dot.fill()
        }
    }
}

/** 小型分区标题。 */
func sectionLabel(_ text: String) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.font = Tokens.text(10, .semibold)
    label.textColor = Tokens.muted(0.38)
    return label
}
