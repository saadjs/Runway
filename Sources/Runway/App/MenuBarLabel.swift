import AppKit

/// One template image: `MenuBarExtra` labels silently drop anything beyond an `Image` + one `Text`.
enum MenuBarLabel {
    struct Token: Equatable {
        let text: String
        let locked: Bool
    }

    private enum Piece {
        case image(NSImage)
        case text(NSAttributedString)

        var size: NSSize {
            switch self {
            case let .image(image): return image.size
            case let .text(string): return string.size()
            }
        }
    }

    static func tokenText(shortCode: String, usage: ProviderUsage?) -> String {
        guard let usage else { return "\(shortCode)–" }
        if usage.isBlocked { return shortCode }
        guard let window = usage.fiveHour ?? usage.weekly ?? usage.monthly else {
            return "\(shortCode)–"
        }
        return "\(shortCode)\(Int(window.usedPercent.rounded()))"
    }

    @MainActor private static var lastRendered: (tokens: [Token], fontSize: CGFloat, image: NSImage)?

    @MainActor static func image(tokens: [Token]) -> NSImage {
        let font = NSFont.menuBarFont(ofSize: 0)
        if let lastRendered, lastRendered.tokens == tokens, lastRendered.fontSize == font.pointSize {
            return lastRendered.image
        }
        let image = render(tokens: tokens, font: font)
        lastRendered = (tokens, font.pointSize, image)
        return image
    }

    private static func render(tokens: [Token], font: NSFont) -> NSImage {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: font.pointSize, weight: .regular)

        func symbol(_ name: String) -> NSImage? {
            let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(symbolConfig)
            image?.isTemplate = true
            return image
        }

        var laidOut: [(piece: Piece, gap: CGFloat)] = []
        if let gauge = symbol("gauge.with.needle") {
            laidOut.append((.image(gauge), 0))
        }
        for (index, token) in tokens.enumerated() {
            laidOut.append((.text(NSAttributedString(string: token.text, attributes: attributes)),
                            index == 0 ? 5 : 8))
            if token.locked, let lock = symbol("lock") {
                laidOut.append((.image(lock), 2))
            }
        }

        let height: CGFloat = 18
        let width = laidOut.reduce(0) { $0 + $1.gap + $1.piece.size.width }
        guard width > 0 else { return NSImage(size: NSSize(width: 1, height: height)) }

        let image = NSImage(size: NSSize(width: ceil(width), height: height), flipped: false) { _ in
            var x: CGFloat = 0
            for (piece, gap) in laidOut {
                x += gap
                let size = piece.size
                let y = (height - size.height) / 2
                switch piece {
                case let .image(symbolImage):
                    symbolImage.draw(in: NSRect(x: x, y: y, width: size.width, height: size.height))
                case let .text(string):
                    string.draw(at: NSPoint(x: x, y: y))
                }
                x += size.width
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
