# Bug: `CookieManager.add_cookie` fails before WebView COM attach

**Status:** ✅ fixed in **0.5.2** (pending cookies applied before first Navigate)  
**Date:** 2026-08-25  
**Component:** `lib/webview2gtk/CookieManager.vala` + `NetworkSession` / host `finish_setup`  
**Repro / test:** [`examples/add-cookie`](../../../examples/add-cookie/main.vala) — `--smoke`

## Symptom

1. App has a logged-in session cookie (e.g. `PHPSESSID`).
2. On first show of a second WebView, it calls `network_session.get_cookie_manager().add_cookie(...)` then `load_uri(...)`.
3. Every `add_cookie` throws / returns failure (`add_cookie failed`).
4. Page loads unauthenticated (login UI). Linux WebKit with the same app code accepts cookies.

## Likely cause

`CookieManager.add_cookie` used `NetworkSession.cookie_host_handle()`, set only in `bind_download_host` during successful `try_attach`. Apps that inject cookies on the same turn as first map/show still hit `cookie_host == null` → `add_cookie failed`. Even after the host pointer existed, `ICoreWebView2` was not ready yet — `cookie_manager_from_host` returned null.

Pending **navigate** already queued until attach; **cookies did not**.

## Fix

Queue `add_cookie` (name/value/domain/path/flags) until the session’s host is ready, then apply them from `finish_setup` **before** `host_flush_pending_navigate`. `add_cookie` / `get_cookies` wait until that apply succeeds instead of throwing.

## How to run

```powershell
& 'C:\msys64\tmp\webview2-gtk\portable-demos\webview2gtk-add-cookie.exe' --smoke
```

```bash
AGENT_WIN_HOST=… ./scripts/agent-remote-build.sh add-cookie
```

Expect **`TEST_PASS`** (`add_cookie` succeeds before attach; `wv2gtk_probe=before_attach` in the jar after `load_changed` FINISHED).

## Related

- [2026-08-24-pending-navigate-first-paned-insert.md](./2026-08-24-pending-navigate-first-paned-insert.md) — pending navigate / multi-host  
- [2026-08-21-webview-nested-zero-size-attach.md](./2026-08-21-webview-nested-zero-size-attach.md) — attach timing
