import AppKit

/** 毛玻璃底：视觉特效层 + 圆角裁剪 + 0.5pt 高光描边 + 柔和投影。 */
final class GlassView: NSView {
    private let effect = NSVisualEffectView()

    init(radius: CGFloat,
         material: NSVisualEffectView.Material = .hudWindow,
         borderAlpha: CGFloat = 0.08,
         shadowOpacity: Float = 0.32) {
        super.init(frame: .zero)
        effect.material = material
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.appearance = NSAppearance(named: .darkAqua)
        effect.wantsLayer = true
        effect.layer?.cornerRadius = radius
        effect.layer?.masksToBounds = true
        addSubview(effect)

        wantsLayer = true
        layer?.cornerRadius = radius
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.white.withAlphaComponent(borderAlpha).cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = shadowOpacity
        layer?.shadowRadius = 18
        layer?.shadowOffset = CGSize(width: 0, height: -10)
    }

    required init?(coder: NSCoder) { fatalError("unsupported") }

    override func layout() {
        super.layout()
        effect.frame = bounds
    }
}

/** 侧栏与卡片用的纯色底，带圆角与可选描边。 */
final class SolidBackdrop: NSView {
    var fillColor: NSColor = Tokens.graphite {
        didSet { needsDisplay = true }
    }
    var radius: CGFloat = 10 {
        didSet { needsDisplay = true }
    }
    var borderColor: NSColor? = nil {
        didSet { needsDisplay = true }
    }

    init(radius: CGFloat = 10, fill: NSColor = Tokens.graphite) {
        self.radius = radius
        self.fillColor = fill
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("unsupported") }

    override func draw(_ dirtyRect: NSRect) {
        fillColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        if let borderColor {
            borderColor.setStroke()
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.25, dy: 0.25),
                                    xRadius: radius, yRadius: radius)
            path.lineWidth = 0.5
            path.stroke()
        }
    }
}

/** SF Symbol 取图并按调色板着色。 */
func symbolImage(_ name: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor) -> NSImage? {
    let base = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
    let colored = base.applying(NSImage.SymbolConfiguration(paletteColors: [color]))
    return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(colored)
}
