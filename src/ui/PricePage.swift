import AppKit

/** 浮卡第一页：现值、涨跌与近三日曲线。 */
final class PricePage: NSView {
    private let title = NSTextField(labelWithString: "国际现货金")
    private let unit = NSTextField(labelWithString: "元/克")
    private let price = NSTextField(labelWithString: "--.--")
    private let badge = NSTextField(labelWithString: "")
    private let stamp = NSTextField(labelWithString: "")
    private let chart = TrendChartView()
    private let refresh = IconButton(symbol: "arrow.clockwise", tooltip: "立即刷新")
    private let loader = TrendLoader()
    private var loading = false
    private var lastLoad = Date.distantPast
    /// 数据来自备用源时在页脚标注，避免把折算价当成交易所原始口径。
    private var sourceNote = ""

    /// 请求主行情刷新。
    var onRefresh: (() -> Void)?
    /// 提供当前离岸汇率，供图表备用源折算。
    var fallbackRate: (() -> Double?)?

    init() {
        super.init(frame: .zero)
        title.font = Tokens.text(12, .semibold)
        title.textColor = Tokens.muted(0.78)
        unit.font = Tokens.text(10.5)
        unit.textColor = Tokens.muted(0.4)

        price.font = Tokens.number(26, .semibold)
        price.textColor = Tokens.paper

        badge.font = Tokens.number(11, .semibold)
        badge.textColor = Tokens.up

        stamp.font = Tokens.number(10)
        stamp.textColor = Tokens.muted(0.38)

        refresh.onClick = { [weak self] in
            self?.onRefresh?()
            self?.reloadChart(force: true)
        }

        [title, unit, price, badge, stamp, chart, refresh].forEach(addSubview)
        reloadChart(force: true)
    }

    required init?(coder: NSCoder) { fatalError("unsupported") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        title.frame = NSRect(x: 0, y: 0, width: 120, height: 16)
        unit.frame = NSRect(x: bounds.width - 40, y: 1, width: 40, height: 14)
        price.frame = NSRect(x: 0, y: 20, width: 160, height: 32)
        badge.frame = NSRect(x: 160, y: 30, width: 120, height: 16)
        refresh.frame = NSRect(x: bounds.width - 22, y: 20, width: 22, height: 22)
        chart.frame = NSRect(x: 0, y: 58, width: bounds.width, height: max(60, bounds.height - 88))
        stamp.frame = NSRect(x: 0, y: bounds.height - 14, width: bounds.width - 60, height: 12)
    }

    /** 主行情更新后调用。 */
    func update(quote: Quote?, signal: PriceSignal, change: Double?) {
        if let quote {
            price.stringValue = String(format: "%.2f", quote.price)
        }
        if let change, abs(change) > 0.0001 {
            badge.stringValue = String(format: "%@%.2f%%", change >= 0 ? "▲ " : "▼ ", abs(change))
            badge.textColor = change >= 0 ? Tokens.up : Tokens.down
        } else {
            badge.stringValue = signal == .closed ? "休市" : ""
            badge.textColor = Tokens.muted(0.42)
        }
        stamp.stringValue = quote.map { "\($0.stamp) · \(signal.rawValue)\(sourceNote)" } ?? "行情暂不可用"
        refresh.needsDisplay = true
    }

    /** 拉取三日曲线，默认 60 秒内不重复请求。 */
    func reloadChart(force: Bool) {
        guard !loading else { return }
        if !force && Date().timeIntervalSince(lastLoad) < 60 { return }
        loading = true
        Task { @MainActor in
            defer { loading = false }
            do {
                let days = try await loader.load(rate: fallbackRate?())
                chart.days = days
                sourceNote = loader.usedFallback ? " · COMEX 备用" : ""
                chart.message = ""
                TrendLoader.saveCache(days)
                lastLoad = Date()
            } catch {
                if chart.days.isEmpty { chart.days = TrendLoader.loadCache() }
                chart.message = chart.days.isEmpty ? "历史行情暂不可用，稍后重试" : "接口不稳 · 显示上次曲线"
                // 行情源抖动时 20 秒后自动再试，不用等用户操作。
                DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
                    self?.reloadChart(force: true)
                }
            }
        }
    }
}
