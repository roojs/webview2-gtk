#!/usr/bin/env bash
# Copy staged library artifacts into the meson install prefix.
set -euo pipefail
STAGE="${1:?staged lib dir}"
INSTALL="${MESON_INSTALL_DESTDIR_PREFIX:?MESON_INSTALL_DESTDIR_PREFIX not set}"
[[ -d "${STAGE}/lib" ]] || exit 0
mkdir -p "${INSTALL}/lib/pkgconfig" "${INSTALL}/include/webview2gtk-1"
cp -f "${STAGE}/lib/libwebview2gtk-1.a" "${INSTALL}/lib/"
cp -f "${STAGE}/lib/webview2gtk-1.vapi" "${INSTALL}/lib/"
cp -f "${STAGE}/lib/WebView2Loader.dll" "${INSTALL}/lib/"
cp -f "${STAGE}/include/webview2gtk-1/"* "${INSTALL}/include/webview2gtk-1/"
cp -f "${STAGE}/lib/pkgconfig/webview2gtk-1.pc" "${INSTALL}/lib/pkgconfig/"
sed -i "s|^prefix=.*|prefix=${INSTALL}|" "${INSTALL}/lib/pkgconfig/webview2gtk-1.pc"
