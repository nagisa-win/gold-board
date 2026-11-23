import AppKit

/** 本地行情缓存：每分钟一行、按天分文件、保留 90 天，单位统一为元/克。 */
final class HistoryStore {
    static let shared = HistoryStore()

    private let directory: URL
    private let stampFormatter: DateFormatter
    private let dayFormatter: DateFormatter
    /// 每个文件已写入的分钟，避免同一分钟重复落盘。
    private var lastMinuteByDay: [String: String] = [:]

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GoldFloat", isDirectory: true)
            .appendingPathComponent("history", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        directory = base

        stampFormatter = DateFormatter()
        stampFormatter.locale = Locale(identifier: "en_US_POSIX")
        stampFormatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        stampFormatter.dateFormat = "yyyy-MM-dd HH:mm"

        dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        dayFormatter.dateFormat = "yyyy-MM-dd"
    }

    /// 缓存目录，供界面与文档展示。
    var folderPath: String { directory.path }

    /// 记录一条行情；分钟级去重后追加到当天 CSV。
    func record(_ quote: Quote, source: String) {
        let stamp = stampFormatter.string(from: quote.date)
        let day = String(stamp.prefix(10))
        guard lastMinuteByDay[day] != stamp else { return }
        lastMinuteByDay[day] = stamp

        let goldUSD = quote.fxRate > 0 ? quote.price * gramsPerTroyOunce / quote.fxRate : 0
        let line = String(format: "%@,%.4f,%.2f,%.6f,%@\n",
                          stamp, quote.price, goldUSD, quote.fxRate, source)
        let url = directory.appendingPathComponent("\(day).csv")

        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            let header = "time,price_cny_g,gold_usd_oz,usdcnh,source\n"
            try? (header + line).write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// 删除超过保留期的按天文件。
    func prune(keeping days: Int = 90) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let cutoffKey = dayFormatter.string(from: cutoff)
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        for file in files where file.hasSuffix(".csv") {
            let key = String(file.dropLast(4))
            if key < cutoffKey {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
            }
        }
    }

    /// 已缓存的天数与行数，界面显示用。
    func summary() -> (days: Int, rows: Int) {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return (0, 0) }
        let csv = files.filter { $0.hasSuffix(".csv") }
        var rows = 0
        for file in csv {
            if let text = try? String(contentsOfFile: directory.appendingPathComponent(file).path, encoding: .utf8) {
                rows += max(0, text.split(separator: "\n").count - 1)
            }
        }
        return (csv.count, rows)
    }

    /// 把全部缓存合并导出成一个 CSV，返回导出的数据行数。
    @discardableResult
    func export(to path: String) throws -> Int {
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            .filter { $0.hasSuffix(".csv") }
            .sorted()
        var rows: [String] = ["time,price_cny_g,gold_usd_oz,usdcnh,source"]
        for file in files {
            let url = directory.appendingPathComponent(file)
            guard let text = try? String(contentsOfFile: url.path, encoding: .utf8) else { continue }
            rows.append(contentsOf: text.split(separator: "\n").dropFirst().map(String.init).filter { !$0.isEmpty })
        }
        try (rows.joined(separator: "\n") + "\n").write(toFile: path, atomically: true, encoding: .utf8)
        return rows.count - 1
    }
}
