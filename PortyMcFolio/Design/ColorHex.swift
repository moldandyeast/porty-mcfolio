import SwiftUI
import AppKit

extension Color {
    /// Resolve to a hex string under the specified appearance. NSColor
    /// dynamic providers (used by `Color(light:dark:)` and `Color(nsColor:)`
    /// bindings to semantic AppKit colors) evaluate against the current
    /// drawing appearance — use `performAsCurrentDrawingAppearance` to
    /// pin it during the resolution.
    func hex(for appearance: NSAppearance) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        appearance.performAsCurrentDrawingAppearance {
            NSColor(self)
                .usingColorSpace(.sRGB)?
                .getRed(&r, green: &g, blue: &b, alpha: &a)
        }
        return String(
            format: "#%02X%02X%02X",
            Int(round(r * 255)),
            Int(round(g * 255)),
            Int(round(b * 255))
        )
    }
}
