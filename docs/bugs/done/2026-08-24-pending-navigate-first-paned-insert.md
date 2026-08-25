# Bug: pending `load_uri` blank after first paned insert

**Status:** ✅ fixed in **0.5.1** (host DrawingArea created in `construct`, not only `WebView()`)  
**Date:** 2026-08-24 (fixed 2026-08-25)  
**Component:** `lib/webview2gtk/webview.vala`  
**Repro / test:** [`examples/paned-insert`](../../../examples/paned-insert/main.vala) — `--smoke`

## Symptom

1. Browser `Gtk.Stack` (primary + management) is **constructed** while a login panel owns the paned start child (stack orphaned).
2. After sign-in: `paned.set_start_child(browser_stack)` then `primary.load_uri(...)` (often 0×0, then real size; sometimes a second `load_uri` after session-loading churn).
3. Primary reaches real size, opacity 1, stack=`primary`, Vala URI field set — **zero** `load_changed`. Pane stays blank.
4. Plain `new WebView()` demos / management paths that use the default constructor can still work on the same host.

## Root cause

`WebView` created the host `Gtk.DrawingArea` (map / tick / attach) only in `WebView()`. Subclasses that chain with `Object(web_context:…, is_controlled_by_automation:…)` (WebKitGTK-shaped automation construct) **never run** `WebView()`, so `host` stayed null, `try_attach` always bailed, and pending navigate never reached COM.

Orphaned-stack timing made this obvious; the defect is the construct path, not paned reparent alone.

## Fix

Create the DrawingArea and wire map / tick / opacity / media settings in `construct {}` so every `g_object_new` path (default ctor and automation subclass) gets a host widget.

## How to run

```powershell
& 'C:\msys64\tmp\webview2-gtk\portable-demos\webview2gtk-paned-insert.exe' --smoke
```

```bash
AGENT_WIN_HOST=… ./scripts/agent-remote-build.sh paned-insert
```

Expect **`TEST_PASS`** (`ready=yes`, `load_changed` FINISHED).

## Related

- Nested 0×0 attach: [2026-08-21-webview-nested-zero-size-attach.md](./2026-08-21-webview-nested-zero-size-attach.md)
- Automation construct props: [plans/3.6-webview-construct-automation.md](../../plans/3.6-webview-construct-automation.md)
- Multi-controller: [plans/4.0-multi-webview-host.md](../../plans/4.0-multi-webview-host.md)
