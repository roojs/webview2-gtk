#!/usr/bin/env bash
# Run webview2gtk-smoke-hidden-stack --google in the interactive Windows session.
# Gate for docs/bugs/2026-08-28-win32atspi-hidden-stack-host-missing-document.md
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

test -f build/webview2gtk-smoke-hidden-stack.exe

OUT_DIR="${ROOT}/portable-demos"
mkdir -p "${OUT_DIR}"
cp -f build/webview2gtk-smoke-hidden-stack.exe "${OUT_DIR}/"
cp -f build/vendor/webview2/x64/WebView2Loader.dll "${OUT_DIR}/" 2>/dev/null || true
if [[ ! -f "${OUT_DIR}/libgtk-4-1.dll" && -x "${ROOT}/scripts/copy-exe-runtime-dlls.sh" ]]; then
	"${ROOT}/scripts/copy-exe-runtime-dlls.sh" \
		build/webview2gtk-smoke-hidden-stack.exe "${OUT_DIR}" \
		build/vendor/webview2/x64/WebView2Loader.dll
fi

LOG=/c/Users/Alan/AppData/Local/Temp/webview2gtk-hidden-stack-smoke.log
rm -f "${LOG}"

BAT="${OUT_DIR}/run-hidden-stack-smoke.bat"
cat > "${BAT}" << 'EOF'
@echo off
set LOG=%LOCALAPPDATA%\Temp\webview2gtk-hidden-stack-smoke.log
cd /d C:\msys64\tmp\webview2-gtk\portable-demos
set "FONTCONFIG_FILE=%~dp0etc\fonts\fonts.conf"
set "XDG_DATA_DIRS=%~dp0share"
echo starting > "%LOG%"
webview2gtk-smoke-hidden-stack.exe --google >> "%LOG%" 2>&1
echo exit=%ERRORLEVEL% >> "%LOG%"
EOF

schtasks //Delete //TN WebView2GtkHiddenStackSmoke //F >/dev/null 2>&1 || true
schtasks //Create //TN WebView2GtkHiddenStackSmoke \
	//TR "C:\\msys64\\tmp\\webview2-gtk\\portable-demos\\run-hidden-stack-smoke.bat" \
	//SC ONCE //ST 23:59 //F //IT
schtasks //Run //TN WebView2GtkHiddenStackSmoke
echo "task started — waiting for ${LOG}"
for _ in $(seq 1 90); do
	if [[ -f "${LOG}" ]] && grep -qE 'VERDICT=|DIAG_DONE|DIAG_FAIL|^exit=' "${LOG}" 2>/dev/null; then
		break
	fi
	sleep 1
done
schtasks //Delete //TN WebView2GtkHiddenStackSmoke //F >/dev/null 2>&1 || true

echo "--- log ---"
cat "${LOG}" 2>&1 || echo NO_LOG
if grep -q 'VERDICT=HIDDEN_OK' "${LOG}" 2>/dev/null && grep -q 'PICK OK' "${LOG}" 2>/dev/null; then
	echo SMOKE_PASS
	exit 0
fi
echo SMOKE_FAIL
exit 1
