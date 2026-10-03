import SwiftUI

@main
struct SpottyApp: App {
    @NSApplicationDelegateAdaptor(SpottyApplicationDelegate.self) private var delegate

    var body: some Scene {
        // A window rather than a Settings scene, which SwiftUI always keeps at a fixed size.
        Window("Settings", id: SettingsView.windowID) {
            SettingsView(preferences: delegate.preferences, commands: delegate.commands, inputTap: delegate.inputTap)
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
        MenuBarExtra("Spotty", image: "MenuBarIcon", isInserted: Binding(
            get: { delegate.preferences.general.showsMenuBarIcon },
            set: { delegate.preferences.general.showsMenuBarIcon = $0 })) {
            SpottyMenu(drawing: delegate.drawing, inputTap: delegate.inputTap)
        }
    }
}

/// The menu bar menu. Drawing items toggle like a tap of their shortcut.
private struct SpottyMenu: View {
    let drawing: DrawingController
    let inputTap: InputTap

    var body: some View {
        let commands = drawing.commands
        Button(drawing.isDrawing ? "Stop Drawing" : "Draw") { drawing.toggle() }
            .keyboardShortcut(commands.shortcut(for: .draw)?.keyboardShortcut)
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
    private var hotKeys: GlobalHotKeyCenter?
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
            RunLoop.main.perform { NSApp.terminate(nil) }
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
            let policy = preferences.general.activationPolicy
            if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
        } onChange: { [weak self] in
            Task { @MainActor in self?.observePreferences() }
        }
    }
}
