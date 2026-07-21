# Install webview2-gtk (Windows)

Requirements:

- **Windows 10/11** with [WebView2 Runtime](https://developer.microsoft.com/en-us/microsoft-edge/webview2/) (Evergreen; usually preinstalled)
- For building or pacman installs: **MSYS2** at `C:\msys64` ([installer](https://www.msys2.org/)) — see [build-this-library.md](build-this-library.md) for how to run UCRT64 bash from PowerShell

Two ways to install the library — pick one.

## Option A: `webview2gtk-setup.exe` (any Windows user)

Download **`webview2gtk-setup.exe`** from [GitHub Releases](https://github.com/roojs/webview2-gtk/releases) and run it. Default location: `C:\Program Files\webview2gtk\`.

Check the install:

```powershell
C:\msys64\msys2_shell.cmd -defterm -no-start -ucrt64 -c 'export PKG_CONFIG_PATH="/c/Program Files/webview2gtk/lib/pkgconfig:$PKG_CONFIG_PATH"; pkg-config --modversion webview2gtk-1'
```

Demos (after install):

```powershell
& 'C:\Program Files\webview2gtk\bin\webview2gtk-hello.exe'
```

Uninstall via Windows Settings → Apps.

## Option B: MSYS2 pacman (UCRT64 toolchain)

Installs into `C:\msys64\ucrt64\` — `pkg-config --libs webview2gtk-1` works without extra `PKG_CONFIG_PATH`.

**From a release** (edit the URL to match the asset on [Releases](https://github.com/roojs/webview2-gtk/releases)):

```powershell
C:\msys64\msys2_shell.cmd -defterm -no-start -ucrt64 -c 'pacman -U --noconfirm https://github.com/roojs/webview2-gtk/releases/download/vX.Y.Z/mingw-w64-ucrt-x86_64-webview2gtk-X.Y.Z-1-any.pkg.tar.zst'
```

Verify:

```powershell
C:\msys64\msys2_shell.cmd -defterm -no-start -ucrt64 -c 'pkg-config --modversion webview2gtk-1'
```

Demos (GTK on `PATH` inside UCRT64): `C:\msys64\ucrt64\bin\webview2gtk-hello.exe`

Uninstall: `pacman -R mingw-w64-ucrt-x86_64-webview2gtk`

**Build the package yourself** (from a clone):

```powershell
C:\msys64\msys2_shell.cmd -defterm -no-start -ucrt64 -c 'cd /c/path/to/webview2-gtk && ./scripts/build-pacman-package.sh && pacman -U --noconfirm packaging/msys2/mingw-w64-ucrt-x86_64-webview2gtk-*.pkg.tar.zst'
```

PKGBUILD: [`packaging/msys2/PKGBUILD`](../packaging/msys2/PKGBUILD)
