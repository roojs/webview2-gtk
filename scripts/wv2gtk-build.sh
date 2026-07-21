#!/usr/bin/env bash
# Build webview2-gtk library and examples (MSYS2 UCRT64 / native Windows).
#
# Usage:
#   wv2gtk-build.sh lib      <builddir> <prefix>
#   wv2gtk-build.sh hello    <builddir> <out.exe>
#   wv2gtk-build.sh browser  <builddir> <out.exe>
set -euo pipefail

MODE="${1:?mode: lib|hello|browser}"
BUILD_DIR="${2:?build directory}"
OUT="${3:?output (prefix for lib, exe for examples)}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
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

HOST_VALA=(
	"${HOST}/win32-ui-webview2-host.vala"
	"${HOST}/webview2gtk-host-listeners.vala"
	"${GEN}/win32-ui-webview2-host-glue.vala"
	"${GEN}/win32-ui-webview2-com-sync.vala"
	"${GEN}/win32-wide-strings.vala"
	"${GEN}/win32-ui-webview2-events-bridge.vala"
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
	lib/webview2gtk/NetworkSession.vala
	lib/webview2gtk/Settings.vala
	lib/webview2gtk/JavaScriptResult.vala
	lib/webview2gtk/PrintOperation.vala
)

CC_QUIET=(
	-Wno-discarded-qualifiers
	-Wno-incompatible-pointer-types
	-Wno-implicit-function-declaration
)

WEBVIEW2_LINK=( -lole32 -luuid -lshell32 -ladvapi32 -loleaut32 -luiautomationcore )
GTK_CFLAGS="$(pkg-config --cflags gtk4 libsoup-3.0 gee-0.8)"
GTK_LIBS="$(pkg-config --libs gtk4 libsoup-3.0 gee-0.8)"

compile_host_c() {
	local host_dir="$1"
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
	# valac -d "${host_dir}" keeps source-relative subdirs (lib/host/, generated/).
	echo \
		"${host_dir}/lib/host/win32-ui-webview2-host.c" \
		"${host_dir}/lib/host/webview2gtk-host-listeners.c" \
		"${host_dir}/generated/win32-ui-webview2-host-glue.c" \
		"${host_dir}/generated/win32-ui-webview2-com-sync.c" \
		"${host_dir}/generated/win32-wide-strings.c" \
		"${host_dir}/generated/win32-ui-webview2-events-bridge.c" \
		"${GEN}/win32-ui-webview2-com-sync.c" \
		"${GEN}/win32-ui-webview2-events.c" \
		"${HOST}/win32-ui-webview2-loader.c" \
		"${HOST}/win32-ui-webview2-com-glue.c" \
		"${HOST}/win32-ui-webview2-script.c" \
		"${HOST}/win32-ui-webview2-capture.c" \
		"${HOST}/win32-ui-webview2-print.c" \
		"${HOST}/win32-ui-webview2-cookies.c" \
		"${HOST}/win32-ui-webview2-document-response.c" \
		"${HOST}/win32-ui-webview2-a11y.c" \
		"${HOST}/win32-ui-webview2-a11y-diag.c"
}

inc_flags() {
	local host_dir="$1"
	local extra_dir="${2:-}"
	local -a flags=(
		-mwindows
		-I"${host_dir}"
		-I"${GEN}"
		-I"${WEBVIEW2_INC}"
		-I"${HOST}"
		-I"${WIDGET_INC}"
	)
	if [[ -n "${extra_dir}" ]]; then
		flags+=(-I"${extra_dir}")
	fi
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
		cc -c "${CC_QUIET[@]}" $(inc_flags "${host_dir}") \
			-o "${obj_dir}/${base}.o" "${src}"
	done
}

case "${MODE}" in
	lib)
		PREFIX="${OUT}"
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
		cc -c "${CC_QUIET[@]}" $(inc_flags "${HOST_DIR}" "${GTK_DIR}") \
			-o "${OBJ_DIR}/webview2gtk-gdk-win32.o" "${GDK_WIN32_C}"
		shopt -s nullglob
		for src in "${GTK_DIR}/lib/webview2gtk"/*.c \
			"${GTK_DIR}/lib/webview2gtk"/win32atspi/*.c; do
			base="$(basename "${src}" .c)"
			cc -c "${CC_QUIET[@]}" $(inc_flags "${HOST_DIR}" "${GTK_DIR}") \
				-include "${GTK_HEADER}" \
				-o "${OBJ_DIR}/${base}.o" "${src}"
		done
		shopt -u nullglob
		ar rcs "${PREFIX}/lib/libwebview2gtk-1.a" "${OBJ_DIR}"/*.o
		cp -f "${VAPI}/webview2gtk-1.vapi" "${PREFIX}/lib/webview2gtk-1.vapi"
		cp -f "${GTK_HEADER}" "${PREFIX}/include/webview2gtk-1/webview2gtk.h"
		cp -f "${GTK_HEADER}" "${WIDGET_INC}/webview2gtk.h"
		cp -f "${HOST}/webview2gtk-host-api.h" "${PREFIX}/include/webview2gtk-1/"
		sed "s|@prefix@|${PREFIX}|g" "${ROOT}/webview2gtk-1.pc.in" > "${PREFIX}/lib/pkgconfig/webview2gtk-1.pc"
		cp -f "${ROOT}/build/vendor/webview2/x64/WebView2Loader.dll" "${PREFIX}/lib/" 2>/dev/null || true
		;;
	hello|browser)
		;;
	*)
		echo "unknown mode: ${MODE}" >&2
		exit 1
		;;
esac

if [[ "${MODE}" != lib ]]; then
	HOST_DIR="${BUILD_DIR}/host"
	GTK_DIR="${BUILD_DIR}/gtk-${MODE}"
	compile_host_c "${HOST_DIR}"
	(
		cd "${ROOT}"
		valac "${GTK_VALA_ARGS[@]}" --vapidir "${VAPI}" -C -d "${GTK_DIR}" \
			lib/webview2gtk/webview.vala \
			"${CAPTURE_VALA[@]}" \
			"examples/${MODE}/main.vala"
	)
	MAIN_C="${GTK_DIR}/examples/${MODE}/main.c"
	GTK_C=()
	shopt -s nullglob
	for src in "${GTK_DIR}/lib/webview2gtk"/*.c \
		"${GTK_DIR}/lib/webview2gtk"/win32atspi/*.c; do
		GTK_C+=("${src}")
	done
	shopt -u nullglob
	# shellcheck disable=SC2046,SC2086
	cc "${CC_QUIET[@]}" $(inc_flags "${HOST_DIR}" "${GTK_DIR}") \
		-o "${OUT}" \
		"${MAIN_C}" \
		"${GTK_C[@]}" \
		"${GDK_WIN32_C}" \
		$(host_c_files "${HOST_DIR}") \
		"${WEBVIEW2_LINK[@]}" \
		${GTK_LIBS}
	cp -f "${ROOT}/build/vendor/webview2/x64/WebView2Loader.dll" "$(dirname "${OUT}")/" 2>/dev/null || true
fi

echo "wv2gtk-build: ${MODE} -> ${OUT}"
