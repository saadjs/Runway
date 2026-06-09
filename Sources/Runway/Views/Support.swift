import AppKit
import SwiftUI

enum Logo {
    /// The SwiftPM resource bundle, located *without* the generated `Bundle.module`
    /// accessor. That accessor `fatalError`s when it can't find the bundle, and in a
    /// packaged `.app` it looks only at the bundle root — never `Contents/Resources`,
    /// where the bundle actually ships (it can't live at the root: codesign rejects
    /// unsealed content there). So routing logo lookups through `Bundle.module` crashes
    /// the app the moment the popover opens. We resolve it by hand and tolerate a miss.
    private static let resources: Bundle? = {
        let name = "Runway_Runway.bundle"
        let candidates = [
            Bundle.main.resourceURL,        // packaged .app -> Contents/Resources
            Bundle.main.bundleURL,          // `swift run` -> dir beside the executable
        ].compactMap { $0?.appendingPathComponent(name) }
        return candidates.lazy.compactMap(Bundle.init(url:)).first
    }()

    /// Loads a bundled vector logo as a template image so SwiftUI's
    /// `foregroundStyle` tints it to match the native control color.
    /// Falls back to an SF Symbol if the resource is missing — never traps.
    static func image(_ name: String) -> Image {
        if let url = resources?.url(forResource: name, withExtension: "pdf"),
           let nsImage = NSImage(contentsOf: url) {
            nsImage.isTemplate = true
            return Image(nsImage: nsImage)
        }
        return Image(systemName: "app.dashed")
    }
}

/// Short "resets in" string, e.g. "2h 14m" or "3d 4h".
func resetCountdown(_ date: Date?) -> String? {
    guard let date else { return nil }
    let seconds = Int(date.timeIntervalSinceNow)
    guard seconds > 0 else { return "now" }
    let d = seconds / 86_400
    let h = (seconds % 86_400) / 3_600
    let m = (seconds % 3_600) / 60
    if d > 0 { return "\(d)d \(h)h" }
    if h > 0 { return "\(h)h \(m)m" }
    return "\(m)m"
}
