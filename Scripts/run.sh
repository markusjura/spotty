#!/bin/zsh
# Switches the running Spotty between the development build and the installed one.
# Usage:
#   Scripts/run.sh dev        # build Debug, quit any running Spotty, launch the Debug build
#   Scripts/run.sh installed  # quit any running Spotty, launch /Applications/Spotty.app
# Both builds share preferences and global shortcuts, so only one runs at a time.
set -euo pipefail
cd "${0:A:h:h}"

bundle_id=local.markus.Spotty
fail() { print -u2 "$1"; exit 1 }

case "${1:-}" in
  dev)
    app="$PWD/.build/acceptance-tests/Build/Products/Debug/Spotty.app"
    # Build before quitting, so a failed build leaves the running app alone. Tests use the same
    # derived data, so a build after a test run is incremental.
    xcodebuild -quiet -project Spotty.xcodeproj -scheme Spotty -configuration Debug \
      -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/acceptance-tests build
    ;;
  installed)
    app=/Applications/Spotty.app
    [[ -d "$app" ]] || fail "$app is missing. Install a build with Scripts/install.sh first."
    ;;
  *) fail "Usage: Scripts/run.sh dev | installed" ;;
esac

if pgrep -xq Spotty; then
  osascript -e "tell application id \"$bundle_id\" to quit"
  # Quit is immediate; allow a moment for the process to exit.
  for _ in {1..75}; do pgrep -xq Spotty || break; sleep 0.2; done
  pgrep -xq Spotty && fail "Spotty didn't quit within 15 s. Quit it, then retry."
fi

open "$app"
print "Launched $app ($(/usr/bin/defaults read "$app/Contents/Info" CFBundleShortVersionString) build $(/usr/bin/defaults read "$app/Contents/Info" CFBundleVersion))"
