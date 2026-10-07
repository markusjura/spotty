import SwiftUI

@main
struct SpottyApp: App {
    @NSApplicationDelegateAdaptor(SpottyApplicationDelegate.self) private var delegate

    var body: some Scene {
        // A window rather than a Settings scene, which SwiftUI always keeps at a fixed size.
        Window("Settings", id: SettingsView.windowID) {
            SettingsView(preferences: delegate.preferences, commands: delegate.commands, inputTap: delegate.inputTap,
                         updater: delegate.updater)
                .onAppear { delegate.settingsIsOpen = true }
                .onDisappear { delegate.settingsIsOpen = false }
        }
        // System Settings' toolbar height and control size.
        .windowToolbarStyle(.unified)
        .defaultSize(width: 660, height: 608)
        .windowResizability(.contentMinSize)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)
        .commands {
            SwiftUI.CommandGroup(replacing: .appSettings) { SettingsButton() }
        }
        MenuBarExtra(isInserted: Binding(
            get: { delegate.preferences.general.showsMenuBarIcon },
            set: { delegate.preferences.general.showsMenuBarIcon = $0 })) {
            SpottyMenu(drawing: delegate.drawing, inputTap: delegate.inputTap, updater: delegate.updater)
        } label: {
            MenuBarLabel(showsUpdateDot: delegate.updater.needsAttention)
        }
    }
}

/// The menu bar item: Spotty's highlighter, with a blue dot while an update needs the user.
private struct MenuBarLabel: View {
    let showsUpdateDot: Bool

    var body: some View {
        Image(nsImage: showsUpdateDot ? Self.iconWithDot : Self.icon)
    }

    private static let icon: NSImage = {
        let image = NSImage(resource: .menuBarIcon)
        image.isTemplate = true
        image.accessibilityDescription = "Spotty"
        return image
    }()

    /// The icon with a blue dot in its top right corner. A template image can't carry color, so this
    /// one draws the glyph itself in the menu bar's label color, resolved each time it draws.
    private static let iconWithDot: NSImage = {
        let image = NSImage(size: icon.size, flipped: false) { bounds in
            icon.draw(in: bounds)
            NSColor.labelColor.set()
            bounds.fill(using: .sourceAtop)
            let dot = CGRect(x: bounds.maxX - 6, y: bounds.maxY - 6, width: 6, height: 6)
            // A clear ring keeps the dot apart from the highlighter tip it overlaps.
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: dot.insetBy(dx: -1.5, dy: -1.5)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.systemBlue.setFill()
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
        image.cacheMode = .never
        image.accessibilityDescription = "Spotty, update available"
        return image
    }()
}

/// The menu bar menu. Drawing items toggle like a tap of their shortcut.
private struct SpottyMenu: View {
    let drawing: DrawingController
    let inputTap: InputTap
    let updater: AppUpdater

    var body: some View {
        let commands = drawing.commands
        Button(drawing.isDrawing ? "Stop Drawing" : "Draw") { drawing.perform(.toggleDrawing) }
            .keyboardShortcut(commands.shortcut(for: .toggleDrawing)?.keyboardShortcut)
        Divider()
        ForEach(DrawingTool.allCases, id: \.self) { tool in
            Toggle(isOn: Binding(get: { drawing.isDrawing && drawing.session.tool == tool }, set: { _ in drawing.toggle(tool) })) {
                Text(tool.title)
            }
            .keyboardShortcut(commands.shortcut(for: .draw(tool))?.keyboardShortcut)
        }
        Divider()
        Button(CommandID.undo.title) { drawing.perform(.undo) }
            .keyboardShortcut(commands.shortcut(for: .undo)?.keyboardShortcut)
        Button(CommandID.clear.title) { drawing.perform(.clear) }
            .keyboardShortcut(commands.shortcut(for: .clear)?.keyboardShortcut)
        Divider()
        if commands.needsEventTap && !inputTap.isTrusted {
            Button("Allow Accessibility Access…") { inputTap.requestAccess() }
        }
        UpdateMenuItem(updater: updater)
        SettingsButton()
        Button("Quit Spotty") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

@MainActor
final class SpottyApplicationDelegate: NSObject, NSApplicationDelegate {
    let preferences = AppPreferences()
    let commands = CommandRegistry()
    lazy var drawing = DrawingController(preferences: preferences, commands: commands)
    lazy var inputTap = InputTap(registry: commands) { [weak self] in self?.drawing.handle($0) }
    lazy var updater = AppUpdater(environment: .init(isBusy: { [drawing] in drawing.hasWork }))
    private var hotKeys: GlobalHotKeyCenter?
    /// Open Settings makes Spotty a regular app, so the window gets a Dock icon, a Cmd-Tab entry,
    /// and the app menu, and window switchers list it like any other window.
    var settingsIsOpen = false {
        didSet { updateActivationPolicy() }
    }
    /// macOS shows its Accessibility prompt once, on first launch, when a default needs it.
    private static let accessibilityRequestedKey = "accessibilityRequested"
    #if DEBUG
    private var installedLaunchObservation: NSKeyValueObservation?
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 700])
        guard NSClassFromString("XCTestCase") == nil else { return }
        #if DEBUG
        keepOneSpottyRunning()
        #endif
        observePreferences()
        BackgroundCursor.enable()
        hotKeys = GlobalHotKeyCenter(registry: commands) { [weak self] in self?.drawing.handle($0) }
        hotKeys?.start()
        inputTap.start()
        // Creating the updater starts Sparkle's schedule; the menu bar may have created it already.
        _ = updater
        if commands.needsEventTap, !inputTap.isTrusted, !UserDefaults.standard.bool(forKey: Self.accessibilityRequestedKey) {
            UserDefaults.standard.set(true, forKey: Self.accessibilityRequestedKey)
            inputTap.requestAccess()
        }
    }

    #if DEBUG
    /// Spotty Dev and the installed Spotty share global shortcuts, so only the one opened last keeps
    /// running. Launching Spotty Dev quits the installed build, and launching the installed build
    /// quits Spotty Dev. Only Debug builds carry this, so the installed build has no launch-time checks.
    private func keepOneSpottyRunning() {
        let installedID = "local.markus.Spotty"
        NSRunningApplication.runningApplications(withBundleIdentifier: installedID).forEach { $0.terminate() }
        installedLaunchObservation = NSWorkspace.shared.observe(\.runningApplications, options: [.new]) { _, change in
            guard change.newValue?.contains(where: { $0.bundleIdentifier == installedID }) == true else { return }
            // Quit from the next run loop pass, outside the KVO callback.
            RunLoop.main.perform { MainActor.assumeIsolated { NSApp.terminate(nil) } }
        }
    }
    #endif

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationDidBecomeActive(_ notification: Notification) { inputTap.refreshTrust() }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NSApp.activate()
        // Open Settings through its app menu command, the one bridge from AppKit to the SwiftUI window.
        if let menu = NSApp.mainMenu?.items.compactMap(\.submenu).first(where: { menu in
            menu.items.contains { $0.keyEquivalent == "," && $0.keyEquivalentModifierMask.contains(.command) }
        }), let index = menu.items.firstIndex(where: { $0.keyEquivalent == "," && $0.keyEquivalentModifierMask.contains(.command) }) {
            menu.performActionForItem(at: index)
        }
        return false
    }

    func applicationWillTerminate(_ notification: Notification) { hotKeys?.stop() }

    private func observePreferences() {
        withObservationTracking {
            NSApp.appearance = preferences.general.appearance.nsAppearance
            updateActivationPolicy()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observePreferences() }
        }
    }

    private func updateActivationPolicy() {
        // Read the preference unconditionally so preference observation keeps tracking it.
        let preferred = preferences.general.activationPolicy
        let policy = settingsIsOpen ? .regular : preferred
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
        // Activate after becoming a regular app so Settings comes forward with the app menu. Only
        // Settings activates, so a login launch with the Dock icon on doesn't take focus.
        if settingsIsOpen { NSApp.activate() }
    }
}
