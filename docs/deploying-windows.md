# Deploying a Windows build

Ship a folder containing your `.exe` plus runtime DLLs. End users also need the [WebView2 Runtime](https://developer.microsoft.com/en-us/microsoft-edge/webview2/) on the PC.

## Runtime bundling

GTK/GLib DLLs live in `C:\msys64\ucrt64\bin\` at **build** time. They are **not** linked statically. To run from Explorer or plain PowerShell, copy toolchain DLLs beside your exe.

| Script | Purpose |
|--------|---------|
| [`scripts/copy-exe-runtime-dlls.sh`](../scripts/copy-exe-runtime-dlls.sh) | `ldd` an exe → copy `/ucrt64/bin` deps into an output dir |
| [`scripts/sample-package-windows.sh`](../scripts/sample-package-windows.sh) | Template: exe + `WebView2Loader.dll` + GTK DLLs → `dist/` |
| [`scripts/package-demos.sh`](../scripts/package-demos.sh) | This repo’s hello + browser → `dist-demos/` |
| [`scripts/bundle-bin-runtime.sh`](../scripts/bundle-bin-runtime.sh) | All exes in a `bin/` dir (meson install / release staging) |

Copy `copy-exe-runtime-dlls.sh` + `sample-package-windows.sh` into your project (rename the latter to `package-windows.sh` if you like), build, then:

```powershell
C:\msys64\msys2_shell.cmd -defterm -no-start -ucrt64 -c 'cd /c/path/to/my-app && EXE_PATH=build/my-browser-app.exe ./scripts/package-windows.sh'
```

That writes `dist\my-browser-app.exe`, `WebView2Loader.dll`, and GTK DLLs. Zip `dist\` for download.

## GitHub Actions

1. Copy [`scripts/sample-github-build-windows.yml`](../scripts/sample-github-build-windows.yml) → `.github/workflows/build-windows.yml` in **your** repo.
2. Copy `scripts/copy-exe-runtime-dlls.sh` and `scripts/sample-package-windows.sh` → `scripts/package-windows.sh`.
3. Edit the `env` block and the **Build app** step for your Meson project.
4. Push — the workflow builds webview2gtk (or uses a submodule), builds your app, packages `dist/`, and uploads an artifact. On a GitHub **Release**, it can attach a zip.

Add webview2-gtk as a **submodule** at `webview2-gtk/` to skip the clone step, or point `WEBVIEW2GTK_REPO` at your fork.

This library’s own releases use [`.github/workflows/release.yml`](../.github/workflows/release.yml) (tag `v*` → `webview2gtk-setup.exe` + pacman package).
