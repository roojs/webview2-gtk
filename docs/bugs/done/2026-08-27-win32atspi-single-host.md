# Bug — Win32Atspi only walks the last registered WebView

**Status:** ✅ fixed in **0.5.4**  
**Platform:** Windows  
**Area:** `lib/webview2gtk/win32atspi/Win32Atspi.vala` (`Bridge`), `win32-ui-webview2-a11y.c`  
**Seen:** 2026-08-27

---

## Problem

🔷 `Win32Atspi.register_webview(web)` stores a **single** `Bridge.host`.

🔷 Each attach overwrites the previous host. `rebuild()` walks only that host’s HWND.

🔷 A process with two (or more) `WebView` instances can dump the **wrong** Document (title / tree from the last-registered view).

🔷 Callers that match by document name / URI (AT-SPI-shaped walk) still see the other view’s tree when only one host is registered.

---

## Wanted

🔷 Stay inside the **existing** Win32Atspi / AT-SPI-shaped surface already exposed
  (`init`, `get_desktop`, `Accessible` tree, `register_webview`). **No new public API.**

🔷 Match the multi-document reality consumers already assume on Linux AT-SPI: more than
  one `document frame` / `document text` can appear under the application, and walkers
  select by name (and URI when present).

🔷 Implementation may track every live registered WebView and rebuild a desktop that
  includes each host’s Document — still via today’s `register_webview` + `get_desktop`
  / child walk. Do **not** invent a parallel “set active host” / dump-target API.

🔷 Until fixed: document that today’s `register_webview` is process-global last-wins
  (workaround: re-call on the target view before dump) — documentation only, not a
  substitute for the multi-Document tree.

---

## Fix

`register_webview` keeps every live `WebView` (weak). `get_desktop` resets the UIA
element cache, walks each ready host, and hangs **one `document frame` per host**
under the application frame. Invoke ids stay unique across that combined walk.

Because several controllers share the GTK toplevel HWND, the host walk picks the
`Chrome_WidgetWin_1` whose window rect overlaps that controller’s bounds, instead of
the first one enumerated.

No public API change.

---

## Notes

🔷 Multi-WebView backlog already noted in `docs/plans/4.0-multi-webview-host.md` /
  `1.0-uia-accessibility.md`.

🔷 Private apps may re-pin with `register_webview` before dump; that is not the
  intended long-term contract.

---

## Related

- [docs/a11y.md](../../a11y.md)  
- [plans/4.0-multi-webview-host.md](../../plans/4.0-multi-webview-host.md)  
