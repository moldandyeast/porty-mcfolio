import SwiftUI

/// Subtle hover-tint + press-scale animation for icon-only buttons.
/// Gives the user tactile feedback (`.iconButton()` replaces `.buttonStyle(.plain)`
/// on icon-only surfaces like toolbars, action bars, breadcrumbs).
///
/// The hover background fills the label's frame, so callers that want a larger
/// hit target should set an explicit `.frame` on the icon. Without a frame the
/// style enforces a 24pt minimum so the tint never hugs the glyph too tightly.
struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        IconButtonBody(configuration: configuration)
    }
}

private struct IconButtonBody: View {
    let configuration: ButtonStyle.Configuration
    @Environment(\.theme) var theme
    @Environment(\.isEnabled) var isEnabled
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .frame(minWidth: 24, minHeight: 24)
            .contentShape(RoundedRectangle(cornerRadius: DT.Radius.small))
            .background(
                backgroundFill,
                in: RoundedRectangle(cornerRadius: DT.Radius.small)
            )
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
            .animation(.easeInOut(duration: 0.12), value: isHovering)
            .onHover { hovering in
                guard isEnabled else { return }
                isHovering = hovering
            }
            .onChange(of: isEnabled) { _, enabled in
                if !enabled { isHovering = false }
            }
    }

    private var backgroundFill: Color {
        guard isEnabled else { return .clear }
        if configuration.isPressed {
            return theme.colors.surfaceHover.opacity(0.6)
        }
        if isHovering {
            return theme.colors.surfaceHover
        }
        return .clear
    }
}

extension View {
    /// Apply the app-standard icon-button feel: subtle hover tint, press scale-down.
    func iconButton() -> some View {
        self.buttonStyle(IconButtonStyle())
    }
}
