import ApplicationServices
import ServiceManagement
import SwiftUI

/// Status is read on appearance and whenever Spotty becomes active after a System Settings visit.
struct PermissionSettingsPane: View {
    let inputTap: InputTap
    @State private var loginStatus = SMAppService.mainApp.status

    var body: some View {
        Form {
            Section("Accessibility") {
                status(inputTap.isTrusted, granted: "Allowed", missing: "Not allowed")
                    .settingsRowNote("Needed only for modifier-only shortcuts, such as holding ⌃⇧, and for mouse button shortcuts. Shortcuts with a key work without it.")
                if !inputTap.isTrusted {
                    HStack {
                        Button("Request Access") { inputTap.requestAccess() }
                        Button("Open System Settings") { SystemSettingsLink.open(SystemSettingsLink.accessibility) }
                    }
                }
            }
            Section("Login item") {
                LabeledContent("Status") { Text(loginStatus.summary).settingsValue() }
                if loginStatus == .requiresApproval {
                    Button("Open Login Items Settings") { SMAppService.openSystemSettingsLoginItems() }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            inputTap.refreshTrust()
            loginStatus = SMAppService.mainApp.status
        }
    }

    /// A status row with an outlined green checkmark when granted, as in Raycast's settings, or a gray cross.
    /// Both glyphs are outlined circles of one size, so the row keeps its alignment when the status changes.
    private func status(_ ok: Bool, granted: String, missing: String) -> some View {
        LabeledContent("Status") {
            Label {
                Text(ok ? granted : missing)
            } icon: {
                Image(systemName: ok ? "checkmark.circle" : "xmark.circle")
                    .foregroundStyle(ok ? SettingsColor.success : SettingsColor.secondaryText)
            }
            .foregroundStyle(ok ? SettingsColor.primaryText : SettingsColor.secondaryText)
        }
    }
}

private extension SMAppService.Status {
    var summary: String {
        switch self {
        case .enabled: "Opens at login"
        case .requiresApproval: "Waiting for approval in System Settings"
        case .notRegistered: "Off"
        case .notFound: "Unavailable for this copy of Spotty"
        @unknown default: "Unknown"
        }
    }
}
