import AppKit

/// The overlay panels, one per display, and the drawings on them across sessions.
/// Panels exist only while drawing is on or drawings are visible.
@MainActor
final class Overlay {
    /// The style for new marks while drawing is on.
    var style: () -> MarkStyle? = { nil }
    var didDraw: () -> Void = { }
    var handleKey: (NSEvent) -> Bool = { _ in false }

    private var panels: [CGDirectDisplayID: (panel: OverlayPanel, view: OverlayView)] = [:]
    /// Views in the order their marks were drawn, for undo across displays.
    private var history: [OverlayView] = []
    private var isActive = false
    private var fadeTask: Task<Void, Never>?
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
        cancelFade()
        isActive = true
        for screen in NSScreen.screens { ensurePanel(for: screen) }
        for (panel, _) in panels.values {
            panel.ignoresMouseEvents = false
            panel.orderFrontRegardless()
        }
        setKeyboard(keyboard)
        NSCursor.crosshair.set()
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

    /// Stops taking the mouse, then fades the drawings after `fadeAfter`, or keeps them for nil.
    func deactivate(fadeAfter: Duration?) {
        isActive = false
        for (panel, view) in panels.values {
            view.finishLive()
            panel.acceptsKey = false
            panel.ignoresMouseEvents = true
            if panel.isKeyWindow { panel.resignKey() }
        }
        NSCursor.arrow.set()
        guard hasDrawings else { return hidePanels() }
        guard let fadeAfter else { return }
        fadeTask = Task { [weak self] in
            try? await Task.sleep(for: fadeAfter)
            guard !Task.isCancelled else { return }
            self?.fadeOut()
        }
    }

    func undo() {
        guard let view = history.popLast() else { return }
        view.removeLast()
        if !isActive && !hasDrawings { hidePanels() }
    }

    func clear() {
        cancelFade()
        for (_, view) in panels.values { view.removeAll() }
        history.removeAll()
        if !isActive { hidePanels() }
    }

    private func fadeOut() {
        let views = panels.values.map(\.view).filter(\.hasMarks)
        guard !views.isEmpty else { return hidePanels() }
        var remaining = views.count
        for view in views {
            view.fadeOut { [weak self] in
                remaining -= 1
                // A new drawing session cancels the fade and keeps the drawings.
                guard remaining == 0, let self, !self.isActive, self.fadeTask != nil else { return }
                self.fadeTask = nil
                self.clear()
            }
        }
    }

    private func cancelFade() {
        fadeTask?.cancel()
        fadeTask = nil
        for (_, view) in panels.values { view.cancelFade() }
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
        view.didFinish = { [weak self] view in
            self?.history.append(view)
            self?.didDraw()
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
            history.removeAll { $0 === entry.view }
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
