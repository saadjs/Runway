import SwiftUI

/// Identifier for the settings `Window` scene (opened from the popover gear button).
enum SettingsWindow { static let id = "settings" }

/// The Settings window: a native grouped `Form` of app preferences.
struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    private let providers = ProviderRegistry.all

    /// Sentinel tag for the "Custom…" picker row (no real interval equals it).
    private static let customTag = -1
    /// Whether the custom stepper is revealed. Seeded from the persisted value
    /// (a non-preset means we're already in custom mode) and held while the user
    /// dials the stepper so it doesn't snap shut when they cross a preset value.
    @State private var customMode = false

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.setLaunchAtLogin($0) }
                ))
                Picker("Refresh every", selection: Binding(
                    get: { customMode ? Self.customTag : settings.refreshIntervalMinutes },
                    set: { selection in
                        if selection == Self.customTag {
                            customMode = true
                        } else {
                            customMode = false
                            settings.refreshIntervalMinutes = selection
                        }
                    }
                )) {
                    ForEach(AppSettings.refreshPresets, id: \.self) { minutes in
                        Text(intervalLabel(minutes)).tag(minutes)
                    }
                    Divider()
                    Text("Custom…").tag(Self.customTag)
                }
                if customMode {
                    Stepper(value: $settings.refreshIntervalMinutes, in: AppSettings.refreshRange) {
                        Text("Every \(intervalLabel(settings.refreshIntervalMinutes))")
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
        .onAppear {
            customMode = !AppSettings.refreshPresets.contains(settings.refreshIntervalMinutes)
        }
    }

    private func intervalLabel(_ minutes: Int) -> String {
        minutes == 1 ? "1 minute" : "\(minutes) minutes"
    }
}
