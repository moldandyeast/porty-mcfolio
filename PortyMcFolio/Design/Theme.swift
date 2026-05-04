import SwiftUI
import AppKit

struct ThemeColors: Hashable {
    let background: Color
    let backgroundAlt: Color
    let surface: Color
    let surfaceHover: Color
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    let border: Color
    let accent: Color
    /// Foreground color to use ON TOP OF accent backgrounds. White for the
    /// chromatic themes (porty/osx) where the accent is mid-luminance mauve;
    /// the inverse-of-accent for BW where the accent is monochrome and flips
    /// near-black/near-white per appearance.
    let accentForeground: Color
    let statusDraft: Color
    let statusActive: Color
    let statusComplete: Color
    let statusArchived: Color
    let error: Color
}

struct Theme: Hashable {
    enum ID: String, CaseIterable, Codable {
        case porty
        case osx
        case bw
    }

    let id: ID
    let name: String
    let colors: ThemeColors
    let grainOpacity: Double

    static let all: [Theme] = [.porty, .osx, .bw]

    static func named(_ id: ID) -> Theme {
        switch id {
        case .porty: return .porty
        case .osx:   return .osx
        case .bw:    return .bw
        }
    }

    // MARK: Porty — cool white · mauve accent

    static let porty = Theme(
        id: .porty,
        name: "Porty",
        colors: ThemeColors(
            background:     Color(light: Color(hex: "F3F4F6"), dark: Color(hex: "14161B")),
            backgroundAlt:  Color(light: Color(hex: "E7E9ED"), dark: Color(hex: "1F232B")),
            surface:        Color(light: Color(hex: "FBFBFC"), dark: Color(hex: "1C1F25")),
            surfaceHover:   Color(light: Color(hex: "ECEDF0"), dark: Color(hex: "262A32")),
            textPrimary:    Color(light: Color(hex: "1A1B1F"), dark: Color(hex: "E8EAEF")),
            textSecondary:  Color(light: Color(hex: "5A5E68"), dark: Color(hex: "9298A3")),
            textTertiary:   Color(light: Color(hex: "9297A0"), dark: Color(hex: "6C717C")),
            border:         Color(light: Color(hex: "DEDFE3"), dark: Color(hex: "2E323B")),
            accent:         Color(light: Color(hex: "B34778"), dark: Color(hex: "C8628F")),
            accentForeground: Color.white,
            statusDraft:    Color(light: Color(hex: "E5484D"), dark: Color(hex: "F85149")),
            statusActive:   Color(light: Color(hex: "FF9500"), dark: Color(hex: "FFA733")),
            statusComplete: Color(light: Color(hex: "3478F6"), dark: Color(hex: "4A9AFF")),
            statusArchived: Color(hex: "8E8E93"),
            error:          Color(light: Color(hex: "E5484D"), dark: Color(hex: "F85149"))
        ),
        grainOpacity: 0.03
    )

    // MARK: OSX — warm white · mauve accent

    static let osx = Theme(
        id: .osx,
        name: "OSX",
        colors: ThemeColors(
            background:     Color(light: Color(hex: "FBFAF7"), dark: Color(hex: "171613")),
            backgroundAlt:  Color(light: Color(hex: "EDEAE2"), dark: Color(hex: "1F1D19")),
            surface:        Color(light: Color(hex: "FEFEFC"), dark: Color(hex: "1E1C18")),
            surfaceHover:   Color(light: Color(hex: "F2F0EB"), dark: Color(hex: "26241F")),
            textPrimary:    Color(light: Color(hex: "1E1B15"), dark: Color(hex: "EFEDE6")),
            textSecondary:  Color(light: Color(hex: "5A5448"), dark: Color(hex: "A09C90")),
            textTertiary:   Color(light: Color(hex: "8F887A"), dark: Color(hex: "777469")),
            border:         Color(light: Color(hex: "E4E1D8"), dark: Color(hex: "2E2C27")),
            accent:         Color(light: Color(hex: "B34778"), dark: Color(hex: "C8628F")),
            accentForeground: Color.white,
            statusDraft:    Color(nsColor: .systemRed),
            statusActive:   Color(nsColor: .systemOrange),
            statusComplete: Color(nsColor: .systemGreen),
            statusArchived: Color(nsColor: .systemGray),
            error:          Color(nsColor: .systemRed)
        ),
        grainOpacity: 0.0
    )

    // MARK: BW — neutral · monochrome accent (art-first)

    static let bw = Theme(
        id: .bw,
        name: "BW",
        colors: ThemeColors(
            background:     Color(light: Color(hex: "F5F6F7"), dark: Color(hex: "16171A")),
            backgroundAlt:  Color(light: Color(hex: "E5E6E8"), dark: Color(hex: "202125")),
            surface:        Color(light: Color(hex: "FCFCFD"), dark: Color(hex: "1D1E21")),
            surfaceHover:   Color(light: Color(hex: "ECEDEE"), dark: Color(hex: "27282B")),
            textPrimary:    Color(light: Color(hex: "1A1B1D"), dark: Color(hex: "EBECED")),
            textSecondary:  Color(light: Color(hex: "5A5B5E"), dark: Color(hex: "9FA0A3")),
            textTertiary:   Color(light: Color(hex: "8B8C8E"), dark: Color(hex: "72737A")),
            border:         Color(light: Color(hex: "D6D7D9"), dark: Color(hex: "303235")),
            accent:         Color(light: Color(hex: "2A2B2D"), dark: Color(hex: "D4D5D8")),
            // BW accent is monochrome — foreground inverts so contrast is
            // maintained in both appearances (white on dark accent, dark on
            // light accent).
            accentForeground: Color(light: Color(hex: "F5F6F7"), dark: Color(hex: "16171A")),
            statusDraft:    Color(light: Color(hex: "CC3333"), dark: Color(hex: "DD5555")),
            statusActive:   Color(light: Color(hex: "CC7700"), dark: Color(hex: "DD9933")),
            statusComplete: Color(light: Color(hex: "1A1B1D"), dark: Color(hex: "EBECED")),
            statusArchived: Color(light: Color(hex: "8B8C8E"), dark: Color(hex: "72737A")),
            error:          Color(light: Color(hex: "CC3333"), dark: Color(hex: "DD5555"))
        ),
        grainOpacity: 0.02
    )
}

extension EnvironmentValues {
    @Entry var theme: Theme = .porty
}

extension Theme {
    /// CSS custom property declarations for the current appearance. NSColor
    /// bridges (used by the OSX theme) resolve to hex at call time.
    /// Called by both the markdown preview and the CodeMirror editor
    /// bundle whenever the theme or appearance changes.
    func cssVariables(appearance: NSAppearance) -> String {
        let c = colors
        return """
        :root {
          --color-background: \(c.background.hex(for: appearance));
          --color-background-alt: \(c.backgroundAlt.hex(for: appearance));
          --color-surface: \(c.surface.hex(for: appearance));
          --color-surface-hover: \(c.surfaceHover.hex(for: appearance));
          --color-text-primary: \(c.textPrimary.hex(for: appearance));
          --color-text-secondary: \(c.textSecondary.hex(for: appearance));
          --color-text-tertiary: \(c.textTertiary.hex(for: appearance));
          --color-border: \(c.border.hex(for: appearance));
          --color-accent: \(c.accent.hex(for: appearance));
          --color-status-draft: \(c.statusDraft.hex(for: appearance));
          --color-status-active: \(c.statusActive.hex(for: appearance));
          --color-status-complete: \(c.statusComplete.hex(for: appearance));
          --color-status-archived: \(c.statusArchived.hex(for: appearance));
          --color-error: \(c.error.hex(for: appearance));
        }
        """
    }
}
