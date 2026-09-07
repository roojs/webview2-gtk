# Bug — CookieManager has no `changed` signal (WebKit parity)

**Status:** ✅ fixed in **0.5.10** (`CookieManager.changed`)  
**Date:** 2026-09-07  
**Component:** `lib/webview2gtk/CookieManager.vala`  
**Related:** [2026-09-07-cookie-manager-get-all-replace.md](./2026-09-07-cookie-manager-get-all-replace.md)  
**Smoke:** `examples/add-cookie --smoke-changed`

---

## Symptom

WebKitGTK `CookieManager` emits `changed` whenever the jar mutates. Apps use
that (often debounced) to mirror cookies to disk or refresh debug traces.

webview2-gtk `CookieManager` had `get_cookies` / `get_all_cookies` /
`add_cookie` / `replace_cookies` but **no** `changed` signal.

---

## Fix

```vala
public signal void changed();
```

Emitted after successful `add_cookie` and `replace_cookies` (once per call).
Page `Set-Cookie` / other host jar mutations are **not** observed — WebView2
exposes no cookie-change COM event wired here.

---

## Acceptance / smoke

```powershell
& 'C:\msys64\tmp\webview2-gtk\portable-demos\webview2gtk-add-cookie.exe' --smoke-changed
```

Expect **`TEST_PASS`**: signal fires after `add_cookie` and again after
`replace_cookies`. Existing `--smoke` / `--smoke-mirror` still pass.

---

## Out of scope (still)

- Real `set_persistent_storage`  
- Emitting on network Set-Cookie  
