#!/usr/bin/env bash
# Agent workflow: rsync Linux → Windows C:, build webview2-gtk, pull artifacts back.
#
#   ./scripts/agent-remote-build.sh          # sync + build + pull
#   ./scripts/agent-remote-build.sh sync     # rsync only
#   ./scripts/agent-remote-build.sh build    # remote build only (sources already synced)
#   ./scripts/agent-remote-build.sh pull     # pull build/ back to Linux
#   ./scripts/agent-remote-build.sh run      # run hello demo on Windows (3s smoke)
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
	ssh -o BatchMode=yes "${REMOTE_HOST}" \
		"C:\\msys64\\msys2_shell.cmd -defterm -no-start -ucrt64 -c \"cd /c/msys64/tmp/webview2-gtk && ./scripts/vendor-webview2-sdk.sh && (test -d build/meson-private || meson setup build) && meson compile -C build 2>&1 | tee build/last-build.log && ./scripts/package-demos.sh\""
}

run_remote_smoke() {
	echo "[agent-remote-build] smoke run portable hello (3s) on ${REMOTE_HOST}"
	ssh -o BatchMode=yes "${REMOTE_HOST}" \
		"C:\\msys64\\msys2_shell.cmd -defterm -no-start -ucrt64 -c \"cd /c/msys64/tmp/webview2-gtk/dist-demos && timeout 3 ./webview2gtk-hello.exe 2>&1 | tee smoke-run.log || true\""
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
	if [[ -f "${ROOT}/build-remote/smoke-run.log" ]]; then
		echo "--- smoke-run.log ---"
		cat "${ROOT}/build-remote/smoke-run.log"
	fi
}

cmd="${1:-build}"

case "${cmd}" in
	build)
		sync_to_windows
		build_rc=0
		run_remote_build || build_rc=$?
		run_remote_smoke || true
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
	*)
		echo "usage: $0 [build|sync|remote-build|pull|run]" >&2
		exit 1
		;;
esac
