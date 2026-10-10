# Pen styles: Dashed with a dash length, Ink, and Calligraphy

Status: implemented. Mockup: pen-settings-final.html in the "Propose meaningful pen drawing styles" thread.

What shipped differs from the plan below in three places: `StrokeStyle` (solid, dashed, ink, calligraphy) replaced `StrokePattern` outright and rectangles use its solid and dashed cases, the four tuning values live in one `StrokeOptions` struct stored as `penOptions` (so a nested migration key `penOptions.dashLength` works), and option labels keep the 50 pt indent aligned with the tool name.

## Goal

The pen gets four styles: Solid, Dashed, Ink, Calligraphy. Dotted goes away; it becomes Dashed with a dash length of 0. Every style except Solid has its own one or two options, shown as rows under the pen's Color and Line width. Color and Line width move up so the pen's rows read Style, Color, Line width, then the style's options, and option labels sit one step (18 pt) past the tool name.

Defaults, from the tuned artifacts: Dash length 2 line widths (the current dash). Ink thinning 69 %, taper 1 line width. Calligraphy nib angle 35°, nib edge 17 %.

## Model (`Spotty/Preferences/PreferenceValues.swift`)

- `StrokePattern` becomes `enum PenStyle: String, Codable, CaseIterable, Sendable { case solid, dashed, ink, calligraphy }`. Rectangles keep a dash too, so keep a tiny `StrokePattern { solid, dashed }` for `ToolStyle.pattern`, or drop it and let `ToolStyle` carry `dash: Double?` directly (nil is solid). I prefer the second: one field, no enum that only exists to be mapped.
- `ToolStyle` gains the fields each style reads. Zero or nil means the style does not apply, so `Mark.paint` needs no extra flags:
  - `dash: Double?` dash length in line widths; nil draws solid. Rectangles set it to 2 for `.dashed`.
  - `pen = PenStyle.solid`
  - `thinning = 0.0` (0...0.9) and `taper = 0.0` (line widths), read by `.ink`.
  - `nibAngle = 0.0` (degrees) and `nibEdge = 0.0` (0.05...0.5), read by `.calligraphy`.
- `DrawingPreferences`: replace `penPattern` with `penStyle = PenStyle.solid`, and add `penDashLength = 2.0`, `penThinning = 69.0`, `penTaper = 1.0`, `penNibAngle = 35.0`, `penNibEdge = 17.0`, with ranges `dashLengthRange = 0...6`, `thinningRange = 0...90`, `taperRange = 0...8`, `nibAngleRange = 0...180`, `nibEdgeRange = 5...50`. The percentages stay 0...100 in preferences, as `spotlightDimming` does, and `style(for:)` divides them. `isValid` checks the new ranges.
- `style(for: .pen)` fills the pen fields; `.rectangle` sets `dash = rectangleStyle == .dashed ? 2 : nil`.
- `migrate`: `penPattern` of `"dotted"` becomes `penStyle: "dashed"` plus `penDashLength: 0`; `"solid"` and `"dashed"` map to `penStyle` unchanged. Remove the `penPattern` key. Add a test next to `testBuild11CornerRadiiMoveToRectanglesAndSpotlights`.

## Rendering (`Spotty/Drawing/Mark.swift`, `OverlayView.swift`, `ToolSample.swift`)

Ink needs speed, so marks record when each point arrived.

- `Mark.points` stays `[CGPoint]` for every tool but the pen; adding a parallel `times: [TimeInterval]` is simplest. `add(_:)` grows it with `CACurrentMediaTime()` (an injectable `now` for tests). `extendMark` and `beginMark` need no change; `Overlay.swift` posts points from the held-button path through the same calls.
- `Paint` gets `kind: .stroke | .fill`. Ink and Calligraphy build a filled outline path and return `Paint(path:, fill: 1, stroke: false)`, the same shape arrows use, so `OverlayView.render` and `ToolSample.draw` need nothing new. Dash patterns only ever apply to stroked paints, which keeps `lineDashPattern` out of the new styles for free.
- `MarkGeometry`:
  - `smoothPath` stays for Solid and Dashed. For the new styles add `resample(_ points: [CGPoint], times:, spacing: 2)` that walks the same Catmull-Rom curve and emits evenly spaced points with interpolated times; the artifacts use exactly this.
  - `inkOutline(points, times, width, thinning, taper) -> CGPath`: per-point width = `width * (1 - thinning * min(1, v / vRef))` with `v` an exponentially smoothed speed (`0.2` factor) and `vRef` 1.8 pt/ms, times a taper factor `0.2 + 0.8 * min(1, edgeDistance / (taper * width + 2))`. Emit the left offsets forward and the right offsets backward, round caps at both ends. One closed path, filled with even-odd off.
  - `calligraphyOutline(points, width, nibAngle, nibEdge) -> CGPath`: a nib vector `n = (cos a, sin a) * width / 2` with `a = -nibAngle`. Append one quad `p+n, q+n, q-n, p-n` per segment, then stroke the centerline with width `width * nibEdge` and union it by appending `centerline.copy(strokingWithWidth:...)`. Filling with non-zero winding merges the overlapping quads.
  - `dash(width:)` moves from `StrokePattern` to a free function `dashLengths(_ dash: Double, width:) -> [CGFloat]`: `[dash * width, 2 * width + 0.25 * dash * width]`, which gives the current `[2w, 2.5w]` at 2 and `[0, 2w]` at 0.
- Shift-constrained strokes (`points.count == 2`) go through the same outline builders with two points; Ink then draws a straight tapered line, which is right.
- `ToolSample.glyph` for the pen draws the wave with `thinning` and the other fields from the current preferences, so the segment shows what the user tuned, as the mockup does. Calligraphy's glyph uses width 3.4 instead of 2 so the nib reads at 34 × 18 pt. The sample wave has no times; give it synthetic ones from slope (the artifact's trick: a hand is fastest between peaks), via a `ToolSample.timed(_:)` helper.

Highlighter is untouched. Rectangles switch from `pattern` to `dash` and lose nothing.

Tests in `MarkTests`: Ink outlines are narrower where points arrive faster and end in a taper; Calligraphy outlines are `width` wide across the nib and `width * nibEdge` wide along it; dash length 0 yields the old dotted pattern.

## Settings (`Spotty/Settings/DrawingSettingsPane.swift`)

- Pen rows become `styleRow("Style", .pen, drawing.penStyle)`, `colorRow`, `widthRow`, then the style's rows:
  - `.dashed`: `option("Dash length", note: "In line widths. 0 draws dots.")` with `ValueSlider(step: 0.5, unit: "×")`. `ValueSlider` formats whole numbers today; give it a `fractionLength(0...1)` when `step < 1`.
  - `.ink`: "Thinning" (note "How thin fast strokes get.", unit "%") and "Taper" (note "Length in line widths.", unit "×").
  - `.calligraphy`: "Nib angle" (unit "°", step 5) and "Nib edge" (note "Thinnest line, in % of the width.", unit "%").
- `optionLabel` grows a `note:` parameter that every row can use; the highlighter already renders notes this way.
- Indent: change `optionIndent` from `chevronWidth + iconWidth + nameGap` (50 pt, aligned with the tool name) to that plus `chevronWidth` (68 pt). The 50 pt alignment put "Style" flush under "Pen", which read as a sibling rather than a child; one extra chevron width makes the hierarchy visible without a second column. The arrow, rectangle, highlighter and spotlight rows share the constant, so they move together.
- The `StyleChoice` conformance for `PenStyle` returns `sampleStyle` with the pen fields copied from `base`, so the glyph uses the live thinning and nib values.
- Height changes when switching styles are fine; the Highlighter group already changes height.

## Out of scope

Laser, Outlined, Pencil. Rectangle dash length (the pen's `dashLengths` helper makes it a one-row addition later).

## Order of work

1. Model and migration, with the preferences test. Build.
2. `dashLengths`, `Paint` fill kind, rectangle and pen Dashed on the new field. `Scripts/test.sh MarkTests`.
3. Point times, `resample`, `inkOutline`, Ink in `Mark.paint` and `ToolSample`. Verify with `Scripts/ui/spotty-ui run` drags at slow and fast speeds.
4. `calligraphyOutline` and Calligraphy.
5. Settings rows, indent, `ValueSlider` fractions. `Scripts/run.sh dev` and compare against the mockup in both appearances.

## Follow-up: fade as a style

Fade moved from Behavior into the default style. `fadesDrawings` is one global switch; `fadeDelay` is the default delay and `StyleOverrides.fadeDelay` lets every persisting tool keep its own, the highlighter included. `DrawingPreferences.fadeAfter(for:)` resolves it and `Overlay.fadeAfter` takes the tool. In Settings the Fade drawings switch and Fade after row sit under Color and Line width in Default style, each tool gets an overridable Fade after row, and those rows disappear while fading is off. Behavior keeps Draw starts with as its only row.
