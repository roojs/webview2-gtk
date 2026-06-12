#!/usr/bin/env python3
"""Copy staged library artifacts into the meson install prefix."""
import os
import shutil
import sys


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <staged-lib-dir>", file=sys.stderr)
        return 1

    stage = sys.argv[1]
    install = os.environ.get("MESON_INSTALL_DESTDIR_PREFIX")
    if not install:
        print("MESON_INSTALL_DESTDIR_PREFIX not set", file=sys.stderr)
        return 1

    stage_lib = os.path.join(stage, "lib")
    if not os.path.isdir(stage_lib):
        return 0

    install_lib = os.path.join(install, "lib")
    install_inc = os.path.join(install, "include", "webview2gtk-1")
    install_pc = os.path.join(install_lib, "pkgconfig")
    os.makedirs(install_pc, exist_ok=True)
    os.makedirs(install_inc, exist_ok=True)

    for name in (
        "libwebview2gtk-1.a",
        "webview2gtk-1.vapi",
        "WebView2Loader.dll",
    ):
        src = os.path.join(stage_lib, name)
        if os.path.isfile(src):
            shutil.copy2(src, os.path.join(install_lib, name))

    stage_inc = os.path.join(stage, "include", "webview2gtk-1")
    if os.path.isdir(stage_inc):
        for name in os.listdir(stage_inc):
            src = os.path.join(stage_inc, name)
            if os.path.isfile(src):
                shutil.copy2(src, os.path.join(install_inc, name))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
