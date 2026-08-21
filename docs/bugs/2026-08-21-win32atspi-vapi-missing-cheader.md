# Bug — consumer Vala using only `Win32Atspi` fails at gcc

**Status:** ✅ fixed (vapi `cheader_filename` on `Win32Atspi`)  
**Severity:** blocker for any app that dumps/walks a11y in its own `.vala` file  
**Opened:** 2026-08-21  
**Seen on:** `mingw-w64-ucrt-x86_64-webview2gtk` **0.4.2-1** (`/ucrt64`)

## Problem

Public docs treat `Win32Atspi.*` as the Windows drop-in for Linux `Atspi.*` ([README](../../README.md), [docs/a11y.md](../a11y.md), [docs/using-in-your-app.md](../using-in-your-app.md)). That path compiles in Vala and then **dies in gcc**.

A consumer file that only talks to `Win32Atspi` (no `WebView2Gtk.WebView` in the same translation unit) produces C that uses `Win32AtspiAccessible` / `win32_atspi_*` with **no `#include` of `webview2gtk.h`**.

Shared apps that rewrite `Atspi` → `Win32Atspi` in a11y modules (files that never mention `WebView`) hit this: Valac succeeds; gcc fails:

```text
A11y.win32atspi.c: unknown type name 'Win32AtspiAccessible'
implicit declaration of function 'win32_atspi_init' / 'win32_atspi_get_desktop' / …
'WIN32_ATSPI_TYPE_ACCESSIBLE' undeclared
'WIN32_ATSPI_SCROLL_TYPE_BOTTOM_EDGE' undeclared
```

Generated includes from that file (0.4.2 install, consumer rebuild):

```c
#include <glib-object.h>
#include <gee.h>
#include <glib.h>
#include <gio/gio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
```

No `webview2gtk.h`.

## Why it looks packaged

0.4.2 **does** ship the C types. Installed tree is only:

- `/ucrt64/include/webview2gtk-1/webview2gtk.h` — **contains** `Win32AtspiAccessible`, `win32_atspi_init`, enums, … (generated `-H` from the lib valac run)
- `/ucrt64/include/webview2gtk-1/webview2gtk-host-api.h`
- `/ucrt64/lib/webview2gtk-1.vapi`
- `/ucrt64/lib/pkgconfig/webview2gtk-1.pc`

This is **not** a missing second header file. gcc never sees the header that is already there.

## Root cause

Hand-written `vapi/webview2gtk-1.vapi`:

- `[CCode(cheader_filename = "webview2gtk.h")]` is on **`WebView2Gtk.WebView` only** (around line 199).
- `namespace Win32Atspi` (from line 257) has **no** `cheader_filename`.

Consumer valac therefore emits Win32Atspi C names with no include. Linux `atspi-2` vapi does set `cheader_filename` on the real AT-SPI headers, which is why the same sources compile on Linux.

In-tree builds hide this:

| Path | Why gcc is happy |
|------|------------------|
| Lib objects | `scripts/wv2gtk-build.sh` compiles generated widget/Win32Atspi `.c` with `-include "${GTK_HEADER}"` |
| `examples/browser` | `main.vala` also uses `WebView`, so that one `.c` gets `#include <webview2gtk.h>` from the WebView CCode |

A consumer a11y module is neither of those.

## Repro (minimal)

Against an installed 0.4.2 prefix, compile a Vala file that **only** uses Win32Atspi (do not also construct a `WebView` in the same file):

```vala
using Win32Atspi;

void walk () {
	Win32Atspi.init ();
	var desktop = Win32Atspi.get_desktop (0);
	var n = desktop.get_child_count ();
	if (n > 0) {
		var acc = desktop.get_child_at_index (0);
		acc.get_name ();
		acc.get_role_name ();
	}
}
```

`valac --pkg webview2gtk-1 -C …` then gcc the emitted `.c` with `pkg-config --cflags webview2gtk-1`. Expect the same unknown-type errors.

`examples/browser` is **not** this repro.

## Proposed fix

🔷 Add `[CCode(cheader_filename = "webview2gtk.h")]` on `namespace Win32Atspi` (and on the types if Vala does not inherit the namespace attribute — match whatever `WebView` already does).

🔷 Add a **consumer** meson/check target: one `.vala` that uses **only** `Win32Atspi`, compiled against the **staged/installed** vapi + header (no `-include` override). Fail the release if gcc cannot compile that `.c`.

🔷 Keep shipping Win32Atspi declarations in the public `webview2gtk.h` (already true for 0.4.2 install). Do not split a second public header unless the vapi `cheader_filename` is updated to match.

## Related packaging nits (same install, not this gcc failure)

- ℹ️ In-tree `lib/webview2gtk/webview2gtk.h` is a **stale** valac dump (WebView only). Install copies the generated header; the committed file does not. Easy to misread when debugging.
- ℹ️ Vapi is installed to **`lib/webview2gtk-1.vapi`**, not `share/vala/vapi`. Consumers need `--vapidir ${prefix}/lib` (or equivalent). Valac `Package webview2gtk-1 not found` without that.
- ℹ️ `webview2gtk-1.pc` `Version` was stuck at `0.2.0` on the 0.4.2 install (`pkg-config --modversion` lied). Fixed in 0.4.3.

## Attempts

- ✔️ 2026-08-21 — pacman 0.4.2-1 on a Windows UCRT64 host. Consumer Vala (including `WebViewAuto` / WebsitePolicies) compiles. gcc dies on the rewritten a11y `.c` that only uses `Win32Atspi`.
- ✔️ Confirmed installed `webview2gtk.h` already declares `Win32AtspiAccessible` (85 `Win32Atspi` hits). Missing include, not missing types.
- ✔️ 2026-08-21 — `[CCode(cheader_filename = "webview2gtk.h")]` on `namespace Win32Atspi` in `vapi/webview2gtk-1.vapi`.
- 🚫 Do not work around this in the consumer by `#include` hacks, compiling `Win32Atspi.vala` into the app, or wrapping dump in `#if !WINDOWS`. Fix the vapi.
