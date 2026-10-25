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

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        UsageStore.shared.start()
    }
}
