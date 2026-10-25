import Foundation
import ServiceManagement
import SwiftUI

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    static let refreshPresets = [1, 2, 5, 10, 15, 30]
    static let refreshRange = 1...240

    private let defaults = UserDefaults.standard
    private enum Key {
        static let refreshIntervalMinutes = "refreshIntervalMinutes"
        static let showResetCountdown = "showResetCountdown"
        static let hiddenProviderIDs = "hiddenProviderIDs"
    }

    @Published var refreshIntervalMinutes: Int {
        didSet { defaults.set(refreshIntervalMinutes, forKey: Key.refreshIntervalMinutes) }
    }
    @Published var showResetCountdown: Bool {
        didSet { defaults.set(showResetCountdown, forKey: Key.showResetCountdown) }
    }
    @Published var hiddenProviderIDs: Set<String> {
        didSet { defaults.set(Array(hiddenProviderIDs), forKey: Key.hiddenProviderIDs) }
    }
    @Published private(set) var launchAtLogin: Bool

    private init() {
        let stored = defaults.object(forKey: Key.refreshIntervalMinutes) as? Int
        refreshIntervalMinutes = stored.map {
            min(max($0, Self.refreshRange.lowerBound), Self.refreshRange.upperBound)
        } ?? 5
        showResetCountdown = defaults.object(forKey: Key.showResetCountdown) as? Bool ?? true
        hiddenProviderIDs = Set(defaults.array(forKey: Key.hiddenProviderIDs) as? [String] ?? [])
        launchAtLogin = Self.isLoginEnabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Runway: launch-at-login \(enabled ? "register" : "unregister") failed: \(error.localizedDescription)")
        }
        launchAtLogin = Self.isLoginEnabled
    }

    private static var isLoginEnabled: Bool {
        switch SMAppService.mainApp.status {
        // `.requiresApproval` took effect and only awaits approval in Login Items.
        case .enabled, .requiresApproval: return true
        default: return false
        }
    }

    func isVisible(_ provider: any UsageProvider) -> Bool {
        !hiddenProviderIDs.contains(provider.id)
    }

    func setVisible(_ provider: any UsageProvider, _ visible: Bool) {
        if visible {
            hiddenProviderIDs.remove(provider.id)
        } else {
            hiddenProviderIDs.insert(provider.id)
        }
    }
}
