#!/bin/bash
# Generate Assets/AppIcon.icns from the `gauge.with.needle` SF Symbol.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$ROOT/Assets"
WORK="$(mktemp -d)"
mkdir -p "$OUT_DIR"

# Render the symbol onto a rounded-square background at 1024px.
cat > "$WORK/render.swift" <<'SWIFT'
import AppKit
let size: CGFloat = 1024
let path = CommandLine.arguments[1]
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
// Background: light rounded square (native app-icon silhouette).
let inset: CGFloat = size * 0.06
let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
NSColor.white.setFill()
NSBezierPath(roundedRect: rect, xRadius: size * 0.22, yRadius: size * 0.22).fill()
// Symbol, centered. SF Symbol template images draw in their own (black) ink;
// recolor to dark gray via a sourceAtop fill on an offscreen image.
let config = NSImage.SymbolConfiguration(pointSize: size * 0.46, weight: .regular)
if let sym = NSImage(systemSymbolName: "gauge.with.needle", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {
    let s = sym.size
    let glyph = NSImage(size: s)
    glyph.lockFocus()
    sym.draw(at: .zero, from: NSRect(origin: .zero, size: s), operation: .sourceOver, fraction: 1)
    NSColor(white: 0.13, alpha: 1).set()
    NSRect(origin: .zero, size: s).fill(using: .sourceAtop)
    glyph.unlockFocus()
    glyph.draw(in: NSRect(x: (size - s.width) / 2, y: (size - s.height) / 2, width: s.width, height: s.height))
}
img.unlockFocus()
guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: URL(fileURLWithPath: path))
SWIFT

swift "$WORK/render.swift" "$WORK/icon_1024.png"

ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
    sips -z "$s" "$s"       "$WORK/icon_1024.png" --out "$ICONSET/icon_${s}x${s}.png"   >/dev/null
    d=$((s * 2))
    sips -z "$d" "$d"       "$WORK/icon_1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o "$OUT_DIR/AppIcon.icns"
rm -rf "$WORK"
echo "Wrote $OUT_DIR/AppIcon.icns"
