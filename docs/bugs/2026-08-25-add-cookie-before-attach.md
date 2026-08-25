# Bug: `CookieManager.add_cookie` fails before WebView COM attach

**Status:** ⏳ open  
**Date:** 2026-08-25  
**Component:** `lib/webview2gtk/CookieManager.vala` + `NetworkSession.cookie_host` / `bind_download_host`  
**Seen in:** webview2-gtk **0.5.1** — cookie inject on a second WebView before attach

## Symptom

1. App has a logged-in session cookie (e.g. `PHPSESSID`).
2. On first show of a second WebView, it calls `network_session.get_cookie_manager().add_cookie(...)` then `load_uri(...)`.
3. Every `add_cookie` throws / returns failure (`add_cookie failed`).
4. Page loads unauthenticated (login UI). Linux WebKit with the same app code accepts cookies.

## Consumer `--debug` (2026-08-25 13:44)

```text
home load host=192.168.88.132 cookie_header_len=1087
cookie inject begin host=192.168.88.132 header_len=1087
cookie inject failed name=CF_Authorization host=192.168.88.132 err=add_cookie failed
cookie inject failed name=PHPSESSID host=192.168.88.132 err=add_cookie failed
cookie inject end host=192.168.88.132
```

Same timestamp for begin + both failures → inject runs before a usable host cookie manager exists (or COM add fails immediately).

## Likely cause

`CookieManager.add_cookie` uses `NetworkSession.cookie_host_handle()`, set only in `bind_download_host` during successful `try_attach`. Apps that inject cookies on the same turn as first map/show (one Idle after making the Stack child visible) still hit `cookie_host == null` → `add_cookie failed`.

Pending **navigate** already queues until attach; **cookies do not**.

## Ask

Queue `add_cookie` (name/value/domain/path/flags) until the session’s host is bound, then flush — same contract as pending `load_uri`. Apps should be able to `add_cookie` then `load_uri` without racing attach.

## App workaround (temporary — not the product fix)

Retry inject after attach / after first `load_changed`, or pass session via URL where the site supports it. Prefer library pending cookies.

## Related

- [2026-08-24-pending-navigate-first-paned-insert.md](./done/2026-08-24-pending-navigate-first-paned-insert.md) — pending navigate / multi-host  
- [2026-08-21-webview-nested-zero-size-attach.md](./done/2026-08-21-webview-nested-zero-size-attach.md) — attach timing
