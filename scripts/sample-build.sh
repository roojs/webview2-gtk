#!/usr/bin/env bash
# Build your GTK/Vala app on Windows (after webview2gtk is installed).
#
# Copy into your project, edit the settings block, then from MSYS2 UCRT64:
#   ./scripts/sample-build.sh
#
# Or from PowerShell (one line):
#   C:\msys64\msys2_shell.cmd -defterm -no-start -ucrt64 -c 'cd /c/path/to/my-app && ./scripts/sample-build.sh'
set -euo pipefail

# --- edit these ---
MSYS_PROJECT_DIR="${MSYS_PROJECT_DIR:-/c/path/to/my-app}"
# setup.exe install (Option A):
WEBVIEW2GTK_PC="${WEBVIEW2GTK_PC:-/c/Program Files/webview2gtk/lib/pkgconfig}"
# pacman install (Option B): leave WEBVIEW2GTK_PC empty
# WEBVIEW2GTK_PC=""
# --- end edit ---

if [[ -n "${WEBVIEW2GTK_PC}" ]]; then
	export PKG_CONFIG_PATH="${WEBVIEW2GTK_PC}:${PKG_CONFIG_PATH:-}"
fi

cd "${MSYS_PROJECT_DIR}"
meson setup build
meson compile -C build

echo "Done: ${MSYS_PROJECT_DIR}/build/"
