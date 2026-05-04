import SwiftUI

// MARK: - Adaptive Color Helper

extension Color {
    /// Creates a color from a hex string (e.g. "1F1F20" or "#1F1F20").
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        let scanner = Scanner(string: hex)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }

    /// Creates a color that adapts to light/dark appearance.
    init(light: Color, dark: Color) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? NSColor(dark) : NSColor(light)
        })
    }
}

// MARK: - Design Tokens

enum DT {

    // MARK: Typography

    enum Typography {
        static let largeTitle = Font.system(size: 28, weight: .semibold)
        static let title      = Font.system(size: 18, weight: .semibold)
        static let headline   = Font.system(size: 15, weight: .medium)
        static let body       = Font.system(size: 14, weight: .regular)
        static let caption    = Font.system(size: 12, weight: .regular)
        static let micro      = Font.system(size: 10, weight: .medium)

        static let mono       = Font.system(size: 13, design: .monospaced)
        static let monoSmall  = Font.system(size: 11, design: .monospaced)
    }

    // MARK: Spacing

    enum Spacing {
        static let xs:  CGFloat = 4
        static let sm:  CGFloat = 8
        static let md:  CGFloat = 12
        static let lg:  CGFloat = 16
        static let xl:  CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // MARK: Radius

    enum Radius {
        static let small:  CGFloat = 6
        static let medium: CGFloat = 10
        static let large:  CGFloat = 16
        static let xlarge: CGFloat = 20
    }

    // MARK: Opacity

    /// Semantic alpha values for recurring surface treatments. Keep these
    /// grouped so the visual system stays coherent — an ad-hoc `.opacity(0.11)`
    /// on a "selected row" drifts from the rest of the app.
    enum Opacity {
        /// Accent-tinted fill for selected rows, cells, chips, palette results.
        static let selection: Double = 0.12

        /// Half-strength text — toolbar separators, muted captions, placeholder-like.
        static let muted: Double = 0.5

        /// Faint decorative line — unfocused thumb borders, list-row separators.
        static let faint: Double = 0.3
    }

    // MARK: Shadows

    enum Shadow {
        struct Style {
            let color: Color
            let radius: CGFloat
            let y: CGFloat
        }

        static let card = Style(
            color: .black.opacity(0.06),
            radius: 8,
            y: 2
        )
        static let floating = Style(
            color: .black.opacity(0.15),
            radius: 24,
            y: 8
        )
    }

    // MARK: Grain

    enum Grain {
        static let opacity: Double = 0.03
    }
}

// MARK: - Shadow Modifier

extension View {
    func dtShadow(_ style: DT.Shadow.Style) -> some View {
        self.shadow(color: style.color, radius: style.radius, x: 0, y: style.y)
    }
}

// MARK: - AppKit Grain (covers toolbar too)

final class GrainNSView: NSView {
    init(opacity: Double) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.opacity = Float(opacity)
    }

    required init?(coder: NSCoder) { fatalError() }

    func updateOpacity(_ value: Double) {
        layer?.opacity = Float(value)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let width = Int(bounds.width)
        let height = Int(bounds.height)
        let count = Int(Double(width * height) * 0.05)

        for _ in 0..<count {
            let x = CGFloat.random(in: 0..<bounds.width)
            let y = CGFloat.random(in: 0..<bounds.height)
            let b = CGFloat.random(in: 0...1)
            ctx.setFillColor(NSColor(white: b, alpha: 1).cgColor)
            ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
        }
    }

    override var mouseDownCanMoveWindow: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
