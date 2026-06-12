#!/usr/bin/env bash
# Package a Windows .exe for release (exe + WebView2Loader + missing GTK DLLs).
#
# Copy into your project, edit defaults or pass env vars, then from MSYS2 UCRT64:
#   EXE_PATH=build/my-app.exe OUT_DIR=dist ./scripts/sample-package-windows.sh
#
# Or:
#   C:\msys64\ucrt64.exe -c "cd /c/path/to/my-app && EXE_PATH=build/my-app.exe ./scripts/sample-package-windows.sh"
set -euo pipefail

EXE_PATH="${EXE_PATH:-build/my-browser-app.exe}"
OUT_DIR="${OUT_DIR:-dist}"
WEBVIEW2_LOADER_SRC="${WEBVIEW2_LOADER_SRC:-/c/Program Files/webview2gtk/bin/WebView2Loader.dll}"
UCRT_BIN="${UCRT_BIN:-/ucrt64/bin}"

if [[ ! -f "${EXE_PATH}" ]]; then
	echo "sample-package-windows: exe not found: ${EXE_PATH} (build first)" >&2
	exit 1
fi

mkdir -p "${OUT_DIR}"
cp -f "${EXE_PATH}" "${OUT_DIR}/"
if [[ -f "${WEBVIEW2_LOADER_SRC}" ]]; then
	cp -f "${WEBVIEW2_LOADER_SRC}" "${OUT_DIR}/"
else
	echo "sample-package-windows: warning: WebView2Loader.dll not at ${WEBVIEW2_LOADER_SRC}" >&2
fi

while IFS= read -r line; do
	case "${line}" in
		*"not found"*)
			dll="$(sed -n 's/^[[:space:]]*\([^[:space:]]*\).*/\1/p' <<< "${line}")"
			if [[ -f "${UCRT_BIN}/${dll}" ]]; then
				cp -f "${UCRT_BIN}/${dll}" "${OUT_DIR}/"
				echo "Copied ${dll}"
			else
				echo "sample-package-windows: warning: missing ${dll} (not in ${UCRT_BIN})" >&2
			fi
			;;
	esac
done < <(ldd "${EXE_PATH}" 2>&1 || true)

echo ""
echo "Release folder: ${OUT_DIR}/"
echo "Zip it for download. Users still need WebView2 Runtime on the PC."
