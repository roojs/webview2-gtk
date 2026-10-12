# Bug: idle WebViews restack every frame and flash overlays

**Date:** 2026-10-12
**Status:** ✅ fixed in **0.6.9**
**Component:** `lib/host/win32-ui-webview2-com-glue.c`, `lib/host/win32-ui-webview2-host.vala`
**Related:** [4.0 multi-webview host](../../plans/done/4.0-multi-webview-host.md) § 4.5

A private app hit this. Evidence of that session stays in that app's tree.

## Symptom

Two `WebView`s are on screen together. Each document has already finished loading and does not navigate again. A GTK overlay drawn over a view — a grey scrim and a status label — replaces the page for a frame, then the page comes back. This repeats. The address does not change.

## Cause

`WebView` adds a frame tick in `construct` and leaves it running after attach:

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

`push_bounds` calls `vala_webview2_host_set_bounds_xywh` on every frame, including when the rectangle has not changed. That function always calls `ICoreWebView2Controller_put_Bounds`, then `vala_webview2_com_present_webview`.

`present_webview` walks every child of the shared toplevel and does `SetWindowPos(..., HWND_TOP, ...)` on each window whose class contains `Chrome` or `WebView`. Both views share that toplevel, and both tick, so every frame each view raises every Chrome child. GTK painted over those windows is covered and uncovered continuously.

Plan 4.5 noted that raising every Chrome child might need to become "raise only this controller's child", and left it as not a blocker. The every-frame call is what makes the flash constant on an idle page.

## Fix

1. In `vala_webview2_host_set_bounds_xywh`, if the new rectangle equals `host->bounds` and the controller is already visible, return. Do not call `put_Bounds` or `present_webview`.
2. `present_webview` raises only the child HWND for this controller, not every Chrome child of the toplevel.
3. Call `present_webview` when this view becomes shown or when its rectangle actually changes. The frame tick keeps running so a pending navigate can still retry, and so a real resize still reaches `put_Bounds`.

Landed in `vala_webview2_host_set_bounds_xywh` and `vala_webview2_com_present_webview`. Present takes the host and raises `host->a11y_hwnd` (`Chrome_WidgetWin_1` matched to this controller). The frame tick in `webview.vala` is unchanged.
