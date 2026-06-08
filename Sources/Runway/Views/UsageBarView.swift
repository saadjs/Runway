import SwiftUI

/// One usage window as a native linear `ProgressView`: title above the bar,
/// percentage and reset countdown below. Uses the system accent tint only.
struct UsageBarView: View {
    let title: String
    let window: UsageWindow?
    var showResetCountdown = true

    var body: some View {
        ProgressView(value: window?.clampedFraction ?? 0) {
            Text(title)
        } currentValueLabel: {
            HStack(spacing: 0) {
                Text(percentText)
                    .monospacedDigit()
                if window != nil {
                    Text(" used").foregroundStyle(.secondary)
                }
                if showResetCountdown, let reset = resetCountdown(window?.resetsAt) {
                    Text(" · resets in \(reset)")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.callout)
        .tint(tint)
    }

    private var percentText: String {
        guard let window else { return "—" }
        return "\(Int(window.usedPercent.rounded()))%"
    }

    /// Semantic tint so usage is scannable at a glance: green with headroom,
    /// orange as it fills, red when nearly exhausted. Falls back to the system
    /// accent when there's no data.
    private var tint: Color {
        guard let window else { return .accentColor }
        switch window.usedPercent {
        case ..<50: return .green
        case ..<75: return .yellow
        case ..<90: return .orange
        default: return .red
        }
    }
}
