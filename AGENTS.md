# Project instructions

This file documents guidance for agents working in this repository. Record only non-obvious pitfalls, surprises, and constraints of the workflow and tools, and add new ones when you discover them. Explain code pitfalls in a comment where they apply, not here.

Spotty is Shotty's sibling. Keep shared patterns (Settings layout, `CommandRegistry`, `ShortcutRecorder`, `AppPreferences`, `Chrome` and `Bar` tokens, scripts) consistent with `~/workspace/shotty` unless Spotty needs something different.

## Commands

Use the narrowest scope that validates the change. Debug builds and tests share this base command:

```sh
xcodebuild -project Spotty.xcodeproj -scheme Spotty -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/acceptance-tests
```

- `<base> build` builds the Debug app without launching it.
- `<base> test -only-testing:SpottyTests/<TestClass>` runs one test class.
- `<base> test` runs all unit tests in a few seconds. It quits a running Spotty Dev.
- `Scripts/run.sh dev` rebuilds Spotty Dev, the Debug build, and relaunches it from `~/Applications/Spotty Dev.app`. Spotlight skips `.build`, so only that copy shows up in Spotlight, Raycast, and System Settings. Every checkout and worktree replaces the same copy. `Scripts/run.sh installed` switches back to `/Applications/Spotty.app`.
- Spotty Dev has its own bundle ID, `local.markus.Spotty.dev`, plus its own preferences and permission grants. Only one of the two runs: Spotty Dev quits the installed build when it launches and quits itself when the installed build launches.
- `osascript -e 'tell application id "local.markus.Spotty.dev" to quit'` quits Spotty Dev. Use `local.markus.Spotty` for the installed build.
- `/usr/bin/log stream --level debug --predicate 'subsystem == "local.markus.Spotty"'` shows shortcut events and drawing mode changes from either build. In zsh, plain `log` is a builtin.

Signing needs the login keychain, which is locked in plain SSH sessions. There `codesign` fails with `errSecInternalComponent`. Build from the Mac's GUI session instead.

Package and install only when I ask. Bump `CURRENT_PROJECT_VERSION` first (never lower it, installs are identified by build number), commit, push to `main`, quit Spotty, then run `Scripts/package.sh` and `Scripts/install.sh .build/releases/<zip>`. `package.sh` refuses anything but a clean `HEAD` equal to `origin/main`. Fleet sync then installs the build on the other Macs; don't copy it there yourself.

Keep `MARKETING_VERSION` at `0.1.0`. Only I change it, when I call a release. Never bump it as part of a feature, fix, or build.

## Verifying drawing

Computer Use cannot hold a key or mouse button while dragging, which every hold-to-draw check needs. `Scripts/ui/spotty-ui run "<steps>"` posts held modifiers, keys, drags, and mouse buttons from one process, and `Scripts/ui/spotty-ui windows` lists the windows of Spotty Dev when it runs, else of the installed Spotty. The overlay is the full-display window on a layer near `CGWindowLevelForKey(.cursorWindow)`. Capture it with `screencapture -x -o -l <id>`. Run the tool without arguments for usage.

- Each `run` starts with no modifiers held, so `mods` in a later `run` releases nothing and Spotty stays in its held gesture. Hold and release modifiers within one `run`.
- Posted input moves the real pointer and types for real. Only use it while the Mac is unlocked and nobody is using it.
- Never post input while Computer Use shows its "ChatGPT is Using Your Mac" shield. The first posted key dismisses the shield and drops the Mac to the real lock screen, where further keys type into the password field.
- Modifier-only and mouse button shortcuts need Accessibility for the build that runs. Grants follow the designated requirement, which includes the bundle ID, so Spotty Dev needs its own grant once. It then survives rebuilds signed with the same identity.
