import Foundation

final class UsageStore: ObservableObject {
    @Published private(set) var snapshot = UsageSnapshot.empty
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefreshedAt: Date?

    private let scanner = CodexSessionScanner()
    private var isRefreshingRateLimits = false

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true

        Task {
            let rateLimits = await scanner.scanLatestRateLimits()
            await MainActor.run {
                if let rateLimits {
                    snapshot = snapshot.replacing(rateLimits: rateLimits)
                }
                lastRefreshedAt = Date()
            }

            let local = await scanner.scan()
            await MainActor.run {
                snapshot = UsageSnapshot(
                    fiveHourTokens: local.fiveHourTokens,
                    weekTokens: local.weekTokens,
                    recentSessionCount: local.recentSessionCount,
                    latestActivity: local.latestActivity,
                    rateLimits: local.latestRateLimits,
                    scannedFiles: local.scannedFiles
                )
                lastRefreshedAt = Date()
                isRefreshing = false
            }
        }
    }

    func refreshRateLimits() {
        guard !isRefreshing, !isRefreshingRateLimits else { return }
        isRefreshingRateLimits = true

        Task {
            let rateLimits = await scanner.scanLatestRateLimits()
            await MainActor.run {
                if let rateLimits {
                    snapshot = snapshot.replacing(rateLimits: rateLimits)
                }
                lastRefreshedAt = Date()
                isRefreshingRateLimits = false
            }
        }
    }
}

struct UsageSnapshot {
    let fiveHourTokens: Int
    let weekTokens: Int
    let recentSessionCount: Int
    let latestActivity: Date?
    let rateLimits: CodexRateLimits?
    let scannedFiles: Int

    static let empty = UsageSnapshot(
        fiveHourTokens: 0,
        weekTokens: 0,
        recentSessionCount: 0,
        latestActivity: nil,
        rateLimits: nil,
        scannedFiles: 0
    )

    var intensity: Double {
        min(1, Double(fiveHourTokens) / 1_000_000)
    }

    var statusText: String {
        scannedFiles == 0 ? "waiting for sessions" : "local activity"
    }

    var latestActivityText: String {
        guard let latestActivity else { return "No Codex token events found yet" }
        return "Updated \(latestActivity.formatted(date: .omitted, time: .shortened))"
    }

    func replacing(rateLimits: CodexRateLimits) -> UsageSnapshot {
        UsageSnapshot(
            fiveHourTokens: fiveHourTokens,
            weekTokens: weekTokens,
            recentSessionCount: recentSessionCount,
            latestActivity: latestActivity,
            rateLimits: rateLimits,
            scannedFiles: scannedFiles
        )
    }
}

extension Int {
    var abbreviatedTokens: String {
        if self >= 1_000_000 {
            return String(format: "%.1fM", Double(self) / 1_000_000)
        }
        if self >= 1_000 {
            return String(format: "%.0fK", Double(self) / 1_000)
        }
        return "\(self)"
    }
}
