#!/usr/bin/env bash
# Run webview2gtk-automation --smoke-stack in the interactive Windows session.
# SSH/session 0 has no Win32 desktop (GUI segfaults); schtasks /IT is required.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

test -f build/webview2gtk-automation.exe

OUT_DIR="${ROOT}/portable-demos"
mkdir -p "${OUT_DIR}"
cp -f build/webview2gtk-automation.exe "${OUT_DIR}/"
cp -f build/vendor/webview2/x64/WebView2Loader.dll "${OUT_DIR}/" 2>/dev/null || true
if [[ ! -f "${OUT_DIR}/libgtk-4-1.dll" && -x "${ROOT}/scripts/copy-exe-runtime-dlls.sh" ]]; then
	"${ROOT}/scripts/copy-exe-runtime-dlls.sh" \
		build/webview2gtk-automation.exe "${OUT_DIR}" \
		build/vendor/webview2/x64/WebView2Loader.dll
fi

LOG=/c/Users/Alan/AppData/Local/Temp/webview2gtk-automation-stack-smoke.log
rm -f "${LOG}"

BAT="${OUT_DIR}/run-auto-stack-smoke.bat"
cat > "${BAT}" << 'EOF'
@echo off
set LOG=%LOCALAPPDATA%\Temp\webview2gtk-automation-stack-smoke.log
cd /d C:\msys64\tmp\webview2-gtk\portable-demos
set "FONTCONFIG_FILE=%~dp0etc\fonts\fonts.conf"
set "XDG_DATA_DIRS=%~dp0share"
echo starting > "%LOG%"
webview2gtk-automation.exe --smoke-stack --inspector-port 19222 >> "%LOG%" 2>&1
echo exit=%ERRORLEVEL% >> "%LOG%"
EOF

schtasks //Delete //TN WebView2GtkAutomationStackSmoke //F >/dev/null 2>&1 || true
schtasks //Create //TN WebView2GtkAutomationStackSmoke \
	//TR "C:\\msys64\\tmp\\webview2-gtk\\portable-demos\\run-auto-stack-smoke.bat" \
	//SC ONCE //ST 23:59 //F //IT
schtasks //Run //TN WebView2GtkAutomationStackSmoke
echo "task started — waiting for ${LOG}"
for _ in $(seq 1 90); do
	if [[ -f "${LOG}" ]] && grep -qE 'STACK_SMOKE_PASS|STACK_SMOKE_FAIL|^exit=' "${LOG}" 2>/dev/null; then
		break
	fi
	sleep 1
done
schtasks //Delete //TN WebView2GtkAutomationStackSmoke //F >/dev/null 2>&1 || true

echo "--- log ---"
cat "${LOG}" 2>&1 || echo NO_LOG
if grep -q STACK_SMOKE_PASS "${LOG}" 2>/dev/null && grep -q "stack primary document" "${LOG}" 2>/dev/null; then
	echo SMOKE_PASS
	exit 0
fi
echo SMOKE_FAIL
exit 1
