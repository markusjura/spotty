import AppKit

/// The overlay panels, one per display, and the drawings on them across sessions.
/// Panels exist only while drawing is on or drawings are visible.
@MainActor
final class Overlay {
    /// The style for new marks while drawing is on.
    var style: () -> MarkStyle? = { nil }
    /// How long each finished mark stays; nil keeps it until cleared.
    var fadeAfter: () -> Duration? = { nil }
    var didDraw: () -> Void = { }
    var handleKey: (NSEvent) -> Bool = { _ in false }

    private var panels: [CGDirectDisplayID: (panel: OverlayPanel, view: OverlayView)] = [:]
    /// Marks in the order they were drawn, for undo across displays.
    private var history: [(view: OverlayView, mark: UUID)] = []
    private var isActive = false
    private var screenObserver: NSObjectProtocol?

    init() {
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        }
    }

    var hasDrawings: Bool { !history.isEmpty }

    /// Shows the panels and starts taking the mouse. `keyboard` also takes key focus, for
    /// toggled-on drawing; held drawing leaves keys with the app you are working in.
    func activate(keyboard: Bool) {
        isActive = true
        for screen in NSScreen.screens { ensurePanel(for: screen) }
        for (panel, _) in panels.values {
            panel.ignoresMouseEvents = false
            panel.orderFrontRegardless()
        }
        setKeyboard(keyboard)
        NSCursor.arrow.set()
    }

    func setKeyboard(_ keyboard: Bool) {
        for (panel, _) in panels.values { panel.acceptsKey = keyboard }
        if keyboard {
            let mouse = NSEvent.mouseLocation
            let target = panels.values.first { $0.panel.frame.contains(mouse) } ?? panels.values.first
            if let target {
                target.panel.makeKey()
                target.panel.makeFirstResponder(target.view)
            }
        } else {
            for (panel, _) in panels.values where panel.isKeyWindow { panel.resignKey() }
        }
    }

    /// Stops taking the mouse. Drawings stay until their own fade timers run out.
    func deactivate() {
        isActive = false
        pointerView = nil
        for (panel, view) in panels.values {
            view.finishLive()
            panel.acceptsKey = false
            panel.ignoresMouseEvents = true
            if panel.isKeyWindow { panel.resignKey() }
        }
        NSCursor.arrow.set()
        if !hasDrawings { hidePanels() }
    }

    /// The view drawing a mark from a held mouse button shortcut, which AppKit never sees as a drag.
    private var pointerView: OverlayView?

    /// Starts or extends a mark at `location`, in Core Graphics global coordinates.
    func dragPointerMark(to location: CGPoint) {
        guard isActive, let primary = NSScreen.screens.first else { return }
        let point = NSPoint(x: location.x, y: primary.frame.maxY - location.y)
        let shift = NSEvent.modifierFlags.contains(.shift)
        if let pointerView, let window = pointerView.window {
            pointerView.extendMark(to: pointerView.convert(window.convertPoint(fromScreen: point), from: nil), shift: shift)
            return
        }
        guard let (panel, view) = panels.values.first(where: { $0.panel.frame.contains(point) }) else { return }
        pointerView = view
        view.beginMark(at: view.convert(panel.convertPoint(fromScreen: point), from: nil), shift: shift)
    }

    func endPointerMark() {
        pointerView?.finishLive()
        pointerView = nil
    }

    func undo() {
        guard let last = history.popLast() else { return }
        last.view.remove(last.mark)
        if !isActive && !hasDrawings { hidePanels() }
    }

    /// Pending fade timers find their marks gone and do nothing.
    func clear() {
        for (_, view) in panels.values { view.removeAll() }
        history.removeAll()
        if !isActive { hidePanels() }
    }

    /// Starts a finished mark's own fade timer, so drawing more never extends it.
    private func scheduleFade(of mark: UUID, in view: OverlayView) {
        guard let fadeAfter = fadeAfter() else { return }
        Task { [weak self, weak view] in
            try? await Task.sleep(for: fadeAfter)
            await view?.fadeOut(mark)
            guard let self else { return }
            history.removeAll { $0.mark == mark }
            if !isActive && !hasDrawings { hidePanels() }
        }
    }

    private func hidePanels() {
        for (panel, _) in panels.values { panel.orderOut(nil) }
    }

    private func ensurePanel(for screen: NSScreen) {
        guard let display = screen.displayID else { return }
        if let existing = panels[display] {
            if existing.panel.frame != screen.frame { existing.panel.setFrame(screen.frame, display: false) }
            return
        }
        let panel = OverlayPanel(screen: screen)
        let view = OverlayView(frame: CGRect(origin: .zero, size: screen.frame.size))
        view.autoresizingMask = [.width, .height]
        view.style = { [weak self] in self?.isActive == true ? self?.style() : nil }
        view.didFinish = { [weak self] view, mark, tool in
            guard let self else { return }
            // A spotlight lasts only while its drag does, whatever the fade setting.
            if tool == .spotlight {
                view.remove(mark)
            } else {
                history.append((view, mark))
                scheduleFade(of: mark, in: view)
            }
            didDraw()
        }
        view.handleKey = { [weak self] event in self?.handleKey(event) ?? false }
        panel.contentView = view
        panels[display] = (panel, view)
    }

    /// Drops panels for disconnected displays and refits the rest.
    private func screensChanged() {
        let displays = Set(NSScreen.screens.compactMap(\.displayID))
        for (display, entry) in panels where !displays.contains(display) {
            entry.panel.orderOut(nil)
            history.removeAll { $0.view === entry.view }
            panels[display] = nil
        }
        if isActive {
            activate(keyboard: panels.values.contains { $0.panel.isKeyWindow })
        } else {
            for screen in NSScreen.screens where screen.displayID.flatMap({ panels[$0] }) != nil { ensurePanel(for: screen) }
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
    }
}
