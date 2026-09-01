# Bug — missing WebKitGTK `decide_policy` / `ResponsePolicyDecision` emulation

**Status:** ✅ fixed (0.5.8)  
**Platform:** Windows (`WebView2Gtk.WebView`)  
**Area:** `lib/webview2gtk/`, `lib/host/win32-ui-webview2-document-response.c`, vapi  
**Seen:** 2026-09-01

---

## Problem

🔷 **webview2-gtk’s stated job** is to emulate WebKitGTK 6 so shared Vala compiles with one `using` swap and **no `#if` around handler logic** ([using-in-your-app.md](../using-in-your-app.md), [plan 3.7](../plans/3.7-website-policies.md): *“remove `#if` around WebKitGTK-shaped APIs”*).

🔷 For main-frame document HTTP responses, WebKitGTK exposes:

```vala
web_view.decide_policy.connect((decision, type) => {
    if (type != PolicyDecisionType.RESPONSE) {
        return false;
    }
    var rd = decision as ResponsePolicyDecision;
    if (rd == null || !rd.is_main_frame_main_resource()) {
        return false;
    }
    var response = rd.response;
    // response.status_code, response.http_headers, response.uri
    return false;
});
```

🔷 Windows had **no equivalent**. Instead the library added a **Windows-only** `main_document_response(status, headers)` signal. That forced consumers to fork their handler into `#if LINUX` / `#if WINDOWS` blocks — the opposite of the project’s design.

🔷 `main_document_response` was also incomplete: no `uri` in the callback (host already tracked `doc_nav_uri` in `win32-ui-webview2-document-response.c` but did not expose it).

---

## Fix (0.5.8)

🔷 Added WebKitGTK-shaped `PolicyDecisionType`, `PolicyDecision`, `ResponsePolicyDecision`, `URIResponse`, and `WebView.decide_policy`.

🔷 Wired from existing host path: `NavigationStarting` (URI) + `WebResourceResponseReceived` (status + headers), filtered to main-frame GET document.

🔷 `main_document_response` removed; public contract is `decide_policy`.

---

## Related

- [2.1-webresource-load-started](../plans/2.1-webresource-load-started.md)  
- [3.7-website-policies](../plans/3.7-website-policies.md)  
- Host: `win32-ui-webview2-document-response.c`, `emit_document_response()`
