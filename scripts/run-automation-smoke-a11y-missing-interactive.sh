#!/usr/bin/env bash
# Run the missing-UIA-document regression in the interactive Windows session.
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

LOG=/c/Users/Alan/AppData/Local/Temp/webview2gtk-automation-a11y-missing-smoke.log
rm -f "${LOG}"

BAT="${OUT_DIR}/run-auto-a11y-missing-smoke.bat"
cat > "${BAT}" << 'EOF'
@echo off
set LOG=%LOCALAPPDATA%\Temp\webview2gtk-automation-a11y-missing-smoke.log
cd /d C:\msys64\tmp\webview2-gtk\portable-demos
set "FONTCONFIG_FILE=%~dp0etc\fonts\fonts.conf"
set "XDG_DATA_DIRS=%~dp0share"
echo starting > "%LOG%"
webview2gtk-automation.exe --smoke-a11y-missing --inspector-port 19222 >> "%LOG%" 2>&1
echo exit=%ERRORLEVEL% >> "%LOG%"
EOF

schtasks //Delete //TN WebView2GtkAutomationA11yMissingSmoke //F >/dev/null 2>&1 || true
schtasks //Create //TN WebView2GtkAutomationA11yMissingSmoke \
	//TR "C:\\msys64\\tmp\\webview2-gtk\\portable-demos\\run-auto-a11y-missing-smoke.bat" \
	//SC ONCE //ST 23:59 //F //IT
schtasks //Run //TN WebView2GtkAutomationA11yMissingSmoke
echo "task started — waiting for ${LOG}"
for _ in $(seq 1 90); do
	if [[ -f "${LOG}" ]] && grep -qE 'A11Y_MISSING_PASS|A11Y_MISSING_FAIL|^exit=' "${LOG}" 2>/dev/null; then
		break
	fi
	sleep 1
done
schtasks //Delete //TN WebView2GtkAutomationA11yMissingSmoke //F >/dev/null 2>&1 || true

echo "--- log ---"
cat "${LOG}" 2>&1 || echo NO_LOG
if grep -q A11Y_MISSING_PASS "${LOG}" 2>/dev/null \
		&& grep -q 'a11y_missing_documents=1 target=0 sibling=1' "${LOG}" 2>/dev/null; then
	echo SMOKE_PASS
	exit 0
fi
echo SMOKE_FAIL
exit 1
