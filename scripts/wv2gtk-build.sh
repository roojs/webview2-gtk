#!/usr/bin/env bash
# Build webview2-gtk library and examples (MSYS2 UCRT64 / native Windows).
#
# Usage:
#   wv2gtk-build.sh lib      <builddir> <prefix> <stamp>
#   wv2gtk-build.sh hello         <builddir> <out.exe> <lib-stage>
#   wv2gtk-build.sh browser       <builddir> <out.exe> <lib-stage>
#   wv2gtk-build.sh automation    <builddir> <out.exe> <lib-stage>
#   wv2gtk-build.sh paned-insert  <builddir> <out.exe> <lib-stage>
#   wv2gtk-build.sh multi-host-spike <builddir> <out.exe>   # raw WebView2 COM spike
#   wv2gtk-build.sh cdp-attach    <builddir> <out.exe>   # soup+json only
#
# Examples link the staged static library from `lib` — they do not recompile
# the widget/host tree (that was tripling CI compile time).
set -euo pipefail

MODE="${1:?mode: lib|hello|browser|automation|paned-insert|multi-host-spike|cdp-attach}"
BUILD_DIR="${2:?build directory}"
OUT="${3:?output (prefix for lib, exe for examples)}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(grep -E "^[[:space:]]*version:" "${ROOT}/meson.build" | head -1 | sed -E "s/.*'([^']+)'.*/\1/")"
VAPI="${ROOT}/vapi"
GEN="${ROOT}/generated"
HOST="${ROOT}/lib/host"
WIDGET_INC="${ROOT}/lib/webview2gtk"
GDK_WIN32_C="${WIDGET_INC}/webview2gtk-gdk-win32.c"
WEBVIEW2_INC="${ROOT}/build/vendor/webview2/include"

if [[ ! -f "${WEBVIEW2_INC}/WebView2.h" ]]; then
	echo "wv2gtk-build: run ./scripts/vendor-webview2-sdk.sh first" >&2
	exit 1
fi

# Prefer ccache when present (CI caches ~/.ccache).
if command -v ccache >/dev/null 2>&1; then
	CC="${CC:-ccache cc}"
else
	CC="${CC:-cc}"
fi

# Skip generated/win32-ui-webview2-events-bridge.vala: Vala target delegates warn
# ("copying delegates is not supported"). Emit symbols live in host-listeners.
HOST_VALA=(
	"${HOST}/win32-ui-webview2-host.vala"
	"${HOST}/webview2gtk-host-listeners.vala"
	"${GEN}/win32-ui-webview2-host-glue.vala"
	"${GEN}/win32-ui-webview2-com-sync.vala"
	"${GEN}/win32-wide-strings.vala"
)

HOST_VALA_ARGS=(
	--vapidir "${VAPI}"
	--profile=posix
	--pkg win32-ui-webview2
	--pkg win32-ui-windowsandmessaging
	--pkg win32-foundation-stub
)

GTK_VALA_ARGS=(
	--vapidir "${VAPI}"
	--profile=gobject
	--pkg gtk4
	--pkg libsoup-3.0
	--pkg gee-0.8
	--pkg posix
)

CAPTURE_VALA=(
	lib/webview2gtk/CaptureBindings.vala
	lib/webview2gtk/A11yBindings.vala
	lib/webview2gtk/win32atspi/Win32Atspi.vala
	lib/webview2gtk/win32atspi/Win32AtspiWin.vala
	lib/webview2gtk/Enums.vala
	lib/webview2gtk/NetworkProxySettings.vala
	lib/webview2gtk/CookieManager.vala
	lib/webview2gtk/URIRequest.vala
	lib/webview2gtk/WebResource.vala
	lib/webview2gtk/Download.vala
	lib/webview2gtk/NetworkSession.vala
	lib/webview2gtk/ApplicationInfo.vala
	lib/webview2gtk/AutomationSession.vala
	lib/webview2gtk/WebContext.vala
	lib/webview2gtk/WebsitePolicies.vala
	lib/webview2gtk/Settings.vala
	lib/webview2gtk/PermissionRequest.vala
	lib/webview2gtk/JavaScriptResult.vala
	lib/webview2gtk/UserContentManager.vala
	lib/webview2gtk/PrintOperation.vala
	lib/webview2gtk/WebInspector.vala
)

CC_QUIET=(
	-Wno-discarded-qualifiers
	-Wno-incompatible-pointer-types
	-Wno-implicit-function-declaration
)

WEBVIEW2_LINK=( -lole32 -luuid -lshell32 -ladvapi32 -loleaut32 -luiautomationcore -lwinhttp -lshlwapi )
GTK_CFLAGS="$(pkg-config --cflags gtk4 libsoup-3.0 gee-0.8)"
GTK_LIBS="$(pkg-config --libs gtk4 libsoup-3.0 gee-0.8)"

compile_host_c() {
	local host_dir="$1"
	# Drop prior valac output so nested vs flat -d layouts cannot mix stale .c.
	rm -rf "${host_dir}"
	mkdir -p "${host_dir}"
	valac "${HOST_VALA_ARGS[@]}" -C -d "${host_dir}" "${HOST_VALA[@]}"
	local f
	for f in $(host_c_files "${host_dir}"); do
		if [[ ! -f "${f}" ]]; then
			echo "wv2gtk-build: missing generated host C: ${f}" >&2
			exit 1
		fi
	done
}

host_c_files() {
	local host_dir="$1"
	local -a valac_c=()
	# valac -d layout differs by version / cwd:
	# nested: host_dir/lib/host/*.c + host_dir/generated/*.c
	# flat:   host_dir/*.c  (MSYS2 / GitHub Actions)
	if [[ -f "${host_dir}/lib/host/win32-ui-webview2-host.c" ]]; then
		valac_c=(
			"${host_dir}/lib/host/win32-ui-webview2-host.c"
			"${host_dir}/lib/host/webview2gtk-host-listeners.c"
			"${host_dir}/generated/win32-ui-webview2-host-glue.c"
			"${host_dir}/generated/win32-ui-webview2-com-sync.c"
			"${host_dir}/generated/win32-wide-strings.c"
		)
	else
		valac_c=(
			"${host_dir}/win32-ui-webview2-host.c"
			"${host_dir}/webview2gtk-host-listeners.c"
			"${host_dir}/win32-ui-webview2-host-glue.c"
			"${host_dir}/win32-ui-webview2-com-sync.c"
			"${host_dir}/win32-wide-strings.c"
		)
	fi
	echo \
		"${valac_c[@]}" \
		"${GEN}/win32-ui-webview2-com-sync.c" \
		"${HOST}/win32-ui-webview2-events.c" \
		"${HOST}/win32-ui-webview2-loader.c" \
		"${HOST}/win32-ui-webview2-com-glue.c" \
		"${HOST}/win32-ui-webview2-automation.c" \
		"${HOST}/win32-ui-webview2-script.c" \
		"${HOST}/win32-ui-webview2-capture.c" \
		"${HOST}/win32-ui-webview2-print.c" \
		"${HOST}/win32-ui-webview2-cookies.c" \
		"${HOST}/win32-ui-webview2-document-response.c" \
		"${HOST}/win32-ui-webview2-script-messages.c" \
		"${HOST}/win32-ui-webview2-downloads.c" \
		"${HOST}/win32-ui-webview2-web-resources.c" \
		"${HOST}/win32-ui-webview2-permissions.c" \
		"${HOST}/win32-ui-webview2-a11y.c" \
		"${HOST}/win32-ui-webview2-a11y-diag.c"
}

inc_flags() {
	local host_dir="$1"
	local extra_dir="${2:-}"
	local -a flags=(
		-mwindows
		-I"${host_dir}"
	)
	# Prefer valac-generated headers over any stale copy under lib/webview2gtk/.
	if [[ -n "${extra_dir}" ]]; then
		flags+=(-I"${extra_dir}/lib/webview2gtk" -I"${extra_dir}")
	fi
	flags+=(
		-I"${GEN}"
		-I"${WEBVIEW2_INC}"
		-I"${HOST}"
		-I"${WIDGET_INC}"
	)
	# shellcheck disable=SC2086
	echo "${flags[@]}" ${GTK_CFLAGS}
}

compile_host_objects() {
	local host_dir="$1"
	local obj_dir="$2"
	mkdir -p "${obj_dir}"
	# shellcheck disable=SC2046,SC2086
	for src in $(host_c_files "${host_dir}"); do
		local base
		base="$(basename "${src}" .c)"
		# CC may be "ccache cc"
		# shellcheck disable=SC2086
		${CC} -c "${CC_QUIET[@]}" $(inc_flags "${host_dir}") \
			-o "${obj_dir}/${base}.o" "${src}"
	done
}

case "${MODE}" in
	lib)
		PREFIX="${OUT}"
		STAMP="${4:?meson stamp output}"
		HOST_DIR="${BUILD_DIR}/host"
		GTK_DIR="${BUILD_DIR}/gtk-lib"
		OBJ_DIR="${BUILD_DIR}/obj"
		mkdir -p "${PREFIX}/lib" "${PREFIX}/include/webview2gtk-1" "${PREFIX}/lib/pkgconfig"
		compile_host_c "${HOST_DIR}"
		mkdir -p "${GTK_DIR}/lib/webview2gtk"
		(
			cd "${ROOT}"
			valac "${GTK_VALA_ARGS[@]}" --vapidir "${VAPI}" \
				-C -H "${GTK_DIR}/lib/webview2gtk/webview2gtk.h" \
				--library=webview2gtk-1 \
				-d "${GTK_DIR}" \
				lib/webview2gtk/webview.vala \
				"${CAPTURE_VALA[@]}"
		)
		GTK_HEADER="${GTK_DIR}/lib/webview2gtk/webview2gtk.h"
		if [[ ! -f "${GTK_HEADER}" ]]; then
			echo "wv2gtk-build: ${GTK_HEADER} not generated" >&2
			exit 1
		fi
		compile_host_objects "${HOST_DIR}" "${OBJ_DIR}"
		# shellcheck disable=SC2086
		${CC} -c "${CC_QUIET[@]}" $(inc_flags "${HOST_DIR}" "${GTK_DIR}") \
			-o "${OBJ_DIR}/webview2gtk-gdk-win32.o" "${GDK_WIN32_C}"
		shopt -s nullglob
		for src in "${GTK_DIR}/lib/webview2gtk"/*.c \
			"${GTK_DIR}/lib/webview2gtk"/win32atspi/*.c; do
			base="$(basename "${src}" .c)"
			# shellcheck disable=SC2086
			${CC} -c "${CC_QUIET[@]}" $(inc_flags "${HOST_DIR}" "${GTK_DIR}") \
				-include "${GTK_HEADER}" \
				-o "${OBJ_DIR}/${base}.o" "${src}"
		done
		shopt -u nullglob
		ar rcs "${PREFIX}/lib/libwebview2gtk-1.a" "${OBJ_DIR}"/*.o
		cp -f "${VAPI}/webview2gtk-1.vapi" "${PREFIX}/lib/webview2gtk-1.vapi"
		printf '%s\n' 'gtk4' 'libsoup-3.0' 'gee-0.8' > "${PREFIX}/lib/webview2gtk-1.deps"
		cp -f "${GTK_HEADER}" "${PREFIX}/include/webview2gtk-1/webview2gtk.h"
		cp -f "${GTK_HEADER}" "${WIDGET_INC}/webview2gtk.h"
		cp -f "${HOST}/webview2gtk-host-api.h" "${PREFIX}/include/webview2gtk-1/"
		sed -e "s|@prefix@|${PREFIX}|g" -e "s|@version@|${VERSION}|g" "${ROOT}/webview2gtk-1.pc.in" > "${PREFIX}/lib/pkgconfig/webview2gtk-1.pc"
		cp -f "${ROOT}/build/vendor/webview2/x64/WebView2Loader.dll" "${PREFIX}/lib/" 2>/dev/null || true
		# Meson custom_target output — without this, `meson install` rebuilds lib every time.
		mkdir -p "$(dirname "${STAMP}")"
		touch "${STAMP}"
		;;
	hello|browser|automation|paned-insert)
		LIB_STAGE="${4:?lib-stage from meson (install-staging)}"
		STAGED_A="${LIB_STAGE}/lib/libwebview2gtk-1.a"
		STAGED_INC="${LIB_STAGE}/include/webview2gtk-1"
		STAGED_VAPI_DIR="${LIB_STAGE}/lib"
		if [[ ! -f "${STAGED_A}" ]]; then
			echo "wv2gtk-build: missing staged library ${STAGED_A} (build lib first)" >&2
			exit 1
		fi
		if [[ ! -f "${STAGED_VAPI_DIR}/webview2gtk-1.vapi" ]]; then
			echo "wv2gtk-build: missing staged vapi in ${STAGED_VAPI_DIR}" >&2
			exit 1
		fi
		GTK_DIR="${BUILD_DIR}/gtk-${MODE}"
		rm -rf "${GTK_DIR}"
		mkdir -p "${GTK_DIR}"
		(
			cd "${ROOT}"
			# Example only — link against staged libwebview2gtk-1.a
			valac "${GTK_VALA_ARGS[@]}" \
				--vapidir "${STAGED_VAPI_DIR}" \
				--vapidir "${VAPI}" \
				--pkg webview2gtk-1 \
				-C -d "${GTK_DIR}" \
				"examples/${MODE}/main.vala"
		)
		MAIN_C="${GTK_DIR}/examples/${MODE}/main.c"
		if [[ ! -f "${MAIN_C}" ]]; then
			# flat -d layout
			MAIN_C="${GTK_DIR}/main.c"
		fi
		if [[ ! -f "${MAIN_C}" ]]; then
			echo "wv2gtk-build: valac did not emit main.c under ${GTK_DIR}" >&2
			find "${GTK_DIR}" -name '*.c' >&2 || true
			exit 1
		fi
		mkdir -p "$(dirname "${OUT}")"
		# Console so smoke prints (TEST_PASS / TEST_FAIL) land in schtasks logs.
		_subsys="${WINDOWS_SUBSYSTEM:--mwindows}"
		if [[ "${MODE}" == "automation" || "${MODE}" == "paned-insert" ]] && [[ -z "${WINDOWS_SUBSYSTEM:-}" ]]; then
			_subsys="-mconsole"
		fi
		# shellcheck disable=SC2086
		${CC} "${CC_QUIET[@]}" ${_subsys} \
			-I"${STAGED_INC}" \
			-I"${WEBVIEW2_INC}" \
			${GTK_CFLAGS} \
			-o "${OUT}" \
			"${MAIN_C}" \
			"${STAGED_A}" \
			"${WEBVIEW2_LINK[@]}" \
			${GTK_LIBS}
		cp -f "${ROOT}/build/vendor/webview2/x64/WebView2Loader.dll" "$(dirname "${OUT}")/" 2>/dev/null || true
		;;
	multi-host-spike)
		# Standalone Win32 + WebView2 COM — no GTK / no libwebview2gtk.
		mkdir -p "$(dirname "${OUT}")"
		# shellcheck disable=SC2086
		${CC} "${CC_QUIET[@]}" -mconsole \
			-I"${WEBVIEW2_INC}" \
			-o "${OUT}" \
			"${ROOT}/examples/multi-host-spike/main.c" \
			"${WEBVIEW2_LINK[@]}"
		cp -f "${ROOT}/build/vendor/webview2/x64/WebView2Loader.dll" "$(dirname "${OUT}")/" 2>/dev/null || true
		;;
	cdp-attach)
		# Console CDP client — libsoup + json-glib only (no WebView2 / GTK widget).
		GTK_DIR="${BUILD_DIR}/gtk-cdp-attach"
		rm -rf "${GTK_DIR}"
		mkdir -p "${GTK_DIR}"
		(
			cd "${ROOT}"
			valac \
				--pkg libsoup-3.0 \
				--pkg json-glib-1.0 \
				-C -d "${GTK_DIR}" \
				"examples/cdp-attach/main.vala"
		)
		MAIN_C="${GTK_DIR}/examples/cdp-attach/main.c"
		if [[ ! -f "${MAIN_C}" ]]; then
			MAIN_C="${GTK_DIR}/main.c"
		fi
		if [[ ! -f "${MAIN_C}" ]]; then
			echo "wv2gtk-build: valac did not emit main.c under ${GTK_DIR}" >&2
			find "${GTK_DIR}" -name '*.c' >&2 || true
			exit 1
		fi
		mkdir -p "$(dirname "${OUT}")"
		CDP_CFLAGS="$(pkg-config --cflags libsoup-3.0 json-glib-1.0)"
		CDP_LIBS="$(pkg-config --libs libsoup-3.0 json-glib-1.0)"
		# shellcheck disable=SC2086
		${CC} "${CC_QUIET[@]}" -mconsole \
			${CDP_CFLAGS} \
			-o "${OUT}" \
			"${MAIN_C}" \
			${CDP_LIBS}
		;;
	*)
		echo "unknown mode: ${MODE}" >&2
		exit 1
		;;
esac

echo "wv2gtk-build: ${MODE} -> ${OUT}"
