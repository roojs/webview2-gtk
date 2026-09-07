# Bug — Ship `CookieManagerExt` vapi alongside CookieManager get_all / replace

**Status:** ✅ fixed in **0.5.11** (`webview2gtk-cookie-ext` + `CookieManagerExt`)  
**Date:** 2026-09-07  
**Component:** `vapi/webview2gtk-cookie-ext.vapi` + `lib/webview2gtk/CookieManagerExt.vala`  
**Related:** [2026-09-07-cookie-manager-get-all-replace.md](./2026-09-07-cookie-manager-get-all-replace.md)  
**Smoke:** `examples/add-cookie --smoke-mirror` (uses Ext)

---

## Symptom

`CookieManager.get_all_cookies` / `replace_cookies` exist as instance methods
(0.5.9+). Cross-platform apps also need a second surface that matches Linux
workarounds for **sealed** stock WebKit Vala bindings.

---

## Fix

| Artifact | Contents |
|----------|----------|
| `webview2gtk-1.vapi` | `CookieManager` instance methods (spaced, one arg per line) |
| `webview2gtk-cookie-ext.vapi` + `.deps` | `CookieManagerExt` static twins; `.deps` → `webview2gtk-1` |
| `CookieManagerExt.vala` | thin `yield` wrappers into instance methods |

```vala
using WebView2Gtk;
CookieManagerExt.replace_cookies.begin(mgr, cookies, null, (o, r) => {
	CookieManagerExt.replace_cookies.end(r);
});
```

`--pkg webview2gtk-cookie-ext` (vapidir next to `webview2gtk-1.vapi`).

---

## Out of scope (still)

- Changing stock WebKitGTK sealed `CookieManager`  
- Real `set_persistent_storage`  
