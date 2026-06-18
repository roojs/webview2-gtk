#!/usr/bin/env bash
# Copy toolchain DLLs beside every .exe already in a bin/ directory (meson install / CI).
#
#   ./scripts/bundle-bin-runtime.sh dist/webview2gtk/bin
set -euo pipefail

BIN_DIR="${1:?bin directory}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COPY_DLLS="${ROOT}/scripts/copy-exe-runtime-dlls.sh"
LOADER=""

for candidate in \
	"${BIN_DIR}/WebView2Loader.dll" \
	"$(dirname "$(dirname "${BIN_DIR}")")/build/vendor/webview2/x64/WebView2Loader.dll" \
	"$(dirname "${BIN_DIR}")/../build/vendor/webview2/x64/WebView2Loader.dll"
do
	if [[ -f "${candidate}" ]]; then
		LOADER="${candidate}"
		break
	fi
done

shopt -s nullglob
exes=("${BIN_DIR}"/*.exe)
if [[ ${#exes[@]} -eq 0 ]]; then
	echo "bundle-bin-runtime: no .exe in ${BIN_DIR}" >&2
	exit 1
fi

for exe in "${exes}"; do
	"${COPY_DLLS}" "${exe}" "${BIN_DIR}" "${LOADER}"
done

echo "bundle-bin-runtime: ${BIN_DIR}/ ($(find "${BIN_DIR}" -maxdepth 1 -name '*.dll' | wc -l) DLLs total)"
