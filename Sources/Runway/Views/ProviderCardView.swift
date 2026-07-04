import SwiftUI

/// One provider as a native `GroupBox`: official logo + name + plan in the
/// header, the 5-hour and weekly bars (or a loading / error state) in the body.
struct ProviderCardView: View {
    let provider: any UsageProvider
    let state: ProviderState
    var showResetCountdown = true

    var body: some View {
        GroupBox {
            switch state {
            case .loading:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Loading…").foregroundStyle(.secondary)
                    Spacer()
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)

            case let .loaded(usage):
                VStack(spacing: 10) {
                    UsageBarView(title: "5-hour", window: usage.fiveHour, showResetCountdown: showResetCountdown)
                    UsageBarView(title: "Weekly", window: usage.weekly, showResetCountdown: showResetCountdown, includeResetWeekday: true)
                }
                .padding(.top, 2)

            case let .failed(message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        } label: {
            HStack(spacing: 6) {
                Logo.image(provider.logoResource)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 15, height: 15)
                    .foregroundStyle(.primary)
                Text(provider.displayName)
                Spacer()
                if case let .loaded(usage) = state, let plan = usage.planLabel {
                    Text(plan).foregroundStyle(.secondary)
                }
            }
            .font(.headline)
        }
    }
}
