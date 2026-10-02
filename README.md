# Spotty

A native macOS screen highlighter tailored to Markus's workflow, from the same family as Shotty. Hold a shortcut, draw on the screen, let go. No mode to enter first and no mode to leave afterwards.

## Using it

Every drawing shortcut works two ways:

- Hold it to draw until you let go. Each drawing fades 2 seconds after you finish it, adjustable in Settings > Drawing.
- Tap it to keep drawing on. Tap it again, press Escape, or click Done to stop.

The defaults, all changeable in Settings > Shortcuts:

| Shortcut | Action |
|----------|--------|
| ⌃⇧ | Draw with the last used tool, or the start tool set in Settings > Drawing |
| None | A second Draw shortcut, such as a mouse button, alongside the keyboard one |
| ⌃⇧P, ⌃⇧H, ⌃⇧A, ⌃⇧R, ⌃⇧O, ⌃⇧S | Draw with the pen, highlighter, arrow, rectangle, ellipse, or spotlight |
| ⌃⇧Z | Undo the last drawing |
| ⌃⇧⌫ | Clear all drawings |

While holding one drawing shortcut, press another to switch tools: hold ⌃⇧, press A, and drag an arrow. Holding a mouse button shortcut and moving the mouse draws, no left click needed. While holding it, the plain letters P, H, A, R, O, and S switch tools, because your hand is off the modifiers. While drawing is toggled on, the plain letters P, H, A, R, O, and S pick tools, ⌘Z or Delete removes the last drawing, ⌘⌫ clears everything, and a toolbar at the top of the screen offers the tools and colors. Shift draws straight lines, 45° arrows, squares, and circles, unless Shift is part of the shortcut you are holding.

A shortcut can be a key with modifiers, a function key on its own (handy for mouse buttons remapped to F13 to F20), two or more modifiers alone, or a middle or side mouse button. Spotty swallows a bound mouse button, so binding Mouse 4 never also means Back in your browser.

Highlighter strokes that are nearly straight snap to a straight line, so highlighting a line of text with a mouse looks clean. Spotlights dim everything else on that display.

## Build and test

Requires an Apple Silicon Mac, macOS 26 or later, Xcode 27, and the existing Apple Development signing identity shared with Shotty. On another Mac, import that identity's certificate and private key instead of letting Xcode create a new certificate, so every Mac signs with the same designated requirement. Create a gitignored `Local.xcconfig` in the repository root containing `DEVELOPMENT_TEAM = YOUR_TEAM_ID`. The shared project includes it through `Config/Signing.xcconfig`; no certificate or private key belongs in the repository.

Open `Spotty.xcodeproj` and select the shared Spotty scheme, or run:

```sh
Scripts/build.sh
xcodebuild -project Spotty.xcodeproj -scheme Spotty -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/acceptance-tests test
Scripts/run.sh dev
```

`Scripts/build.sh` builds the signed Release app at `.build/Build/Products/Release/Spotty.app`. `Scripts/run.sh dev` rebuilds the Debug app and relaunches it; `Scripts/run.sh installed` switches back to `/Applications/Spotty.app`. The target uses Hardened Runtime, no App Sandbox, and no entitlements. This is private Apple Development signing, not a notarized Developer ID release, so a copied build may not launch as trusted on another Mac.

`Scripts/GenerateAppIcon.swift` draws the app icon. Run `swift Scripts/GenerateAppIcon.swift` after changing it.

## Package, install, and roll back

Set `MARKETING_VERSION` and increase `CURRENT_PROJECT_VERSION` in the Spotty target, commit, and push to `main`, then package:

```sh
Scripts/package.sh
```

It refuses to run unless the working tree is clean and `HEAD` is `origin/main`, so each build number names one pushed commit. It builds Release, refuses to continue unless `codesign --verify --deep --strict` passes and the bundle ID is `local.markus.Spotty`, and writes to `.build/releases/`:

- `Spotty-<version>-<build>-<commit>.zip`, created with `ditto` so the signature survives.
- A `.sha256` checksum beside it.
- A `.txt` record of the signing authority, team, designated requirement, and entitlements.

Install on the same Mac:

1. Quit Spotty from its menu. The installer refuses to run while Spotty is running; it does not quit the app for you.
2. Run `Scripts/install.sh .build/releases/Spotty-<version>-<build>-<commit>.zip`.

The installer checks the checksum when the `.sha256` file is present, verifies the signature and bundle ID, and warns before installing a build whose designated requirement differs from the installed one, because macOS ties permission grants to it. It replaces `/Applications/Spotty.app` by renaming and keeps the replaced build at `~/Library/Application Support/Spotty Installer/Spotty.previous.app`. `Scripts/install.sh --rollback` swaps the two. Settings in UserDefaults are never touched.

## Fleet

Install on any fleet Mac as above. Fleet sync from `markusjura/mac-settings` then observes the newer build in `/Applications`, archives it, and installs it on the other Macs within minutes. It quits a running Spotty gracefully and reopens it afterwards. Fleet refuses builds whose designated requirement differs from the one pinned in its policy. Check progress with `fleet status` (`spotty.activation`). Fleet never lowers its target, so it reinstalls the newer build within minutes of `install.sh --rollback`. Set `spotty.enabled` to false in the fleet policy first, or fix forward with a higher build number.

A Mac that receives Spotty for the first time leaves it closed. Open it once there and approve the Accessibility prompt.

## Permissions

Grant permissions to the installed `/Applications/Spotty.app`, not to a build in `.build`. Grants are per Mac; signing does not carry them to another machine.

- **Accessibility** is needed only for modifier-only shortcuts, such as the default ⌃⇧, and for mouse button shortcuts. Spotty asks once on first launch. Shortcuts with a key, such as ⌃⇧A, work without it, through the same hotkey API Shotty uses.
- Screen Recording, Input Monitoring, and every other permission are not needed. Spotty draws over the screen; it never reads it.

Keeping the bundle ID and signing identity stable keeps the grant across updates.
