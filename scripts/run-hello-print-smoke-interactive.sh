#!/usr/bin/env bash
# Run webview2gtk-hello --smoke-print in the interactive Windows session.
# SSH/session 0 has no Win32 desktop (GUI segfaults); schtasks /IT is required.
#
# Exit 0 = TEST_PASS (PDF written). Page size and fonts are inspected after.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

test -f build/webview2gtk-hello.exe

OUT_DIR="${ROOT}/portable-demos"
mkdir -p "${OUT_DIR}"
bash "${ROOT}/scripts/copy-exe-runtime-dlls.sh" \
	build/webview2gtk-hello.exe "${OUT_DIR}" \
	build/vendor/webview2/x64/WebView2Loader.dll

PDF=/c/Users/Alan/AppData/Local/Temp/webview2gtk-print-repro.pdf
LOG=/c/Users/Alan/AppData/Local/Temp/webview2gtk-hello-print-smoke.log
rm -f "${LOG}" "${PDF}"

BAT="${OUT_DIR}/run-hello-print-smoke.bat"
cat > "${BAT}" << 'EOF'
@echo off
set LOG=%LOCALAPPDATA%\Temp\webview2gtk-hello-print-smoke.log
set PDF=%LOCALAPPDATA%\Temp\webview2gtk-print-repro.pdf
cd /d C:\msys64\tmp\webview2-gtk\portable-demos
set "FONTCONFIG_FILE=%~dp0etc\fonts\fonts.conf"
set "XDG_DATA_DIRS=%~dp0share"
echo starting > "%LOG%"
webview2gtk-hello.exe --smoke-print --output "%PDF%" >> "%LOG%" 2>&1
echo exit=%ERRORLEVEL% >> "%LOG%"
EOF

schtasks //Delete //TN WebView2GtkHelloPrintSmoke //F >/dev/null 2>&1 || true
schtasks //Create //TN WebView2GtkHelloPrintSmoke \
	//TR "C:\\msys64\\tmp\\webview2-gtk\\portable-demos\\run-hello-print-smoke.bat" \
	//SC ONCE //ST 23:59 //F //IT
schtasks //Run //TN WebView2GtkHelloPrintSmoke
echo "task started — waiting for ${LOG}"
for _ in $(seq 1 90); do
	if [[ -f "${LOG}" ]] && grep -qE 'TEST_PASS|TEST_FAIL|^exit=' "${LOG}" 2>/dev/null; then
		break
	fi
	sleep 1
done
schtasks //Delete //TN WebView2GtkHelloPrintSmoke //F >/dev/null 2>&1 || true

echo "--- log ---"
cat "${LOG}" 2>&1 || echo NO_LOG
if [[ -f "${PDF}" ]]; then
	cp -f "${PDF}" "${ROOT}/build/print-repro.pdf"
	echo "PDF ${PDF} ($(wc -c < "${PDF}") bytes) -> build/print-repro.pdf"
else
	echo "NO_PDF ${PDF}"
fi
if grep -q TEST_PASS "${LOG}" 2>/dev/null; then
	echo SMOKE_PASS
	exit 0
fi
echo SMOKE_FAIL
exit 1
