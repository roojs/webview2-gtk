# Bug — no way to set Accept-Language on requests

**Status:** ✅ fixed in **0.5.3**  
**Platform:** Windows (WebView2 host)  
**Area:** `lib/host/win32-ui-webview2-web-resources.c`, `WebContext`  
**Seen:** 2026-08-26

---

## Problem

🔷 Outbound navigations / subresources use the OS / Edge default language for `Accept-Language`.

🔷 There is **no** public API to set preferred languages or inject `Accept-Language` (unlike WebKitGTK `WebContext.set_preferred_languages`).

🔷 `WebResourceRequested` today only observes the request URI for the resource-load lifecycle — it does not mutate request headers.

🔷 A private app needs English (or another BCP-47 list) for consistent page chrome / a11y names; evidence stays in that app’s tree.

---

## Wanted

🔷 Vala API: `WebContext.set_preferred_languages` (WebKitGTK shape).

🔷 On `WebResourceRequested`: `get_Request` → `get_Headers` → `SetHeader(L"Accept-Language", …)` when configured.

🔷 Empty / unset → leave engine default (no hardcode in the library forever).

---

## Fix

`WebContext.set_preferred_languages(string[]? languages)` builds the `Accept-Language` header (WebKit-style q-values) in Vala and stores it in the host; `WebResourceRequested` sets the header on each outbound request.

---

## Notes

🔷 WebKitGTK side of the same app can use `set_preferred_languages` already — gap was Windows only.

🔷 Related host surface: existing `WebResourceRequested` filter in `win32-ui-webview2-web-resources.c`.

---

## Related

- [2.1-webresource-load-started](../plans/2.1-webresource-load-started.md)  
