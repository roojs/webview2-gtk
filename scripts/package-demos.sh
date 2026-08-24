#!/usr/bin/env bash
# Bundle hello + browser demos with runtime DLLs (double-click / PowerShell safe).
#
#   ./scripts/package-demos.sh
#
# From PowerShell (one line):
#   C:\msys64\msys2_shell.cmd -defterm -no-start -ucrt64 -c 'cd /c/path/to/webview2-gtk && ./scripts/package-demos.sh'
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-${ROOT}/build}"
OUT_DIR="${OUT_DIR:-${ROOT}/dist-demos}"
LOADER="${WEBVIEW2_LOADER:-${BUILD_DIR}/vendor/webview2/x64/WebView2Loader.dll}"
COPY_DLLS="${ROOT}/scripts/copy-exe-runtime-dlls.sh"

case "$(uname -s 2>/dev/null)" in
MINGW*|MSYS*)
	for image in webview2gtk-hello.exe webview2gtk-browser.exe webview2gtk-automation.exe webview2gtk-cdp-attach.exe webview2gtk-paned-insert.exe; do
		taskkill //F //IM "${image}" >/dev/null 2>&1 || true
	done
	sleep 1
	;;
esac

for name in webview2gtk-hello.exe webview2gtk-browser.exe webview2gtk-automation.exe webview2gtk-cdp-attach.exe webview2gtk-paned-insert.exe; do
	if [[ ! -f "${BUILD_DIR}/${name}" ]]; then
		echo "package-demos: missing ${BUILD_DIR}/${name} — run: meson compile -C build" >&2
		exit 1
	fi
done

rm -rf "${OUT_DIR}"
mkdir -p "${OUT_DIR}"

"${COPY_DLLS}" "${BUILD_DIR}/webview2gtk-hello.exe" "${OUT_DIR}" "${LOADER}"
"${COPY_DLLS}" "${BUILD_DIR}/webview2gtk-browser.exe" "${OUT_DIR}" ""
"${COPY_DLLS}" "${BUILD_DIR}/webview2gtk-automation.exe" "${OUT_DIR}" ""
"${COPY_DLLS}" "${BUILD_DIR}/webview2gtk-cdp-attach.exe" "${OUT_DIR}" ""
"${COPY_DLLS}" "${BUILD_DIR}/webview2gtk-paned-insert.exe" "${OUT_DIR}" ""

# Fontconfig + default fonts (needed when not running inside UCRT64 shell).
MSYS_PREFIX="${MSYSTEM_PREFIX:-/ucrt64}"
if [[ -d "${MSYS_PREFIX}/etc/fonts" ]]; then
	mkdir -p "${OUT_DIR}/etc"
	cp -a "${MSYS_PREFIX}/etc/fonts" "${OUT_DIR}/etc/"
fi
if [[ -d "${MSYS_PREFIX}/share/fonts" ]]; then
	mkdir -p "${OUT_DIR}/share"
	cp -a "${MSYS_PREFIX}/share/fonts" "${OUT_DIR}/share/"
fi

cat > "${OUT_DIR}/run-hello.bat" << 'EOF'
@echo off
cd /d "%~dp0"
set "FONTCONFIG_FILE=%~dp0etc\fonts\fonts.conf"
set "XDG_DATA_DIRS=%~dp0share"
webview2gtk-hello.exe %*
EOF

cat > "${OUT_DIR}/run-browser.bat" << 'EOF'
@echo off
cd /d "%~dp0"
set "FONTCONFIG_FILE=%~dp0etc\fonts\fonts.conf"
set "XDG_DATA_DIRS=%~dp0share"
if "%~1"=="" (
  webview2gtk-browser.exe https://example.com/
) else (
  webview2gtk-browser.exe %*
)
EOF

cat > "${OUT_DIR}/run-automation.bat" << 'EOF'
@echo off
cd /d "%~dp0"
set "FONTCONFIG_FILE=%~dp0etc\fonts\fonts.conf"
set "XDG_DATA_DIRS=%~dp0share"
webview2gtk-automation.exe %*
EOF

echo ""
echo "Portable demos: ${OUT_DIR}/"
echo "  run-hello.bat / webview2gtk-hello.exe"
echo "  run-browser.bat / webview2gtk-browser.exe"
echo "  run-automation.bat / webview2gtk-automation.exe"
echo "  webview2gtk-cdp-attach.exe  (CDP attach/fill smoke; needs automation running)"
echo "  webview2gtk-paned-insert.exe  (login → first paned insert + load_uri)"
echo "Double-click the .bat launchers (or exes if fonts are configured)."
echo "WebView2 Runtime must still be installed on the PC."

# Meson custom_target stamp (optional arg) so install does not re-run this target.
if [[ -n "${1:-}" ]]; then
	mkdir -p "$(dirname "$1")"
	touch "$1"
fi
