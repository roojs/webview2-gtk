# Bug — CookieManager.replace_cookies uses sync COM loop (can AV)

**Status:** ✅ fixed in **0.5.12**  
**Date:** 2026-09-09  
**Component:** `lib/webview2gtk/CookieManager.vala` (`replace_cookies`) + `NetworkSession.apply_pending_cookies`  
**Related:** [2026-09-07-cookie-manager-get-all-replace.md](./2026-09-07-cookie-manager-get-all-replace.md), [../2026-09-09-cookie-manager-set-persistent-storage.md](../2026-09-09-cookie-manager-set-persistent-storage.md)  
**Smoke:** `examples/add-cookie --smoke-replace-startup`

---

## Symptom

`replace_cookies` / `replace_cookies_async` could **access-violate / kill the process** when started early (e.g. fire-and-forget from widget construct while other WebView / network work is in flight) with a large multi-host cookie list.

The **same cookies** succeeded via repeated `add_cookie`.

---

## Root cause

WebView2 has no bulk-set API. `replace_cookies` did `DeleteAllCookies` then a **tight sync** `AddOrUpdateCookie` loop (`wv2_add_cookie_sync`), bypassing Idle yielding. Vala `*_async` only wrapped the operation; the body still blocked COM.

---

## Fix

- `replace_cookies` queues `DeleteAllCookies` + the list on the same **pending path as `add_cookie`**.
- When the host is not ready yet, `finish_setup` **drains the full queue before first Navigate** (avoids COM cookie work overlapping early navigation — the AV case).
- When the host is already live, clear then add with **Idle between** COM calls.

---

## Acceptance / smoke

```powershell
& 'C:\msys64\tmp\webview2-gtk\portable-demos\webview2gtk-add-cookie.exe' --smoke-replace-startup
```

Expect **`TEST_PASS`**: ~320 synthetic cookies (incl. large values) applied via fire-and-forget `replace_cookies_async` at construct overlapping `load_uri`; process stays up.

```bash
AGENT_WIN_HOST=… ./scripts/agent-remote-build.sh add-cookie
```

(Interactive script runs `--smoke`, `--smoke-mirror`, `--smoke-changed`, and `--smoke-replace-startup`.)

---

## Out of scope

- Implementing `set_persistent_storage` (separate bug)  
- Matching WebKit on-disk SQLite format  
- CDP `Network.setCookies` wrapper  
