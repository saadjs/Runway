import SwiftUI

/// The popover: a native stack of provider group boxes with a title bar and footer.
struct MenuView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Runway").font(.headline)
                Spacer()
                Button {
                    Task { await store.refresh(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(store.isRefreshing)
                .help("Refresh now")
            }

            ForEach(store.providers, id: \.id) { provider in
                ProviderCardView(provider: provider, state: store.state(for: provider))
            }

            Divider()

            HStack {
                Text(footerText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
        }
        .padding(14)
        .frame(width: 300)
        .onAppear { Task { await store.refresh() } }
    }

    private var footerText: String {
        guard let updated = store.lastUpdated else { return "Updating…" }
        let f = DateFormatter()
        f.timeStyle = .short
        return "Updated \(f.string(from: updated))"
    }
}
