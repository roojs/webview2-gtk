# Bug — CookieManagerExt must expose `*_async` / `*_finish` (not Vala `.begin` / `.end`)

**Status:** ✅ fixed in **0.5.12** (`*_async` / `*_finish`)  
**Date:** 2026-09-07  
**Component:** `lib/webview2gtk/CookieManagerExt.vala`, `vapi/webview2gtk-cookie-ext.vapi`  
**Related:** [2026-09-07-cookie-manager-ext-vapi.md](./2026-09-07-cookie-manager-ext-vapi.md)  
**Smoke:** `examples/add-cookie --smoke-mirror`

---

## Symptom

0.5.11 initially shipped Vala `async` static methods (`.begin` / `.end`). Linux
C supplements use `*_async` / `*_finish` with `CookieManager` on finish — shared
app call sites needed `#if`.

---

## Fix

```vala
CookieManagerExt.replace_cookies_async(mgr, cookies, null, (o, r) => {
	CookieManagerExt.replace_cookies_finish(mgr, r);
});
CookieManagerExt.get_all_cookies_async(mgr, null, (o, r) => {
	var list = CookieManagerExt.get_all_cookies_finish(mgr, r);
});
```

Thin wrappers → instance `get_all_cookies` / `replace_cookies` begin/end.
Vapi/Vala: args on the signature line; `throws` on the next line when present.

Instance methods on `CookieManager` unchanged.

---

## Out of scope

- Changing stock WebKitGTK sealed `CookieManager`  
- Removing instance methods from `CookieManager`  
