# Bug — `get_extents(WINDOW)` returns screen pixels

**Status:** ✅ fixed in **0.5.4**  
**Platform:** Windows  
**Area:** `Win32Atspi.Accessible.get_extents`  
**Seen:** 2026-08-27

---

## Problem

🔷 UIA walk stores `BoundingRectangle` as **screen** coordinates (documented in a11y plans).

🔷 `Accessible.get_extents(CoordType.WINDOW)` **ignores** `coord_type` and returns those screen values unchanged.

🔷 AT-SPI / WebKitGTK callers expect `CoordType.WINDOW` extents relative to the
  containing window (as on Linux `Atspi.Accessible.get_extents`). Feeding screen
  coords into viewport-relative input (e.g. CDP `Input.dispatchMouseEvent`) misses
  the control: click / fill appear to succeed but do not focus or submit.

---

## Wanted

🔷 Honour the **existing** `CoordType` enum only — same shape as AT-SPI /
  WebKitGTK consumers already call. **No new public API**, no extra “origin”
  getters, no new coordinate enums.

🔷 `get_extents(WINDOW)` → coordinates relative to the containing window /
  Document client origin (AT-SPI `WINDOW` semantics).

🔷 `get_extents(SCREEN)` → absolute screen pixels (current walk values).

🔷 Document the contract in `docs/a11y.md` to match AT-SPI wording.

---

## Fix

`get_extents` keeps storing UIA screen pixels. `WINDOW` subtracts the containing
`document frame` origin (page client). `PARENT` subtracts the parent accessible.
`SCREEN` is unchanged.

---

## Notes

🔷 Phase 4 comments already say “screen coords”; the gap is honouring
  `CoordType.WINDOW` on the existing method.

🔷 Private apps can subtract Document origin before click as a temporary
  workaround until `WINDOW` is correct.

---

## Related

- [docs/a11y.md](../../a11y.md)  
- [plans/1.0-uia-accessibility.md](../../plans/1.0-uia-accessibility.md)  
