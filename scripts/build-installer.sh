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
cd "${ROOT}"
makensis \
	-DINST_SRC="${WIN_SRC}" \
	-DPRODUCT_VERSION="${VERSION}" \
	-DOUTFILE="${OUT_EXE}" \
	packaging/webview2gtk.nsi
echo "build-installer: ${ROOT}/webview2gtk-setup.exe"
