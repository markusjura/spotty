import SwiftUI

/// A slider for quick changes beside a field for exact ones. Both round to `step`, and typed
/// values outside the range snap to its nearest limit. Every slider in Spotty uses this.
struct ValueSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step = 1.0
    let unit: String

    init(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double = 1, unit: String) {
        self.title = title
        _value = value
        self.range = range
        self.step = step
        self.unit = unit
    }

    var body: some View {
        let snapped = Binding { value } set: { value = min(max(($0 / step).rounded() * step, range.lowerBound), range.upperBound) }
        HStack(spacing: 8) {
            PillSlider(title: title, value: snapped, range: range)
                .frame(width: 140)
            HStack(spacing: 3) {
                // Parses with the user's locale.
                TextField(title, value: snapped, format: .number.precision(.fractionLength(0)))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(width: 32)
                Text(unit).foregroundStyle(.secondary)
                    .frame(width: 18, alignment: .leading)
            }
        }
    }
}

/// Shotty's slider look: a thin track and a solid white pill knob. macOS 26 sliders turn their
/// knob into translucent glass while dragged; this one stays solid. VoiceOver sees a standard slider.
private struct PillSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    @Environment(\.isEnabled) private var isEnabled

    private static let knob = CGSize(width: 20, height: 13)
    private var span: Double { range.upperBound - range.lowerBound }

    var body: some View {
        GeometryReader { geometry in
            let knob = Self.knob
            let travel = geometry.size.width - knob.width
            let offset = travel * (value - range.lowerBound) / span
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary).frame(height: 4)
                Capsule().fill(isEnabled ? Color.accentColor : Color.secondary.opacity(0.5))
                    .frame(width: offset + knob.width / 2, height: 4)
                Capsule().fill(.white)
                    .overlay(Capsule().strokeBorder(.black.opacity(0.12), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)
                    .frame(width: knob.width, height: knob.height)
                    .offset(x: offset)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                let fraction = min(max((drag.location.x - knob.width / 2) / travel, 0), 1)
                value = range.lowerBound + fraction * span
            })
        }
        .frame(height: 18)
        .opacity(isEnabled ? 1 : 0.6)
        .accessibilityRepresentation {
            Slider(value: $value, in: range) { Text(title) }
        }
    }
}
