#!/usr/bin/env bash
# One meson compile → pacman package + NSIS installer staging.
#
# Used by .github/workflows/release.yml so we do not build the library twice.
#
# Usage (MSYS2 UCRT64):
#   ./scripts/ci-windows-release-build.sh
#   PKGVER=0.2.9 ./scripts/ci-windows-release-build.sh --sign
#
# Env:
#   PKGVER     — override packaging/msys2/PKGBUILD pkgver (release tags)
#   GPGKEY     — with --sign, for makepkg package signature
#
# Outputs:
#   packaging/msys2/mingw-w64-ucrt-x86_64-webview2gtk-*.pkg.tar.zst[.sig]
#   webview2gtk-setup.exe
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIGN_ARGS=()
for arg in "$@"; do
	case "$arg" in
		--sign) SIGN_ARGS+=(--sign) ;;
		*)
			echo "ci-windows-release-build: unknown arg: $arg" >&2
			exit 1
			;;
	esac
done

if [[ -z "${MINGW_PREFIX:-}" ]]; then
	echo "ci-windows-release-build: MINGW_PREFIX unset (run under MSYS2 UCRT64)" >&2
	exit 1
fi

# Portable path for pacman packages — never the runner's absolute MSYS2 root.
# (Meson may still resolve this at configure time; msys2-normalize-destdir.sh fixes the tree.)
PKG_PREFIX="/ucrt64"

cd "${ROOT}"

./scripts/vendor-webview2-sdk.sh

# Examples go into both the .pkg and the NSIS tree (installer demos).
meson setup build --prefix="${PKG_PREFIX}" -Dexamples=true --reconfigure 2>/dev/null \
	|| meson setup build --prefix="${PKG_PREFIX}" -Dexamples=true
meson compile -C build

DEST="${ROOT}/packaging/msys2/pkg"
rm -rf "${DEST}"
meson install -C build --destdir="${DEST}"
./scripts/msys2-normalize-destdir.sh "${DEST}"

if [[ -f LICENSE ]]; then
	install -Dm644 LICENSE \
		"${DEST}${PKG_PREFIX}/share/licenses/mingw-w64-ucrt-x86_64-webview2gtk/LICENSE"
fi

export WV2GTK_PREBUILT_DESTDIR="${DEST}"
./scripts/build-pacman-package.sh "${SIGN_ARGS[@]+"${SIGN_ARGS[@]}"}"

# NSIS wants a prefix-shaped tree without the leading ucrt64/ segment.
rm -rf "${ROOT}/dist/webview2gtk"
mkdir -p "${ROOT}/dist/webview2gtk"
cp -a "${DEST}${PKG_PREFIX}/." "${ROOT}/dist/webview2gtk/"
./scripts/bundle-bin-runtime.sh "${ROOT}/dist/webview2gtk/bin"
./scripts/build-installer.sh "${ROOT}/dist/webview2gtk"

echo "ci-windows-release-build: done"
