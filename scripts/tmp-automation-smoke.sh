#!/usr/bin/env bash
set -euo pipefail
cd /c/msys64/tmp/webview2-gtk
rm -f build/webview2gtk-automation.exe
ninja -C build webview2gtk-automation.exe
cd build
cp -f vendor/webview2/x64/WebView2Loader.dll . 2>/dev/null || true
./webview2gtk-automation.exe --smoke --inspector-port 19222 >automation-smoke.log 2>&1 || true
echo "EXIT=$?"
echo "---LOG---"
cat automation-smoke.log
if grep -q automation-started automation-smoke.log; then
	echo SMOKE_PASS
	exit 0
fi
echo SMOKE_FAIL
exit 1
