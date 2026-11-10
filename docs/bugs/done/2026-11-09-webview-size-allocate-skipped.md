# Bug: native window stays put when the widget only moves

**Date:** 2026-11-09
**Status:** ✅ fixed in **0.6.16**. Confirmed 2026-11-10: opening the bar no longer leaves the native window painted over it.
**Component:** `lib/webview2gtk/webview.vala` (`size_allocate`, `measure`, `layout_manager`, `on_frame_tick`)

---

## Symptom

Two `WebView`s are on screen. A bar opens above them and the GTK layout moves both widgets down. One view changes height, the other keeps the same height. The second view's page stays at the old screen position and paints over the bar.

---

## Why

`WebView` is a `Gtk.Box`. `Gtk.Box` installs a layout manager, and GTK calls that instead of `Widget.size_allocate`. The override that calls `push_bounds` never ran for a resize.

Clearing the layout manager is not enough for the view whose height stays the same. GTK skips `size_allocate` when the allocated width and height are unchanged, and only the transform is updated. After map, that native child window moved only when opacity or visibility changed.

---

## Fix

Clear the box layout manager after the host `DrawingArea` is parented. `measure` forwards to that child. `size_allocate` gives the child the full allocation, then `push_bounds`, so a resize still reaches `MoveWindow`.

A move with an unchanged size never enters `size_allocate`. The frame tick calls `push_bounds` only when the on-screen rectangle has moved by more than one pixel. `set_bounds` ignores that one-pixel wobble and raises the child only when it leaves the off-screen park, so an idle page does not restack over a GTK overlay.

---

## Smoke

`webview2gtk-move-bounds.exe` is the window. The header button opens a bar above an expanding view and a fixed-height view. `--smoke` waits until both native `WebView2GtkHost` windows match the widgets, opens the bar, and requires the fixed-height host to follow.

```
webview2gtk-move-bounds.exe --smoke
bash scripts/run-move-bounds-smoke-interactive.sh
```

`TEST_PASS` means the fixed-height native window moved with the widget. `TEST_FAIL fixed-height native window stayed put` is this bug.
