import AppKit

/** 行情轮询与信号判定：每 5 秒拉一次，60 秒窗口内净涨跌 0.30% 视为急涨/急跌。 */
final class QuoteFeed {
    private let session = URLSession(configuration: .ephemeral)
    private var pollTimer: Timer?
    private var tickTimer: Timer?
    private var fetching = false
    private var recent: [Quote] = []
    private var reopenedAt = Date.distantPast
    private var stateCheckedAt = Date.distantPast
    private var failureCount = 0

    private(set) var quote: Quote?
    private(set) var signal: PriceSignal = .normal
    private(set) var lastRequestFailed = false
    /// 最近 60 秒窗口内的净涨跌百分比，浮卡用来显示 ▲/▼。
    private(set) var changePercent: Double?
    /// 最新离岸人民币汇率，图表备用源折算用。
    var fxRate: Double? { quote?.fxRate }

    /// 数字、颜色或状态变化时回调（每秒最多一次）。
    var onChange: (() -> Void)?
    /// 只在急涨/急跌的瞬间回调一次，供震动与系统通知使用。
    var onSignalTriggered: ((PriceSignal) -> Void)?

    /** 启动轮询与每秒判定。失败时退避，避免被行情源限流。 */
    func start() {
        refresh()
        let tick = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.evaluate() }
        tick.tolerance = 0.2
        RunLoop.main.add(tick, forMode: .common)
        tickTimer = tick
    }

    func stop() {
        pollTimer?.invalidate()
        tickTimer?.invalidate()
    }

    /** 下一次请求间隔：连续失败按 5→10→20→40→60 秒退避，成功即回到 5 秒。 */
    private func scheduleNextPoll() {
        pollTimer?.invalidate()
        let delay = min(60, 5 * pow(2, Double(failureCount)))
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in self?.refresh() }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    /** 立即拉一次行情。 */
    func refresh() {
        guard !fetching else { return }
        fetching = true
        let url = URL(string: "https://push2.eastmoney.com/api/qt/ulist.np/get?secids=122.XAU,133.USDCNH&fltt=2&fields=f2,f12,f13,f124,f292")!
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.setValue("https://quote.eastmoney.com/", forHTTPHeaderField: "Referer")
        session.dataTask(with: request) { [weak self] data, response, _ in
            guard let self else { return }
            let update = (response as? HTTPURLResponse)?.statusCode == 200 ? data.flatMap(Quote.init) : nil
            DispatchQueue.main.async {
                self.fetching = false
                self.lastRequestFailed = update == nil
                self.failureCount = update == nil ? self.failureCount + 1 : 0
                if let update {
                    self.stateCheckedAt = Date()
                    if self.quote?.marketOpen == false && update.marketOpen {
                        self.reopenedAt = self.stateCheckedAt
                    }
                    let previous = self.quote
                    if previous == nil || previous?.marketOpen != update.marketOpen ||
                        (update.marketOpen && update.date >= previous!.date) {
                        self.quote = update
                    }
                    HistoryStore.shared.record(update, source: "eastmoney")
                }
                self.evaluate()
                // 实时接口失败时按顺序退到备用源：分时线末笔 → 新浪外盘。
                if update == nil { self.fallbackRefresh() }
                self.scheduleNextPoll()
            }
        }.resume()
    }

    /** 每秒重算信号，保证过期/休市状态不依赖下一次请求。 */
    func evaluate() {        guard let quote else {
            onChange?()
            return
        }
        let now = Date()
        let open = marketIsOpen(quote, at: now)
        let next = priceSignal(for: quote, open: open, now: now)
        let previous = signal
        signal = next
        if next != previous, next == .rising || next == .falling {
            onSignalTriggered?(next)
        }
        onChange?()
    }

    /** 浮卡展示用的净涨跌百分比。 */
    private func updateChange() {
        guard let quote, let first = recent.first, first.price > 0 else {
            changePercent = nil
            return
        }
        changePercent = (quote.price - first.price) / first.price * 100
    }

    // MARK: - 备用数据源

    private var fallbackRunning = false

    /** 实时接口失败时的备用链：东财分时线末笔 → 新浪外盘。 */
    private func fallbackRefresh() {
        guard !fallbackRunning else { return }
        fallbackRunning = true
        Task { @MainActor in
            defer { fallbackRunning = false }
            if let quote = try? await trendQuote() {
                apply(quote, source: "eastmoney-trend")
                return
            }
            if let quote = try? await sinaQuote() {
                apply(quote, source: "sina")
            }
        }
    }

    /** 接受一条备用行情：只在更新时替换，并清掉失败计数。 */
    private func apply(_ quote: Quote, source: String) {
        lastRequestFailed = false
        failureCount = 0
        stateCheckedAt = Date()
        if self.quote.map({ quote.date >= $0.date }) ?? true {
            self.quote = quote
        }
        HistoryStore.shared.record(quote, source: source)
        evaluate()
    }

    /** 备用源 1：东财分时线末笔价。 */
    private func trendQuote() async throws -> Quote {
        async let gold = latestTick("122.XAU")
        async let fx = latestTick("133.USDCNH")
        let (goldTick, fxTick) = try await (gold, fx)
        guard let quote = Quote(goldPrice: goldTick.price, fxRate: fxTick.price,
                                date: min(goldTick.date, fxTick.date)) else {
            throw URLError(.cannotParseResponse)
        }
        return quote
    }

    /** 备用源 2：新浪外盘（伦敦金 hf_XAU + 离岸人民币 fx_susdcnh）。 */
    private func sinaQuote() async throws -> Quote {
        let url = URL(string: "https://hq.sinajs.cn/list=hf_XAU,fx_susdcnh")!
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.setValue("https://finance.sina.com.cn", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let gbk = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        guard let text = String(data: data, encoding: gbk) ?? String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }

        var gold: (price: Double, time: String, day: String)?
        var rate: Double?
        for line in text.split(separator: "\n") {
            guard let quote = line.firstIndex(of: "\"") else { continue }
            let head = line[..<quote]
            let body = line[line.index(after: quote)...].split(separator: ",")
            if head.contains("hf_XAU"), body.count > 12,
               let price = Double(body[0]), price > 0 {
                gold = (price, String(body[6]), String(body[12]))
            } else if head.contains("fx_susdcnh"), body.count > 8,
                      let value = Double(body[8]), value > 0 {
                rate = value
            }
        }
        guard let gold, let rate,
              let date = Self.sinaDate(day: gold.day, time: gold.time),
              let quote = Quote(goldPrice: gold.price, fxRate: rate, date: date) else {
            throw URLError(.cannotParseResponse)
        }
        return quote
    }

    private static func sinaDate(day: String, time: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: day + " " + time)
    }

    private func latestTick(_ secid: String) async throws -> (price: Double, date: Date) {
        let url = URL(string: "https://push2his.eastmoney.com/api/qt/stock/trends2/get?secid=\(secid)&fields1=f1,f2&fields2=f51,f52,f53&ndays=1")!
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.setValue("https://quote.eastmoney.com/", forHTTPHeaderField: "Referer")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let market = try JSONDecoder().decode(TrendResponse.self, from: data).data
        guard let last = market.minutes().last else { throw URLError(.cannotParseResponse) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        guard let date = formatter.date(from: last.0) else { throw URLError(.cannotParseResponse) }
        return (last.1, date)
    }

    private func priceSignal(for quote: Quote, open: Bool, now: Date) -> PriceSignal {
        let limit: TimeInterval = quote.minuteGranularity ? 150 : 60
        guard open && quote.marketOpen else {
            recent.removeAll()
            changePercent = nil
            if !open { return .closed }
            return now.timeIntervalSince(max(quote.date, reopenedAt)) > limit ? .stale : .normal
        }
        recent.removeAll { now.timeIntervalSince($0.date) > 60 }
        if now.timeIntervalSince(quote.date) > limit {
            return now.timeIntervalSince(reopenedAt) > limit ? .stale : .normal
        }
        if recent.last?.date == quote.date {
            recent[recent.count - 1] = quote
        } else {
            recent.append(quote)
        }
        updateChange()
        guard let first = recent.first else { return .normal }
        // 以“分”为单位的整数基点比较，避免浮点误差（30 bp = 0.30%）。
        let baseline = Int64((first.price * 100).rounded())
        let cents = Int64((quote.price * 100).rounded())
        let change = (cents - baseline) * 10_000
        if change >= baseline * 30 { return .rising }
        if change <= -baseline * 30 { return .falling }
        return .normal
    }

    /** 休市判定：绕开周末与每日 17:15–18:00 纽约时间的结算空档。 */
    private func marketIsOpen(_ quote: Quote, at now: Date) -> Bool {
        if now.timeIntervalSince(stateCheckedAt) <= 60 { return quote.marketOpen }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let local = calendar.dateComponents([.weekday, .hour, .minute], from: now)
        let weekday = local.weekday ?? 1
        let minute = (local.hour ?? 0) * 60 + (local.minute ?? 0)
        if weekday == 7 || (weekday == 1 && minute < 1080) || (weekday == 6 && minute >= 1035)
            || (1035..<1080).contains(minute) { return false }
        if quote.marketOpen { return true }
        guard let nextOpen = calendar.nextDate(after: stateCheckedAt,
                                               matching: DateComponents(hour: 18, minute: 0),
                                               matchingPolicy: .nextTime) else { return false }
        return now >= nextOpen
    }
}
