import SwiftUI

struct SplashView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.theme) var theme
    @State private var logo: NSImage?

    var body: some View {
        ZStack {
            theme.colors.background.ignoresSafeArea()

            GeometryReader { geo in
                VStack(spacing: DT.Spacing.sm) {
                    if let image = logo {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: geo.size.width * 0.5)
                    }

                    Text("Minimal Lovable Software by Mold&Yeast")
                        .font(DT.Typography.caption)
                        .foregroundStyle(theme.colors.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { logo = loadLogo() }
        .onChange(of: colorScheme) { _, _ in logo = loadLogo() }
    }

    private func loadLogo() -> NSImage? {
        let name = colorScheme == .dark ? "logo-dark" : "logo-light"
        guard let url = Bundle.main.url(forResource: name, withExtension: "svg") else { return nil }
        return NSImage(contentsOf: url)
    }
}
