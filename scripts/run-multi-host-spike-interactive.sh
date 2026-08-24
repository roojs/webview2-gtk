#!/usr/bin/env bash
# Run webview2gtk-multi-host-spike --smoke in the interactive Windows session.
# 4.5 kill switch: two controllers on one HWND.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

test -f build/webview2gtk-multi-host-spike.exe

OUT_DIR="${ROOT}/portable-demos"
mkdir -p "${OUT_DIR}"
cp -f build/webview2gtk-multi-host-spike.exe "${OUT_DIR}/"
cp -f build/vendor/webview2/x64/WebView2Loader.dll "${OUT_DIR}/" 2>/dev/null || true

LOG=/c/Users/Alan/AppData/Local/Temp/webview2gtk-multi-host-spike.log
rm -f "${LOG}"

BAT="${OUT_DIR}/run-multi-host-spike.bat"
cat > "${BAT}" << 'EOF'
@echo off
set LOG=%LOCALAPPDATA%\Temp\webview2gtk-multi-host-spike.log
cd /d C:\msys64\tmp\webview2-gtk\portable-demos
echo starting > "%LOG%"
webview2gtk-multi-host-spike.exe --smoke >> "%LOG%" 2>&1
echo exit=%ERRORLEVEL% >> "%LOG%"
EOF

schtasks //Delete //TN WebView2GtkMultiHostSpike //F >/dev/null 2>&1 || true
schtasks //Create //TN WebView2GtkMultiHostSpike \
	//TR "C:\\msys64\\tmp\\webview2-gtk\\portable-demos\\run-multi-host-spike.bat" \
	//SC ONCE //ST 23:59 //F //IT
schtasks //Run //TN WebView2GtkMultiHostSpike
echo "task started — waiting for ${LOG}"
for _ in $(seq 1 45); do
	if [[ -f "${LOG}" ]] && grep -qE 'SPIKE_PASS|SPIKE_FAIL|^exit=' "${LOG}" 2>/dev/null; then
		break
	fi
	sleep 1
done
schtasks //Delete //TN WebView2GtkMultiHostSpike //F >/dev/null 2>&1 || true

echo "--- log ---"
cat "${LOG}" 2>&1 || echo NO_LOG
if grep -q SPIKE_PASS "${LOG}" 2>/dev/null; then
	echo SPIKE_PASS
	exit 0
fi
echo SPIKE_FAIL
exit 1
