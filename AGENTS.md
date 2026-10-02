# Project instructions

This file documents guidance for agents working in this repository. Record only non-obvious pitfalls, surprises, and constraints, and add new ones when you discover them.

Spotty is Shotty's sibling. Keep shared patterns (Settings layout, `CommandRegistry`, `ShortcutRecorder`, `AppPreferences`, `Chrome` and `Bar` tokens, scripts) consistent with `~/workspace/shotty` unless Spotty needs something different.

## Commands

Use the narrowest scope that validates the change. Debug builds and tests share this base command:

```sh
xcodebuild -project Spotty.xcodeproj -scheme Spotty -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/acceptance-tests
```

- `<base> build` builds the Debug app without launching it.
- `<base> test -only-testing:SpottyTests/<TestClass>` runs one test class.
- `<base> test` runs all unit tests in a few seconds. It quits a running Debug build.
- `Scripts/run.sh dev` rebuilds and relaunches the Debug build.
- `osascript -e 'tell application id "local.markus.Spotty" to quit'` quits whichever build is running.
- `/usr/bin/log stream --level debug --predicate 'subsystem == "local.markus.Spotty"'` shows shortcut events and drawing mode changes. In zsh, plain `log` is a builtin.

Signing needs the login keychain, which is locked in plain SSH sessions. There `codesign` fails with `errSecInternalComponent`. Build from the Mac's GUI session instead.

Package and install only when I ask. Bump `CURRENT_PROJECT_VERSION` first, commit, push to `main`, quit Spotty, then run `Scripts/package.sh` and `Scripts/install.sh .build/releases/<zip>`. `package.sh` refuses anything but a clean `HEAD` equal to `origin/main`. Fleet sync then installs the build on the other Macs; don't copy it there yourself.

## Verifying drawing

Computer Use cannot hold a key or mouse button while dragging, which every hold-to-draw check needs. `Scripts/ui/spotty-ui run "<steps>"` posts held modifiers, keys, drags, and mouse buttons from one process, and `Scripts/ui/spotty-ui windows` lists Spotty's windows. The overlay is the full-display window on a layer near `CGWindowLevelForKey(.cursorWindow)`. Capture it with `screencapture -x -o -l <id>`. Run the tool without arguments for usage.

- Posted input moves the real pointer and types for real. Only use it while the Mac is unlocked and nobody is using it.
- Never post input while Computer Use shows its "ChatGPT is Using Your Mac" shield. The first posted key dismisses the shield and drops the Mac to the real lock screen, where further keys type into the password field.
- Modifier-only and mouse button shortcuts need Accessibility for the build that runs. Grants follow the designated requirement, so they survive rebuilds signed with the same identity.

## AppKit pitfalls

- Spotty never activates while drawing. The overlay panels are non-activating, take key focus only while drawing is toggled on, and accept the first click, so the app under the pointer keeps focus and its window stays active.
- Carbon hotkeys repeat their press event while held. `GlobalHotKeyCenter` reports only the first press and the release.
