# Bug — CookieManager.set_persistent_storage TEXT path jar

**Status:** ✔️ agent (TEXT); `SQLITE` not supported  
**Date:** 2026-09-09  
**Component:** `lib/webview2gtk/CookieManager.vala` (`set_persistent_storage`)

ℹ️ Plan emoji: 🔷 user req, 💩 LLM suggestion, ⏳ backlog, 🚫 veto.

ℹ️ Related: [done/2026-09-07-cookie-manager-get-all-replace.md](./done/2026-09-07-cookie-manager-get-all-replace.md)

ℹ️ WebKit: `webkit_cookie_manager_set_persistent_storage` — load from path; flush non-session cookies on `changed`; never on ephemeral.

---

## Emulation rule (mandatory)

🔷 This library **only emulates existing WebKitGTK APIs** so shared Vala (`#if WINDOWS` / `#else`) can use the same shapes.

---

## Purpose

- 🔷 Emulate WebKitGTK `CookieManager.set_persistent_storage` for **TEXT**.
- 🔷 On set: **read** `filename` into that session’s cookie jar.
- 🔷 On `changed`: **write** non-session cookies back to `filename`.
- 🔷 Call on ephemeral / automation session: **no-op**.
- 🔷 `CookiePersistentStorage.SQLITE`: **not supported** — `GLib.error` (WebKit API has no `GError`; do not `throws`).

---

## Done (TEXT)

- 🔷 ✔️ `set_persistent_storage(path, TEXT)` — load/flush newline Set-Cookie headers.
- 🔷 ✔️ Jar-only get/add/replace/get_all when TEXT persistence is set (no COM).
- 🔷 ✔️ Ephemeral / automation (`mark_ephemeral`): no-op.
- 🔷 ✔️ `SQLITE`: `GLib.error` (not supported).
- 🔷 ✔️ Smoke: `examples/add-cookie --smoke-persist` (TEXT only; SQLITE aborts so not in-process).

---

## Out of scope

- 🚫 Implementing `CookiePersistentStorage.SQLITE`.
- 🚫 Making automation / ephemeral sessions durable.
- 🚫 Multi-Environment / Profile isolation redesign.
