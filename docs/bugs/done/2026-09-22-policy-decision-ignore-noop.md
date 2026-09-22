# Bug — `PolicyDecision.ignore()` on RESPONSE is a no-op

**Status:** ✅ fixed in **0.6.5**  
**Date:** 2026-09-22  
**Component:** `lib/webview2gtk/PolicyDecision.vala` + `lib/webview2gtk/webview.vala`  
**API parity:** WebKitGTK `webkit_policy_decision_ignore`  
**Related:** [decide_policy RESPONSE emit](./2026-09-01-decide-policy-response-emulation.md) (0.5.8 — observe only)  
**Smoke:** `examples/hello --smoke-policy-ignore` (`TEST_PASS` on `snappr-win`)

ℹ️ Plan emoji: 🔷 user req, 💩 LLM suggestion, ⏳ backlog, 🚫 veto.

---

## Overview

The shared app already does the right WebKit thing: on `decide_policy` RESPONSE, read `Content-Type`, and if it is not HTML call `decision.ignore()`. On Linux that **cancels the load**. On Windows `ignore()` was empty, so Edge still showed the PDF viewer.

**Done:** `ignore()` cancels that document on WebView2. Same Vala on both platforms. No new Windows-only API. No `#if` + `stop_loading()`.

**How:**

1. `ignore()` sets a flag on the decision object.
2. After `decide_policy` returns, if that flag is set, call WebView2 **Stop**.
3. Treat the navigation as **cancelled** (`load_failed` + `NetworkError.CANCELLED`).
4. 🔷 If Stop is too late and the Edge PDF UI still commits, navigate to **`about:blank`**.

`is_mime_type_supported()` is **not** part of this. It is a read-only question (“can the engine display this MIME?”). You cannot set it. WebKit returns **true** for PDF because it has a PDF viewer. The app checks headers and calls `ignore()`. We honour `ignore()`.

---

## Symptom

🔷 Shared Vala already compiles the WebKitGTK-shaped handler (0.5.8):

```vala
web_view.decide_policy.connect((decision, type) => {
    if (type != PolicyDecisionType.RESPONSE) {
        return false;
    }
    var rd = decision as ResponsePolicyDecision;
    if (rd == null || !rd.is_main_frame_main_resource()) {
        return false;
    }
    var mime = content_type_from(rd.response.http_headers);
    if (mime == "text/html" || mime == "application/xhtml+xml") {
        return false;
    }
    decision.ignore();
    return true;
});
```

🔷 On **WebKitGTK**, `ignore()` cancels that main-frame load. The previous HTML stays (or the pane is blank). The built-in PDF viewer does **not** commit. `load_failed` fires as cancelled.

🔷 On **webview2-gtk**, the same call compiled and returned. `PolicyDecision.ignore()` was empty. The Edge PDF viewer still committed.

---

## What the consumer needs

🔷 One `ignore()` path on Linux and Windows. After MIME is known, refuse the document.

🔷 Typical allow-list: `text/html`, `application/xhtml+xml`, empty / missing `Content-Type`. Everything else (especially `application/pdf`) must not become the view’s document.

🔷 After `ignore()`: no PDF chrome left; previous HTML **or** `about:blank`; `load_failed` cancelled; `stop_loading()` is optional, not required.

---

## Why not `NavigationStarting` Cancel

MIME is on the **response**. `NavigationStarting.put_Cancel` runs before headers exist. Honour `ignore()` on the RESPONSE emit we already have (0.5.8).

---

## Why not `is_mime_type_supported()`

That method is a **query**, not a policy knob. WebKitGTK: “can this WebView display this MIME type?” PDF → **true** (built-in viewer). There is no setter. Apps that want to block PDF still have to call `ignore()` themselves.

---

## How (Windows)

Keep RESPONSE emit **synchronous**. Do not idle-defer it.

1. **Flag.** `PolicyDecision.ignore()` sets a first-wins internal action. `use()` / `download()` also first-wins but stay no-ops for this bug.
2. **Stop.** After emit, if ignored: remember the URI, set `load_cancelled`, `wv2_host_stop` (not `stop_loading()`).
3. **Signals.** `load_failed(STARTED, ignored_uri, CANCELLED)`. No `FINISHED` for the ignored document.
4. **If PDF still commits** (`NavigationCompleted` success): 🔷 `Navigate("about:blank")`. Swallow that blanking nav’s `STARTED` / `FINISHED` / RESPONSE.

🚫 No Chromium flag to disable the PDF extension.
🚫 No `WebResourceRequested` prefetch / fake 204.
🚫 No proxy rewrite.
🚫 No Windows-only “block PDF” signal.
🚫 `NAVIGATION_ACTION` / `NEW_WINDOW_ACTION` / `download()` are out of this bug.

---

## Verify

`examples/hello --smoke-policy-ignore` on `snappr-win` (`scripts/run-hello-policy-ignore-smoke-interactive.sh`):

```
decide_policy RESPONSE mime=text/html uri=data:text/html;…
smoke-policy-ignore html FINISHED
decide_policy RESPONSE mime=application/pdf uri=https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf
smoke-policy-ignore load_failed …/dummy.pdf: Load cancelled
smoke-policy-ignore after ignore uri=about:blank loading=no try=1
TEST_PASS
```
