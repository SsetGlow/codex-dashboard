import Foundation

struct LocalUsageSummary {
    var fiveHourTokens = 0
    var weekTokens = 0
    var recentSessionCount = 0
    var latestActivity: Date?
    var latestRateLimits: CodexRateLimits?
    var scannedFiles = 0
}

struct CodexRateLimits {
    let primary: CodexRateLimit
    let secondary: CodexRateLimit
    let planType: String?
    let reachedType: String?
    let capturedAt: Date
    let sourceFile: URL?

    func withSourceFile(_ sourceFile: URL) -> CodexRateLimits {
        CodexRateLimits(
            primary: primary,
            secondary: secondary,
            planType: planType,
            reachedType: reachedType,
            capturedAt: capturedAt,
            sourceFile: sourceFile
        )
    }
}

struct CodexRateLimit {
    let usedPercent: Double
    let windowMinutes: Int
    let resetsAt: Date?

    var remainingPercent: Double {
        max(0, min(100, 100 - usedPercent))
    }
}

final class CodexSessionScanner {
    private let codexDirectory: URL
    private let decoder = ISO8601DateFormatter()

    init(codexDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")) {
        self.codexDirectory = codexDirectory
        decoder.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func scan() async -> LocalUsageSummary {
        await Task.detached(priority: .utility) { [codexDirectory, decoder] in
            let now = Date()
            let fiveHoursAgo = now.addingTimeInterval(-5 * 60 * 60)
            let weekAgo = now.addingTimeInterval(-7 * 24 * 60 * 60)
            var summary = LocalUsageSummary()
            var recentSessions = Set<URL>()
            let files = Self.jsonlFiles(under: codexDirectory, modifiedAfter: weekAgo)

            summary.latestRateLimits = Self.latestRateLimits(in: files, decoder: decoder)

            for file in files {
                summary.scannedFiles += 1
                var fileHasRecentUsage = false

                guard let handle = try? FileHandle(forReadingFrom: file) else { continue }
                defer { try? handle.close() }

                let data = handle.readDataToEndOfFile()
                guard let text = String(data: data, encoding: .utf8) else { continue }

                for line in text.split(separator: "\n") {
                    guard let event = Self.parseLogLine(String(line), decoder: decoder) else {
                        continue
                    }

                    if let lastTokens = event.lastTokens, event.timestamp >= fiveHoursAgo {
                        summary.fiveHourTokens += lastTokens
                    }
                    if let lastTokens = event.lastTokens, event.timestamp >= weekAgo {
                        summary.weekTokens += lastTokens
                        fileHasRecentUsage = true
                    }
                    if event.lastTokens != nil && (summary.latestActivity == nil || event.timestamp > summary.latestActivity!) {
                        summary.latestActivity = event.timestamp
                    }
                }

                if fileHasRecentUsage {
                    recentSessions.insert(file)
                }
            }

            summary.recentSessionCount = recentSessions.count
            return summary
        }.value
    }

    func scanLatestRateLimits() async -> CodexRateLimits? {
        await Task.detached(priority: .userInitiated) { [codexDirectory, decoder] in
            let weekAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
            let files = Self.jsonlFiles(under: codexDirectory, modifiedAfter: weekAgo)
            return Self.latestRateLimits(in: files, decoder: decoder)
        }.value
    }

    private static func jsonlFiles(under root: URL, modifiedAfter cutoff: Date) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return enumerator.compactMap { item in
            guard let url = item as? URL, url.pathExtension == "jsonl" else { return nil }
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
                  values.isRegularFile == true,
                  (values.contentModificationDate ?? .distantPast) >= cutoff else {
                return nil
            }
            return url
        }
    }

    private static func latestRateLimits(in files: [URL], decoder: ISO8601DateFormatter) -> CodexRateLimits? {
        let sortedFiles = files.sorted { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhsDate > rhsDate
        }

        var latest: CodexRateLimits?

        for file in sortedFiles {
            guard let handle = try? FileHandle(forReadingFrom: file) else { continue }
            defer { try? handle.close() }

            let data = handle.readDataToEndOfFile()
            guard let text = String(data: data, encoding: .utf8) else { continue }

            for line in text.split(separator: "\n").reversed() where line.contains("rate_limits") {
                guard let event = parseLogLine(String(line), decoder: decoder),
                      let rateLimits = event.rateLimits else {
                    continue
                }

                let sourcedRateLimits = rateLimits.withSourceFile(file)
                if latest == nil || sourcedRateLimits.capturedAt > latest!.capturedAt {
                    latest = sourcedRateLimits
                }
                break
            }
        }

        return latest
    }

    private static func parseLogLine(_ line: String, decoder: ISO8601DateFormatter) -> (timestamp: Date, lastTokens: Int?, rateLimits: CodexRateLimits?)? {
        guard line.contains("token_count") || line.contains("rate_limits"),
              let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let timestampText = object["timestamp"] as? String,
              let timestamp = decoder.date(from: timestampText) ?? ISO8601DateFormatter().date(from: timestampText) else {
            return nil
        }

        let lastTokens = parseLastTokens(from: object)
        let rateLimits = parseRateLimits(from: object, capturedAt: timestamp)
        guard lastTokens != nil || rateLimits != nil else { return nil }
        return (timestamp, lastTokens, rateLimits)
    }

    private static func parseLastTokens(from object: [String: Any]) -> Int? {
        guard let payload = object["payload"] as? [String: Any],
              payload["type"] as? String == "token_count",
              let info = payload["info"] as? [String: Any] else {
            return nil
        }

        if let last = info["last_token_usage"] as? [String: Any],
           let total = numericInt(last["total_tokens"]) {
            return total
        }

        if let total = info["total_token_usage"] as? [String: Any],
           let tokens = numericInt(total["total_tokens"]) {
            return tokens
        }

        return nil
    }

    private static func parseRateLimits(from object: [String: Any], capturedAt: Date) -> CodexRateLimits? {
        let payload = object["payload"] as? [String: Any]
        guard let rateLimits = object["rate_limits"] as? [String: Any] ?? payload?["rate_limits"] as? [String: Any],
              let primaryObject = rateLimits["primary"] as? [String: Any],
              let secondaryObject = rateLimits["secondary"] as? [String: Any],
              let primary = parseRateLimit(from: primaryObject),
              let secondary = parseRateLimit(from: secondaryObject) else {
            return nil
        }

        return CodexRateLimits(
            primary: primary,
            secondary: secondary,
            planType: rateLimits["plan_type"] as? String,
            reachedType: rateLimits["rate_limit_reached_type"] as? String,
            capturedAt: capturedAt,
            sourceFile: nil
        )
    }

    private static func parseRateLimit(from object: [String: Any]) -> CodexRateLimit? {
        guard let usedPercent = numericDouble(object["used_percent"]),
              let windowMinutes = numericInt(object["window_minutes"]) else {
            return nil
        }

        let resetsAt = numericDouble(object["resets_at"]).map { Date(timeIntervalSince1970: $0) }
        return CodexRateLimit(usedPercent: usedPercent, windowMinutes: windowMinutes, resetsAt: resetsAt)
    }

    private static func numericDouble(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }

    private static func numericInt(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? Double { return Int(value) }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }
}
