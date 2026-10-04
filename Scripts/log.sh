#!/bin/zsh
# Streams the log of whichever Spotty runs: shortcut events and drawing mode changes.
# Usage: Scripts/log.sh
# The full path matters in zsh, where plain `log` is a builtin.
exec /usr/bin/log stream --level debug --predicate 'subsystem == "local.markus.Spotty"'
