import AppKit

/// Markdown highlighter — styles headings with size/weight, dims syntax
/// characters (**, *, #, >, `, ~~) to tertiary color so content stands out.
final class MarkdownHighlighter {

    private let fontSize: CGFloat = 15
    private let lineHeightMultiple: CGFloat = 1.6

    // Fonts — single size, weight only for hierarchy
    private lazy var bodyFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    private lazy var bodyMedium = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .medium)
    private lazy var bodySemibold = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold)
    private lazy var bodyBold = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)

    // Colors — settable via applyTheme(_:); defaults match the Porty theme.
    var textColor: NSColor = .labelColor
    var syntaxColor: NSColor = .tertiaryLabelColor
    var accentColor: NSColor = NSColor(red: 0.702, green: 0.278, blue: 0.471, alpha: 1) // #B34778

    /// Update colors from an active theme, then re-highlight the attached text storage.
    func applyTheme(_ theme: Theme) {
        textColor = NSColor(theme.colors.textPrimary)
        syntaxColor = NSColor(theme.colors.textTertiary)
        accentColor = NSColor(theme.colors.accent)
    }

    // Paragraph style
    private lazy var baseParagraphStyle: NSMutableParagraphStyle = {
        let ps = NSMutableParagraphStyle()
        ps.lineHeightMultiple = lineHeightMultiple
        ps.paragraphSpacing = 4
        return ps
    }()

    // Regex patterns (compiled once)
    private static let headingRE = try! NSRegularExpression(pattern: #"^(#{1,6})\s"#, options: .anchorsMatchLines)
    private static let boldRE = try! NSRegularExpression(pattern: #"(\*\*|__)(.+?)\1"#)
    private static let italicRE = try! NSRegularExpression(pattern: #"(?<!\*)(\*|_)(?!\*)(.+?)\1(?!\*)"#)
    private static let strikeRE = try! NSRegularExpression(pattern: #"(~~)(.+?)\1"#)
    private static let codeRE = try! NSRegularExpression(pattern: #"`([^`]+)`"#)
    private static let blockquoteRE = try! NSRegularExpression(pattern: #"^>\s?"#, options: .anchorsMatchLines)
    private static let linkRE = try! NSRegularExpression(pattern: #"\[([^\]]*)\]\(([^)]*)\)"#)
    private static let embedRE = try! NSRegularExpression(pattern: #"!\[\[([^\]]+)\]\]"#)
    private static let hrRE = try! NSRegularExpression(pattern: #"^---+\s*$"#, options: .anchorsMatchLines)
    private static let listMarkerRE = try! NSRegularExpression(pattern: #"^(\s*)([-*+]|\d+\.)\s"#, options: .anchorsMatchLines)

    /// Fast path — only set base font/color on the edited line. No regex, no layout changes.
    func applyBase(_ textStorage: NSTextStorage, in editedRange: NSRange) {
        let string = textStorage.string as NSString
        guard string.length > 0 else { return }
        let clampedLocation = min(editedRange.location, string.length)
        let clampedLength = min(editedRange.length, string.length - clampedLocation)
        let lineRange = string.lineRange(for: NSRange(location: clampedLocation, length: clampedLength))
        guard lineRange.length > 0 else { return }

        textStorage.beginEditing()
        textStorage.addAttributes([
            .font: bodyFont,
            .foregroundColor: textColor,
        ], range: lineRange)
        textStorage.endEditing()
    }

    /// Full highlight pass — regex-based syntax styling. Call debounced, not on every keystroke.
    func highlight(_ textStorage: NSTextStorage, in editedRange: NSRange) {
        let string = textStorage.string as NSString
        guard string.length > 0 else { return }

        // Expand to cover full lines affected by the edit
        let clampedLocation = min(editedRange.location, string.length)
        let clampedLength = min(editedRange.length, string.length - clampedLocation)
        let lineRange = string.lineRange(for: NSRange(location: clampedLocation, length: clampedLength))
        guard lineRange.length > 0 else { return }

        textStorage.beginEditing()

        // 1. Base attributes for the edited region
        let baseAttrs: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: textColor,
            .paragraphStyle: baseParagraphStyle,
        ]
        textStorage.setAttributes(baseAttrs, range: lineRange)

        // 2. Bold — emphasize content, dim markers
        Self.boldRE.enumerateMatches(in: textStorage.string, range: lineRange) { match, _, _ in
            guard let match else { return }
            let markerLen = match.range(at: 1).length
            let contentRange = match.range(at: 2)
            textStorage.addAttribute(.font, value: bodySemibold, range: contentRange)
            // Dim opening marker
            textStorage.addAttribute(.foregroundColor, value: syntaxColor,
                range: NSRange(location: match.range.location, length: markerLen))
            // Dim closing marker
            textStorage.addAttribute(.foregroundColor, value: syntaxColor,
                range: NSRange(location: NSMaxRange(contentRange), length: markerLen))
        }

        // 3. Italic — dim markers
        Self.italicRE.enumerateMatches(in: textStorage.string, range: lineRange) { match, _, _ in
            guard let match else { return }
            let markerRange = match.range(at: 1)
            let contentRange = match.range(at: 2)
            if let font = NSFontManager.shared.convert(self.bodyFont, toHaveTrait: .italicFontMask) as NSFont? {
                textStorage.addAttribute(.font, value: font, range: contentRange)
            }
            textStorage.addAttribute(.foregroundColor, value: syntaxColor, range: markerRange)
            textStorage.addAttribute(.foregroundColor, value: syntaxColor,
                range: NSRange(location: NSMaxRange(contentRange), length: markerRange.length))
        }

        // 5. Strikethrough — dim markers
        Self.strikeRE.enumerateMatches(in: textStorage.string, range: lineRange) { match, _, _ in
            guard let match else { return }
            let contentRange = match.range(at: 2)
            textStorage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: contentRange)
            // Dim ~~ markers
            textStorage.addAttribute(.foregroundColor, value: syntaxColor,
                range: NSRange(location: match.range.location, length: 2))
            textStorage.addAttribute(.foregroundColor, value: syntaxColor,
                range: NSRange(location: NSMaxRange(contentRange), length: 2))
        }

        // 6. Inline code — dim backticks
        Self.codeRE.enumerateMatches(in: textStorage.string, range: lineRange) { match, _, _ in
            guard let match else { return }
            // Dim opening backtick
            textStorage.addAttribute(.foregroundColor, value: syntaxColor,
                range: NSRange(location: match.range.location, length: 1))
            // Dim closing backtick
            textStorage.addAttribute(.foregroundColor, value: syntaxColor,
                range: NSRange(location: NSMaxRange(match.range) - 1, length: 1))
        }

        // 7. Blockquote > prefix — dim
        Self.blockquoteRE.enumerateMatches(in: textStorage.string, range: lineRange) { match, _, _ in
            guard let match else { return }
            textStorage.addAttribute(.foregroundColor, value: syntaxColor, range: match.range)
        }

        // 8. Links [text](url) — accent the text, dim the syntax
        Self.linkRE.enumerateMatches(in: textStorage.string, range: lineRange) { match, _, _ in
            guard let match else { return }
            let textRange = match.range(at: 1)
            let urlRange = match.range(at: 2)
            // Link text in accent
            textStorage.addAttribute(.foregroundColor, value: accentColor, range: textRange)
            // Dim brackets and parens
            textStorage.addAttribute(.foregroundColor, value: syntaxColor,
                range: NSRange(location: match.range.location, length: 1)) // [
            textStorage.addAttribute(.foregroundColor, value: syntaxColor,
                range: NSRange(location: NSMaxRange(textRange), length: 2)) // ](
            textStorage.addAttribute(.foregroundColor, value: syntaxColor,
                range: NSRange(location: NSMaxRange(urlRange), length: 1)) // )
            // URL in syntax color
            textStorage.addAttribute(.foregroundColor, value: syntaxColor, range: urlRange)
        }

        // 9. Embeds ![[filename]] — accent the filename, dim the syntax
        Self.embedRE.enumerateMatches(in: textStorage.string, range: lineRange) { match, _, _ in
            guard let match else { return }
            let filenameRange = match.range(at: 1)
            textStorage.addAttribute(.foregroundColor, value: accentColor, range: filenameRange)
            // Dim ![[
            textStorage.addAttribute(.foregroundColor, value: syntaxColor,
                range: NSRange(location: match.range.location, length: 3))
            // Dim ]]
            textStorage.addAttribute(.foregroundColor, value: syntaxColor,
                range: NSRange(location: NSMaxRange(filenameRange), length: 2))
        }

        // 10. Horizontal rules --- dim
        Self.hrRE.enumerateMatches(in: textStorage.string, range: lineRange) { match, _, _ in
            guard let match else { return }
            textStorage.addAttribute(.foregroundColor, value: syntaxColor, range: match.range)
        }

        // 11. List markers - * + 1. — dim
        Self.listMarkerRE.enumerateMatches(in: textStorage.string, range: lineRange) { match, _, _ in
            guard let match else { return }
            let markerRange = match.range(at: 2)
            textStorage.addAttribute(.foregroundColor, value: syntaxColor, range: markerRange)
        }

        // 12. Headings — weight only, same size. Applied last to override inline styles.
        Self.headingRE.enumerateMatches(in: textStorage.string, range: lineRange) { match, _, _ in
            guard let match else { return }
            let level = match.range(at: 1).length
            let fullLineRange = string.lineRange(for: match.range)

            let headingFont: NSFont
            switch level {
            case 1: headingFont = bodyBold
            case 2: headingFont = bodySemibold
            default: headingFont = bodyMedium
            }

            textStorage.addAttribute(.font, value: headingFont, range: fullLineRange)

            // Dim the # prefix
            textStorage.addAttribute(.foregroundColor, value: syntaxColor, range: match.range)
        }

        textStorage.endEditing()
    }
}
