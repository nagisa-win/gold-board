import AppKit

/** 全部视觉常量集中于此：改风格只动这个文件。 */
enum Tokens {
    // MARK: - 颜色

    /** 浮字态文字（浅底/透明壁纸用）。 */
    static let ink = NSColor(srgbRed: 0.043, green: 0.047, blue: 0.051, alpha: 1)
    /** 深底态文字。 */
    static let paper = NSColor(srgbRed: 0.961, green: 0.953, blue: 0.933, alpha: 1)
    /** 浮窗与浮卡底色（石墨中性色）。 */
    static let graphite = NSColor(srgbRed: 0.078, green: 0.086, blue: 0.094, alpha: 1)
    /** 侧栏更深一档。 */
    static let railInk = NSColor(srgbRed: 0.055, green: 0.063, blue: 0.071, alpha: 1)
    /** 品牌强调色：开关开启、选中态。 */
    static let gold = NSColor(srgbRed: 0.898, green: 0.706, blue: 0.353, alpha: 1)
    /** 曲线主线。 */
    static let curve = NSColor(srgbRed: 0.969, green: 0.788, blue: 0.451, alpha: 1)
    static let up = NSColor(srgbRed: 0.941, green: 0.600, blue: 0.235, alpha: 1)
    static let down = NSColor(srgbRed: 0.204, green: 0.765, blue: 0.561, alpha: 1)
    static let warn = NSColor(srgbRed: 0.886, green: 0.294, blue: 0.294, alpha: 1)
    static let neutral = NSColor(srgbRed: 0.541, green: 0.541, blue: 0.541, alpha: 1)

    /** 次要文字（默认 55% 白）。 */
    static func muted(_ alpha: CGFloat = 0.55) -> NSColor {
        NSColor(srgbRed: 0.96, green: 0.95, blue: 0.93, alpha: alpha)
    }

    /** 0.5pt 分隔线。 */
    static func hairline(_ alpha: CGFloat = 0.08) -> NSColor {
        NSColor.white.withAlphaComponent(alpha)
    }

    // MARK: - 字体

    /// Maple Mono 的 PostScript 名按字重映射；没装时退回系统等宽数字字体。
    private static let mapleNames: [String: String] = [
        "Regular": "MapleMono-Regular",
        "Medium": "MapleMono-Medium",
        "Semibold": "MapleMono-SemiBold",
        "Bold": "MapleMono-Bold",
    ]

    /** 等宽数字字体（Maple Mono），价格与计时都用它，避免数字跳动。 */
    static func number(_ size: CGFloat, _ weight: NSFont.Weight = .semibold) -> NSFont {
        let key: String
        switch weight {
        case .bold, .heavy, .black: key = "Bold"
        case .semibold: key = "Semibold"
        case .medium: key = "Medium"
        default: key = "Regular"
        }
        if let name = mapleNames[key], let font = NSFont(name: name, size: size) { return font }
        return NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
    }

    /** 中文标签字体：Maple Mono NF CN 带 CJK 字形，缺失时退回系统字体。 */
    static func cjk(_ size: CGFloat, _ weight: NSFont.Weight = .medium) -> NSFont {
        let name: String
        switch weight {
        case .bold, .heavy, .black: name = "MapleMono-NF-CN-Bold"
        case .semibold: name = "MapleMono-NF-CN-SemiBold"
        case .medium: name = "MapleMono-NF-CN-Medium"
        default: name = "MapleMono-NF-CN-Regular"
        }
        if let font = NSFont(name: name, size: size) { return font }
        return NSFont.systemFont(ofSize: size, weight: weight)
    }

    static func text(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: weight)
    }

    // MARK: - 尺寸

    enum Metric {
        static let capsuleHeight: CGFloat = 28
        static let capsulePadLeft: CGFloat = 12
        static let capsulePadRight: CGFloat = 7
        static let capsuleRadius: CGFloat = 14
        static let capsuleMinWidth: CGFloat = 112
        static let capsuleWidth: CGFloat = 128
        static let buttonSize: CGFloat = 20
        static let buttonGap: CGFloat = 4

        static let railWidth: CGFloat = 48
        static let cardWidth: CGFloat = 372
        static let cardHeight: CGFloat = 296
        static let cardRadius: CGFloat = 16
        static let cardGap: CGFloat = 8
        static let cardInset: CGFloat = 14
    }

    // MARK: - 动效

    enum Motion {
        static let hoverIn: TimeInterval = 0.14
        static let hoverOut: TimeInterval = 0.18
        static let hoverDelay: TimeInterval = 0.25
        static let hoverLeaveDelay: TimeInterval = 0.4
    }
}
