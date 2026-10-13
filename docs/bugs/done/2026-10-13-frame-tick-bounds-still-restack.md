# Bug: idle WebViews still flash a GTK overlay after 0.6.9

**Date:** 2026-10-13
**Status:** ✅ fixed in **0.6.10**
**Component:** `lib/webview2gtk/webview.vala` (`on_frame_tick`, `push_bounds`), `lib/host/win32-ui-webview2-com-glue.c` (`vala_webview2_host_set_bounds_xywh`, `vala_webview2_com_present_webview`), `lib/webview2gtk/webview2gtk-gdk-win32.c` (`webview2gtk_widget_bounds_xywh`)
**Related:** [frame-tick restack](2026-10-12-frame-tick-restack-flicker.md) (fixed in **0.6.9**, not enough)

A private app hit this again on Windows, on a build that includes 0.6.9. Evidence of that session stays in that app's tree.

---

## Symptom

Two `WebView`s are on screen together. Each document has already finished loading and does not navigate. Every so often the page disappears for a frame: the pane goes flat grey and the GTK overlay's status label (a loading caption) sits at the bottom. Then the page is back. The address does not change. Both views do it.

0.6.9 was supposed to stop this. It still happens, just not on every single frame.

---

## Why 0.6.9 does not hold

The frame tick still pushes bounds after attach (`lib/webview2gtk/webview.vala`):

```vala
private bool on_frame_tick(Gtk.Widget widget, Gdk.FrameClock frame_clock) {
    if (!attached) {
        try_attach();
    } else {
        push_bounds();
        try_navigate();
    }
    return Source.CONTINUE;
}
```

`push_bounds` calls `vala_webview2_host_set_bounds_xywh` every frame. The 0.6.9 skip returns only when the rectangle is an exact match **and** `get_IsVisible` says the controller is visible:

```c
if (bounds_equal (&bounds, &host->bounds) && controller_is_visible (host)) {
    return;
}
host->bounds = bounds;
if (host->controller != NULL) {
    ICoreWebView2Controller_put_Bounds (host->controller, bounds);
    if (host->host_visible) {
        vala_webview2_com_present_webview (host);
    }
}
```

Anything that misses that `if` still calls `put_Bounds` and `present_webview`. Present does `SetWindowPos(host->a11y_hwnd, HWND_TOP, ...)`. That raise covers the GTK overlay, then the page paints back. Two views share the toplevel, so each raise can flash the other view too.

The skip misses in two ways:

1. **The rectangle is not exact.** `webview2gtk_widget_bounds_xywh` rounds `(widget bounds + surface transform) * scale` to integers. A fraction near .5 flips to the neighbour pixel between frames. `bounds_equal` fails, so that frame calls `put_Bounds` and raises. That matches a flash every so often, not a solid flicker.
2. **`get_IsVisible` fails or returns false.** `controller_is_visible` then returns false, the skip never runs, and the tick restacks every frame again. The view can still be on screen: `sync_host_visible` keeps `IsVisible` true and parks with bounds, but the query is what the skip trusts.

`size_allocate`, map, and opacity already call `push_bounds`. The tick does not need to.

---

## Fix

1. After attach, the frame tick must not call `push_bounds`. Leave it for `try_attach` and `try_navigate` only.
2. Once `put_Bounds` has applied a rectangle, skip again when the new rectangle is within 1px of that one. Do not call `get_IsVisible` to decide.
3. Call `present_webview` only when the view moves from parked (off-screen, around −30000) onto the screen. A size change of a view that is already on screen is `put_Bounds` only. Do not `SetWindowPos(..., HWND_TOP)` on that path.

A real resize and a real show still move the child. An idle page does not raise it.

Landed in `on_frame_tick` and `vala_webview2_host_set_bounds_xywh`.
