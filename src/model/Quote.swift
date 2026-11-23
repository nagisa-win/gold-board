import AppKit

let gramsPerTroyOunce = 31.1034768

/** 东方财富行情响应解析：国际现货黄金 XAU 按离岸人民币折算成元/克。 */
struct Quote {
    private struct Response: Decodable {
        struct Listing: Decodable {
            struct Tick: Decodable {
                let f2: Double
                let f12: String
                let f13: Int
                let f292: Int?
                let f124: TimeInterval
            }
            let diff: [Tick]
        }
        let data: Listing
    }

    let price: Double
    /// 离岸人民币汇率（元/美元），图表备用源需要它做折算。
    let fxRate: Double
    let stamp: String
    let date: Date
    let marketOpen: Bool
    /// 备用源只有分钟粒度，过期判定要放宽到 150 秒。
    let minuteGranularity: Bool

    /// 备用构造：实时接口不可用时，用分时线的末笔价与同分钟汇率折算。
    init?(goldPrice: Double, fxRate: Double, date: Date) {
        guard goldPrice > 0, fxRate > 0 else { return nil }
        price = goldPrice * fxRate / gramsPerTroyOunce
        self.fxRate = fxRate
        self.date = date
        // 末笔在 5 分钟内视为开市，与分时线口径一致。
        marketOpen = Date().timeIntervalSince(date) < 300
        minuteGranularity = true
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "MM-dd HH:mm"
        stamp = formatter.string(from: date)
    }

    init?(_ data: Data) {
        guard let ticks = try? JSONDecoder().decode(Response.self, from: data).data.diff,
              let gold = ticks.first(where: { $0.f12 == "XAU" && $0.f13 == 122 }),
              let fx = ticks.first(where: { $0.f12 == "USDCNH" && $0.f13 == 133 }),
              let state = gold.f292, (1...16).contains(state),
              gold.f2 > 0, fx.f2 > 0, gold.f124 > 0, fx.f124 > 0 else { return nil }
        marketOpen = [1, 2, 4, 11, 12].contains(state)
        minuteGranularity = false
        price = gold.f2 * fx.f2 / gramsPerTroyOunce
        fxRate = fx.f2
        date = Date(timeIntervalSince1970: min(gold.f124, fx.f124))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "MM-dd HH:mm:ss"
        stamp = formatter.string(from: date)
    }
}

/** 价格信号的四种状态，决定浮窗数字的颜色。 */
enum PriceSignal: String {
    case normal = "行情"
    case rising = "急涨"
    case falling = "急跌"
    case stale = "报价已过期"
    case closed = "休市"

    var color: NSColor {
        switch self {
        case .normal: return Tokens.neutral
        case .rising: return Tokens.up
        case .falling: return Tokens.down
        case .stale: return Tokens.warn
        case .closed: return Tokens.neutral
        }
    }
}
