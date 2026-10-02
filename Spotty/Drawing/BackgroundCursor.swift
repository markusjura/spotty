import AppKit

/// Lets Spotty set the cursor while another app is active, so drawing shows the plain arrow
/// instead of the app's cursor below, such as an I-beam over text, without taking focus. macOS
/// only honors cursor changes from the active app unless the connection opts in through the
/// private `SetsCursorInBackground` property. The symbols are looked up at runtime; if they ever
/// disappear, the cursor is whatever the app below sets.
enum BackgroundCursor {
    private typealias DefaultConnection = @convention(c) () -> Int32
    private typealias SetProperty = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32

    /// Call once at launch.
    static func enable() {
        guard let handle = dlopen(nil, RTLD_NOW),
              let connectionSymbol = dlsym(handle, "_CGSDefaultConnection"),
              let setSymbol = dlsym(handle, "CGSSetConnectionProperty") else { return }
        let connection = unsafeBitCast(connectionSymbol, to: DefaultConnection.self)()
        _ = unsafeBitCast(setSymbol, to: SetProperty.self)(connection, connection, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
    }
}
