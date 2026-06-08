import AppKit

/// Renders the menu-bar label as a single template `NSImage`.
///
/// `MenuBarExtra` only reliably renders an `Image` plus one `Text` — additional
/// sibling views, `ForEach`, and inline-in-`Text` images are dropped. To mix the
/// gauge glyph, per-provider text, and SF Symbol locks we composite them into one
/// template image, which the menu bar tints for light/dark automatically.
enum MenuBarLabel {
    /// One provider's compact token, e.g. ("CL61", locked: false).
    struct Token {
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

    static func image(tokens: [Token]) -> NSImage {
        let font = NSFont.menuBarFont(ofSize: 0)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: font.pointSize, weight: .regular)

        func symbol(_ name: String) -> NSImage? {
            let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(symbolConfig)
            image?.isTemplate = true
            return image
        }

        // Build (piece, leading gap) pairs.
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

        let image = NSImage(size: NSSize(width: ceil(width), height: height))
        image.lockFocus()
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
        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}
