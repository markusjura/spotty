# Project instructions

This file documents guidance for agents working in this repository. Record only non-obvious pitfalls, surprises, and constraints of the workflow and tools, and add new ones when you discover them. Explain code pitfalls in a comment where they apply, not here.

Spotty is Shotty's sibling. Keep shared patterns (Settings layout, `CommandRegistry`, `ShortcutRecorder`, `AppPreferences`, `Chrome` and `Bar` tokens, scripts) consistent with `~/workspace/shotty` unless Spotty needs something different.

## Commands

- `Scripts/run.sh dev` builds and relaunches Spotty Dev. Run it after every successful change, so the running app matches the code.
- `Scripts/run.sh installed` switches back to the installed Spotty.
- `Scripts/test.sh [TestClass]` runs all unit tests or one class.
- `Scripts/log.sh` streams Spotty's log: shortcut events and drawing mode changes.
- Run `Scripts/release.sh` and `Scripts/publish.sh` only when I ask.
- In a new worktree, run `./.worktree-setup.sh` once if the build fails with "Signing for Spotty requires a development team". It links `Local.xcconfig` from the main checkout, and not every worktree tool runs it.

## Verifying drawing

Computer Use cannot hold a key or mouse button while dragging, which every hold-to-draw check needs. `Scripts/ui/spotty-ui run "<steps>"` posts held modifiers, keys, drags, and mouse buttons from one process, and `Scripts/ui/spotty-ui windows` lists the windows of Spotty Dev when it runs, else of the installed Spotty. The overlay is the full-display window on a layer near `CGWindowLevelForKey(.cursorWindow)`. Capture it with `screencapture -x -o -l <id>`. Run the tool without arguments for usage.

- Each `run` starts with no modifiers held, so `mods` in a later `run` releases nothing and Spotty stays in its held gesture. Hold and release modifiers within one `run`.
- Posted input moves the real pointer and types for real. Only use it while the Mac is unlocked and nobody is using it.
- Never post input while Computer Use shows its "ChatGPT is Using Your Mac" shield. The first posted key dismisses the shield and drops the Mac to the real lock screen, where further keys type into the password field.
- Modifier-only and mouse button shortcuts need Accessibility for the build that runs. Grants follow the designated requirement, which includes the bundle ID, so Spotty Dev needs its own grant once. It then survives rebuilds signed with the same identity.

### Menu bar menu

System Events opens the menu without moving the pointer: `osascript -e 'tell application "System Events" to tell process "Spotty Dev" to click menu bar item 1 of menu bar 2' &`. The menu is the layer 101 window in `spotty-ui windows`. Close it with `perform action "AXCancel" of menu 1 of menu bar item 1 of menu bar 2`, or click a `menu item "<title>" of menu 1 …` to run it.

- `click` on the menu bar item toggles, so a second one closes an open menu.
- The first use from a new host app shows macOS's Automation prompt for System Events, and the commands block until I answer it.

### Clean up

If the task was only your own verification, run `Scripts/run.sh installed`; otherwise leave Spotty Dev running for me.
