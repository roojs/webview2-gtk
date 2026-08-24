#!/usr/bin/env bash
# Run webview2gtk-paned-insert --smoke in the interactive Windows session.
# SSH/session 0 has no Win32 desktop (GUI segfaults); schtasks /IT is required.
#
# Exit 0 = TEST_PASS (page loaded). Exit 1 = TEST_FAIL (blank pane / never finished).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

test -f build/webview2gtk-paned-insert.exe

OUT_DIR="${ROOT}/portable-demos"
mkdir -p "${OUT_DIR}"
bash "${ROOT}/scripts/copy-exe-runtime-dlls.sh" \
	build/webview2gtk-paned-insert.exe "${OUT_DIR}" \
	build/vendor/webview2/x64/WebView2Loader.dll

LOG=/c/Users/Alan/AppData/Local/Temp/webview2gtk-paned-insert-smoke.log
rm -f "${LOG}"

BAT="${OUT_DIR}/run-paned-insert-smoke.bat"
cat > "${BAT}" << 'EOF'
@echo off
set LOG=%LOCALAPPDATA%\Temp\webview2gtk-paned-insert-smoke.log
cd /d C:\msys64\tmp\webview2-gtk\portable-demos
set "FONTCONFIG_FILE=%~dp0etc\fonts\fonts.conf"
set "XDG_DATA_DIRS=%~dp0share"
echo starting > "%LOG%"
webview2gtk-paned-insert.exe --smoke >> "%LOG%" 2>&1
echo exit=%ERRORLEVEL% >> "%LOG%"
EOF

schtasks //Delete //TN WebView2GtkPanedInsertSmoke //F >/dev/null 2>&1 || true
schtasks //Create //TN WebView2GtkPanedInsertSmoke \
	//TR "C:\\msys64\\tmp\\webview2-gtk\\portable-demos\\run-paned-insert-smoke.bat" \
	//SC ONCE //ST 23:59 //F //IT
schtasks //Run //TN WebView2GtkPanedInsertSmoke
echo "task started — waiting for ${LOG}"
for _ in $(seq 1 45); do
	if [[ -f "${LOG}" ]] && grep -qE 'TEST_PASS|TEST_FAIL|^exit=' "${LOG}" 2>/dev/null; then
		break
	fi
	sleep 1
done
schtasks //Delete //TN WebView2GtkPanedInsertSmoke //F >/dev/null 2>&1 || true

echo "--- log ---"
cat "${LOG}" 2>&1 || echo NO_LOG
if grep -q TEST_PASS "${LOG}" 2>/dev/null; then
	echo SMOKE_PASS
	exit 0
fi
echo SMOKE_FAIL
exit 1
