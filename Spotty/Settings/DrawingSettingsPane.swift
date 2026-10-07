import SwiftUI

/// How drawing behaves, the default style, and each tool's style. A tool's collapsed row previews
/// its current look; expanded, it shows only the options that tool draws with. Pen, arrow, and
/// rectangle follow the default color and width unless changed; the highlighter has its own.
/// The toolbar's color menu changes the same colors while drawing.
struct DrawingSettingsPane: View {
    @Bindable var preferences: AppPreferences
    @State private var expanded: Set<DrawingTool> = []

    /// Tool options start under the tool's name: chevron, icon, and spacing columns.
    private static let chevronWidth: CGFloat = 18, iconWidth: CGFloat = 26, nameGap: CGFloat = 6
    private static let optionIndent = chevronWidth + iconWidth + nameGap

    var body: some View {
        Form {
            Section("Behavior") {
                Picker("Draw starts with", selection: $preferences.drawing.startTool) {
                    Text("Last used tool").tag(DrawingTool?.none)
                    Divider()
                    ForEach(DrawingTool.allCases, id: \.self) { tool in
                        Label(tool.title, systemImage: tool.symbol).tag(DrawingTool?.some(tool))
                    }
                }
                .buttonStyle(.borderless)
                Toggle("Fade drawings", isOn: $preferences.drawing.fadesDrawings)
                LabeledContent("Fade after") {
                    HStack(spacing: 3) {
                        // Parses with the user's locale, so a German Mac takes 1,5. Out of range values snap to the nearest limit.
                        let range = DrawingPreferences.fadeDelayRange
                        TextField("Fade after", value: Binding(get: { preferences.drawing.fadeDelay },
                                                               set: { preferences.drawing.fadeDelay = min(max($0, range.lowerBound), range.upperBound) }),
                                  format: .number.precision(.fractionLength(0...2)))
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .frame(width: 48)
                        Text("seconds").settingsValue()
                    }
                }
                .disabled(!preferences.drawing.fadesDrawings)
            }
            Section("Default style") {
                LabeledContent("Color") { ColorPalettePicker("Color", selection: $preferences.drawing.color) }
                LabeledContent("Line width") {
                    ValueSlider("Line width", value: $preferences.drawing.lineWidth, in: DrawingPreferences.widthRange, unit: "pt")
                }
                Text("Pen, arrow, and rectangle use these unless you change them below.").settingsNote()
            }
            Section("Tool styles") {
                ForEach(DrawingTool.allCases, id: \.self) { tool in
                    header(tool)
                    if expanded.contains(tool) { options(for: tool) }
                }
            }
        }
    }

    /// The tool's disclosure row with a preview of its current look.
    private func header(_ tool: DrawingTool) -> some View {
        let isExpanded = expanded.contains(tool)
        return Button {
            withAnimation(.snappy(duration: 0.2)) {
                if isExpanded { expanded.remove(tool) } else { expanded.insert(tool) }
            }
        } label: {
            HStack(spacing: 0) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SettingsColor.secondaryText)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: Self.chevronWidth)
                Image(systemName: tool.symbol).frame(width: Self.iconWidth)
                Text(tool.title).padding(.leading, Self.nameGap)
                Spacer()
                Image(nsImage: ToolSample.preview(tool, preferences.drawing))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tool.title)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
    }

    /// Only the options each tool draws with, one form row each.
    @ViewBuilder
    private func options(for tool: DrawingTool) -> some View {
        let drawing = $preferences.drawing
        switch tool {
        case .pen:
            styleRow("Style", tool, drawing.penPattern)
            colorRow(tool)
            widthRow(tool)
        case .highlighter:
            styleRow("Tip", tool, drawing.highlighterTip)
            option("Color") { ColorPalettePicker("Color", selection: drawing.highlighterColor) }
            option("Line width") {
                ValueSlider("Line width", value: drawing.highlighterWidth, in: DrawingPreferences.highlighterWidthRange, unit: "pt")
            }
            LabeledContent {
                Toggle("Straighten strokes", isOn: drawing.straightensHighlighter).labelsHidden().toggleStyle(.switch).controlSize(.mini)
            } label: {
                optionLabel("Straighten strokes", note: "Shift always draws a straight line.")
            }
            LabeledContent {
                ValueSlider("Tolerance", value: drawing.straightenTolerance, in: DrawingPreferences.straightenToleranceRange, unit: "pt")
            } label: {
                optionLabel("Tolerance", note: "How much a stroke may waver.")
            }
            .disabled(!preferences.drawing.straightensHighlighter)
        case .arrow:
            styleRow("Style", tool, drawing.arrowStyle)
            colorRow(tool)
            widthRow(tool)
            option("Corner radius") {
                ValueSlider("Corner radius", value: drawing.arrowCornerRadius, in: DrawingPreferences.arrowCornerRadiusRange, unit: "pt")
            }
        case .rectangle:
            styleRow("Style", tool, drawing.rectangleStyle)
            colorRow(tool)
            widthRow(tool)
            option("Corner radius") {
                ValueSlider("Corner radius", value: drawing.rectangleCornerRadius, in: DrawingPreferences.cornerRadiusRange, unit: "pt")
            }
        case .spotlight:
            option("Corner radius") {
                ValueSlider("Corner radius", value: drawing.spotlightCornerRadius, in: DrawingPreferences.cornerRadiusRange, unit: "pt")
            }
            option("Dimming") {
                ValueSlider("Dimming", value: drawing.spotlightDimming, in: DrawingPreferences.dimmingRange, step: 5, unit: "%")
            }
        }
    }

    private func optionLabel(_ title: String, note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if let note { Text(note).font(.callout).settingsValue() }
        }
        .padding(.leading, Self.optionIndent)
    }

    private func option(_ title: String, @ViewBuilder control: () -> some View) -> some View {
        LabeledContent { control() } label: { optionLabel(title) }
    }

    /// The style choices as a segmented control of rendered samples.
    private func styleRow<Choice: StyleChoice>(_ title: String, _ tool: DrawingTool, _ selection: Binding<Choice>) -> some View {
        let base = preferences.drawing.style(for: tool)
        return option(title) {
            Picker(title, selection: selection) {
                ForEach(Choice.allCases, id: \.self) { choice in
                    Image(nsImage: ToolSample.glyph(tool, choice.sampleStyle(base), title: choice.title))
                        .accessibilityLabel(choice.title)
                        .tag(choice)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
    }

    private func colorRow(_ tool: DrawingTool) -> some View {
        overrideRow("Color", tool, \.color, fallback: \.color) { ColorPalettePicker("Color", selection: $0) }
    }

    private func widthRow(_ tool: DrawingTool) -> some View {
        overrideRow("Line width", tool, \.width, fallback: \.lineWidth) {
            ValueSlider("Line width", value: $0, in: DrawingPreferences.widthRange, unit: "pt")
        }
    }

    /// A default-style option that shows the default value until changed. Changing it sets the
    /// tool's own value; the reset button makes the tool follow the default style again.
    private func overrideRow<Value: Equatable, Control: View>(
        _ title: String, _ tool: DrawingTool, _ property: WritableKeyPath<StyleOverrides, Value?>,
        fallback: KeyPath<DrawingPreferences, Value>, @ViewBuilder control: (Binding<Value>) -> Control
    ) -> some View {
        let isCustom = preferences.drawing[overrides: tool][keyPath: property] != nil
        let current = preferences.drawing[overrides: tool][keyPath: property] ?? preferences.drawing[keyPath: fallback]
        let value = Binding { current } set: {
            // A text field commits its shown value when it loses focus, as after a reset. That is no change.
            guard $0 != current else { return }
            preferences.drawing[overrides: tool][keyPath: property] = $0
        }
        return option(title) {
            HStack(spacing: 6) {
                ResetButton(isVisible: isCustom) { preferences.drawing[overrides: tool][keyPath: property] = nil }
                control(value)
            }
        }
    }
}

/// The annotation palette, as in the toolbar's color menu.
private struct ColorPalettePicker: View {
    let title: String
    @Binding var selection: RGBAColor

    init(_ title: String, selection: Binding<RGBAColor>) {
        self.title = title
        _selection = selection
    }

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(RGBAColor.palette, id: \.name) { swatch in
                Label { Text(swatch.name) } icon: { ColorDot(color: swatch.color, size: 12) }.tag(swatch.color)
            }
        }
        .labelsHidden()
        .fixedSize()
        .buttonStyle(.borderless)
    }
}

/// Follows the default style again. Shown only beside a tool's own value.
private struct ResetButton: View {
    let isVisible: Bool
    let action: () -> Void

    var body: some View {
        if isVisible {
            Button(action: action) {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(.borderless)
            .help("Use default style")
            .accessibilityLabel("Use default style")
        }
    }
}
