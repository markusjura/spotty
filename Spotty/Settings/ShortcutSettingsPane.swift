import SwiftUI

struct ShortcutSettingsPane: View {
    let commands: CommandRegistry
    let inputTap: InputTap
    let preferences: AppPreferences
    @State private var problems: [CommandID: ShortcutProblem] = [:]

    var body: some View {
        Form {
            ForEach(CommandGroup.allCases, id: \.self) { group in
                Section {
                    ForEach(group.commands, id: \.self, content: row)
                    Button("Restore \(group.title) Defaults") { report(commands.restoreDefaults(in: group), for: group.commands) }
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
            Text("Hold a shortcut to draw until you let go. Tap it to keep drawing on, and tap it again or press Escape to stop. While holding one, press another to switch tools, such as ⌃⇧ and then A. While holding a mouse button, press a tool letter alone, such as A.")
                .secondaryNote()
        case .actions:
            EmptyView()
        case .whileDrawing:
            Text("While drawing is on, Escape stops, ⌘Z or Delete removes the last drawing, and ⌘⌫ clears all. Shift draws straight lines, squares, and circles.")
                .secondaryNote()
        }
    }

    /// The title and recorder share one line; a note goes below them, so it never moves the recorder.
    private func row(_ id: CommandID) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if let tool = id.tool { Label(id.title, systemImage: tool.symbol) } else { Text(title(for: id)) }
                Spacer()
                ShortcutRecorder(commands: commands, command: id) { problems[id] = $0 }
                    .fixedSize()
            }
            if let problem = problems[id] {
                Label(problem.message, systemImage: "exclamationmark.triangle").secondaryNote()
            } else if commands.registrationFailures.contains(id) {
                Label("Another app or macOS already uses this shortcut. Choose a different one.", systemImage: "exclamationmark.triangle")
                    .secondaryNote()
            } else if id.isGlobal, commands.shortcut(for: id)?.needsEventTap == true, !inputTap.isTrusted {
                HStack {
                    Label("Needs Accessibility access.", systemImage: "exclamationmark.triangle").secondaryNote()
                    Button("Allow…") { inputTap.requestAccess() }.controlSize(.small)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// Draw names the tool it starts with.
    private func title(for id: CommandID) -> String {
        guard id == .draw || id == .drawAlternate else { return id.title }
        let title = preferences.drawing.startTool.map { "Draw with \($0.title)" } ?? "Draw with Last Tool"
        return id == .drawAlternate ? "\(title), Alternate" : title
    }

    private func report(_ result: [CommandID: ShortcutProblem], for ids: [CommandID]) {
        for id in ids { problems[id] = result[id] }
    }
}
