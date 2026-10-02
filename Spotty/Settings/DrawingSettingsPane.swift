import SwiftUI

/// Starting tool, colors, and what happens to drawings afterwards. The toolbar's color menu
/// changes the same colors while drawing.
struct DrawingSettingsPane: View {
    @Bindable var preferences: AppPreferences

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
            Section("Style") {
                colorPicker("Color", selection: $preferences.drawing.color)
                colorPicker("Highlighter color", selection: $preferences.drawing.highlighterColor)
                Picker("Line width", selection: $preferences.drawing.lineWidth) {
                    ForEach(DrawingPreferences.widthPresets, id: \.self) { width in
                        Text("\(Int(width)) pt").tag(width)
                    }
                }
                Picker("Corner radius", selection: $preferences.drawing.cornerRadius) {
                    ForEach(DrawingPreferences.cornerRadiusPresets, id: \.self) { radius in
                        Text(radius == 0 ? "None" : "\(Int(radius)) pt").tag(radius)
                    }
                }
                .help("Rectangles and spotlights")
                LabeledContent("Spotlight dimming") {
                    HStack {
                        // No step: a stepped macOS slider draws a tick per step.
                        Slider(value: Binding(get: { preferences.drawing.spotlightDimming },
                                              set: { preferences.drawing.spotlightDimming = ($0 / 5).rounded() * 5 }),
                               in: DrawingPreferences.dimmingRange)
                        Text("\(Int(preferences.drawing.spotlightDimming))%").monospacedDigit().frame(width: 40, alignment: .trailing)
                    }
                    .frame(maxWidth: 260)
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
                     ? "Each drawing fades on its own timer, counted from when you finish it. Spotlights stay until you clear them."
                     : "Drawings stay on screen until you clear them. Clicks pass through them.")
                    .secondaryNote()
            }
        }
    }

    private func colorPicker(_ title: String, selection: Binding<RGBAColor>) -> some View {
        Picker(title, selection: selection) {
            ForEach(RGBAColor.palette, id: \.name) { swatch in
                Label { Text(swatch.name) } icon: { ColorDot(color: swatch.color, size: 12) }.tag(swatch.color)
            }
        }
    }
}
