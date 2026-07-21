# Build this library

Build **webview2-gtk** on **Windows** (MSYS2 UCRT64). There is no Linux cross-compile path for the library itself. Valadoc can be built on Linux with `-Ddocs=true` — see [code-documentation.md](code-documentation.md).

## How to run MSYS2 from PowerShell

Do **not** open the MSYS2 / UCRT64 terminal to paste long blocks.

**Do** launch bash scripts with **one PowerShell line**:

```powershell
C:\msys64\msys2_shell.cmd -defterm -no-start -ucrt64 -c 'cd /c/path/to/webview2-gtk && ./scripts/SOME-SCRIPT.sh'
```

PowerShell only starts MSYS2; **bash** runs the logic. Change `C:\msys64` if your MSYS2 root differs.

Optional (once per PowerShell session):

```powershell
function msys { & C:\msys64\msys2_shell.cmd -defterm -no-start -ucrt64 -c $args[0] }
```

Then: `msys 'cd /c/path/to/webview2-gtk && ./scripts/package-demos.sh'`

| Script | One PowerShell line (`...` = `C:\msys64\msys2_shell.cmd -defterm -no-start -ucrt64`) |
|--------|-------------------------------------------------------------------------------------|
| Toolchain (first time) | `... -c 'pacman -Syu --noconfirm && pacman -S --needed --noconfirm mingw-w64-ucrt-x86_64-gcc mingw-w64-ucrt-x86_64-vala mingw-w64-ucrt-x86_64-meson mingw-w64-ucrt-x86_64-ninja mingw-w64-ucrt-x86_64-pkg-config mingw-w64-ucrt-x86_64-gtk4 mingw-w64-ucrt-x86_64-libgee mingw-w64-ucrt-x86_64-libsoup3 mingw-w64-ucrt-x86_64-cantarell-fonts mingw-w64-ucrt-x86_64-curl mingw-w64-ucrt-x86_64-nsis'` |
| Vendor WebView2 SDK | `... -c 'cd /c/path/to/webview2-gtk && ./scripts/vendor-webview2-sdk.sh'` |
| Configure + compile | `... -c 'cd /c/path/to/webview2-gtk && meson setup build && meson compile -C build'` |
| Package portable demos | `... -c 'cd /c/path/to/webview2-gtk && ./scripts/package-demos.sh'` |
| Build pacman package | `... -c 'cd /c/path/to/webview2-gtk && ./scripts/build-pacman-package.sh'` |
| Build NSIS installer | `... -c 'cd /c/path/to/webview2-gtk && ./scripts/build-installer.sh dist/webview2gtk'` |

Same idea as [vala.win32 `docs/windows-build.md`](https://github.com/roojs/vala.win32/blob/master/docs/windows-build.md).

## Configure and compile

```powershell
C:\msys64\msys2_shell.cmd -defterm -no-start -ucrt64 -c 'cd /c/path/to/webview2-gtk && ./scripts/vendor-webview2-sdk.sh && meson setup build && meson compile -C build'
```

With examples enabled (default), `meson compile` also runs **`package-demos`** → `dist-demos\`.

Install to a prefix (for other Meson projects / installer staging):

```powershell
C:\msys64\msys2_shell.cmd -defterm -no-start -ucrt64 -c 'cd /c/path/to/webview2-gtk && mkdir -p dist && meson setup build --prefix=$(pwd)/dist/webview2gtk && meson compile -C build && meson install -C build && ./scripts/bundle-bin-runtime.sh dist/webview2gtk/bin'
```

Build the NSIS installer after that (needs `mingw-w64-ucrt-x86_64-nsis`):

```powershell
C:\msys64\msys2_shell.cmd -defterm -no-start -ucrt64 -c 'cd /c/path/to/webview2-gtk && ./scripts/build-installer.sh dist/webview2gtk'
```

## Portable demos (`dist-demos\`)

GTK apps need toolchain DLLs beside the `.exe`. Raw `build\webview2gtk-hello.exe` only has `WebView2Loader.dll` — double-clicking it fails with missing `lib…dll`.

Use **`dist-demos\`** (from `meson compile` or `./scripts/package-demos.sh`):

```powershell
& 'C:\path\to\webview2-gtk\dist-demos\webview2gtk-hello.exe'
& 'C:\path\to\webview2-gtk\dist-demos\webview2gtk-browser.exe' 'https://example.com/'
```

| Step | Demo location | GTK DLLs bundled? |
|------|----------------|-------------------|
| `build\` only | `build\webview2gtk-*.exe` | **No** |
| `meson compile` (examples on) | `dist-demos\` | **Yes** — use this to run |
| `meson install` + `bundle-bin-runtime.sh` | `dist\webview2gtk\bin\` | **Yes** |
| `webview2gtk-setup.exe` | `C:\Program Files\webview2gtk\bin\` | **Yes** |
| pacman package | `C:\msys64\ucrt64\bin\` | Via UCRT64 `PATH` |

## What you get

| Output | Purpose |
|--------|---------|
| `build\install-staging\lib\libwebview2gtk-1.a` | Static library |
| `build\install-staging\lib\webview2gtk-1.vapi` | Vala API |
| `build\install-staging\include\webview2gtk-1\…` | C headers |
| `build\install-staging\lib\pkgconfig\webview2gtk-1.pc` | pkg-config |
| `build\install-staging\lib\WebView2Loader.dll` | Ship next to your exe |
| `build\webview2gtk-hello.exe` / `browser.exe` | Demos (prefer `dist-demos\`) |

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `valac` not found | Run via `msys2_shell.cmd … -ucrt64 -c '…'`, not bare cmd |
| `cannot proceed because lib…dll was not found` | Run from **`dist-demos\`**, not raw `build\` |
| Web area blank | Confirm [WebView2 Runtime](https://developer.microsoft.com/en-us/microsoft-edge/webview2/) is installed |

## Remote build from Linux (rsync + SSH)

If you develop on Linux but have a Windows box with MSYS2:

```bash
./scripts/agent-remote-build.sh          # sync + build + pull (default)
./scripts/agent-remote-build.sh sync
./scripts/agent-remote-build.sh pull
./scripts/agent-remote-build.sh run      # short smoke of hello on Windows
```

Override host: `AGENT_WIN_HOST=my-win-pc ./scripts/agent-remote-build.sh build`

Sources mirror to `C:\msys64\tmp\webview2-gtk\` by default.
