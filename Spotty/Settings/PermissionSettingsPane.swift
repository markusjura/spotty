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
                Text("Needed only for modifier-only shortcuts, such as holding ⌃⇧, and for mouse button shortcuts. Shortcuts with a key work without it.")
                    .settingsNote()
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

    /// A status row with a white checkmark on system green when granted, as in System Settings, or a gray cross.
    private func status(_ ok: Bool, granted: String, missing: String) -> some View {
        LabeledContent("Status") {
            Label {
                Text(ok ? granted : missing)
            } icon: {
                if ok {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color(nsColor: .systemGreen))
                } else {
                    Image(systemName: "xmark.circle").foregroundStyle(SettingsColor.secondaryText)
                }
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
