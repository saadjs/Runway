import Foundation
import ServiceManagement
import SwiftUI

/// User-facing configuration, persisted in `UserDefaults`. The single source of
/// truth read by both the views and `UsageStore`.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    /// Quick-pick cadences in Settings; users can also enter a custom value via
    /// the "Custom…" picker option. 5 min is the default. Note: very short
    /// intervals can trip Anthropic's rate limit for Claude (see CLAUDE.md).
    static let refreshPresets = [1, 2, 5, 10, 15, 30]
    /// Bounds for a custom interval. 1 min floor (can't be zero/negative); 4 h cap.
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
    /// Reflects the real `SMAppService` state; only mutated via `setLaunchAtLogin`.
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

    /// Registers/unregisters the app as a login item, then re-reads the real
    /// state so the toggle reflects reality (and stays off if `register()` throws
    /// — expected when run unbundled or from outside `/Applications`).
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

    /// True when the app is registered as a login item. `.requiresApproval` counts as
    /// on: the registration took effect and only awaits the user's approval in System
    /// Settings → General → Login Items, so the toggle should reflect the intent.
    private static var isLoginEnabled: Bool {
        switch SMAppService.mainApp.status {
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
