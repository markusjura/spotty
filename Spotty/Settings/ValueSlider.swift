import SwiftUI

/// A slider for quick changes beside a field for exact ones. Both round to `step`, and typed
/// values outside the range snap to its nearest limit.
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
            // No step: a stepped macOS slider draws a tick per step.
            Slider(value: snapped, in: range) { Text(title) }
                .labelsHidden()
                .frame(width: 160)
            HStack(spacing: 4) {
                // Parses with the user's locale.
                TextField(title, value: snapped, format: .number.precision(.fractionLength(0)))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(width: 40)
                Text(unit).foregroundStyle(.secondary)
                    .frame(width: 18, alignment: .leading)
            }
        }
    }
}
