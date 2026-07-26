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
    /// The weekly window is used as a fallback while a provider's 5-hour limit
    /// is unavailable.
    private func tokenText(for provider: any UsageProvider) -> String {
        if case let .loaded(usage) = store.state(for: provider) {
            return MenuBarLabel.tokenText(shortCode: provider.shortCode, usage: usage)
        }
        return MenuBarLabel.tokenText(shortCode: provider.shortCode, usage: nil)
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
