# Bug — `window.open` opens an Edge popup

**Status:** open
**Date:** 2026-10-30
**Platform:** Windows (`WebView2Gtk.WebView`)
**Area:** `lib/host/win32-ui-webview2-events.c`, `lib/webview2gtk/webview.vala`, `lib/webview2gtk/PolicyDecision.vala`
**Emoji:** 🔷 user req, 💩 LLM suggestion, ⏳ backlog, 🚫 veto.

---

## Problem

🔷 A private app hit this. Evidence stays in that app's tree.

🔷 `window.open` and `<a target="_blank">` open a real top-level Edge window. The embedded `WebView` stays where it was. The app has no signal to cancel it.

ℹ️ WebKitGTK does not open a window for the same call. `decide-policy` can arrive as `NEW_WINDOW_ACTION`. If that decision is ignored, or if `WebView.create` is unhandled and returns null, the load is dropped. `window.open` returns null.

ℹ️ webview2-gtk's job is that same shape, with no `#if` in the app. `PolicyDecisionType.NEW_WINDOW_ACTION` is already in the enum. Nothing emits it. `PolicyDecision` says only `RESPONSE` is emitted today.

ℹ️ WebView2 raises `NewWindowRequested`. If `Handled` is left false and `NewWindow` is not set, Edge opens the popup. `vala_webview2_events_register_host` never calls `add_NewWindowRequested`. It registers navigation start, navigation complete, title, and proxy auth only.

ℹ️ The accessibility diagnostic in `lib/host/win32-ui-webview2-a11y-diag.c` does register the event, and it leaves `Handled` false on purpose. That file is compiled out of normal builds. It is not the production path.

---

## Expected

🔷 No OS window. The current `WebView` does not navigate to the popup URI either.

🔷 `decide_policy` runs with `PolicyDecisionType.NEW_WINDOW_ACTION` and a request URI, on the same signal apps already connect for `RESPONSE`.

🔷 `ignore()` sets `Handled` true and does not set `NewWindow`. The popup is cancelled.

🔷 No handler, or a handler that returns false without `ignore()`, also cancels. That matches WebKit when `create` returns null. It does not match script dialogs, where no handler keeps Edge's own UI.

🚫 Do not navigate the existing view to the popup URI.

🚫 Do not add `WebView.create` or `put_NewWindow` in this bug. No consumer hosts the popup in a second view.

🚫 Do not take a deferral. The decision is synchronous.

🚫 `LaunchingExternalUriScheme` (a custom scheme that starts another process) is a different event. Out of this bug.

---

## How

💩 ⏳ Register `NewWindowRequested` beside the other handlers in `vala_webview2_events_register_host`. Remove the token in `vala_webview2_events_unregister_host`. Store the token on `WebView2Host` next to `tok_nav_starting`.

💩 ⏳ On the event, read the URI and `IsUserInitiated`. Invoke a host callback into the Vala `WebView`, same crossing as `script_dialog`.

💩 ⏳ Emit `decide_policy` with `NEW_WINDOW_ACTION`. The decision needs the URI (`NavigationPolicyDecision` is enough: a request, `ignore()` already on `PolicyDecision`). Full `NavigationAction` (mouse button, modifiers) is not required.

💩 ⏳ After the signal returns, `put_Handled(TRUE)` unless a later bug supplies a `NewWindow`. Do this when the handler called `ignore()`, and when it did not. Never leave `Handled` false.

💩 ⏳ Update the `PolicyDecision` comment that says only `RESPONSE` is emitted.

💩 ⏳ Smoke: one `WebView`, a page that calls `window.open("https://example.test/")` and a link with `target="_blank"`. No new top-level window. The signal's URI is the one that was refused. The original document stays put.
