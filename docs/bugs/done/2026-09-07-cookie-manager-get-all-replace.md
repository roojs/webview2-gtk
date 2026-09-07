# Bug — CookieManager: no bulk get/replace for automation cookie mirror

**Status:** ✅ fixed in **0.5.8** (`get_all_cookies` / `replace_cookies`)  
**Date:** 2026-09-07  
**Component:** `lib/webview2gtk/CookieManager.vala` + `lib/host/win32-ui-webview2-cookies.c`  
**Related:** [2026-08-25-add-cookie-before-attach](./2026-08-25-add-cookie-before-attach.md) (per-cookie add exists)  
**Smoke:** `examples/add-cookie --smoke-mirror`

---

## Symptom

An app keeps an automation-controlled `WebView` (`is_controlled_by_automation` + `get_network_session_for_automation()`). It needs to **persist third-party site cookies across process restarts** by:

1. On startup — load a disk jar into the live session  
2. On jar change — dump the live session back to disk  

On **WebKitGTK**, that uses `CookieManager.get_all_cookies` / `replace_cookies` (C API since 2.42).  

On **webview2-gtk**, only `get_cookies(uri)` and `add_cookie` existed. There was no way to enumerate **all** cookies in the session or replace the jar in one shot. `set_persistent_storage` remains a no-op stub.

---

## Fix

| Method | Implementation |
|--------|----------------|
| `get_all_cookies()` | Host `GetCookies` with null URI (all cookies in profile) → `Soup.Cookie` list |
| `replace_cookies(list)` | `DeleteAllCookies` then `AddOrUpdateCookie` for each |

`get_cookies(uri)` / `add_cookie` unchanged. `set_persistent_storage` still stubbed — apps own disk serialization.

---

## Acceptance / smoke

```powershell
& 'C:\msys64\tmp\webview2-gtk\portable-demos\webview2gtk-add-cookie.exe' --smoke-mirror
```

Expect **`TEST_PASS`**: two cookies from different hosts appear in `get_all_cookies`; after `replace_cookies` with a third-only list, only that cookie remains.

```bash
AGENT_WIN_HOST=… ./scripts/agent-remote-build.sh add-cookie
```

(Interactive script runs `--smoke` and `--smoke-mirror`.)

---

## Out of scope (still)

- Real `set_persistent_storage`  
- Matching Linux SQLite on-disk format  
- Changing ephemeral automation sessions  
