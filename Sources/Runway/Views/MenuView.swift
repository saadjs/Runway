import SwiftUI

/// The popover: a native stack of provider group boxes with a title bar and footer.
struct MenuView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.openWindow) private var openWindow

    private var visibleProviders: [any UsageProvider] {
        store.providers.filter { settings.isVisible($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Runway").font(.headline)
                Spacer()
                Button { openSettings() } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("Settings")
                Button {
                    Task { await store.refresh(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(store.isRefreshing)
                .help("Refresh now")
            }

            if visibleProviders.isEmpty {
                Text("All providers hidden — enable them in Settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(visibleProviders, id: \.id) { provider in
                    ProviderCardView(provider: provider,
                                     state: store.state(for: provider),
                                     showResetCountdown: settings.showResetCountdown)
                }
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

    private func openSettings() {
        openWindow(id: SettingsWindow.id)
        NSApp.activate(ignoringOtherApps: true)
    }

    private var footerText: String {
        guard let updated = store.lastUpdated else { return "Updating…" }
        let f = DateFormatter()
        f.timeStyle = .short
        return "Updated \(f.string(from: updated))"
    }
}
