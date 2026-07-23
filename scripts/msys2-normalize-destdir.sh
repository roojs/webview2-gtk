#!/usr/bin/env bash
# Normalize a meson --destdir tree to portable MSYS2 UCRT64 layout.
#
# GitHub's msys2/setup-msys2 installs under D:/a/_temp/msys64 (etc.). Meson
# resolves --prefix=/ucrt64 to that absolute path, so `meson install --destdir`
# emits a/_temp/msys64/ucrt64/... and .pc files with Windows prefixes. Pacman
# then extracts those paths on the user's machine — broken.
#
# Usage:
#   ./scripts/msys2-normalize-destdir.sh <destdir>
#
# Result: <destdir>/ucrt64/{lib,include,...} and webview2gtk-1.pc with
#   prefix=/ucrt64
set -euo pipefail

DEST="${1:?destdir}"
CANON_PREFIX="/ucrt64"

if [[ ! -d "${DEST}" ]]; then
	echo "msys2-normalize-destdir: missing ${DEST}" >&2
	exit 1
fi

pc="$(find "${DEST}" -path '*/lib/pkgconfig/webview2gtk-1.pc' -print -quit || true)"
if [[ -z "${pc}" ]]; then
	echo "msys2-normalize-destdir: webview2gtk-1.pc not found under ${DEST}" >&2
	find "${DEST}" -maxdepth 6 -type d 2>/dev/null | head -40 >&2 || true
	exit 1
fi

# .../ucrt64/lib/pkgconfig/webview2gtk-1.pc → prefix root (.../ucrt64)
prefix_root="$(cd "$(dirname "${pc}")/../.." && pwd)"

staged="${DEST}/.wv2gtk-ucrt64-stage"
rm -rf "${staged}"
mkdir -p "${staged}${CANON_PREFIX}"
cp -a "${prefix_root}/." "${staged}${CANON_PREFIX}/"

# Drop whatever meson emitted (a/_temp/..., D:/..., bare ucrt64/, …).
find "${DEST}" -mindepth 1 -maxdepth 1 ! -name '.wv2gtk-ucrt64-stage' -exec rm -rf {} +

mv "${staged}${CANON_PREFIX}" "${DEST}${CANON_PREFIX}"
rmdir "${staged}" 2>/dev/null || rm -rf "${staged}"

PC="${DEST}${CANON_PREFIX}/lib/pkgconfig/webview2gtk-1.pc"
sed -i "s|^prefix=.*|prefix=${CANON_PREFIX}|" "${PC}"

echo "msys2-normalize-destdir: ${DEST}${CANON_PREFIX} (prefix=${CANON_PREFIX})"
