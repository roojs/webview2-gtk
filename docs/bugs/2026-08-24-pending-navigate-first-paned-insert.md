# Bug: pending `load_uri` still blank on first paned insert

**Status:** ✅ fixed — plan [4.0](../plans/4.0-multi-webview-host.md) (2026-08-24)  
**Date:** 2026-08-24  
**Component:** `lib/webview2gtk/webview.vala` + multi-instance host (`lib/host/`)  
**Repro / test:** [`examples/paned-insert`](../../examples/paned-insert/main.vala) — `--smoke` → **`TEST_PASS`**.

## Failing sequence (was)

1. Two `WebView` widgets (primary + management). Old limit: **one WebView2 COM host per process**.
2. Management mapped first and attached (claimed the host); `about:blank` got `load_changed`.
3. Sign-in switched Stack to primary and called `primary.load_uri(...)` in the same turn (nested Overlay → ScrolledWindow → Overlay tree inside a `Gtk.Paned`).
4. Primary never emitted `load_changed`. Shared host could still report URI/title while events never reached that widget.

## Fix

One `ICoreWebView2Controller` per GTK `WebView`, shared Environment, per-host nav/title event tokens and callbacks. See plan 4.0.

## How to run

```powershell
& 'C:\msys64\tmp\webview2-gtk\portable-demos\webview2gtk-paned-insert.exe' --smoke
```

Expect **`TEST_PASS`**.
