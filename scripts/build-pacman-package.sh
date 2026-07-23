#!/usr/bin/env bash
# Build mingw-w64-ucrt-x86_64-webview2gtk.pkg.tar.zst (MSYS2 UCRT64).
#
# Usage:
#   ./scripts/build-pacman-package.sh
#   ./scripts/build-pacman-package.sh --sign          # needs GPGKEY / imported secret key
#   PKGVER=0.2.7 ./scripts/build-pacman-package.sh    # override PKGBUILD pkgver (releases)
#
# Output:
#   packaging/msys2/mingw-w64-ucrt-x86_64-webview2gtk-*.pkg.tar.zst
#   packaging/msys2/mingw-w64-ucrt-x86_64-webview2gtk-*.pkg.tar.zst.sig  (with --sign)
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

if [[ -n "${PKGVER:-}" ]]; then
	sed -i "s/^pkgver=.*/pkgver=${PKGVER}/" PKGBUILD
	echo "build-pacman-package: pkgver=${PKGVER}"
fi

"${MAKEPKG}" -C -f --noconfirm --skipchecksums "$@"

shopt -s nullglob
pkgs=(mingw-w64-ucrt-x86_64-webview2gtk-*.pkg.tar.zst)
if ((${#pkgs[@]} == 0)); then
	echo "build-pacman-package: no package produced" >&2
	exit 1
fi
for pkg in "${pkgs[@]}"; do
	echo "build-pacman-package: ${PKG_DIR}/${pkg}"
	if [[ -f "${pkg}.sig" ]]; then
		echo "build-pacman-package: ${PKG_DIR}/${pkg}.sig"
	fi
done
