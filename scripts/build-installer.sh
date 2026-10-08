#!/usr/bin/env bash
# Build webview2gtk-setup.exe from a meson install tree (MSYS2 UCRT64 + NSIS).
#
# Usage:
#   ./scripts/build-installer.sh [staging-dir]
#
# Default staging-dir: dist/webview2gtk
# Output: webview2gtk-setup.exe in the repo root
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAGE="${1:-${ROOT}/dist/webview2gtk}"
VERSION="$(grep -E "^[[:space:]]*version:" "${ROOT}/meson.build" | head -1 | sed -E "s/.*'([^']+)'.*/\1/")"

if [[ ! -f "${STAGE}/lib/libwebview2gtk-1.a" ]]; then
	echo "build-installer: missing ${STAGE}/lib/libwebview2gtk-1.a" >&2
	echo "Run: meson setup build --prefix=\"\$(pwd)/dist/webview2gtk\" && meson install -C build" >&2
	exit 1
fi

if ! command -v makensis >/dev/null 2>&1; then
	echo "build-installer: install NSIS: pacman -S mingw-w64-ucrt-x86_64-nsis" >&2
	exit 1
fi

WIN_SRC="$(cygpath -aw "${STAGE}")"
OUT_EXE="$(cygpath -aw "${ROOT}/webview2gtk-setup.exe")"

# MSYS2 ships nsDialogs.dll under Plugins/unicode. NSIS 3.12 looks in
# Plugins/amd64-unicode unless the script adds the real directory for the
# active target. Without that, MUI_PAGE_WELCOME cannot call nsDialogs.
PLUGIN_DIR=""
if [[ -n "${MINGW_PREFIX:-}" ]]; then
	for candidate in \
		"${MINGW_PREFIX}/share/nsis/Plugins/amd64-unicode" \
		"${MINGW_PREFIX}/share/nsis/Plugins/x86-unicode" \
		"${MINGW_PREFIX}/share/nsis/Plugins/unicode"
	do
		if [[ -f "${candidate}/nsDialogs.dll" ]]; then
			# Forward slashes: a Windows path through _temp contains \t, which
			# some NSIS string handling treats as a tab.
			PLUGIN_DIR="$(cygpath -m "${candidate}")"
			break
		fi
	done
fi

cd "${ROOT}"
makensis_args=(
	-DINST_SRC="${WIN_SRC}"
	-DPRODUCT_VERSION="${VERSION}"
	-DOUTFILE="${OUT_EXE}"
)
if [[ -n "${PLUGIN_DIR}" ]]; then
	echo "build-installer: NSIS plugins ${PLUGIN_DIR}"
	makensis_args+=(-DPLUGIN_DIR="${PLUGIN_DIR}")
fi
makensis "${makensis_args[@]}" packaging/webview2gtk.nsi
echo "build-installer: ${ROOT}/webview2gtk-setup.exe"
