import AppKit
import SwiftUI

enum Logo {
    /// Not `Bundle.module`: its accessor only checks the app root and `fatalError`s in a packaged app.
    private static let resources: Bundle? = {
        let name = "Runway_Runway.bundle"
        let candidates = [
            Bundle.main.resourceURL,
            Bundle.main.bundleURL,
        ].compactMap { $0?.appendingPathComponent(name) }
        return candidates.lazy.compactMap(Bundle.init(url:)).first
    }()

    @MainActor private static var loaded: [String: Image] = [:]

    @MainActor static func image(_ name: String) -> Image {
        if let image = loaded[name] { return image }
        let image: Image
        if let url = resources?.url(forResource: name, withExtension: "pdf"),
           let nsImage = NSImage(contentsOf: url) {
            nsImage.isTemplate = true
            image = Image(nsImage: nsImage)
        } else {
            image = Image(systemName: "app.dashed")
        }
        loaded[name] = image
        return image
    }
}

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

enum ResetTimeStyle {
    case time
    case weekday
    case date
}

func resetClockTime(_ date: Date?, style: ResetTimeStyle) -> String? {
    guard let date else { return nil }
    let time = date.formatted(.dateTime.hour().minute())
    switch style {
    case .time: return time
    case .weekday: return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    // A combined date+time format ("Sep 15 at 3:45 PM") overruns the popover row.
    case .date: return "\(date.formatted(.dateTime.month(.abbreviated).day())), \(time)"
    }
}
