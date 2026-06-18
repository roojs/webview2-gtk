#!/usr/bin/env bash
# Package a Windows .exe for release (exe + WebView2Loader + GTK/GLib runtime DLLs).
#
# Copy into your project, edit defaults or pass env vars, then from MSYS2 UCRT64:
#   EXE_PATH=build/my-app.exe OUT_DIR=dist ./scripts/sample-package-windows.sh
#
# Or from PowerShell (one line):
#   C:\msys64\msys2_shell.cmd -defterm -no-start -ucrt64 -c 'cd /c/path/to/my-app && EXE_PATH=build/my-app.exe ./scripts/sample-package-windows.sh'
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXE_PATH="${EXE_PATH:-build/my-browser-app.exe}"
OUT_DIR="${OUT_DIR:-dist}"
WEBVIEW2_LOADER_SRC="${WEBVIEW2_LOADER_SRC:-/c/Program Files/webview2gtk/bin/WebView2Loader.dll}"

if [[ ! -f "${EXE_PATH}" ]]; then
	echo "sample-package-windows: exe not found: ${EXE_PATH} (build first)" >&2
	exit 1
fi

LOADER_ARG=""
if [[ -f "${WEBVIEW2_LOADER_SRC}" ]]; then
	LOADER_ARG="${WEBVIEW2_LOADER_SRC}"
else
	echo "sample-package-windows: warning: WebView2Loader.dll not at ${WEBVIEW2_LOADER_SRC}" >&2
fi

"${ROOT}/scripts/copy-exe-runtime-dlls.sh" "${EXE_PATH}" "${OUT_DIR}" "${LOADER_ARG}"

echo ""
echo "Release folder: ${OUT_DIR}/"
echo "Zip it for download. Users still need WebView2 Runtime on the PC."
