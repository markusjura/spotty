#!/bin/zsh
# Runs the unit tests, all of them or one class.
# Usage: Scripts/test.sh [TestClass]
# The test host is a Spotty Dev build with the same bundle ID, so a running Spotty Dev quits for the
# run. It is relaunched afterwards. The installed Spotty keeps running.
set -euo pipefail
cd "${0:A:h:h}"

dev_running=$(lsappinfo find bundleid=local.markus.Spotty.dev)
result=0
Scripts/xcode.sh debug -quiet test ${1:+-only-testing:SpottyTests/$1} || result=$?
[[ -n "$dev_running" ]] && open ~/Applications/"Spotty Dev.app"
(( result == 0 )) && print "Tests passed."
exit $result
