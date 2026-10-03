import SwiftUI

struct ShortcutSettingsPane: View {
    let commands: CommandRegistry
    let inputTap: InputTap
    let preferences: AppPreferences
    @State private var problems: [ShortcutSlot: ShortcutProblem] = [:]

    var body: some View {
        Form {
            ForEach(CommandGroup.allCases, id: \.self) { group in
                Section {
                    ForEach(group.commands, id: \.self, content: row)
                    Button("Restore \(group.title) Defaults") { report(commands.restoreDefaults(in: group), for: group.commands.flatMap(\.slots)) }
                } header: {
                    Text(group.title)
                } footer: {
                    footer(for: group)
                }
            }
        }
    }

    @ViewBuilder
    private func footer(for group: CommandGroup) -> some View {
        switch group {
        case .drawing:
            Text("Hold a shortcut to draw until you let go. Tap it to keep drawing on, and tap it again or press Escape to stop. While holding one, press another to switch tools, such as ⌃⇧ and then A. Add a second shortcut, such as a mouse button, in the right column. While holding a mouse button, press a tool letter alone.")
                .settingsNote()
        case .actions:
            EmptyView()
        case .whileDrawing:
            Text("While drawing is on, Escape stops, ⌘Z or Delete removes the last drawing, and ⌘⌫ clears all. Shift draws straight lines, 45° arrows, and squares.")
                .settingsNote()
        }
    }

    /// The title and recorders share one line; a note goes below them, so it never moves a recorder.
    /// Global commands show a second recorder for an extra shortcut, such as a mouse button.
    private func row(_ id: CommandID) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if let tool = id.tool { Label(id.title, systemImage: tool.symbol) } else { Text(title(for: id)) }
                Spacer()
                ForEach(id.slots, id: \.self) { slot in
                    ShortcutRecorder(commands: commands, slot: slot) { problems[slot] = $0 }
                        .fixedSize()
                }
            }
            if let problem = id.slots.lazy.compactMap({ problems[$0] }).first {
                Label(problem.message, systemImage: "exclamationmark.triangle").settingsNote()
            } else if id.slots.contains(where: commands.registrationFailures.contains) {
                Label("Another app or macOS already uses this shortcut. Choose a different one.", systemImage: "exclamationmark.triangle")
                    .settingsNote()
            } else if id.isGlobal, id.slots.contains(where: { commands.shortcut(for: $0)?.needsEventTap == true }), !inputTap.isTrusted {
                HStack {
                    Label("Needs Accessibility access.", systemImage: "exclamationmark.triangle").settingsNote()
                    Button("Allow…") { inputTap.requestAccess() }.controlSize(.small)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// Draw names the tool it starts with.
    private func title(for id: CommandID) -> String {
        guard id == .draw else { return id.title }
        return preferences.drawing.startTool.map { "Draw with \($0.title)" } ?? "Draw with Last Tool"
    }

    private func report(_ result: [ShortcutSlot: ShortcutProblem], for slots: [ShortcutSlot]) {
        for slot in slots { problems[slot] = result[slot] }
    }
}
