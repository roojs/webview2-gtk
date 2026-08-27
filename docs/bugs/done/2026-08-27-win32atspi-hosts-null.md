# Bug — Win32Atspi `Bridge.hosts` null on `register_webview`

**Status:** ✅ fixed in **0.5.5**  
**Platform:** Windows  
**Area:** `lib/webview2gtk/win32atspi/Win32Atspi.vala` (`Bridge.hosts`)  
**Seen:** 2026-08-27 — `webview2gtk-automation.exe --smoke`

---

## Problem

🔷 After the multi-host change, `register_webview` hits:

```text
gee_abstract_collection_contains: assertion 'self != NULL' failed
gee_abstract_collection_add: assertion 'self != NULL' failed
```

🔷 `Bridge.hosts` is a static `Gee.ArrayList` field initializer. At first
  `register()`, the list pointer is still **null** — Vala static field
  `new` for Gee collections is not reliable here.

🔷 Effect: hosts are never recorded; `rebuild()` walks an empty list;
  multi-Document a11y from [done/2026-08-27-win32atspi-single-host](./2026-08-27-win32atspi-single-host.md)
  does not actually work despite compile/install succeeding.

🔷 `--smoke` still printed `automation-started` / `SMOKE_PASS` — so the
  current smoke does **not** catch this.

---

## Wanted

🔷 Stay on the **existing** API (`register_webview` / `get_desktop` /
  `Accessible`). **No new public API.**

🔷 Lazy-init `hosts` before `contains` / `add` / `remove` / `size` (or
  otherwise guarantee a non-null list before first use).

🔷 **Smoke (required — do not mark fixed without these):**

  1. `webview2gtk-automation.exe --smoke` (interactive session) must
     finish **without** Gee `self != NULL` CRITICAL on register.
  2. Two ready WebViews → `get_desktop` walk finds **two**
     `document frame` (or `document text`) children under the app frame;
     names/URIs match each page (not last-wins).
  3. `get_extents(WINDOW)` still document-relative
     ([done/2026-08-27-win32atspi-window-extents](./2026-08-27-win32atspi-window-extents.md)) —
     spot-check one pressable node is near the control, not screen-absolute.
  4. Prefer extending automation / multi-host smoke so a null `hosts`
     or empty walk **fails the smoke**, instead of only checking
     `automation-started`.

---

## Fix

`register` creates the Gee list on first use. `--smoke` now places two
WebViews, waits until both are `ready`, walks `get_desktop`, and requires
`a11y_documents>=2` plus `WINDOW` origin `(0,0)` (and a child offset vs
`SCREEN`). The interactive smoke script fails on Gee `self != NULL` or
missing `TEST_PASS`.

---

## Related

- [2026-08-27-win32atspi-single-host.md](./2026-08-27-win32atspi-single-host.md)  
- [2026-08-27-win32atspi-window-extents.md](./2026-08-27-win32atspi-window-extents.md)  
- [docs/a11y.md](../../a11y.md)  
- `scripts/run-automation-smoke-interactive.sh`  
