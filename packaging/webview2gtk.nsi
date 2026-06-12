; webview2-gtk Windows installer (NSIS)
;
; Build from MSYS2 UCRT64 after meson install:
;   WIN_SRC=$(cygpath -aw "$PWD/dist/webview2gtk")
;   makensis -DINST_SRC="$WIN_SRC" -DPRODUCT_VERSION=0.1.0 packaging/webview2gtk.nsi
;
; Or: ./scripts/build-installer.sh dist/webview2gtk

!include "MUI2.nsh"

Name "webview2-gtk"
OutFile "webview2gtk-setup.exe"
InstallDir "$PROGRAMFILES64\webview2gtk"
InstallDirRegKey HKLM "Software\webview2-gtk" "InstallDir"
RequestExecutionLevel admin
Unicode true

!ifndef PRODUCT_VERSION
  !define PRODUCT_VERSION "0.1.0"
!endif
!ifndef INST_SRC
  !define INST_SRC "dist\webview2gtk"
!endif

!define PRODUCT_PUBLISHER "webview2-gtk"
!define PRODUCT_WEB_SITE "https://github.com/webview2-gtk/webview2-gtk"
!define UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\webview2-gtk"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

Section "webview2-gtk" SecMain
  SectionIn RO
  SetOutPath "$INSTDIR"

  SetOutPath "$INSTDIR\bin"
  File "${INST_SRC}\bin\webview2gtk-hello.exe"
  File "${INST_SRC}\bin\webview2gtk-browser.exe"
  File "${INST_SRC}\bin\WebView2Loader.dll"

  SetOutPath "$INSTDIR\lib"
  File "${INST_SRC}\lib\libwebview2gtk-1.a"
  File "${INST_SRC}\lib\webview2gtk-1.vapi"
  File "${INST_SRC}\lib\WebView2Loader.dll"

  SetOutPath "$INSTDIR\lib\pkgconfig"
  File "${INST_SRC}\lib\pkgconfig\webview2gtk-1.pc"

  SetOutPath "$INSTDIR\include\webview2gtk-1"
  File "${INST_SRC}\include\webview2gtk-1\webview2gtk.h"
  File "${INST_SRC}\include\webview2gtk-1\webview2gtk-host-api.h"

  FileOpen $0 "$INSTDIR\README.txt" w
  FileWrite $0 "webview2-gtk ${PRODUCT_VERSION}$\r$\n$\r$\n"
  FileWrite $0 "Installed to: $INSTDIR$\r$\n$\r$\n"
  FileWrite $0 "Check install (UCRT64):$\r$\n"
  FileWrite $0 "  C:\msys64\ucrt64.exe -c $\"export PKG_CONFIG_PATH=$INSTDIR\lib\pkgconfig:$$PKG_CONFIG_PATH; pkg-config --modversion webview2gtk-1$\"$\r$\n$\r$\n"
  FileWrite $0 "Build your app (UCRT64 shell):$\r$\n"
  FileWrite $0 "  export PKG_CONFIG_PATH=$\"$INSTDIR\lib\pkgconfig$\":$$PKG_CONFIG_PATH$\r$\n"
  FileWrite $0 "  pkg-config --modversion webview2gtk-1$\r$\n$\r$\n"
  FileWrite $0 "Demos:$\r$\n"
  FileWrite $0 "  $INSTDIR\bin\webview2gtk-hello.exe$\r$\n"
  FileWrite $0 "  $INSTDIR\bin\webview2gtk-browser.exe$\r$\n$\r$\n"
  FileWrite $0 "Ship WebView2Loader.dll next to your own .exe.$\r$\n"
  FileWrite $0 "WebView2 Runtime must be installed on the target PC.$\r$\n"
  FileClose $0

  Call FixPkgConfig

  WriteRegStr HKLM "Software\webview2-gtk" "InstallDir" "$INSTDIR"
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  WriteRegStr HKLM "${UNINST_KEY}" "DisplayName" "webview2-gtk"
  WriteRegStr HKLM "${UNINST_KEY}" "DisplayVersion" "${PRODUCT_VERSION}"
  WriteRegStr HKLM "${UNINST_KEY}" "Publisher" "${PRODUCT_PUBLISHER}"
  WriteRegStr HKLM "${UNINST_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "${UNINST_KEY}" "UninstallString" "$\"$INSTDIR\Uninstall.exe$\""
  WriteRegDWORD HKLM "${UNINST_KEY}" "NoModify" 1
  WriteRegDWORD HKLM "${UNINST_KEY}" "NoRepair" 1
SectionEnd

Function FixPkgConfig
  FileOpen $0 "$INSTDIR\lib\pkgconfig\webview2gtk-1.pc" w
  FileWrite $0 "prefix=$INSTDIR$\r$\n"
  FileWrite $0 "libdir=$${prefix}/lib$\r$\n"
  FileWrite $0 "includedir=$${prefix}/include$\r$\n"
  FileWrite $0 "$\r$\n"
  FileWrite $0 "Name: webview2gtk-1$\r$\n"
  FileWrite $0 "Description: GTK 4 WebView2 widget for Windows (Edge Chromium)$\r$\n"
  FileWrite $0 "Version: ${PRODUCT_VERSION}$\r$\n"
  FileWrite $0 "Requires: gtk4$\r$\n"
  FileWrite $0 "Libs: -L$${libdir} -lwebview2gtk-1 -lole32 -luuid -lshell32 -ladvapi32$\r$\n"
  FileWrite $0 "Cflags: -I$${includedir}/webview2gtk-1$\r$\n"
  FileClose $0
FunctionEnd

Section "Uninstall"
  Delete "$INSTDIR\README.txt"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir /r "$INSTDIR\bin"
  RMDir /r "$INSTDIR\lib"
  RMDir /r "$INSTDIR\include"
  RMDir "$INSTDIR"
  DeleteRegKey HKLM "${UNINST_KEY}"
  DeleteRegKey HKLM "Software\webview2-gtk"
SectionEnd
