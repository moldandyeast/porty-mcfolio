import SwiftUI

struct TagChipInput: View {
    @Binding var tags: [String]
    var placeholder = "Add tag…"
    var suggestions: [String] = []
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool
    @Environment(\.theme) var theme

    /// Suggestions filtered to match current input, excluding already-selected tags
    private var filteredSuggestions: [String] {
        guard !inputText.isEmpty else { return [] }
        let query = inputText.lowercased()
        return suggestions
            .filter { $0.lowercased().hasPrefix(query) && !tags.contains($0) }
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DT.Spacing.sm) {
            // Tag pills
            if !tags.isEmpty {
                tagPills
            }

            // Input field
            TextField(placeholder, text: $inputText)
                .textFieldStyle(.plain)
                .font(DT.Typography.body)
                .foregroundStyle(theme.colors.textPrimary)
                .padding(.horizontal, DT.Spacing.sm)
                .padding(.vertical, DT.Spacing.sm)
                .background(theme.colors.backgroundAlt, in: RoundedRectangle(cornerRadius: DT.Radius.small))
                .overlay(RoundedRectangle(cornerRadius: DT.Radius.small).stroke(theme.colors.border, lineWidth: 0.5))
                .focused($isInputFocused)
                .onChange(of: inputText) { _, newValue in
                    // Auto-add on comma
                    if newValue.contains(",") {
                        addTag()
                    }
                }
                .onKeyPress(.return) {
                    if !inputText.trimmingCharacters(in: .whitespaces).isEmpty {
                        addTag()
                        return .handled
                    }
                    return .ignored // empty field — let Enter propagate to Create/Save
                }
                .onKeyPress(.tab) {
                    if !inputText.trimmingCharacters(in: .whitespaces).isEmpty {
                        addTag()
                    }
                    // Always return .ignored so SwiftUI advances focus to the next field.
                    return .ignored
                }

            // Autocomplete suggestions
            if !filteredSuggestions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredSuggestions, id: \.self) { suggestion in
                        Button {
                            selectSuggestion(suggestion)
                        } label: {
                            Text(suggestion)
                                .font(DT.Typography.caption)
                                .foregroundStyle(theme.colors.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, DT.Spacing.sm)
                                .padding(.vertical, DT.Spacing.xs)
                        }
                        .buttonStyle(.plain)
                        .onHover { hovering in
                            if hovering {
                                NSCursor.pointingHand.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                    }
                }
                .background(theme.colors.surfaceHover, in: RoundedRectangle(cornerRadius: DT.Radius.small))
                .overlay(
                    RoundedRectangle(cornerRadius: DT.Radius.small)
                        .stroke(theme.colors.border, lineWidth: 0.5)
                )
            }
        }
    }

    private var tagPills: some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(tags.enumerated()), id: \.offset) { idx, tag in
                tagChip(tag, at: idx)
            }
        }
    }

    private func tagChip(_ tag: String, at index: Int) -> some View {
        HStack(spacing: DT.Spacing.xs) {
            Text(tag)
                .font(DT.Typography.caption)
                .foregroundStyle(theme.colors.textPrimary)

            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(theme.colors.textTertiary)
        }
        .padding(.leading, 10)
        .padding(.trailing, DT.Spacing.sm)
        .padding(.vertical, 5)
        .background(theme.colors.surfaceHover, in: Capsule())
        .overlay(Capsule().stroke(theme.colors.border, lineWidth: 0.5))
        .contentShape(Capsule())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                // Index-based removal — exactly removes the tapped chip even
                // when duplicate strings exist. (Was firstIndex(of: tag).)
                if index < tags.count {
                    _ = tags.remove(at: index)
                }
            }
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Remove \(tag)")
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    private func addTag() {
        let newTags = inputText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !tags.contains($0) }
        withAnimation(.easeInOut(duration: 0.15)) {
            tags.append(contentsOf: newTags)
        }
        inputText = ""
    }

    private func selectSuggestion(_ suggestion: String) {
        guard !tags.contains(suggestion) else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            tags.append(suggestion)
        }
        inputText = ""
        isInputFocused = true
    }
}
