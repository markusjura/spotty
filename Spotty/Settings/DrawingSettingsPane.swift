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
                Picker("Drawings fade", selection: $preferences.drawing.fade) {
                    ForEach(FadeDelay.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Text(preferences.drawing.fade == .never
                     ? "Drawings stay on screen until you clear them. Clicks pass through them."
                     : "Counted from when you stop drawing. Drawing again first keeps them.")
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
