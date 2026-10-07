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
        case .actions:
            EmptyView()
        case .whileDrawing:
            Text("While drawing is on, Escape stops, ⌘Z or Delete removes the last drawing, and ⌘⌫ clears all. Shift draws straight lines, 45° arrows, and squares.")
        }
    }

    /// The title and recorders share one line. Below them goes at most one note: a problem, else
    /// missing Accessibility, else what the command does when its name doesn't say enough.
    /// Global commands show a second recorder for an extra shortcut, such as a mouse button.
    private func row(_ id: CommandID) -> some View {
        let problem = id.slots.lazy.compactMap({ problems[$0] }).first?.message
            ?? (id.slots.contains(where: commands.registrationFailures.contains)
                ? "Another app or macOS already uses this shortcut. Choose a different one." : nil)
        let needsAccess = problem == nil && id.isGlobal && !inputTap.isTrusted
            && id.slots.contains(where: { commands.shortcut(for: $0)?.needsEventTap == true })
        let row = HStack {
            if let tool = id.tool {
                // A fixed icon column, so tool names line up whatever the symbol's width.
                Label { Text(id.title) } icon: { Image(systemName: tool.symbol).frame(width: 20) }
            } else {
                Text(title(for: id))
            }
            Spacer()
            ForEach(id.slots, id: \.self) { slot in
                ShortcutRecorder(commands: commands, slot: slot) { problems[slot] = $0 }
                    .fixedSize()
            }
        }
        let note = id == .toggleDrawing
            ? "Toggle Drawing turns drawing on with the same tool as Draw, without holding. Press it again or Escape to stop." : nil
        // Each modifier gets nil unless the ones before it do, so the row never gets two notes.
        return row
            .settingsRowWarning(problem)
            .settingsRowWarning(needsAccess ? "Needs Accessibility access." : nil) {
                Button("Allow…") { inputTap.requestAccess() }.controlSize(.small)
            }
            .settingsRowNote(problem == nil && !needsAccess ? note : nil)
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
