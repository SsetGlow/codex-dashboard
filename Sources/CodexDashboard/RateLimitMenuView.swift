import SwiftUI

struct RateLimitMenuView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if let limits = store.snapshot.rateLimits {
                limitRow(title: "5h remaining", limit: limits.primary, tint: .green)
                limitRow(title: "Week remaining", limit: limits.secondary, tint: .blue)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No Codex rate limit data found yet")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Run Codex once and open /status to refresh local logs.")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
            }

            footer
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 300, height: 146)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                .font(.system(size: 12, weight: .semibold))
            Text("Codex usage")
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            Text(store.snapshot.rateLimits?.planType?.capitalized ?? "Local")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack(spacing: 4) {
            if store.isRefreshing {
                ProgressView()
                    .controlSize(.mini)
            }
            Text(statusText)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            Text(appVersionText)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.tertiary)
        }
    }

    private var statusText: String {
        if store.isRefreshing {
            return "Refreshing..."
        }
        if let capturedAt = store.snapshot.rateLimits?.capturedAt {
            return "Usage \(capturedAt.formatted(date: .omitted, time: .standard))"
        }
        guard let lastRefreshedAt = store.lastRefreshedAt else {
            return "Not refreshed yet"
        }
        return "Refreshed \(lastRefreshedAt.formatted(date: .omitted, time: .standard))"
    }

    private var appVersionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        return "v\(version)"
    }

    private func limitRow(title: String, limit: CodexRateLimit, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Text("\(Int(limit.remainingPercent.rounded()))%")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }

            ProgressView(value: limit.remainingPercent, total: 100)
                .tint(tint)
                .controlSize(.small)

            if let resetsAt = limit.resetsAt {
                Text("Resets \(resetsAt.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
