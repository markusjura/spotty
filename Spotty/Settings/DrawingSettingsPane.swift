import SwiftUI

/// Starting tool, styles, and what happens to drawings afterwards. Each tool's collapsed group shows
/// only the options it draws with. Pen, arrow, rectangle, and spotlight start from the default style
/// and can override it per option; the highlighter has its own style. The toolbar's color menu
/// changes the same colors while drawing.
struct DrawingSettingsPane: View {
    @Bindable var preferences: AppPreferences
    @State private var expanded: Set<DrawingTool> = []

    var body: some View {
        Form {
            Section {
                Picker("Draw starts with", selection: $preferences.drawing.startTool) {
                    Text("Last used tool").tag(DrawingTool?.none)
                    Divider()
                    ForEach(DrawingTool.allCases, id: \.self) { tool in
                        Label(tool.title, systemImage: tool.symbol).tag(DrawingTool?.some(tool))
                    }
                }
                Text("Tool shortcuts always start with their own tool.").secondaryNote()
            }
            Section("Default style") {
                ColorPalettePicker("Color", selection: $preferences.drawing.color)
                LabeledContent("Line width") {
                    ValueSlider("Line width", value: $preferences.drawing.lineWidth, in: DrawingPreferences.widthRange, unit: "pt")
                        .padding(.trailing, ResetButton.width)
                }
                LabeledContent("Corner radius") {
                    ValueSlider("Corner radius", value: $preferences.drawing.cornerRadius, in: DrawingPreferences.cornerRadiusRange, unit: "pt")
                        .padding(.trailing, ResetButton.width)
                }
                Text("Tools use these unless you change them below.").secondaryNote()
            }
            Section("Tools") {
                ForEach(DrawingTool.allCases, id: \.self) { tool in
                    DisclosureGroup(isExpanded: Binding(get: { expanded.contains(tool) },
                                                        set: { if $0 { expanded.insert(tool) } else { expanded.remove(tool) } })) {
                        // Grouped forms draw no separators inside a disclosure group, so each option brings its own.
                        Group(subviews: options(for: tool)) { rows in
                            ForEach(rows) { row in
                                VStack(spacing: 0) {
                                    Divider()
                                    row.padding(.vertical, 3)
                                }
                                .padding(.leading, 28)
                            }
                        }
                    } label: {
                        LabeledContent { summary(of: tool) } label: { Label(tool.title, systemImage: tool.symbol) }
                    }
                }
            }
            Section {
                Toggle("Fade drawings", isOn: $preferences.drawing.fadesDrawings)
                LabeledContent("Fade after") {
                    HStack {
                        // Parses with the user's locale, so a German Mac takes 1,5. Out of range values snap to the nearest limit.
                        let range = DrawingPreferences.fadeDelayRange
                        TextField("Fade after", value: Binding(get: { preferences.drawing.fadeDelay },
                                                               set: { preferences.drawing.fadeDelay = min(max($0, range.lowerBound), range.upperBound) }),
                                  format: .number.precision(.fractionLength(0...2)))
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("seconds")
                    }
                }
                .disabled(!preferences.drawing.fadesDrawings)
                Text(preferences.drawing.fadesDrawings
                     ? "Each drawing fades on its own timer, counted from when you finish it. Spotlights disappear when you let go."
                     : "Drawings stay on screen until you clear them. Clicks pass through them.")
                    .secondaryNote()
            }
        }
    }

    /// Only the options each tool draws with.
    @ViewBuilder
    private func options(for tool: DrawingTool) -> some View {
        switch tool {
        case .pen, .arrow:
            overrideRow("Color", tool, \.color, fallback: \.color) { ColorPalettePicker("Color", selection: $0) }
            widthRow(tool)
        case .rectangle:
            overrideRow("Color", tool, \.color, fallback: \.color) { ColorPalettePicker("Color", selection: $0) }
            widthRow(tool)
            radiusRow(tool)
        case .highlighter:
            ColorPalettePicker("Color", selection: $preferences.drawing.highlighterColor)
                .padding(.trailing, ResetButton.width)
            LabeledContent("Line width") {
                ValueSlider("Line width", value: $preferences.drawing.highlighterWidth, in: DrawingPreferences.highlighterWidthRange, unit: "pt")
                    .padding(.trailing, ResetButton.width)
            }
        case .spotlight:
            radiusRow(tool)
            LabeledContent("Dimming") {
                ValueSlider("Dimming", value: $preferences.drawing.spotlightDimming, in: DrawingPreferences.dimmingRange, step: 5, unit: "%")
                    .padding(.trailing, ResetButton.width)
            }
        }
    }

    private func widthRow(_ tool: DrawingTool) -> some View {
        overrideRow("Line width", tool, \.width, fallback: \.lineWidth) {
            ValueSlider("Line width", value: $0, in: DrawingPreferences.widthRange, unit: "pt")
        }
    }

    private func radiusRow(_ tool: DrawingTool) -> some View {
        overrideRow("Corner radius", tool, \.cornerRadius, fallback: \.cornerRadius) {
            ValueSlider("Corner radius", value: $0, in: DrawingPreferences.cornerRadiusRange, unit: "pt")
        }
    }

    /// A tool option that shows the default style's value until changed. Changing it sets the
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
        return LabeledContent(title) {
            HStack(spacing: 0) {
                control(value).labelsHidden()
                ResetButton(isVisible: isCustom) { preferences.drawing[overrides: tool][keyPath: property] = nil }
            }
        }
    }

    /// The tool's color and width, or the dimming for spotlights, so collapsed groups still show their look.
    @ViewBuilder
    private func summary(of tool: DrawingTool) -> some View {
        if tool == .spotlight {
            Text("\(Int(preferences.drawing.spotlightDimming))% dimming")
        } else {
            let style = preferences.drawing.style(for: tool)
            HStack(spacing: 6) {
                ColorDot(color: style.color, size: 10)
                Text("\(style.width.formatted()) pt").monospacedDigit()
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
    }
}

/// Follows the default style again. Hidden rows keep its space, so controls stay aligned.
private struct ResetButton: View {
    static let width: CGFloat = 26
    let isVisible: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.uturn.backward")
        }
        .buttonStyle(.borderless)
        .help("Use default style")
        .accessibilityLabel("Use default style")
        .frame(width: Self.width, alignment: .trailing)
        .opacity(isVisible ? 1 : 0)
        .disabled(!isVisible)
        .accessibilityHidden(!isVisible)
    }
}
