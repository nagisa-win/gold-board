import AppKit

/** 可以接入「Turn 完成」提醒的本地工具。 */
enum HookTool: String, CaseIterable {
    case claude = "Claude Code"
    case codex = "Codex"
    case dsh = "DSH"

    var configPath: String {
        switch self {
        case .claude: return NSHomeDirectory() + "/.claude/settings.json"
        case .codex: return NSHomeDirectory() + "/.codex/config.toml"
        case .dsh: return NSHomeDirectory() + "/.dsh"
        }
    }
}

enum HookError: LocalizedError {
    case unsupported(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unsupported(let text), .failed(let text): return text
        }
    }
}

/** 把「Turn 完成」提醒写进各工具配置：写前备份，可一键回滚。 */
final class HookInstaller {
    static let shared = HookInstaller()

    private let marker = "--haptic turn-done"
    private let stamp: String = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHHmmss"
        return formatter.string(from: Date())
    }()

    /// 家目录可注入，便于在不碰真实配置的情况下自测。
    var home = NSHomeDirectory()
    var cliPath: String { Bundle.main.executablePath ?? CommandLine.arguments[0] }

    /// 各工具配置文件路径。
    func path(for tool: HookTool) -> String {
        switch tool {
        case .claude: return home + "/.claude/settings.json"
        case .codex: return home + "/.codex/config.toml"
        case .dsh: return home + "/.dsh"
        }
    }
    var commandLine: String { "\"\(cliPath)\" --haptic turn-done" }

    private init() {}

    /** 是否已接入。 */
    func isInstalled(_ tool: HookTool) -> Bool {
        switch tool {
        case .claude:
            return claudeCommands().contains { $0.contains(marker) }
        case .codex:
            guard let text = try? String(contentsOfFile: path(for: tool), encoding: .utf8) else { return false }
            // Codex 的 notify 是参数数组，分成了两行，按 --haptic 判定即可。
            return text.contains("--haptic")
        case .dsh:
            return false
        }
    }

    /** 一键接入，返回给用户看的说明文字。 */
    func install(_ tool: HookTool) throws -> String {
        switch tool {
        case .claude:
            return try installClaude()
        case .codex:
            return try installCodex()
        case .dsh:
            throw HookError.unsupported("DSH 没有配置文件式 hook，需通过插件接入；已把命令复制好，可贴到插件或手动触发。")
        }
    }

    /** 回滚到安装前的备份。 */
    func uninstall(_ tool: HookTool) throws -> String {
        switch tool {
        case .claude:
            return try uninstallClaude()
        case .codex:
            return try uninstallCodex()
        case .dsh:
            throw HookError.unsupported("DSH 侧未做自动配置，无需回滚。")
        }
    }

    // MARK: - Claude Code

    private func claudeRoot() -> [String: Any] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path(for: .claude))),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return root
    }

    private func claudeCommands() -> [String] {
        let hooks = claudeRoot()["hooks"] as? [String: Any] ?? [:]
        let stop = hooks["Stop"] as? [[String: Any]] ?? []
        return stop.flatMap { entry -> [String] in
            let inner = entry["hooks"] as? [[String: Any]] ?? []
            return inner.compactMap { $0["command"] as? String }
        }
    }

    private func installClaude() throws -> String {
        let path = path(for: .claude)
        var root = claudeRoot()
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        var stop = hooks["Stop"] as? [[String: Any]] ?? []
        if !claudeCommands().contains(where: { $0.contains(marker) }) {
            stop.append(["hooks": [["type": "command", "command": commandLine]]])
        }
        hooks["Stop"] = stop
        root["hooks"] = hooks

        guard let data = try? JSONSerialization.data(withJSONObject: root,
                                                     options: [.prettyPrinted, .sortedKeys]) else {
            throw HookError.failed("无法序列化 settings.json")
        }
        try backup(path)
        try data.write(to: URL(fileURLWithPath: path))
        return "已写入 \(path) 的 hooks.Stop"
    }

    private func uninstallClaude() throws -> String {
        let path = path(for: .claude)
        var root = claudeRoot()
        guard var hooks = root["hooks"] as? [String: Any],
              let stop = hooks["Stop"] as? [[String: Any]] else {
            return "没有需要移除的 hook"
        }
        let kept = stop.filter { entry in
            let inner = entry["hooks"] as? [[String: Any]] ?? []
            return !inner.contains { ($0["command"] as? String)?.contains(marker) == true }
        }
        if kept.isEmpty {
            hooks.removeValue(forKey: "Stop")
        } else {
            hooks["Stop"] = kept
        }
        root["hooks"] = hooks
        guard let data = try? JSONSerialization.data(withJSONObject: root,
                                                     options: [.prettyPrinted, .sortedKeys]) else {
            throw HookError.failed("无法序列化 settings.json")
        }
        try backup(path)
        try data.write(to: URL(fileURLWithPath: path))
        return "已从 \(path) 移除 hook"
    }

    // MARK: - Codex

    private func installCodex() throws -> String {
        let path = path(for: .codex)
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            throw HookError.failed("找不到 \(path)")
        }
        var lines = text.components(separatedBy: "\n")
        let block = [
            "notify = [",
            "    \"\(cliPath)\",",
            "    \"--haptic\",",
            "    \"turn-done\",",
            "]",
        ]
        if let start = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("notify") }) {
            var end = start
            while end < lines.count && !lines[end].contains("]") { end += 1 }
            lines.replaceSubrange(start...min(end, lines.count - 1), with: block)
        } else {
            lines.insert(contentsOf: block + [""], at: 0)
        }
        try backup(path)
        try lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
        return "已接管 \(path) 的 notify（原配置已备份）"
    }

    private func uninstallCodex() throws -> String {
        let path = path(for: .codex)
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
        let name = URL(fileURLWithPath: path).lastPathComponent
        let backups = (try? FileManager.default.contentsOfDirectory(atPath: directory.path))?
            .filter { $0.hasPrefix(name + ".bak-") }
            .sorted() ?? []
        guard let latest = backups.last else {
            throw HookError.failed("没有找到 \(name) 的备份，无法自动回滚")
        }
        try backup(path)
        let source = directory.appendingPathComponent(latest)
        let text = try String(contentsOf: source, encoding: .utf8)
        try text.write(toFile: path, atomically: true, encoding: .utf8)
        return "已用备份 \(latest) 还原 notify"
    }

    // MARK: - 通用

    /** 写前备份，保留最近三份。 */
    private func backup(_ path: String) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: path) else { return }
        let destination = "\(path).bak-\(stamp)"
        if !fileManager.fileExists(atPath: destination) {
            try fileManager.copyItem(atPath: path, toPath: destination)
        }
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent().path
        let name = URL(fileURLWithPath: path).lastPathComponent
        let backups = (try? fileManager.contentsOfDirectory(atPath: directory))?
            .filter { $0.hasPrefix(name + ".bak-") }
            .sorted() ?? []
        for stale in backups.dropLast(3) {
            try? fileManager.removeItem(atPath: directory + "/" + stale)
        }
    }
}
