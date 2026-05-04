# Design Tokens & Style Guide Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a design token system with warm neutral palette and a live style guide view for iterating on the visual language before applying it app-wide.

**Architecture:** A single `DesignTokens` enum with nested namespaces (Colors, Typography, Spacing, Radius, Shadow) defines all visual constants. A `StyleGuideView` renders every token live with a Light/Dark/System toggle. No existing views are changed beyond adding a toolbar button to access the guide.

**Tech Stack:** SwiftUI, NSColor for adaptive color definitions, SF Pro system font.

---

## File Structure

| File | Purpose |
|------|---------|
| Create: `PortyMcFolio/Design/DesignTokens.swift` | All token definitions — colors, typography, spacing, radius, shadows |
| Create: `PortyMcFolio/Views/StyleGuideView.swift` | Live preview with appearance toggle + all token sections + component mockups |
| Modify: `PortyMcFolio/Views/ProjectListView.swift` | Add toolbar button to open style guide sheet |

---

### Task 1: DesignTokens.swift — Color System

**Files:**
- Create: `PortyMcFolio/Design/DesignTokens.swift`

- [ ] **Step 1: Create the Design directory**

```bash
mkdir -p PortyMcFolio/Design
```

- [ ] **Step 2: Write DesignTokens.swift with Color extension and all color tokens**

Create `PortyMcFolio/Design/DesignTokens.swift`:

```swift
import SwiftUI

// MARK: - Adaptive Color Helper

extension Color {
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

    // MARK: Colors

    enum Colors {
        static let background = Color(
            light: Color(red: 0.98, green: 0.98, blue: 0.973),  // #FAFAF8
            dark: Color(red: 0.11, green: 0.11, blue: 0.118)    // #1C1C1E
        )
        static let surface = Color(
            light: .white,                                        // #FFFFFF
            dark: Color(red: 0.173, green: 0.173, blue: 0.18)   // #2C2C2E
        )
        static let surfaceHover = Color(
            light: Color(red: 0.961, green: 0.961, blue: 0.953), // #F5F5F3
            dark: Color(red: 0.227, green: 0.227, blue: 0.235)  // #3A3A3C
        )
        static let textPrimary = Color(
            light: Color(red: 0.102, green: 0.102, blue: 0.102), // #1A1A1A
            dark: Color(red: 0.961, green: 0.961, blue: 0.961)  // #F5F5F5
        )
        static let textSecondary = Color(
            light: Color(red: 0.42, green: 0.42, blue: 0.42),    // #6B6B6B
            dark: Color(red: 0.631, green: 0.631, blue: 0.631)  // #A1A1A1
        )
        static let textTertiary = Color(
            light: Color(red: 0.6, green: 0.6, blue: 0.6),       // #999999
            dark: Color(red: 0.4, green: 0.4, blue: 0.4)        // #666666
        )
        static let border = Color(
            light: Color(red: 0.91, green: 0.91, blue: 0.898),   // #E8E8E5
            dark: Color(red: 0.227, green: 0.227, blue: 0.235)  // #3A3A3C
        )
        static let accent = Color(
            light: Color(red: 0.204, green: 0.471, blue: 0.965), // #3478F6
            dark: Color(red: 0.29, green: 0.604, blue: 1.0)     // #4A9AFF
        )

        // Status colors
        static let statusDraft = Color(red: 0.557, green: 0.557, blue: 0.576)   // #8E8E93
        static let statusActive = Color(
            light: Color(red: 0.204, green: 0.78, blue: 0.349),  // #34C759
            dark: Color(red: 0.188, green: 0.82, blue: 0.345)   // #30D158
        )
        static let statusComplete = Color(
            light: Color(red: 0.204, green: 0.471, blue: 0.965), // #3478F6
            dark: Color(red: 0.29, green: 0.604, blue: 1.0)     // #4A9AFF
        )
        static let statusArchived = Color(
            light: Color(red: 1.0, green: 0.584, blue: 0.0),     // #FF9500
            dark: Color(red: 1.0, green: 0.655, blue: 0.2)      // #FFA733
        )
    }
}
```

- [ ] **Step 3: Add Typography, Spacing, Radius, and Shadow tokens**

Append to `DesignTokens.swift` inside the `DT` enum, after the `Colors` enum:

```swift
    // MARK: Typography

    enum Typography {
        static let largeTitle = Font.system(size: 28, weight: .semibold)
        static let title      = Font.system(size: 18, weight: .semibold)
        static let headline   = Font.system(size: 15, weight: .medium)
        static let body       = Font.system(size: 14, weight: .regular)
        static let caption    = Font.system(size: 12, weight: .regular)
        static let micro      = Font.system(size: 10, weight: .medium)
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
        static let large:  CGFloat = 14
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
```

- [ ] **Step 4: Add View extension for shadow convenience**

Append after the `DT` enum closing brace:

```swift
// MARK: - Shadow Modifier

extension View {
    func dtShadow(_ style: DT.Shadow.Style) -> some View {
        self.shadow(color: style.color, radius: style.radius, x: 0, y: style.y)
    }
}
```

- [ ] **Step 5: Build**

Run: `xcodebuild -scheme PortyMcFolio -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add PortyMcFolio/Design/DesignTokens.swift
git commit -m "feat: add design token system — colors, typography, spacing, radius, shadows"
```

---

### Task 2: StyleGuideView — Appearance Toggle + Color Section

**Files:**
- Create: `PortyMcFolio/Views/StyleGuideView.swift`

- [ ] **Step 1: Create StyleGuideView with appearance toggle and color palette section**

Create `PortyMcFolio/Views/StyleGuideView.swift`:

```swift
import SwiftUI

enum AppearanceMode: String, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
}

struct StyleGuideView: View {
    @State private var appearanceMode: AppearanceMode = .system

    private var colorSchemeOverride: ColorScheme? {
        switch appearanceMode {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with appearance toggle
            HStack {
                Text("Style Guide")
                    .font(DT.Typography.largeTitle)
                    .foregroundStyle(DT.Colors.textPrimary)

                Spacer()

                Picker("", selection: $appearanceMode) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
            .padding(.horizontal, DT.Spacing.xxl)
            .padding(.vertical, DT.Spacing.xl)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: DT.Spacing.xxl) {
                    colorPaletteSection
                }
                .padding(DT.Spacing.xxl)
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .background(DT.Colors.background)
        .preferredColorScheme(colorSchemeOverride)
    }

    // MARK: - Color Palette

    @ViewBuilder
    private var colorPaletteSection: some View {
        sectionHeader("Colors")

        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: DT.Spacing.lg)], spacing: DT.Spacing.lg) {
            colorSwatch("background", DT.Colors.background, bordered: true)
            colorSwatch("surface", DT.Colors.surface, bordered: true)
            colorSwatch("surfaceHover", DT.Colors.surfaceHover)
            colorSwatch("textPrimary", DT.Colors.textPrimary)
            colorSwatch("textSecondary", DT.Colors.textSecondary)
            colorSwatch("textTertiary", DT.Colors.textTertiary)
            colorSwatch("border", DT.Colors.border, bordered: true)
            colorSwatch("accent", DT.Colors.accent)
            colorSwatch("statusDraft", DT.Colors.statusDraft)
            colorSwatch("statusActive", DT.Colors.statusActive)
            colorSwatch("statusComplete", DT.Colors.statusComplete)
            colorSwatch("statusArchived", DT.Colors.statusArchived)
        }
    }

    private func colorSwatch(_ name: String, _ color: Color, bordered: Bool = false) -> some View {
        VStack(spacing: DT.Spacing.sm) {
            RoundedRectangle(cornerRadius: DT.Radius.small)
                .fill(color)
                .frame(height: 60)
                .overlay(
                    RoundedRectangle(cornerRadius: DT.Radius.small)
                        .strokeBorder(DT.Colors.border, lineWidth: bordered ? 1 : 0)
                )

            Text(name)
                .font(DT.Typography.micro)
                .foregroundStyle(DT.Colors.textSecondary)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(DT.Typography.title)
            .foregroundStyle(DT.Colors.textPrimary)
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild -scheme PortyMcFolio -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add PortyMcFolio/Views/StyleGuideView.swift
git commit -m "feat: style guide view with appearance toggle and color palette"
```

---

### Task 3: StyleGuideView — Typography, Spacing, Radius, Shadow Sections

**Files:**
- Modify: `PortyMcFolio/Views/StyleGuideView.swift`

- [ ] **Step 1: Add typography, spacing, radius, and shadow sections to the ScrollView**

In `StyleGuideView.swift`, inside the `ScrollView`'s `VStack`, after `colorPaletteSection`, add:

```swift
                    typographySection
                    spacingSection
                    radiusSection
                    shadowSection
```

- [ ] **Step 2: Implement the typography section**

Add these computed properties to `StyleGuideView`:

```swift
    // MARK: - Typography

    @ViewBuilder
    private var typographySection: some View {
        sectionHeader("Typography")

        VStack(alignment: .leading, spacing: DT.Spacing.lg) {
            typographyRow("largeTitle", DT.Typography.largeTitle, detail: "28pt Semibold")
            typographyRow("title", DT.Typography.title, detail: "18pt Semibold")
            typographyRow("headline", DT.Typography.headline, detail: "15pt Medium")
            typographyRow("body", DT.Typography.body, detail: "14pt Regular")
            typographyRow("caption", DT.Typography.caption, detail: "12pt Regular")
            typographyRow("micro", DT.Typography.micro, detail: "10pt Medium")
        }
    }

    private func typographyRow(_ name: String, _ font: Font, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Portfolio \u{2014} 2026")
                .font(font)
                .foregroundStyle(DT.Colors.textPrimary)
                .frame(minWidth: 280, alignment: .leading)

            Text(name)
                .font(DT.Typography.micro)
                .foregroundStyle(DT.Colors.textTertiary)
                .frame(width: 80, alignment: .leading)

            Text(detail)
                .font(DT.Typography.micro)
                .foregroundStyle(DT.Colors.textTertiary)
        }
    }
```

- [ ] **Step 3: Implement the spacing section**

```swift
    // MARK: - Spacing

    @ViewBuilder
    private var spacingSection: some View {
        sectionHeader("Spacing")

        VStack(alignment: .leading, spacing: DT.Spacing.md) {
            spacingRow("xs", DT.Spacing.xs)
            spacingRow("sm", DT.Spacing.sm)
            spacingRow("md", DT.Spacing.md)
            spacingRow("lg", DT.Spacing.lg)
            spacingRow("xl", DT.Spacing.xl)
            spacingRow("xxl", DT.Spacing.xxl)
        }
    }

    private func spacingRow(_ name: String, _ value: CGFloat) -> some View {
        HStack(spacing: DT.Spacing.md) {
            Text(name)
                .font(DT.Typography.micro)
                .foregroundStyle(DT.Colors.textSecondary)
                .frame(width: 30, alignment: .trailing)

            RoundedRectangle(cornerRadius: 2)
                .fill(DT.Colors.accent.opacity(0.3))
                .frame(width: value, height: 20)

            Text("\(Int(value))pt")
                .font(DT.Typography.micro)
                .foregroundStyle(DT.Colors.textTertiary)
        }
    }
```

- [ ] **Step 4: Implement the radius section**

```swift
    // MARK: - Corner Radius

    @ViewBuilder
    private var radiusSection: some View {
        sectionHeader("Corner Radius")

        HStack(spacing: DT.Spacing.xl) {
            radiusSample("small", DT.Radius.small)
            radiusSample("medium", DT.Radius.medium)
            radiusSample("large", DT.Radius.large)
        }
    }

    private func radiusSample(_ name: String, _ radius: CGFloat) -> some View {
        VStack(spacing: DT.Spacing.sm) {
            RoundedRectangle(cornerRadius: radius)
                .fill(DT.Colors.surface)
                .frame(width: 100, height: 60)
                .overlay(
                    RoundedRectangle(cornerRadius: radius)
                        .strokeBorder(DT.Colors.border, lineWidth: 1)
                )

            Text("\(name) — \(Int(radius))pt")
                .font(DT.Typography.micro)
                .foregroundStyle(DT.Colors.textSecondary)
        }
    }
```

- [ ] **Step 5: Implement the shadow section**

```swift
    // MARK: - Shadows

    @ViewBuilder
    private var shadowSection: some View {
        sectionHeader("Shadows")

        HStack(spacing: DT.Spacing.xl) {
            shadowSample("card", DT.Shadow.card)
            shadowSample("floating", DT.Shadow.floating)
        }
    }

    private func shadowSample(_ name: String, _ style: DT.Shadow.Style) -> some View {
        VStack(spacing: DT.Spacing.sm) {
            RoundedRectangle(cornerRadius: DT.Radius.medium)
                .fill(DT.Colors.surface)
                .frame(width: 140, height: 80)
                .dtShadow(style)

            Text(name)
                .font(DT.Typography.micro)
                .foregroundStyle(DT.Colors.textSecondary)
        }
    }
```

- [ ] **Step 6: Build**

Run: `xcodebuild -scheme PortyMcFolio -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 7: Commit**

```bash
git add PortyMcFolio/Views/StyleGuideView.swift
git commit -m "feat: style guide typography, spacing, radius, and shadow sections"
```

---

### Task 4: StyleGuideView — Component Mockups

**Files:**
- Modify: `PortyMcFolio/Views/StyleGuideView.swift`

- [ ] **Step 1: Add component mockups section to the ScrollView**

In `StyleGuideView.swift`, inside the `ScrollView`'s `VStack`, after `shadowSection`, add:

```swift
                    componentSection
```

- [ ] **Step 2: Implement the component mockups section**

Add these computed properties to `StyleGuideView`:

```swift
    // MARK: - Component Mockups

    @ViewBuilder
    private var componentSection: some View {
        sectionHeader("Components")

        // Status badges
        VStack(alignment: .leading, spacing: DT.Spacing.md) {
            Text("Status Badges")
                .font(DT.Typography.headline)
                .foregroundStyle(DT.Colors.textSecondary)

            HStack(spacing: DT.Spacing.sm) {
                mockBadge("Draft", DT.Colors.statusDraft)
                mockBadge("Active", DT.Colors.statusActive)
                mockBadge("Complete", DT.Colors.statusComplete)
                mockBadge("Archived", DT.Colors.statusArchived)
            }
        }

        // Sample project card
        VStack(alignment: .leading, spacing: DT.Spacing.md) {
            Text("Project Card")
                .font(DT.Typography.headline)
                .foregroundStyle(DT.Colors.textSecondary)

            mockProjectCard
        }
    }

    private func mockBadge(_ label: String, _ color: Color) -> some View {
        Text(label)
            .font(DT.Typography.micro)
            .foregroundStyle(color)
            .padding(.horizontal, DT.Spacing.sm)
            .padding(.vertical, DT.Spacing.xs)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.small))
    }

    private var mockProjectCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Image placeholder
            RoundedRectangle(cornerRadius: 0)
                .fill(DT.Colors.surfaceHover)
                .frame(height: 120)
                .overlay(
                    Image(systemName: "photo")
                        .font(.system(size: 28))
                        .foregroundStyle(DT.Colors.textTertiary)
                )

            VStack(alignment: .leading, spacing: DT.Spacing.sm) {
                HStack {
                    Text("2026")
                        .font(DT.Typography.caption)
                        .foregroundStyle(DT.Colors.textSecondary)
                    Spacer()
                    mockBadge("Draft", DT.Colors.statusDraft)
                }

                Text("Brand Identity System")
                    .font(DT.Typography.title)
                    .foregroundStyle(DT.Colors.textPrimary)

                Text("Acme Corp")
                    .font(DT.Typography.body)
                    .foregroundStyle(DT.Colors.textSecondary)

                HStack(spacing: DT.Spacing.xs) {
                    mockTag("branding")
                    mockTag("identity")
                    mockTag("print")
                }
            }
            .padding(DT.Spacing.lg)
        }
        .frame(width: 320)
        .background(DT.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.medium))
        .dtShadow(DT.Shadow.card)
    }

    private func mockTag(_ label: String) -> some View {
        Text(label)
            .font(DT.Typography.micro)
            .foregroundStyle(DT.Colors.textSecondary)
            .padding(.horizontal, DT.Spacing.sm)
            .padding(.vertical, DT.Spacing.xs)
            .background(DT.Colors.surfaceHover)
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.small))
    }
```

- [ ] **Step 3: Build**

Run: `xcodebuild -scheme PortyMcFolio -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add PortyMcFolio/Views/StyleGuideView.swift
git commit -m "feat: style guide component mockups — badges, project card, tags"
```

---

### Task 5: Wire Up StyleGuideView in ProjectListView

**Files:**
- Modify: `PortyMcFolio/Views/ProjectListView.swift`

- [ ] **Step 1: Add state for showing the style guide**

In `ProjectListView`, add a `@State` property:

```swift
    @State private var isShowingStyleGuide = false
```

- [ ] **Step 2: Add toolbar button to open the style guide**

In the `.toolbar` block in `ProjectListView`, add a new `ToolbarItem` before the existing ones:

```swift
            ToolbarItem(placement: .automatic) {
                Button {
                    isShowingStyleGuide = true
                } label: {
                    Image(systemName: "paintbrush")
                }
                .help("Style Guide")
            }
```

- [ ] **Step 3: Add sheet modifier**

Add a `.sheet` modifier to the `ScrollView` in `ProjectListView`, after the existing `.sheet(isPresented: $appState.isShowingNewProject)`:

```swift
        .sheet(isPresented: $isShowingStyleGuide) {
            StyleGuideView()
                .frame(minWidth: 700, minHeight: 500)
        }
```

- [ ] **Step 4: Build and test**

Run: `xcodebuild -scheme PortyMcFolio -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add PortyMcFolio/Views/ProjectListView.swift
git commit -m "feat: wire up style guide — paintbrush toolbar button opens as sheet"
```
