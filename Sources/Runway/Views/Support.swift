import AppKit
import SwiftUI

enum Logo {
    /// Loads a bundled vector logo as a template image so SwiftUI's
    /// `foregroundStyle` tints it to match the native control color.
    static func image(_ name: String) -> Image {
        if let url = Bundle.module.url(forResource: name, withExtension: "pdf"),
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
