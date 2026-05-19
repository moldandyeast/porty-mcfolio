import SwiftUI

/// A trigger + popover picker for setting a project's optional When.
///
/// Two modes selected via a 2-button toggle:
/// - **Year only** — a year nav (‹ YYYY ›). The folder year is the picked year.
/// - **Range** — explicit Start and End fields, each opening an inline month
///   picker. The folder year is the year-component of End.
///
/// Writes through to `Binding<WhenValue>` continuously; persistence happens
/// when the surrounding `ProjectSettingsPopover` saves.
struct WhenPicker: View {
    @Binding var value: WhenValue

    @State private var isOpen = false
    @State private var activeField: ActiveField? = nil

    @Environment(\.theme) var theme

    private enum ActiveField { case start, end }

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private var displayYear: Int {
        if let end = value.dateEnd {
            return calendar.component(.year, from: end)
        }
        return value.yearOnlyYear ?? calendar.component(.year, from: Date())
    }

    var body: some View {
        Button {
            isOpen.toggle()
        } label: {
            HStack(spacing: DT.Spacing.sm) {
                Image(systemName: "calendar")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.colors.textTertiary)
                Text(triggerLabel)
                    .font(DT.Typography.body)
                    .foregroundStyle(value.isYearOnly ? theme.colors.textTertiary : theme.colors.textPrimary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(theme.colors.textTertiary)
            }
            .padding(.horizontal, DT.Spacing.md)
            .padding(.vertical, DT.Spacing.sm)
            .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: DT.Radius.small))
            .overlay(
                RoundedRectangle(cornerRadius: DT.Radius.small)
                    .stroke(theme.colors.border, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isOpen, arrowEdge: .top) {
            popoverBody
                .frame(width: 320)
                .padding(DT.Spacing.md)
                .background(theme.colors.surface)
        }
    }

    private var triggerLabel: String {
        WhenFormatting.summaryString(
            date: value.date,
            dateEnd: value.dateEnd,
            year: displayYear
        )
    }

    @ViewBuilder
    private var popoverBody: some View {
        VStack(alignment: .leading, spacing: DT.Spacing.md) {
            modeToggle
            if value.isYearOnly {
                yearOnlyBody
            } else {
                rangeBody
            }
        }
    }

    private var modeToggle: some View {
        HStack(spacing: 4) {
            modeButton(title: "Year only", isActive: value.isYearOnly) {
                guard !value.isYearOnly else { return }
                let yr = calendar.component(.year, from: value.dateEnd ?? value.date)
                value = WhenValue.yearOnly(year: yr, anchor: value.date)
                activeField = nil
            }
            modeButton(title: "Range", isActive: value.isRange) {
                guard !value.isRange else { return }
                value = WhenValue.rangeBootstrap(from: Date())
                activeField = .end
            }
        }
        .padding(3)
        .background(theme.colors.backgroundAlt, in: RoundedRectangle(cornerRadius: DT.Radius.small))
    }

    private func modeButton(title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(DT.Typography.caption)
                .fontWeight(isActive ? .semibold : .regular)
                .foregroundStyle(isActive ? theme.colors.accentForeground : theme.colors.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DT.Spacing.xs)
                .background(
                    isActive ? theme.colors.accent : Color.clear,
                    in: RoundedRectangle(cornerRadius: DT.Radius.small - 2)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Year-only body

    private var yearOnlyBody: some View {
        VStack(spacing: DT.Spacing.md) {
            HStack {
                Button { stepYearOnlyYear(by: -1) } label: {
                    Image(systemName: "chevron.left").font(.system(size: 12, weight: .medium))
                }
                .iconButton()
                Spacer()
                Text(String(displayYear))
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.colors.textPrimary)
                Spacer()
                Button { stepYearOnlyYear(by: 1) } label: {
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .medium))
                }
                .iconButton()
            }
            .padding(.horizontal, DT.Spacing.sm)
            .padding(.vertical, DT.Spacing.xs)
            .background(theme.colors.backgroundAlt, in: RoundedRectangle(cornerRadius: DT.Radius.small))

            Text("Project filed under \(String(displayYear)).")
                .font(DT.Typography.caption)
                .foregroundStyle(theme.colors.textTertiary)
                .frame(maxWidth: .infinity)
        }
    }

    private func stepYearOnlyYear(by delta: Int) {
        let yr = (value.yearOnlyYear ?? calendar.component(.year, from: Date())) + delta
        value = WhenValue.yearOnly(year: yr, anchor: value.date)
    }

    // MARK: - Range body

    private var rangeBody: some View {
        VStack(spacing: DT.Spacing.sm) {
            rangeFieldRow(label: "Start", date: value.date, field: .start)
            rangeFieldRow(label: "End", date: value.dateEnd ?? value.date, field: .end)

            if let active = activeField {
                inlineMonthPicker(for: active)
            }

            HStack(spacing: DT.Spacing.sm) {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.colors.accent)
                Text("Filed under \(filedUnderYear) (year of End)")
                    .font(DT.Typography.caption)
                    .foregroundStyle(theme.colors.accent)
                Spacer()
            }
            .padding(.horizontal, DT.Spacing.sm)
            .padding(.vertical, DT.Spacing.xs)
            .background(theme.colors.accent.opacity(DT.Opacity.selection), in: RoundedRectangle(cornerRadius: DT.Radius.small))
        }
    }

    private var filedUnderYear: String {
        if let end = value.dateEnd {
            return String(calendar.component(.year, from: end))
        }
        return String(displayYear)
    }

    private func rangeFieldRow(label: String, date: Date, field: ActiveField) -> some View {
        HStack(spacing: DT.Spacing.md) {
            Text(label.uppercased())
                .font(DT.Typography.micro)
                .foregroundStyle(theme.colors.textSecondary)
                .tracking(1.2)
                .frame(width: 44, alignment: .leading)
            Button {
                activeField = (activeField == field) ? nil : field
            } label: {
                HStack {
                    Text(formatMonthYear(date))
                        .font(DT.Typography.body)
                        .foregroundStyle(theme.colors.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(theme.colors.textTertiary)
                }
                .padding(.horizontal, DT.Spacing.sm)
                .padding(.vertical, DT.Spacing.xs)
                .background(theme.colors.backgroundAlt, in: RoundedRectangle(cornerRadius: DT.Radius.small))
                .overlay(
                    RoundedRectangle(cornerRadius: DT.Radius.small)
                        .stroke(activeField == field ? theme.colors.accent : Color.clear, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func inlineMonthPicker(for field: ActiveField) -> some View {
        let date = (field == .start) ? value.date : (value.dateEnd ?? value.date)
        let visibleYear = calendar.component(.year, from: date)
        let visibleMonth = calendar.component(.month, from: date)

        return VStack(spacing: DT.Spacing.xs) {
            HStack {
                Button {
                    shiftField(field, byYears: -1)
                } label: {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .medium))
                }
                .iconButton()
                Spacer()
                Text(String(visibleYear))
                    .font(DT.Typography.body)
                    .fontWeight(.medium)
                    .foregroundStyle(theme.colors.textPrimary)
                Spacer()
                Button {
                    shiftField(field, byYears: 1)
                } label: {
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .medium))
                }
                .iconButton()
            }

            let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 4)
            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(1...12, id: \.self) { month in
                    Button {
                        setField(field, month: month, year: visibleYear)
                    } label: {
                        Text(monthAbbrev(month))
                            .font(DT.Typography.caption)
                            .fontWeight(month == visibleMonth ? .semibold : .regular)
                            .foregroundStyle(month == visibleMonth ? theme.colors.accentForeground : theme.colors.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, DT.Spacing.xs)
                            .background(
                                month == visibleMonth ? theme.colors.accent : Color.clear,
                                in: RoundedRectangle(cornerRadius: DT.Radius.small)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(DT.Spacing.sm)
        .background(theme.colors.backgroundAlt, in: RoundedRectangle(cornerRadius: DT.Radius.small))
    }

    private func shiftField(_ field: ActiveField, byYears delta: Int) {
        switch field {
        case .start:
            let yr = calendar.component(.year, from: value.date) + delta
            let m = calendar.component(.month, from: value.date)
            if let newStart = calendar.date(from: DateComponents(year: yr, month: m, day: 1)) {
                value.date = newStart
            }
        case .end:
            let baseEnd = value.dateEnd ?? value.date
            let yr = calendar.component(.year, from: baseEnd) + delta
            let m = calendar.component(.month, from: baseEnd)
            value.dateEnd = lastDay(of: m, year: yr)
        }
    }

    private func setField(_ field: ActiveField, month: Int, year: Int) {
        switch field {
        case .start:
            if let newStart = calendar.date(from: DateComponents(year: year, month: month, day: 1)) {
                value.date = newStart
                // If the new start is after the current end, push end forward.
                if let end = value.dateEnd, newStart > end {
                    value.dateEnd = lastDay(of: month, year: year)
                }
            }
        case .end:
            let newEnd = lastDay(of: month, year: year)
            value.dateEnd = newEnd
            // If the new end is before the current start, pull start back.
            if newEnd < value.date {
                value.date = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? value.date
            }
        }
    }

    private func lastDay(of month: Int, year: Int) -> Date {
        let cal = calendar
        let firstOfNext = cal.date(from: DateComponents(year: year, month: month + 1, day: 1))!
        return cal.date(byAdding: .day, value: -1, to: firstOfNext)!
    }

    private func monthAbbrev(_ month: Int) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: "UTC")
        df.dateFormat = "MMM"
        let date = calendar.date(from: DateComponents(year: 2000, month: month, day: 1))!
        return df.string(from: date)
    }

    private func formatMonthYear(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: "UTC")
        df.dateFormat = "MMM yyyy"
        return df.string(from: date).uppercased()
    }
}
