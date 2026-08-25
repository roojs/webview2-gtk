# Bug: WebView stays unattached / blank when nested (e.g. ScrolledWindow)

**Status:** ✅ fixed (host content size + box expand + `WebView.map` attach retry)  
**Date:** 2026-08-21  
**Component:** `lib/webview2gtk/webview.vala`  
**Seen in:** nested `WebView` (e.g. `Gtk.ScrolledWindow` / overlay) — blank on Windows; a later-mapped sibling WebView could still work.

## Symptom

`load_uri` before or during first layout does not show a page. Apps that poll `get_mapped()` / size in Idle either hang forever or race. Linux WebKit in the same GTK tree is fine.

## Cause

1. Attach runs from the inner `DrawingArea` map / tick / `size_allocate`, using `widget_bounds_xywh(host)`.
2. The host `DrawingArea` had **no content size** and relied only on expand. Nested in `Gtk.ScrolledWindow` / overlays, it often got **0×0** (or never mapped as the app expected), so `try_attach` bailed and the pending URI never navigated on screen.
3. `WebView.map` only called `sync_host_visible`, not `try_attach`, so a mapped outer box with an unallocated host left the COM host uncreated.

## Fix

- Give the host DrawingArea a minimal content size so layout always yields w/h &gt; 0 once the parent has space.
- Hex/vexpand the `WebView` box itself in `WebView()`.
- On `WebView.map`, `try_attach` + Idle retry (same pattern as `on_host_map`), then `try_navigate` for pending URI/HTML.

## App side

Callers should `load_uri` normally (pending navigate is enough). Do **not** Idle-spin on `web_view.get_mapped()` — that deadlocks when map waits on attach/content.
