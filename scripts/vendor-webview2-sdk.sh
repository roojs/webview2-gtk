#!/usr/bin/env bash
# Download Microsoft.Web.WebView2 NuGet (.nupkg is a zip) and stage headers + loader DLL.
#
# Staged layout (gitignored under build/vendor/webview2/):
#   include/WebView2.h
#   include/WebView2EnvironmentOptions.h
#   x64/WebView2Loader.dll
#   x86/WebView2Loader.dll
#
# Linux/macOS, or invoked from Windows via:
#   msys2_shell.cmd -defterm -no-start -ucrt64 -c 'cd /c/msys64/tmp/vala.win32 && ./scripts/vendor-webview2-sdk.sh'
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REF_FILE="${ROOT}/metadata/webview2-sdk-ref.txt"
VERSION="${WEBVIEW2_SDK_VERSION:-}"
if [[ -z "${VERSION}" && -f "${REF_FILE}" ]]; then
	VERSION="$(grep -v '^#' "${REF_FILE}" | grep -v '^[[:space:]]*$' | head -1)"
fi
VERSION="${VERSION:-1.0.2792.45}"

VENDOR_DIR="${ROOT}/build/vendor"
NUPKG="${VENDOR_DIR}/webview2.nupkg"
OUT="${VENDOR_DIR}/webview2"
# Extract under local /tmp — full zip tree on X: (Samba) often fails (FileNotFoundError).
EXTRACT="$(mktemp -d "${TMPDIR:-/tmp}/webview2-extract.XXXXXX")"
trap 'rm -rf "${EXTRACT}"' EXIT
PKG_URL="https://www.nuget.org/api/v2/package/Microsoft.Web.WebView2/${VERSION}"

mkdir -p "${VENDOR_DIR}"

if [[ ! -f "${NUPKG}" ]]; then
	echo "Downloading ${PKG_URL} ..."
	curl -fsSL --connect-timeout 60 -o "${NUPKG}" "${PKG_URL}"
else
	echo "Using cached ${NUPKG}"
fi

extract_nupkg() {
	mkdir -p "${EXTRACT}"
	# .nupkg is zip. Extract to /tmp (not X:); copy only headers/DLLs into build/vendor/.
	if command -v unzip >/dev/null 2>&1; then
		unzip -q -o "${NUPKG}" -d "${EXTRACT}"
		return 0
	fi
	if tar -xf "${NUPKG}" -C "${EXTRACT}" 2>/dev/null; then
		return 0
	fi
	echo "error: need unzip to extract .nupkg (Windows: rerun setup-msys2-toolchain.sh or pacman -S unzip)" >&2
	exit 1
}

extract_nupkg

mkdir -p "${OUT}/include" "${OUT}/x64" "${OUT}/x86"

cp -- "${EXTRACT}/build/native/include/WebView2.h" "${OUT}/include/"
cp -- "${EXTRACT}/build/native/include/WebView2EnvironmentOptions.h" "${OUT}/include/"
cp -- "${ROOT}/metadata/webview2-stub/EventToken.h" "${OUT}/include/"

# Prefer runtimes/ paths; fall back to build/native/.
if [[ -f "${EXTRACT}/runtimes/win-x64/native/WebView2Loader.dll" ]]; then
	cp -- "${EXTRACT}/runtimes/win-x64/native/WebView2Loader.dll" "${OUT}/x64/"
else
	cp -- "${EXTRACT}/build/native/x64/WebView2Loader.dll" "${OUT}/x64/"
fi

if [[ -f "${EXTRACT}/runtimes/win-x86/native/WebView2Loader.dll" ]]; then
	cp -- "${EXTRACT}/runtimes/win-x86/native/WebView2Loader.dll" "${OUT}/x86/"
else
	cp -- "${EXTRACT}/build/native/x86/WebView2Loader.dll" "${OUT}/x86/"
fi

cat > "${OUT}/VERSION.txt" <<EOF
Microsoft.Web.WebView2 NuGet ${VERSION}
staged $(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

echo "Staged WebView2 SDK ${VERSION} -> ${OUT}"
echo "  include/WebView2.h"
echo "  x64/WebView2Loader.dll"
echo "  x86/WebView2Loader.dll"
