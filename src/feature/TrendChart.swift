import AppKit

struct TrendResponse: Decodable {
    struct Market: Decodable {
        let market: Int
        let code: String
        let trends: [String]

        /** 把 "2026-11-23 14:32,3560.10,3561.20" 解析成 (分钟, 价格)。 */
        func minutes() -> [(String, Double)] {
            trends.compactMap { row in
                let fields = row.split(separator: ",", omittingEmptySubsequences: false)
                guard fields.count >= 3, fields[0].count == 16,
                      let price = Double(fields[2]), price.isFinite, price > 0 else { return nil }
                return (String(fields[0]), price)
            }
        }
    }
    let data: Market
}

/** 单日曲线：日期键 + 折算后的元/克序列（可缓存，供接口不可用时兜底）。 */
struct DayCurve: Codable {
    let day: String
    var prices: [Double] = []

    /** 按同一分钟把金价与离岸汇率配对，再折算成元/克。 */
    static func convert(gold: TrendResponse.Market, fx: TrendResponse.Market) throws -> [DayCurve] {
        guard gold.market == 122, gold.code == "XAU", fx.market == 133, fx.code == "USDCNH" else {
            throw URLError(.cannotParseResponse)
        }
        let rates = Dictionary(fx.minutes(), uniquingKeysWith: { _, latest in latest })
        var days: [DayCurve] = []
        var previous = ""
        for (minute, price) in gold.minutes() {
            guard minute > previous, let rate = rates[minute] else { continue }
            let day = minute.prefix(10).replacingOccurrences(of: "-", with: "")
            if days.last?.day != day { days.append(DayCurve(day: day)) }
            days[days.count - 1].prices.append(price * rate / gramsPerTroyOunce)
            previous = minute
        }
        guard !days.isEmpty else { throw URLError(.cannotParseResponse) }
        return Array(days.suffix(3))
    }
}

/// 新浪全球期货分钟线响应（JSONP 里的 minLine_1d）。
struct SinaMinLine: Decodable {
    let minLine_1d: [[String]]
}

/** 拉取近五日分钟线，金价与汇率各请求一次；接口不可用时退到新浪 COMEX 分钟线。 */
final class TrendLoader {
    private let session = URLSession(configuration: .ephemeral)

    private func history(_ symbol: String) async throws -> TrendResponse.Market {
        let url = URL(string: "https://push2his.eastmoney.com/api/qt/stock/trends2/get?secid=\(symbol)&fields1=f1,f2&fields2=f51,f52,f53&ndays=5")!
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue("https://quote.eastmoney.com/", forHTTPHeaderField: "Referer")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(TrendResponse.self, from: data).data
    }

    /// 缓存文件：接口抖动时至少还能画出上次的曲线。
    private static var cacheURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GoldFloat", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("trend-cache.json")
    }

    static func loadCache() -> [DayCurve] {
        guard let data = try? Data(contentsOf: cacheURL) else { return [] }
        return (try? JSONDecoder().decode([DayCurve].self, from: data)) ?? []
    }

    static func saveCache(_ days: [DayCurve]) {
        guard let data = try? JSONEncoder().encode(days) else { return }
        try? data.write(to: cacheURL)
    }

    /// 本次数据是否来自备用源（界面据此标注）。
    private(set) var usedFallback = false

    func load() async throws -> [DayCurve] {
        async let gold = history("122.XAU")
        async let fx = history("133.USDCNH")
        return try await DayCurve.convert(gold: gold, fx: fx)
    }

    /// 带兜底的加载：东财失败就改用新浪 COMEX 分钟线 × 当前离岸汇率。
    func load(rate: Double?) async throws -> [DayCurve] {
        do {
            usedFallback = false
            return try await load()
        } catch {
            guard let rate, rate > 0 else { throw error }
            let days = try await loadSina(rate: rate)
            usedFallback = true
            return days
        }
    }

    /// 备用源：新浪 COMEX 黄金分钟线，按当前汇率折算成元/克（只有当日）。
    func loadSina(rate: Double) async throws -> [DayCurve] {
        let url = URL(string: "https://stock2.finance.sina.com.cn/futures/api/jsonp.php/var%20t=/GlobalFuturesService.getGlobalFuturesMinLine?symbol=GC")!
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue("https://finance.sina.com.cn", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        guard let text = String(data: data, encoding: .utf8),
              let open = text.firstIndex(of: "("), let close = text.lastIndex(of: ")"),
              open < close else { throw URLError(.cannotParseResponse) }
        let payload = String(text[text.index(after: open)..<close])
        guard let json = payload.data(using: .utf8) else { throw URLError(.cannotParseResponse) }
        let decoded = try JSONDecoder().decode(SinaMinLine.self, from: json)

        var days: [DayCurve] = []
        for row in decoded.minLine_1d {
            guard row.count >= 2, let price = Double(row[1]), price > 0,
                  let stamp = row.last(where: { $0.count == 19 && $0.contains("-") && $0.contains(":") })
            else { continue }
            let day = String(stamp.prefix(10)).replacingOccurrences(of: "-", with: "")
            if days.last?.day != day { days.append(DayCurve(day: day)) }
            days[days.count - 1].prices.append(price * rate / gramsPerTroyOunce)
        }
        guard !days.isEmpty else { throw URLError(.cannotParseResponse) }
        let cleaned = days.map { day -> DayCurve in
            let sorted = day.prices.sorted()
            guard !sorted.isEmpty else { return day }
            let median = sorted[sorted.count / 2]
            var curve = DayCurve(day: day.day)
            // 开市头两笔常是集合竞价/隔夜价，会造成左侧竖刺；再丢掉偏离中位数 5% 的点。
            let body = day.prices.count > 10 ? Array(day.prices.dropFirst(2)) : day.prices
            curve.prices = body.filter { abs($0 - median) / median < 0.05 }
            return curve
        }
        return Array(cleaned.suffix(1))
    }
}

/** 三日曲线：只画图，不画标题（标题由所在页面负责）。 */
final class TrendChartView: NSView {
    var days: [DayCurve] = [] {
        didSet { needsDisplay = true }
    }
    var message = "正在读取分时行情…" {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    private func label(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat = 9.5,
                       color: NSColor, centered: Bool = false) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: Tokens.number(size, .regular),
            .foregroundColor: color,
        ]
        let width = centered ? (text as NSString).size(withAttributes: attrs).width : 0
        (text as NSString).draw(at: NSPoint(x: x - width / 2, y: y), withAttributes: attrs)
    }

    override func draw(_ dirtyRect: NSRect) {
        let prices = days.flatMap(\.prices)
        guard let low = prices.min(), let high = prices.max(), let last = prices.last else {
            label(message, x: bounds.midX, y: bounds.midY - 5, size: 11,
                  color: Tokens.muted(0.5), centered: true)
            return
        }

        let axisWidth: CGFloat = 42
        let plot = NSRect(x: 0, y: 6, width: max(40, bounds.width - axisWidth), height: max(30, bounds.height - 26))
        let spread = max(0.02, high - low)
        let top = (high + low + spread) / 2

        // 三条水平网格：上 / 中 / 下，右侧标价
        for fraction: CGFloat in [0, 0.5, 1] {
            let y = plot.minY + fraction * plot.height
            Tokens.hairline(0.10).setStroke()
            let line = NSBezierPath()
            line.move(to: NSPoint(x: plot.minX, y: y))
            line.line(to: NSPoint(x: plot.maxX, y: y))
            line.lineWidth = 0.5
            line.stroke()
            label(String(format: "%.2f", top - fraction * spread), x: plot.maxX + 6, y: y - 5,
                  color: Tokens.muted(0.42))
        }

        var index = 0
        let step = plot.width / CGFloat(max(1, prices.count - 1))
        let curve = NSBezierPath()
        curve.lineWidth = 1.4
        curve.lineJoinStyle = .round
        var lastPoint = NSPoint.zero
        var previousLabelEnd = -CGFloat.infinity

        for day in days {
            let x = plot.minX + CGFloat(index) * step
            if index > 0 {
                Tokens.hairline(0.10).setStroke()
                let divider = NSBezierPath()
                divider.move(to: NSPoint(x: x, y: plot.minY))
                divider.line(to: NSPoint(x: x, y: plot.maxY))
                divider.lineWidth = 0.5
                divider.stroke()
            }
            let center = min(plot.maxX, max(plot.minX + 15, x + CGFloat(day.prices.count - 1) * step / 2))
            let date = "\(day.day.dropFirst(4).prefix(2))/\(day.day.suffix(2))"
            if center - 15 > previousLabelEnd {
                label(date, x: center, y: plot.maxY + 7, color: Tokens.muted(0.42), centered: true)
                previousLabelEnd = center + 15
            }
            for (offset, value) in day.prices.enumerated() {
                lastPoint = NSPoint(x: plot.minX + CGFloat(index) * step,
                                    y: plot.minY + (top - value) / spread * plot.height)
                if offset == 0 { curve.move(to: lastPoint) } else { curve.line(to: lastPoint) }
                index += 1
            }
        }

        Tokens.curve.setStroke()
        curve.stroke()
        Tokens.curve.setFill()
        NSBezierPath(ovalIn: NSRect(x: lastPoint.x - 2, y: lastPoint.y - 2, width: 4, height: 4)).fill()
        _ = last
    }

    /** 曲线末笔价，供页面页脚显示。 */
    var lastPrice: Double? { days.flatMap(\.prices).last }
}
