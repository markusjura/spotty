import AppKit

/// Images of real marks for Settings: each tool's current look in its row, and its style choices.
/// Both draw `Mark.paint`, so Settings shows exactly what drawing puts on screen.
enum ToolSample {
    /// The tool's current look over placeholder text lines.
    static func preview(_ tool: DrawingTool, _ drawing: DrawingPreferences) -> NSImage {
        // Marks are laid out in a 190 × 55 pt space and drawn at 40%, so widths keep their proportions.
        let size = CGSize(width: 76, height: 22), scale = 0.4
        var style = drawing.style(for: tool)
        if tool == .highlighter { style.color = style.color.withAlpha(0.4) }
        let mark = sampleMark(tool, style: style)
        let image = NSImage(size: size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let card = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
            NSColor.labelColor.withAlphaComponent(0.06).setFill()
            card.fill()
            // Keeps the spotlight's dimming inside the card's rounded corners.
            card.addClip()
            context.scaleBy(x: scale, y: scale)
            NSColor.labelColor.withAlphaComponent(0.14).setFill()
            for (y, length) in [(38.0, 160.0), (25.0, 160.0), (12.0, 90.0)] {
                NSBezierPath(roundedRect: CGRect(x: 15, y: y - 2.5, width: length, height: 5), xRadius: 2.5, yRadius: 2.5).fill()
            }
            if tool == .spotlight {
                context.addPath(MarkGeometry.dimming(CGRect(x: 0, y: 0, width: 190, height: 55), spotlight: mark.paint.path))
                context.setFillColor(CGColor(gray: 0, alpha: drawing.spotlightDimming / 100))
                context.fillPath()
            } else {
                draw(mark, in: context)
            }
            return true
        }
        image.accessibilityDescription = "\(tool.title) preview"
        return image
    }

    /// A template image of one style choice, drawn with a thin line.
    static func glyph(_ tool: DrawingTool, _ style: ToolStyle, title: String) -> NSImage {
        let mark = glyphMark(tool, style: style)
        let image = NSImage(size: CGSize(width: 34, height: 18), flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            draw(mark, in: context)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = title
        return image
    }

    private static func draw(_ mark: Mark, in context: CGContext) {
        let paint = mark.paint, color = mark.style.color
        if paint.fill > 0 {
            context.addPath(paint.path)
            context.setFillColor(color.withAlpha(color.alpha * paint.fill).cgColor)
            context.fillPath()
        }
        guard paint.stroke else { return }
        context.addPath(paint.path)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(mark.width)
        context.setLineCap(paint.cap)
        context.setLineJoin(paint.join)
        context.setLineDash(phase: 0, lengths: paint.dash)
        context.strokePath()
    }

    /// A finished mark dragged through `points`. The drag speeds up where the path is steepest, as
    /// a hand does between the peaks of a wave, so ink samples show their thinning.
    private static func mark(_ tool: DrawingTool, _ style: ToolStyle, _ points: [CGPoint]) -> Mark {
        let slopes = points.indices.map { index -> CGFloat in
            let before = points[max(index - 1, 0)], after = points[min(index + 1, points.count - 1)]
            return abs(after.y - before.y) / max(abs(after.x - before.x), 0.01)
        }
        let steepest = max(slopes.max() ?? 1, 0.01)
        var mark = Mark(tool: tool, at: points[0], style: style, time: 0)
        var time = 0.0
        for index in points.indices.dropFirst() {
            let speed = 300 + 1500 * min(1, slopes[index] / steepest) // points per second
            time += hypot(points[index].x - points[index - 1].x, points[index].y - points[index - 1].y) / speed
            mark.add(points[index], at: time)
        }
        mark.finish()
        return mark
    }

    private static func sampleMark(_ tool: DrawingTool, style: ToolStyle) -> Mark {
        switch tool {
        case .pen:
            return mark(tool, style, stride(from: 15.0, through: 175, by: 4).map { CGPoint(x: $0, y: 27 + 12 * sin($0 / 22)) })
        case .highlighter:
            // A slightly wavering stroke, which straightens when the highlighter straightens strokes.
            return mark(tool, style, stride(from: 15.0, through: 140, by: 5).map { CGPoint(x: $0, y: 25 + 2 * sin($0 / 9)) })
        case .arrow:
            return mark(tool, style, [CGPoint(x: 18, y: 12), CGPoint(x: 80, y: 40), CGPoint(x: 172, y: 44)])
        case .rectangle:
            return mark(tool, style, [CGPoint(x: 45, y: 9), CGPoint(x: 145, y: 46)])
        case .spotlight:
            return mark(tool, style, [CGPoint(x: 40, y: 9), CGPoint(x: 150, y: 46)])
        }
    }

    private static func glyphMark(_ tool: DrawingTool, style: ToolStyle) -> Mark {
        var style = style
        style.color = RGBAColor.black.withAlpha(style.color.alpha)
        switch tool {
        case .pen:
            // A thin line, except the calligraphy nib, which needs some width to show its angle.
            style.width = style.stroke == .calligraphy ? 3.4 : 2
            return mark(tool, style, stride(from: 3.0, through: 31, by: 1).map { CGPoint(x: $0, y: 9 + 5 * sin(($0 - 3) / 4.5)) })
        case .highlighter:
            style.width = 8
            return mark(tool, style, [CGPoint(x: 8, y: 9), CGPoint(x: 26, y: 9)])
        case .arrow:
            style.width = 2
            style.cornerRadius = 0.5
            return mark(tool, style, style.arrow == .curved
                        ? [CGPoint(x: 3, y: 4), CGPoint(x: 15, y: 13), CGPoint(x: 31, y: 9)]
                        : [CGPoint(x: 3, y: 9), CGPoint(x: 31, y: 9)])
        case .rectangle, .spotlight:
            style.width = 1.6
            style.cornerRadius = 1.5
            return mark(tool, style, [CGPoint(x: 4, y: 3), CGPoint(x: 30, y: 15)])
        }
    }
}

/// A tool option shown as a segmented control of rendered samples.
protocol StyleChoice: CaseIterable, Hashable where AllCases: RandomAccessCollection {
    var title: String { get }
    /// The style a sample of this choice draws with.
    func sampleStyle(_ base: ToolStyle) -> ToolStyle
}

extension StrokeStyle: StyleChoice {
    var title: String {
        switch self { case .solid: "Solid"; case .dashed: "Dashed"; case .ink: "Ink"; case .calligraphy: "Calligraphy" }
    }
    func sampleStyle(_ base: ToolStyle) -> ToolStyle { var style = base; style.stroke = self; return style }
}

extension HighlighterTip: StyleChoice {
    var title: String {
        switch self { case .round: "Round tip"; case .flat: "Flat tip" }
    }
    func sampleStyle(_ base: ToolStyle) -> ToolStyle {
        var style = base; style.hasFlatTips = self == .flat; style.color = style.color.withAlpha(0.45); return style
    }
}

extension ArrowStyle: StyleChoice {
    var title: String {
        switch self { case .standard: "Standard"; case .open: "Open"; case .double: "Double"; case .curved: "Curved" }
    }
    func sampleStyle(_ base: ToolStyle) -> ToolStyle { var style = base; style.arrow = self; return style }
}

extension RectangleStyle: StyleChoice {
    var title: String {
        switch self { case .outline: "Outline"; case .dashed: "Dashed"; case .tinted: "Tinted" }
    }
    func sampleStyle(_ base: ToolStyle) -> ToolStyle {
        var style = base; style.stroke = self == .dashed ? .dashed : .solid; style.isTinted = self == .tinted; return style
    }
}
