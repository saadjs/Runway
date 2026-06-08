import SwiftUI

/// Identifier for the settings `Window` scene (opened from the popover gear button).
enum SettingsWindow { static let id = "settings" }

/// The Settings window: a native grouped `Form` of app preferences.
struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    private let providers = ProviderRegistry.all

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.setLaunchAtLogin($0) }
                ))
                Picker("Refresh every", selection: $settings.refreshIntervalMinutes) {
                    ForEach(AppSettings.refreshPresets, id: \.self) { minutes in
                        Text(intervalLabel(minutes)).tag(minutes)
                    }
                }
            }

            Section("Display") {
                Toggle("Show reset countdown", isOn: $settings.showResetCountdown)
            }

            Section("Providers") {
                ForEach(providers, id: \.id) { provider in
                    Toggle(provider.displayName, isOn: Binding(
                        get: { settings.isVisible(provider) },
                        set: { settings.setVisible(provider, $0) }
                    ))
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func intervalLabel(_ minutes: Int) -> String {
        minutes == 1 ? "1 minute" : "\(minutes) minutes"
    }
}
