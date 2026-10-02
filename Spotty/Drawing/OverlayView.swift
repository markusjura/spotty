import AppKit
import QuartzCore

/// What a new mark looks like, read when a drag starts.
struct MarkStyle: Equatable {
    var tool: DrawingTool
    /// The tool's color, opaque. Highlighters draw it translucent.
    var color: RGBAColor
    var width: CGFloat
    var cornerRadius: CGFloat
    /// Spotlight dimming, 0...1.
    var dimming: CGFloat
    /// False while Shift belongs to the held drawing shortcut, as in ⌃⇧.
    var shiftConstrains: Bool
}

/// A transparent panel covering one display. It passes clicks through unless drawing is on,
/// and it never activates Spotty, so the app you are pointing at keeps focus.
final class OverlayPanel: NSPanel {
    /// Only while drawing is toggled on, so tool keys and Escape reach the overlay.
    var acceptsKey = false

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = Chrome.overlayLevel
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { acceptsKey }
    override var canBecomeMain: Bool { false }
}

/// Draws marks with one shape layer each, so live drags and fades stay on the GPU.
final class OverlayView: NSView {
    /// The style for a new mark; nil when drawing is off.
    var style: () -> MarkStyle? = { nil }
    /// Called with each kept mark, for undo and its fade timer.
    var didFinish: (OverlayView, UUID, DrawingTool) -> Void = { _, _, _ in }
    /// Returns true when the key was handled.
    var handleKey: (NSEvent) -> Bool = { _ in false }

    /// A mark and the layer that draws it. Spotlights keep a hidden layer and cut a hole in `dimming` instead.
    private struct Drawn {
        let id = UUID()
        var mark: Mark
        let layer: CAShapeLayer
    }

    /// Holds the dimming and the mark layers above it.
    private let content = CALayer()
    private let dimming = CAShapeLayer()
    private var marks: [Drawn] = []
    private var live: Drawn?
    private var currentDimming: CGFloat = 0.5

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(content)
        dimming.fillColor = NSColor.black.cgColor
        dimming.isHidden = true
        content.addSublayer(dimming)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        withoutAnimation {
            content.frame = bounds
            dimming.frame = bounds
            updateDimming()
        }
    }

    // MARK: Mouse

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        beginMark(at: convert(event.locationInWindow, from: nil), shift: event.modifierFlags.contains(.shift))
    }

    override func mouseDragged(with event: NSEvent) {
        extendMark(to: convert(event.locationInWindow, from: nil), shift: event.modifierFlags.contains(.shift))
    }

    override func mouseUp(with event: NSEvent) {
        mouseDragged(with: event)
        finishLive()
    }

    /// Starts a mark at `point` in view coordinates, from a left drag or a held mouse button shortcut.
    func beginMark(at point: CGPoint, shift: Bool) {
        guard let style = style() else { return }
        finishLive()
        let color = style.tool == .highlighter ? style.color.withAlpha(0.4) : style.color
        let mark = Mark(tool: style.tool, at: point, color: color, width: style.width, cornerRadius: style.cornerRadius)
        let layer = CAShapeLayer()
        layer.lineCap = .round
        // Round joins would soften a rectangle's hard corners.
        layer.lineJoin = style.tool == .rectangle ? .miter : .round
        if style.tool == .spotlight {
            currentDimming = style.dimming
            layer.isHidden = true
        }
        withoutAnimation { content.addSublayer(layer) }
        live = Drawn(mark: mark, layer: layer)
        extendMark(to: point, shift: shift)
    }

    func extendMark(to point: CGPoint, shift: Bool) {
        guard var current = live else { return }
        current.mark.add(point)
        current.mark.isConstrained = shift && (style()?.shiftConstrains ?? true)
        live = current
        render(current)
    }

    /// Keeps a finished mark, or drops one too small to matter. Ending drawing mid-drag finishes it too.
    func finishLive() {
        guard var current = live else { return }
        live = nil
        current.mark.finish()
        if current.mark.isEmpty {
            withoutAnimation { current.layer.removeFromSuperlayer() }
            updateDimming()
            return
        }
        // Kept before rendering, so the dimming still counts a finished spotlight.
        marks.append(current)
        render(current)
        didFinish(self, current.id, current.mark.tool)
    }

    private func render(_ item: Drawn) {
        withoutAnimation {
            let shape = item.mark.shape
            if item.mark.tool == .spotlight {
                updateDimming()
                return
            }
            // Nothing shows until the drag is long enough to keep, so a click draws no lone arrowhead.
            item.layer.path = item.mark.isEmpty ? nil : shape.path
            item.layer.fillColor = shape.filled ? item.mark.color.cgColor : nil
            item.layer.strokeColor = shape.filled ? nil : item.mark.color.cgColor
            item.layer.lineWidth = item.mark.width
        }
    }

    private func updateDimming() {
        let spotlights = (marks + [live].compactMap { $0 }).filter { $0.mark.tool == .spotlight }.map(\.mark.shape.path)
        withoutAnimation {
            dimming.isHidden = spotlights.isEmpty
            dimming.opacity = Float(currentDimming)
            dimming.path = spotlights.isEmpty ? nil : MarkGeometry.dimming(bounds, spotlights: spotlights)
        }
    }

    // MARK: Editing

    /// Does nothing when the mark is already gone.
    func remove(_ id: UUID) {
        guard let index = marks.firstIndex(where: { $0.id == id }) else { return }
        let removed = marks.remove(at: index)
        withoutAnimation { removed.layer.removeFromSuperlayer() }
        if removed.mark.tool == .spotlight { updateDimming() }
    }

    func removeAll() {
        withoutAnimation {
            for item in marks { item.layer.removeFromSuperlayer() }
            live?.layer.removeFromSuperlayer()
        }
        marks.removeAll()
        live = nil
        updateDimming()
    }

    // MARK: Fading

    /// Fades one stroked or filled mark out and removes it. Returns at once when the mark is already gone.
    /// Spotlights never fade; they draw no layer of their own.
    func fadeOut(_ id: UUID) async {
        guard let item = marks.first(where: { $0.id == id }) else { return }
        await withCheckedContinuation { continuation in
            CATransaction.begin()
            CATransaction.setCompletionBlock { continuation.resume() }
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1
            fade.toValue = 0
            fade.duration = Chrome.reduceMotion ? 0.01 : Chrome.drawingFadeDuration
            fade.timingFunction = CAMediaTimingFunction(name: .easeIn)
            fade.fillMode = .forwards
            fade.isRemovedOnCompletion = false
            item.layer.add(fade, forKey: "fade")
            CATransaction.commit()
        }
        remove(id)
    }

    // MARK: Keys and cursor

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        // Unhandled keys are swallowed rather than beeping.
        _ = handleKey(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.isKeyWindow == true, event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
        return handleKey(event)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.activeAlways, .inVisibleRect, .mouseMoved, .cursorUpdate, .mouseEnteredAndExited],
                                       owner: self))
    }

    /// Drawing keeps the plain arrow. Spotty stays inactive while drawing, so cursor rects alone are not enough.
    override func cursorUpdate(with event: NSEvent) { if style() != nil { NSCursor.arrow.set() } }
    override func mouseMoved(with event: NSEvent) { if style() != nil { NSCursor.arrow.set() } }
    override func mouseEntered(with event: NSEvent) { if style() != nil { NSCursor.arrow.set() } }

    private func withoutAnimation(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }
}
