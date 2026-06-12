#!/usr/bin/env bash
# Build mingw-w64-ucrt-x86_64-webview2gtk.pkg.tar.zst (MSYS2 UCRT64).
#
# Usage:
#   ./scripts/build-pacman-package.sh
#
# Output:
#   packaging/msys2/mingw-w64-ucrt-x86_64-webview2gtk-*.pkg.tar.zst
#
# Install:
#   pacman -U packaging/msys2/mingw-w64-ucrt-x86_64-webview2gtk-*.pkg.tar.zst
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG_DIR="${ROOT}/packaging/msys2"
MAKEPKG="${MAKEPKG:-makepkg-mingw}"

if ! command -v "${MAKEPKG}" >/dev/null 2>&1; then
	echo "build-pacman-package: ${MAKEPKG} not found (use MSYS2 UCRT64; pacman -S base-devel)" >&2
	exit 1
fi

cd "${PKG_DIR}"

# Windows checkouts may introduce CRLF; makepkg refuses to source PKGBUILD with \r.
if grep -q $'\r' PKGBUILD 2>/dev/null; then
	sed -i 's/\r$//' PKGBUILD
fi

"${MAKEPKG}" -C -f --noconfirm --skipchecksums "$@"
echo "build-pacman-package: ${PKG_DIR}/mingw-w64-ucrt-x86_64-webview2gtk-"*.pkg.tar.zst
