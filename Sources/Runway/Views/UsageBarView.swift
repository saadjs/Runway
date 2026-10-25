import SwiftUI

struct UsageBarView: View {
    let title: String
    let window: UsageWindow?
    var showResetCountdown = true
    var resetStyle: ResetTimeStyle = .time

    var body: some View {
        ProgressView(value: window?.clampedFraction ?? 0) {
            Text(title)
        } currentValueLabel: {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                if let window {
                    Text("\(Int(window.usedPercent.rounded()))%")
                        .monospacedDigit()
                    Text(" used").foregroundStyle(.secondary)
                    if showResetCountdown, let reset = resetCountdown(window.resetsAt) {
                        Text(" · resets in \(reset)")
                            .foregroundStyle(.secondary)
                        if let clock = resetClockTime(window.resetsAt, style: resetStyle) {
                            Text(" (\(clock))")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("No data").foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
        .font(.callout)
        .lineLimit(1)
        .minimumScaleFactor(0.9)
        .tint(tint)
    }

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
