import SwiftUI

@main
struct RunwayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = UsageStore.shared
    @StateObject private var settings = AppSettings.shared

    var body: some Scene {
        MenuBarExtra {
            MenuView(store: store)
        } label: {
            // The label is drawn as one template NSImage; see MenuBarLabel.
            Image(nsImage: MenuBarLabel.image(tokens: menuBarTokens))
        }
        .menuBarExtraStyle(.window)

        Window("Runway Settings", id: SettingsWindow.id) {
            SettingsView()
        }
        .windowResizability(.contentSize)
    }

    private var menuBarTokens: [MenuBarLabel.Token] {
        store.providers.filter { settings.isVisible($0) }.map { provider in
            MenuBarLabel.Token(text: tokenText(for: provider), locked: isBlocked(provider))
        }
    }

    /// "CL61" / "CX" (no number when any usage window is capped — the lock follows) / "CL–".
    private func tokenText(for provider: any UsageProvider) -> String {
        if case let .loaded(usage) = store.state(for: provider) {
            if usage.isBlocked { return provider.shortCode }
            if let five = usage.fiveHour {
                return "\(provider.shortCode)\(Int(five.usedPercent.rounded()))"
            }
        }
        return "\(provider.shortCode)–"
    }

    private func isBlocked(_ provider: any UsageProvider) -> Bool {
        if case let .loaded(usage) = store.state(for: provider) { return usage.isBlocked }
        return false
    }
}

/// Hides the Dock icon so Runway lives only in the menu bar.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        UsageStore.shared.start()
    }
}
