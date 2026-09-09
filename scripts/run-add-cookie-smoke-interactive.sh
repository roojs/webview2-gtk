#!/usr/bin/env bash
# Run webview2gtk-add-cookie smokes in the interactive Windows session.
# SSH/session 0 has no Win32 desktop (GUI segfaults); schtasks /IT is required.
#
# Exit 0 = all TEST_PASS. Exit 1 = any TEST_FAIL.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

test -f build/webview2gtk-add-cookie.exe

OUT_DIR="${ROOT}/portable-demos"
mkdir -p "${OUT_DIR}"
bash "${ROOT}/scripts/copy-exe-runtime-dlls.sh" \
	build/webview2gtk-add-cookie.exe "${OUT_DIR}" \
	build/vendor/webview2/x64/WebView2Loader.dll

run_one() {
	local flag="$1"
	local task="$2"
	local log="$3"
	local bat="$4"
	local wait_secs="${5:-45}"

	rm -f "${log}"
	cat > "${bat}" << EOF
@echo off
set LOG=%LOCALAPPDATA%\\Temp\\$(basename "${log}")
cd /d C:\\msys64\\tmp\\webview2-gtk\\portable-demos
set "FONTCONFIG_FILE=%~dp0etc\\fonts\\fonts.conf"
set "XDG_DATA_DIRS=%~dp0share"
echo starting > "%LOG%"
webview2gtk-add-cookie.exe ${flag} >> "%LOG%" 2>&1
echo exit=%ERRORLEVEL% >> "%LOG%"
EOF

	schtasks //Delete //TN "${task}" //F >/dev/null 2>&1 || true
	schtasks //Create //TN "${task}" \
		//TR "C:\\msys64\\tmp\\webview2-gtk\\portable-demos\\$(basename "${bat}")" \
		//SC ONCE //ST 23:59 //F //IT
	schtasks //Run //TN "${task}"
	echo "task ${task} started — waiting for ${log}"
	for _ in $(seq 1 "${wait_secs}"); do
		if [[ -f "${log}" ]] && grep -qE 'TEST_PASS|TEST_FAIL|^exit=' "${log}" 2>/dev/null; then
			break
		fi
		sleep 1
	done
	schtasks //Delete //TN "${task}" //F >/dev/null 2>&1 || true

	echo "--- ${flag} log ---"
	cat "${log}" 2>&1 || echo NO_LOG
	if ! grep -q TEST_PASS "${log}" 2>/dev/null; then
		echo "SMOKE_FAIL (${flag})"
		return 1
	fi
	echo "SMOKE_PASS (${flag})"
	return 0
}

LOG_ATTACH=/c/Users/Alan/AppData/Local/Temp/webview2gtk-add-cookie-smoke.log
LOG_MIRROR=/c/Users/Alan/AppData/Local/Temp/webview2gtk-add-cookie-mirror-smoke.log
LOG_CHANGED=/c/Users/Alan/AppData/Local/Temp/webview2gtk-add-cookie-changed-smoke.log
LOG_REPLACE=/c/Users/Alan/AppData/Local/Temp/webview2gtk-add-cookie-replace-startup-smoke.log
LOG_PERSIST=/c/Users/Alan/AppData/Local/Temp/webview2gtk-add-cookie-persist-smoke.log
fail=0
run_one --smoke WebView2GtkAddCookieSmoke "${LOG_ATTACH}" \
	"${OUT_DIR}/run-add-cookie-smoke.bat" || fail=1
run_one --smoke-mirror WebView2GtkAddCookieMirrorSmoke "${LOG_MIRROR}" \
	"${OUT_DIR}/run-add-cookie-mirror-smoke.bat" || fail=1
run_one --smoke-changed WebView2GtkAddCookieChangedSmoke "${LOG_CHANGED}" \
	"${OUT_DIR}/run-add-cookie-changed-smoke.bat" || fail=1
run_one --smoke-replace-startup WebView2GtkAddCookieReplaceStartupSmoke "${LOG_REPLACE}" \
	"${OUT_DIR}/run-add-cookie-replace-startup-smoke.bat" 75 || fail=1
run_one --smoke-persist WebView2GtkAddCookiePersistSmoke "${LOG_PERSIST}" \
	"${OUT_DIR}/run-add-cookie-persist-smoke.bat" || fail=1

if [[ "${fail}" -eq 0 ]]; then
	echo SMOKE_PASS
	exit 0
fi
echo SMOKE_FAIL
exit 1
