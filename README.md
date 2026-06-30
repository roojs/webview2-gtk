# webview2-gtk

**GTK 4** widget embedding **Microsoft Edge WebView2** on Windows — a practical substitute for WebKitGTK when you already use GTK and need a modern HTML engine.

![webview2-gtk browser demo](https://github.com/user-attachments/assets/6cbc26f0-a172-4615-ac48-70d2cc9bef53)

The widget takes the native HWND from `gdk_win32_surface_get_handle()` on the window’s `GdkSurface` and parents WebView2 there.

Build this library on **Windows**. Anything that links against it must be built on Windows too — there is no Linux cross-compile path.

You can still share Vala source with a Linux build that uses WebKitGTK instead (`#if WINDOWS` — see below).

**Windows commands:** open PowerShell, paste one line per step, run bash scripts in `scripts/` (see [How to run bash scripts from PowerShell](#how-to-run-msys2-from-powershell)). Same idea as [vala.win32 `docs/windows-build.md`](../vala.win32/docs/windows-build.md).

| | |
|--|--|
| Linux git host | e.g. `/home/alan/gitlive/webview2-gtk` |
| Windows SSH | `ssh snappr-win` (your Windows box) |
| Windows repo (agent rsync) | **`C:\msys64\tmp\webview2-gtk\`** |
| Portable demos (run at desktop) | **`C:\msys64\tmp\webview2-gtk\dist-demos\`** (or your clone’s `dist-demos\`) |
| Raw compile output | `build\` (needs toolchain on `PATH` — do not double-click) |

## How to run MSYS2 from PowerShell

Do **not** open the MSYS2 / UCRT64 terminal to paste blocks. That paste path is unreliable on this setup.

**Do not** use repo `.ps1` scripts — Windows PowerShell 5.1 misparses long embedded bash.

**Do** use **bash scripts in `scripts/`** and launch each with **one PowerShell line**:

```powershell
C:\msys64\msys2_shell.cmd -defterm -no-start -ucrt64 -c 'cd /c/msys64/tmp/webview2-gtk && ./scripts/SOME-SCRIPT.sh'
```

PowerShell only starts MSYS2; **bash** runs the logic.

Repo path inside MSYS2: **`/c/msys64/tmp/webview2-gtk`** (or `/c/path/to/webview2-gtk` for a local clone).

| Script | One PowerShell line |
|--------|---------------------|
| Toolchain (first time) | `... -c 'pacman -Syu --noconfirm && pacman -S --needed --noconfirm mingw-w64-ucrt-x86_64-gcc mingw-w64-ucrt-x86_64-vala mingw-w64-ucrt-x86_64-meson mingw-w64-ucrt-x86_64-ninja mingw-w64-ucrt-x86_64-pkg-config mingw-w64-ucrt-x86_64-gtk4 mingw-w64-ucrt-x86_64-cantarell-fonts mingw-w64-ucrt-x86_64-curl mingw-w64-ucrt-x86_64-nsis'` |
| Vendor WebView2 SDK | `... -c 'cd /c/msys64/tmp/webview2-gtk && ./scripts/vendor-webview2-sdk.sh'` |
| Configure + compile | `... -c 'cd /c/msys64/tmp/webview2-gtk && meson setup build && meson compile -C build'` |
| Package portable demos | `... -c 'cd /c/msys64/tmp/webview2-gtk && ./scripts/package-demos.sh'` |
| Build pacman package | `... -c 'cd /c/msys64/tmp/webview2-gtk && ./scripts/build-pacman-package.sh'` |
| Build NSIS installer | `... -c 'cd /c/msys64/tmp/webview2-gtk && ./scripts/build-installer.sh dist/webview2gtk'` |

(`...` = `C:\msys64\msys2_shell.cmd -defterm -no-start -ucrt64`)

Optional (once per PowerShell session): `function msys { & C:\msys64\msys2_shell.cmd -defterm -no-start -ucrt64 -c $args[0] }` then `msys 'cd /c/msys64/tmp/webview2-gtk && ./scripts/package-demos.sh'`.

## Download (Windows)

Two ways to install — pick one.

### Option A: `webview2gtk-setup.exe` (any Windows user)

Download **`webview2gtk-setup.exe`** from [GitHub Releases](https://github.com/YOUR_ORG/webview2-gtk/releases) and run it. Default location: `C:\Program Files\webview2gtk\`.

Check the install:

```powershell
C:\msys64\msys2_shell.cmd -defterm -no-start -ucrt64 -c 'export PKG_CONFIG_PATH="/c/Program Files/webview2gtk/lib/pkgconfig:$PKG_CONFIG_PATH"; pkg-config --modversion webview2gtk-1'
```

Demos (after install — double-click or from PowerShell):

```powershell
& 'C:\Program Files\webview2gtk\bin\webview2gtk-hello.exe'
```

Uninstall via Windows Settings → Apps.

### Option B: MSYS2 pacman (developers already using the UCRT64 toolchain)

Installs into `C:\msys64\ucrt64\` — `pkg-config --libs webview2gtk-1` works without extra `PKG_CONFIG_PATH`.

**From a release** (edit URL to match the release):

```powershell
C:\msys64\msys2_shell.cmd -defterm -no-start -ucrt64 -c 'pacman -U --noconfirm https://github.com/YOUR_ORG/webview2-gtk/releases/download/v0.1.0/mingw-w64-ucrt-x86_64-webview2gtk-0.1.0-1-any.pkg.tar.zst'
```

Verify:

```powershell
C:\msys64\msys2_shell.cmd -defterm -no-start -ucrt64 -c 'pkg-config --modversion webview2gtk-1'
```

Demos (inside UCRT64 — GTK on `PATH`): `C:\msys64\ucrt64\bin\webview2gtk-hello.exe`

Uninstall: `pacman -R mingw-w64-ucrt-x86_64-webview2gtk`

**Build the package yourself** (from a clone):

```powershell
C:\msys64\msys2_shell.cmd -defterm -no-start -ucrt64 -c 'cd /c/path/to/webview2-gtk && ./scripts/build-pacman-package.sh && pacman -U --noconfirm packaging/msys2/mingw-w64-ucrt-x86_64-webview2gtk-*.pkg.tar.zst'
```

PKGBUILD: [`packaging/msys2/PKGBUILD`](packaging/msys2/PKGBUILD)

## Requirements

- **Windows 10/11** with [WebView2 Runtime](https://developer.microsoft.com/en-us/microsoft-edge/webview2/) (Evergreen; usually preinstalled)
- **MSYS2** at `C:\msys64` ([installer](https://www.msys2.org/)) — see [How to run bash scripts from PowerShell](#how-to-run-msys2-from-powershell)

## Build this library

**One PowerShell line** (vendor SDK, configure, compile, package demos):

```powershell
C:\msys64\msys2_shell.cmd -defterm -no-start -ucrt64 -c 'cd /c/msys64/tmp/webview2-gtk && ./scripts/vendor-webview2-sdk.sh && meson setup build && meson compile -C build'
```

`meson compile` runs **`package-demos`** when examples are enabled (see below).

### Portable demos (`dist-demos\`) — run from Explorer / PowerShell

GTK apps built with MSYS2 need **toolchain DLLs** (`libgtk-4-1.dll`, `libglib-2.0-0.dll`, …) beside the `.exe`. Raw `build\webview2gtk-hello.exe` only has `WebView2Loader.dll` — double-clicking it shows **“cannot proceed because lib…dll was not found”**.

**Fix:** use **`dist-demos\`** (created automatically by `meson compile`, or manually via `./scripts/package-demos.sh`). That folder contains:

- `webview2gtk-hello.exe`, `webview2gtk-browser.exe`
- `WebView2Loader.dll` + GTK/GLib DLLs from `/ucrt64/bin` (via `ldd`)
- `etc/fonts`, `share/fonts` (fontconfig for runs outside UCRT64)
- `run-hello.bat`, `run-browser.bat` (optional — set font paths for Explorer double-click)

**Run the demos** (portable `dist-demos\` — DLLs bundled):

```powershell
& 'C:\msys64\tmp\webview2-gtk\dist-demos\webview2gtk-hello.exe'
& 'C:\msys64\tmp\webview2-gtk\dist-demos\webview2gtk-browser.exe' 'https://example.com/'
```

Re-package only (after a compile):

```powershell
C:\msys64\msys2_shell.cmd -defterm -no-start -ucrt64 -c 'cd /c/msys64/tmp/webview2-gtk && ./scripts/package-demos.sh'
```

**Where outputs land**

| Step | Demo location | GTK DLLs bundled? |
|------|----------------|-------------------|
| `build\` only | `build\webview2gtk-hello.exe` | **No** — dev compile artifact |
| `meson compile` (examples on) | `dist-demos\` | **Yes** — **use this to run** |
| `meson install` + `bundle-bin-runtime.sh` | `dist\webview2gtk\bin\` | **Yes** (CI / installer staging) |
| `webview2gtk-setup.exe` | `C:\Program Files\webview2gtk\bin\` | **Yes** (release installer) |
| pacman package | `C:\msys64\ucrt64\bin\` | Via UCRT64 `PATH` only |

You should see a GTK window with **Edge WebView2** content inside. [WebView2 Runtime](https://developer.microsoft.com/en-us/microsoft-edge/webview2/) must be installed on the PC.

### Troubleshooting

| Problem | Fix |
|---------|-----|
| `valac` not found | Run via PowerShell (`C:\msys64\msys2_shell.cmd -defterm -no-start -ucrt64 -c '…'`), not bare cmd |
| `cannot proceed because lib…dll was not found` | Run from **`dist-demos\`**, not raw `build\` |
| Web area blank | Rebuild; confirm WebView2 Runtime is installed |

### Remote build from Linux (rsync + SSH)

If you develop on Linux but have a Windows box with MSYS2 (same rsync/SSH pattern as **vala.win32** `scripts/agent-remote-build.sh`):

1. **SSH** — `~/.ssh/config` entry (e.g. `Host snappr-win` → your Windows host).
2. **Rsync on Windows** — `pacman -S rsync` in MSYS2 UCRT64.
3. **GTK4 on Windows** — run the toolchain line in [How to run bash scripts from PowerShell](#how-to-run-msys2-from-powershell) (first table row).

From the Linux clone:

```bash
./scripts/agent-remote-build.sh          # rsync → build on Windows → pull artifacts
./scripts/agent-remote-build.sh sync     # rsync only
./scripts/agent-remote-build.sh build    # sync + build + pull (default)
./scripts/agent-remote-build.sh pull     # pull build/ back only
./scripts/agent-remote-build.sh run      # 3s smoke run of hello on Windows
```

Sources mirror to `C:\msys64\tmp\webview2-gtk\` on the Windows host. Portable demos land in **`dist-demos\`** on Windows (and `build-remote/portable/` when pulled to Linux).

Override the SSH host: `AGENT_WIN_HOST=my-win-pc ./scripts/agent-remote-build.sh build`

Install to a prefix (for other Meson projects):

```powershell
C:\msys64\msys2_shell.cmd -defterm -no-start -ucrt64 -c 'cd /c/path/to/webview2-gtk && mkdir -p dist && meson setup build --prefix=$(pwd)/dist/webview2gtk && meson compile -C build && meson install -C build && ./scripts/bundle-bin-runtime.sh dist/webview2gtk/bin'
```

That produces `dist\webview2gtk\`:

```
dist\webview2gtk\
  bin\          webview2gtk-hello.exe, webview2gtk-browser.exe, WebView2Loader.dll
  lib\          libwebview2gtk-1.a, webview2gtk-1.vapi, WebView2Loader.dll, pkgconfig\
  include\      webview2gtk-1\webview2gtk.h, webview2gtk-host-api.h
```

### Build the Windows installer (.exe)

After the install step above (also needs NSIS once: `pacman -S mingw-w64-ucrt-x86_64-nsis` in UCRT64):

```powershell
C:\msys64\msys2_shell.cmd -defterm -no-start -ucrt64 -c 'cd /c/path/to/webview2-gtk && ./scripts/build-installer.sh dist/webview2gtk'
```

Output: `C:\path\to\webview2-gtk\webview2gtk-setup.exe`

## What you get

| Output | Purpose |
|--------|---------|
| `build\install-staging\lib\libwebview2gtk-1.a` | Static library |
| `build\install-staging\lib\webview2gtk-1.vapi` | Vala API |
| `build\install-staging\include\webview2gtk-1\webview2gtk.h` | C header |
| `build\install-staging\lib\pkgconfig\webview2gtk-1.pc` | pkg-config |
| `build\install-staging\lib\WebView2Loader.dll` | Ship next to your exe |
| `build\webview2gtk-hello.exe` | Minimal hello page |
| `build\webview2gtk-browser.exe` | Back / forward / reload / URL bar |

## Use in your app

```vala
using Gtk;

#if WINDOWS
using WebView2Gtk;
#else
using WebKit;
#endif

var web = new WebView ();
web.load_uri ("https://example.com/");
window.set_child (web);
```

On Windows, pass `-D WINDOWS` to `valac` (or use Meson — see sample below).

**Build locally:** copy [`scripts/sample-build.sh`](scripts/sample-build.sh) into your project, edit the settings at the top, then:

```powershell
C:\msys64\msys2_shell.cmd -defterm -no-start -ucrt64 -c 'cd /c/path/to/my-app && ./scripts/sample-build.sh'
```

### Sample `meson.build` (consumer project)

Full copy: [`examples/consumer-meson.build`](examples/consumer-meson.build)

```meson
project('my-browser-app', ['c', 'vala'], version: '1.0.0')

gtk4 = dependency('gtk4')
win = host_machine.system() == 'windows'

if win
  # setup.exe → 'C:/Program Files/webview2gtk/lib/pkgconfig'
  # pacman   → already on PKG_CONFIG_PATH under /ucrt64
  webview2gtk_pc = 'C:/Program Files/webview2gtk/lib/pkgconfig'
  meson.add_env('PKG_CONFIG_PATH', webview2gtk_pc, method: 'prepend')
  webview_dep = dependency('webview2gtk-1')
  vala_args = ['-D', 'WINDOWS']
else
  webview_dep = dependency('webkitgtk-6.0', version: '>= 6.0')
  vala_args = []
endif

executable(
  'my-browser-app',
  files('src/main.vala'),
  dependencies: [gtk4, webview_dep],
  vala_args: vala_args,
  install: true,
)
```

Build your app on each platform locally (Linux → WebKitGTK, Windows → webview2gtk).

## Deploying a Windows build

Ship a folder containing your `.exe` plus runtime DLLs. End users also need the [WebView2 Runtime](https://developer.microsoft.com/en-us/microsoft-edge/webview2/) on the PC.

### Runtime bundling (for your own app)

GTK/GLib DLLs live in `C:\msys64\ucrt64\bin\` at **build** time. They are **not** linked statically. To run from Explorer or plain PowerShell, copy toolchain DLLs beside your exe (same approach as **vala.win32** `copy_ldd_runtime_dlls` in `scripts/build-win.sh`).

**Reuse from this repo:**

| Script | Purpose |
|--------|---------|
| [`scripts/copy-exe-runtime-dlls.sh`](scripts/copy-exe-runtime-dlls.sh) | Core: `ldd` an exe → copy `/ucrt64/bin` deps into an output dir |
| [`scripts/sample-package-windows.sh`](scripts/sample-package-windows.sh) | Template for consumer apps: exe + `WebView2Loader.dll` + GTK DLLs → `dist/` |
| [`scripts/package-demos.sh`](scripts/package-demos.sh) | This repo’s hello + browser → `dist-demos/` |
| [`scripts/bundle-bin-runtime.sh`](scripts/bundle-bin-runtime.sh) | All exes in a `bin/` dir (meson install / GitHub release staging) |

**Minimal integration** — copy `copy-exe-runtime-dlls.sh` + `sample-package-windows.sh` into your project, build, then:

```powershell
C:\msys64\msys2_shell.cmd -defterm -no-start -ucrt64 -c 'cd /c/path/to/my-app && EXE_PATH=build/my-browser-app.exe ./scripts/package-windows.sh'
```

That writes `dist\my-browser-app.exe`, `WebView2Loader.dll`, and GTK DLLs. Zip `dist\` for download.

**Wrapping in your own tooling:** one PowerShell line per step — `C:\msys64\msys2_shell.cmd -defterm -no-start -ucrt64 -c '…./scripts/….sh'`. For CI (GitHub Actions) use `shell: msys2 {0}` and call the same bash scripts directly.

### Local packaging

Same as **Minimal integration** above — copy scripts into your project:

```powershell
C:\msys64\msys2_shell.cmd -defterm -no-start -ucrt64 -c 'cd /c/path/to/my-app && EXE_PATH=build/my-browser-app.exe ./scripts/package-windows.sh'
```

That copies your exe, `WebView2Loader.dll`, and missing GTK/GLib DLLs from the toolchain into `dist\`. Zip `dist\` for download.

### GitHub Actions

1. Copy [`scripts/sample-github-build-windows.yml`](scripts/sample-github-build-windows.yml) → `.github/workflows/build-windows.yml` in **your** repo.
2. Copy `scripts/copy-exe-runtime-dlls.sh` and `scripts/sample-package-windows.sh` → `scripts/package-windows.sh`.
3. Edit the `env` block (`APP_EXE_NAME`, `WEBVIEW2GTK_REPO`, …) and the **Build app** step for your Meson project.
4. Push — the workflow builds webview2gtk, builds your app, runs `package-windows.sh`, and uploads `dist/` as an artifact. On a GitHub **Release**, it also attaches `my-app-windows.zip`.

Add webview2-gtk as a **submodule** at `webview2-gtk/` to skip the clone step, or point `WEBVIEW2GTK_REPO` at your fork.

(This library’s own releases use [`.github/workflows/release.yml`](.github/workflows/release.yml): push a tag like `v0.1.0` to build and publish **`webview2gtk-setup.exe`** and **`mingw-w64-ucrt-x86_64-webview2gtk-*.pkg.tar.zst`**. Manual run: Actions → Release → Run workflow.)

## API (WebKitGTK 6–aligned)

`WebView2Gtk.WebView` mirrors the common **WebKit.WebView** surface so the same Vala call sites compile on Linux (WebKitGTK) and Windows (WebView2):

| WebKitGTK 6 | WebView2Gtk |
|-------------|-------------|
| `load_uri()` | `load_uri()` |
| `load_html()` / `load_plain_text()` | same |
| `go_back()` / `go_forward()` / `reload()` | same |
| `can_go_back()` / `can_go_forward()` | same |
| `stop_loading()` | same |
| `get_uri()` / `get_title()` | same (`web.uri` / `web.title` on WebKit; use getters on both for shared code) |
| `is_loading` / `estimated_load_progress` | same (progress is approximate) |
| `zoom_level` / `get_zoom_level()` / `set_zoom_level()` | same |
| `load_changed(LoadEvent)` | same enum names |

WebView2Gtk-only: `ready` — host COM object attached.

Not implemented yet: settings, inspector, policy callbacks, JS bridge, etc. (`load_failed` and `JavaScriptResult.to_string` are implemented.)

**Limitation:** one WebView2 host per process today (shared COM singleton).

## Layout

```
lib/host/           WebView2 COM host (from vala.win32)
lib/webview2gtk/    Public GTK 4 widget (Vala)
generated/          Host glue
vapi/               Win32/WebView2 bindings for the host
examples/hello/     Hello HTML demo
examples/browser/   Minimal browser chrome
examples/consumer-meson.build   Sample Meson for your app
packaging/          NSIS installer + packaging/msys2/PKGBUILD (pacman)
scripts/            vendor SDK, build, package-demos.sh, copy-exe-runtime-dlls.sh,
                    sample-build.sh, sample-package-windows.sh,
                    sample-github-build-windows.yml, agent-remote-build.sh,
                    build-pacman-package.sh, bundle-bin-runtime.sh
.github/workflows/  Release CI (tag `v*` → setup.exe + pacman package)
```

## Manual build (without top-level Meson)

```powershell
C:\msys64\msys2_shell.cmd -defterm -no-start -ucrt64 -c 'cd /c/path/to/webview2-gtk && ./scripts/vendor-webview2-sdk.sh && ./scripts/wv2gtk-build.sh lib build build/install-staging && ./scripts/wv2gtk-build.sh hello build build/webview2gtk-hello.exe && ./scripts/wv2gtk-build.sh browser build build/webview2gtk-browser.exe && ./scripts/package-demos.sh'
```

## Origin

Host stack vendored from **vala.win32** (Phase 7 WebView2). This repo is the GTK 4 widget layer and packaging.
