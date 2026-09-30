# Bug — no WebKitGTK `script_dialog` (native alert / confirm / prompt)

**Status:** ✅ fixed in **0.6.7**  
**Platform:** Windows (`WebView2Gtk.WebView`)  
**Area:** `lib/webview2gtk/webview.vala`, `lib/webview2gtk/ScriptDialog.vala`, `lib/host/win32-ui-webview2-script-dialogs.c`  
**Seen:** 2026-09-29  
**Smoke:** `examples/hello --smoke-script-dialog`

---

## Problem

🔷 **webview2-gtk’s stated job** is to emulate WebKitGTK 6 so shared Vala compiles with one `using` swap and **no `#if` around handler logic**.

🔷 WebKitGTK `WebView.script_dialog` fires for page `alert()`, `confirm()`, `prompt()`, and before-unload. The app reads the message and kind, accepts or dismisses, and returns **true** so the engine does **not** show its own modal.

🔷 webview2-gtk `WebView` had **no** `script_dialog` signal. `AreDefaultScriptDialogsEnabled` stayed at the default (**true**). Edge showed a native modal. Page script did not continue until that window was dismissed.

🔷 `ICoreWebView2.add_ScriptDialogOpening` was already declared in `vapi/win32-ui-webview2.vapi` and was **not** connected.

---

## Expected

🔷 Same shape as WebKitGTK, so the handler below compiles on both backends:

```vala
web_view.script_dialog.connect((dialog) => {
    // dialog.get_message(), dialog.get_dialog_type()
    // confirm_set_confirmed / prompt_set_text as on WebKit
    return true;
});
```

🔷 Return **true** → app handled it, no native dialog. Alert completes. Confirm and before-unload follow `confirm_set_confirmed` (unset cancels). Prompt returns `prompt_set_text` (unset cancels; empty string is an answer).

🔷 No handler → Edge’s dialog, same as before.

🚫 Do not require the app to `#if` Windows to swallow or answer a script dialog.

---

## How

WebView2 raises `ScriptDialogOpening` only when `AreDefaultScriptDialogsEnabled` is **false**. The host turns that off when a `script_dialog` handler is connected (before the first navigation, and again if a handler is connected later). The callback builds a `ScriptDialog`, emits the signal, and calls `Accept` / `put_ResultText` from the fields above.

A connected handler that returns **false** cannot fall back to Edge’s dialog for that event. A Win32 dialog answers the page instead (message box for alert, confirm, and before-unload; a text field for prompt).
