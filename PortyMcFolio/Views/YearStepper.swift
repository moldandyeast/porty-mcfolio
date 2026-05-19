import SwiftUI

struct YearStepper: View {
    @Binding var year: Int
    /// When true, the stepper grabs keyboard focus on first appearance so
    /// ←/→ arrow stepping works without an extra click. Used by hosts like
    /// `WhenPicker` that present the stepper inside a popover.
    var autoFocus: Bool = false
    @State private var isEditing = false
    @State private var editText = ""
    /// Focus for the inline TextField when editing via tap.
    @FocusState private var isEditorFocused: Bool
    /// Focus for the stepper as a whole. Tab-stop between sibling fields.
    /// When focused (and not editing), ←/→ adjust the year.
    @FocusState private var isStepperFocused: Bool
    @Environment(\.theme) var theme

    var body: some View {
        HStack(spacing: 0) {
            Button {
                decrement()
            } label: {
                Image(systemName: "chevron.left")
                    .font(DT.Typography.micro)
                    .foregroundStyle(year > 1337 ? theme.colors.textSecondary : theme.colors.textTertiary.opacity(0.4))
                    .frame(width: 36, height: 32)
            }
            .iconButton()

            Spacer()

            if isEditing {
                TextField("", text: $editText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.colors.textPrimary)
                    .multilineTextAlignment(.center)
                    .frame(width: 56)
                    .focused($isEditorFocused)
                    .onSubmit { commitEdit() }
                    .onChange(of: isEditorFocused) { _, focused in
                        if !focused { commitEdit() }
                    }
            } else {
                Text(String(year))
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.colors.textPrimary)
                    .onTapGesture {
                        editText = String(year)
                        isEditing = true
                        isEditorFocused = true
                    }
            }

            Spacer()

            Button {
                increment()
            } label: {
                Image(systemName: "chevron.right")
                    .font(DT.Typography.micro)
                    .foregroundStyle(year < 2310 ? theme.colors.textSecondary : theme.colors.textTertiary.opacity(0.4))
                    .frame(width: 36, height: 32)
            }
            .iconButton()
        }
        .background(theme.colors.backgroundAlt, in: RoundedRectangle(cornerRadius: DT.Radius.small))
        .overlay(
            RoundedRectangle(cornerRadius: DT.Radius.small)
                .stroke(
                    isStepperFocused && !isEditing ? theme.colors.accent.opacity(0.7) : theme.colors.border,
                    lineWidth: 0.5
                )
        )
        .focusable(!isEditing)
        .focused($isStepperFocused)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) {
            guard !isEditing else { return .ignored }
            decrement()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard !isEditing else { return .ignored }
            increment()
            return .handled
        }
        .onAppear {
            guard autoFocus else { return }
            // Defer to next runloop so the hosting popover/window has time to
            // become key — focusing too early gets dropped by AppKit.
            DispatchQueue.main.async {
                isStepperFocused = true
            }
        }
    }

    private func decrement() {
        if year > 1337 { year -= 1 }
    }

    private func increment() {
        if year < 2310 { year += 1 }
    }

    private func commitEdit() {
        if let typed = Int(editText), typed >= 1337, typed <= 2310 {
            year = typed
        }
        isEditing = false
    }
}
