#!/usr/bin/env bash
# Agent workflow: rsync Linux → Windows C:, build webview2-gtk, pull artifacts back.
#
#   ./scripts/agent-remote-build.sh          # sync + build + pull
#   ./scripts/agent-remote-build.sh sync     # rsync only
#   ./scripts/agent-remote-build.sh build    # remote build only (sources already synced)
#   ./scripts/agent-remote-build.sh pull     # pull build/ back to Linux
#   ./scripts/agent-remote-build.sh run      # run hello demo on Windows (3s smoke)
#   ./scripts/agent-remote-build.sh paned-insert  # build + run first-insert blank-pane test
#   ./scripts/agent-remote-build.sh add-cookie    # build + run add_cookie-before-attach test
#   ./scripts/agent-remote-build.sh multi-host-spike  # 4.5 two-controller HWND spike
#   ./scripts/agent-remote-build.sh automation        # build + automation --smoke
#
# Requires: AGENT_WIN_HOST (SSH Host), MSYS2 rsync on Windows (see vala.win32 docs/windows-build.md § Rsync).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REMOTE_HOST="${AGENT_WIN_HOST:?set AGENT_WIN_HOST to your Windows SSH Host alias}"
REMOTE_ROOT="/c/msys64/tmp/webview2-gtk"
REMOTE_BUILD="${REMOTE_ROOT}/build"
RSYNC_SSH=(ssh -o BatchMode=yes)
RSYNC_PATH=(--rsync-path='C:/msys64/usr/bin/rsync')

RSYNC_EXCLUDES=(
	--exclude 'build/'
	--exclude 'build-remote/'
	--exclude 'dist/'
	--exclude 'dist-demos/'
	--exclude '.git/'
	--exclude '.specstory/'
	--exclude 'build/gen/'
	--exclude '*.pkg.tar.zst'
	--exclude 'webview2gtk-setup.exe'
)

sync_to_windows() {
	echo "[agent-remote-build] rsync -> ${REMOTE_HOST}:${REMOTE_ROOT}/"
	rsync -avz "${RSYNC_EXCLUDES[@]}" \
		-e "${RSYNC_SSH[*]}" \
		"${RSYNC_PATH[@]}" \
		"${ROOT}/" "${REMOTE_HOST}:${REMOTE_ROOT}/"
}

run_remote_build() {
	echo "[agent-remote-build] build on ${REMOTE_HOST} (C: mirror)"
	# Prefer ninja targets; package-demos often fails if dist-demos is locked.
	ssh -o BatchMode=yes "${REMOTE_HOST}" \
		"C:\\msys64\\msys2_shell.cmd -defterm -no-start -ucrt64 -c \"cd /c/msys64/tmp/webview2-gtk && ./scripts/vendor-webview2-sdk.sh && meson setup --reconfigure build && ninja -C build libwebview2gtk-1.stamp webview2gtk-hello.exe webview2gtk-browser.exe webview2gtk-automation.exe webview2gtk-cdp-attach.exe webview2gtk-paned-insert.exe webview2gtk-add-cookie.exe 2>&1 | tee build/last-build.log && (OUT_DIR=/c/msys64/tmp/webview2-gtk/portable-demos ./scripts/package-demos.sh || true)\""
}

run_remote_smoke() {
	echo "[agent-remote-build] smoke run hello (3s) on ${REMOTE_HOST}"
	ssh -o BatchMode=yes "${REMOTE_HOST}" \
		"C:\\msys64\\msys2_shell.cmd -defterm -no-start -ucrt64 -c \"cd /c/msys64/tmp/webview2-gtk/build && cp -f vendor/webview2/x64/WebView2Loader.dll . 2>/dev/null || cp -f ../build/vendor/webview2/x64/WebView2Loader.dll .; timeout 3 ./webview2gtk-hello.exe 2>&1 | tee smoke-run.log || true\""
}

run_remote_automation_smoke() {
	echo "[agent-remote-build] automation --smoke (interactive RDP session) on ${REMOTE_HOST}"
	# SSH session 0 has no Win32 desktop — GUI exes segfault there.
	# Run via schtasks /IT into the logged-on session; DLL-complete portable-demos.
	ssh -o BatchMode=yes "${REMOTE_HOST}" \
		"C:\\msys64\\msys2_shell.cmd -defterm -no-start -ucrt64 -c \"bash /c/msys64/tmp/webview2-gtk/scripts/run-automation-smoke-interactive.sh\""
}

run_remote_paned_insert_build() {
	echo "[agent-remote-build] paned-insert build on ${REMOTE_HOST}"
	ssh -o BatchMode=yes "${REMOTE_HOST}" \
		"C:\\msys64\\msys2_shell.cmd -defterm -no-start -ucrt64 -c \"cd /c/msys64/tmp/webview2-gtk && ./scripts/vendor-webview2-sdk.sh && meson setup --reconfigure build && rm -f build/webview2gtk-paned-insert.exe && set -o pipefail && ninja -C build libwebview2gtk-1.stamp webview2gtk-paned-insert.exe 2>&1 | tee build/last-build.log && OUT_DIR=/c/msys64/tmp/webview2-gtk/portable-demos ./scripts/copy-exe-runtime-dlls.sh build/webview2gtk-paned-insert.exe /c/msys64/tmp/webview2-gtk/portable-demos build/vendor/webview2/x64/WebView2Loader.dll\""
}

run_remote_paned_insert_smoke() {
	echo "[agent-remote-build] paned-insert --smoke (interactive RDP session) on ${REMOTE_HOST}"
	ssh -o BatchMode=yes "${REMOTE_HOST}" \
		"C:\\msys64\\msys2_shell.cmd -defterm -no-start -ucrt64 -c \"bash /c/msys64/tmp/webview2-gtk/scripts/run-paned-insert-smoke-interactive.sh\""
}

run_remote_add_cookie_build() {
	echo "[agent-remote-build] add-cookie build on ${REMOTE_HOST}"
	ssh -o BatchMode=yes "${REMOTE_HOST}" \
		"C:\\msys64\\msys2_shell.cmd -defterm -no-start -ucrt64 -c \"cd /c/msys64/tmp/webview2-gtk && ./scripts/vendor-webview2-sdk.sh && meson setup --reconfigure build && rm -f build/webview2gtk-add-cookie.exe build/libwebview2gtk-1.stamp && set -o pipefail && ninja -C build libwebview2gtk-1.stamp webview2gtk-add-cookie.exe 2>&1 | tee build/last-build.log && OUT_DIR=/c/msys64/tmp/webview2-gtk/portable-demos ./scripts/copy-exe-runtime-dlls.sh build/webview2gtk-add-cookie.exe /c/msys64/tmp/webview2-gtk/portable-demos build/vendor/webview2/x64/WebView2Loader.dll\""
}

run_remote_add_cookie_smoke() {
	echo "[agent-remote-build] add-cookie --smoke (interactive RDP session) on ${REMOTE_HOST}"
	ssh -o BatchMode=yes "${REMOTE_HOST}" \
		"C:\\msys64\\msys2_shell.cmd -defterm -no-start -ucrt64 -c \"bash /c/msys64/tmp/webview2-gtk/scripts/run-add-cookie-smoke-interactive.sh\""
}

run_remote_multi_host_spike_build() {
	echo "[agent-remote-build] multi-host-spike build on ${REMOTE_HOST}"
	ssh -o BatchMode=yes "${REMOTE_HOST}" \
		"C:\\msys64\\msys2_shell.cmd -defterm -no-start -ucrt64 -c \"cd /c/msys64/tmp/webview2-gtk && ./scripts/vendor-webview2-sdk.sh && meson setup --reconfigure build && rm -f build/webview2gtk-multi-host-spike.exe && set -o pipefail && ninja -C build webview2gtk-multi-host-spike.exe 2>&1 | tee build/last-build.log && cp -f build/webview2gtk-multi-host-spike.exe build/vendor/webview2/x64/WebView2Loader.dll /c/msys64/tmp/webview2-gtk/portable-demos/ 2>/dev/null; mkdir -p /c/msys64/tmp/webview2-gtk/portable-demos && cp -f build/webview2gtk-multi-host-spike.exe /c/msys64/tmp/webview2-gtk/portable-demos/ && cp -f build/vendor/webview2/x64/WebView2Loader.dll /c/msys64/tmp/webview2-gtk/portable-demos/\""
}

run_remote_multi_host_spike_smoke() {
	echo "[agent-remote-build] multi-host-spike --smoke (interactive RDP session) on ${REMOTE_HOST}"
	ssh -o BatchMode=yes "${REMOTE_HOST}" \
		"C:\\msys64\\msys2_shell.cmd -defterm -no-start -ucrt64 -c \"bash /c/msys64/tmp/webview2-gtk/scripts/run-multi-host-spike-interactive.sh\""
}

pull_artifacts() {
	mkdir -p "${ROOT}/build-remote"
	echo "[agent-remote-build] pull build/ <- ${REMOTE_HOST}"
	rsync -avz \
		-e "${RSYNC_SSH[*]}" \
		"${RSYNC_PATH[@]}" \
		"${REMOTE_HOST}:${REMOTE_BUILD}/" \
		"${ROOT}/build-remote/"
	mkdir -p "${ROOT}/build-remote/portable"
	echo "[agent-remote-build] pull dist-demos/ <- ${REMOTE_HOST}"
	rsync -avz \
		-e "${RSYNC_SSH[*]}" \
		"${RSYNC_PATH[@]}" \
		"${REMOTE_HOST}:${REMOTE_ROOT}/dist-demos/" \
		"${ROOT}/build-remote/portable/"
}

print_hint() {
	echo ""
	echo "Linux copy: ${ROOT}/build-remote/"
	echo "  portable/               double-click-ready demos + GTK DLLs"
	echo "  webview2gtk-hello.exe   raw meson build (needs UCRT64 PATH)"
	if [[ -f "${ROOT}/build-remote/last-build.log" ]]; then
		echo "--- tail last-build.log ---"
		tail -20 "${ROOT}/build-remote/last-build.log"
	fi
	if [[ -f "${ROOT}/build-remote/automation-smoke.log" ]]; then
		echo "--- automation-smoke.log ---"
		cat "${ROOT}/build-remote/automation-smoke.log"
	elif [[ -f "${ROOT}/build-remote/portable/automation-smoke.log" ]]; then
		echo "--- automation-smoke.log ---"
		cat "${ROOT}/build-remote/portable/automation-smoke.log"
	elif [[ -f "${ROOT}/build-remote/smoke-run.log" ]]; then
		echo "--- smoke-run.log ---"
		cat "${ROOT}/build-remote/smoke-run.log"
	fi
	if [[ -f "${ROOT}/build-remote/paned-insert-smoke.log" ]]; then
		echo "--- paned-insert-smoke.log ---"
		cat "${ROOT}/build-remote/paned-insert-smoke.log"
	fi
	if [[ -f "${ROOT}/build-remote/add-cookie-smoke.log" ]]; then
		echo "--- add-cookie-smoke.log ---"
		cat "${ROOT}/build-remote/add-cookie-smoke.log"
	fi
}

cmd="${1:-build}"

case "${cmd}" in
	build)
		sync_to_windows
		build_rc=0
		run_remote_build || build_rc=$?
		run_remote_smoke || true
		run_remote_automation_smoke || build_rc=$?
		pull_artifacts || true
		print_hint
		exit "${build_rc}"
		;;
	sync)
		sync_to_windows
		;;
	remote-build)
		run_remote_build
		run_remote_smoke || true
		run_remote_automation_smoke || true
		pull_artifacts || true
		print_hint
		;;
	pull)
		pull_artifacts
		print_hint
		;;
	run)
		run_remote_smoke
		pull_artifacts || true
		print_hint
		;;
	automation)
		sync_to_windows
		build_rc=0
		run_remote_build || build_rc=$?
		run_remote_automation_smoke || build_rc=$?
		pull_artifacts || true
		print_hint
		exit "${build_rc}"
		;;
	paned-insert)
		sync_to_windows
		build_rc=0
		run_remote_paned_insert_build || build_rc=$?
		if [[ "${build_rc}" -eq 0 ]]; then
			run_remote_paned_insert_smoke || build_rc=$?
		fi
		ssh -o BatchMode=yes "${REMOTE_HOST}" \
			"C:\\msys64\\msys2_shell.cmd -defterm -no-start -ucrt64 -c \"cp -f /c/Users/Alan/AppData/Local/Temp/webview2gtk-paned-insert-smoke.log /c/msys64/tmp/webview2-gtk/build/paned-insert-smoke.log 2>/dev/null || true\"" \
			|| true
		pull_artifacts || true
		print_hint
		exit "${build_rc}"
		;;
	add-cookie)
		sync_to_windows
		build_rc=0
		run_remote_add_cookie_build || build_rc=$?
		if [[ "${build_rc}" -eq 0 ]]; then
			run_remote_add_cookie_smoke || build_rc=$?
		fi
		ssh -o BatchMode=yes "${REMOTE_HOST}" \
			"C:\\msys64\\msys2_shell.cmd -defterm -no-start -ucrt64 -c \"cp -f /c/Users/Alan/AppData/Local/Temp/webview2gtk-add-cookie-smoke.log /c/msys64/tmp/webview2-gtk/build/add-cookie-smoke.log 2>/dev/null || true\"" \
			|| true
		pull_artifacts || true
		print_hint
		exit "${build_rc}"
		;;
	multi-host-spike)
		sync_to_windows
		build_rc=0
		run_remote_multi_host_spike_build || build_rc=$?
		if [[ "${build_rc}" -eq 0 ]]; then
			run_remote_multi_host_spike_smoke || build_rc=$?
		fi
		ssh -o BatchMode=yes "${REMOTE_HOST}" \
			"C:\\msys64\\msys2_shell.cmd -defterm -no-start -ucrt64 -c \"cp -f /c/Users/Alan/AppData/Local/Temp/webview2gtk-multi-host-spike.log /c/msys64/tmp/webview2-gtk/build/multi-host-spike.log 2>/dev/null || true\"" \
			|| true
		pull_artifacts || true
		print_hint
		exit "${build_rc}"
		;;
	*)
		echo "usage: $0 [build|sync|remote-build|pull|run|automation|paned-insert|add-cookie|multi-host-spike]" >&2
		exit 1
		;;
esac
