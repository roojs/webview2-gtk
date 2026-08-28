# Bug — Win32Atspi omits document for unmapped Gtk.Stack WebView host

**Status:** 🔴 **REOPENED** 2026-08-28 — still fails consumer Google smoke on tagged **0.5.6**; follow-up is **0.5.7**  
**Platform:** Windows (WebView2 + UIA)  
**Area:** `lib/host/win32-ui-webview2-a11y.c` (`find_page_document`, `a11y_walk_into`), `lib/webview2gtk/webview.vala` (`sync_host_visible`), `lib/webview2gtk/win32atspi/Win32Atspi.vala` (`Bridge.rebuild`)  
**Seen:** 2026-08-28 — multi-WebView app with `Gtk.Stack` (one visible, one hidden); regression recheck same day  
**Library version tested:** **0.5.6** (tagged `v0.5.6`) — hidden primary still `HIDDEN_MISS`

**Repro (consumer-shaped):** [2026-08-28-win32atspi-hidden-stack-host-missing-document/](./2026-08-28-win32atspi-hidden-stack-host-missing-document/) — `smoke-hidden-stack.vala`

---

## Problem

🔷 A process has **two** live `WebView2Gtk.WebView` instances registered with
  `Win32Atspi.register_webview`. Both are `ready` and report the correct
  `get_uri()` / `get_title()`.

🔷 Only **one** stack child is mapped at a time (`Gtk.Stack.set_visible_child`).
  The hidden view is parked off-screen by `WebView.sync_host_visible()` (bounds
  `-30000,-30000,1×1` while `IsVisible` stays true for capture).

🔷 `Win32Atspi.get_desktop()` / document walk finds the **visible** host’s
  `document frame`, but **not** the hidden host’s — even though that WebView
  loaded a real page.

🔷 Callers that match documents by `Accessible.get_name()` and URI (Linux
  AT-SPI-shaped pick) throw `no document matching title=… url=…` while the
  WebView API still reports that title/URL.

🔷 When the hidden view is switched to the mapped stack child, the same walk
  **does** find its document (and often both documents).

---

## Linux parity (why this is a library bug)

🔷 `Win32Atspi` is documented and consumed as an **AT-SPI drop-in**
  ([docs/a11y.md](../a11y.md)): same tree shape, same
  multi-`document frame` expectation as Linux `atspi-2` with more than one
  WebKitGTK view.

🔷 On Linux, the same app layout (two WebViews in a `Gtk.Stack`, load on the
  hidden primary while the other stack child is visible) **works** — dumps
  match the primary URL and title without forcing a stack switch.

🔷 Windows `--smoke` ([examples/automation/main.vala](../../examples/automation/main.vala))
  passes with **both** views side-by-side in an `HBox` (both mapped). Failure
  appears only with **Stack + one unmapped** host — a layout multi-host apps use.

---

## Repro (in-tree)

Build and run (interactive Windows session):

```text
webview2gtk-automation.exe --smoke-stack
```

Or: `./scripts/run-automation-smoke-stack-interactive.sh` (schtasks /IT).

### Sequence (`--smoke-stack`)

1. `Gtk.ApplicationWindow` + `Gtk.Stack` with two wrapped `WebView`s
   (`primary`, `secondary`) — same nesting as real apps (`Box` → `Overlay` →
   `ScrolledWindow` → `WebView`).
2. Show `primary` briefly so it attaches (`ready` + `get_mapped()`).
3. `stack.set_visible_child_name("secondary")`.
4. Load HTML on **secondary** (`<title>stack secondary document</title>`).
5. Load HTML on **primary** (`<title>stack primary document</title>`) while it
   is **not** mapped (`primary.get_mapped() == false`).
6. Wait until both `ready`.
7. **Phase A (hidden primary):** `Win32Atspi.init()` → walk all
   `document frame` / `document text` nodes → print names/URIs.
8. **Phase B (visible primary):** `stack.set_visible_child_name("primary")`,
   wait `primary.get_mapped()`, walk again.

### Expected (Linux / AT-SPI parity)

Phase A finds **two** documents:

| Document name | Notes |
|---------------|--------|
| `stack secondary document` | visible stack child |
| `stack primary document` | hidden but loaded + registered |

Walkers can pick the primary by title/URI without changing `Gtk.Stack`.

### Actual (0.5.5)

**Phase A (hidden primary):**

```text
webview primary uri=… title=stack primary document
webview secondary uri=… title=stack secondary document
primary_mapped=no secondary_mapped=yes
a11y_doc name=stack secondary document uri= …
a11y_doc name=stack secondary document uri= …   ← duplicate secondary common
PICK primary title=stack primary document → FAIL (not in tree)
STACK_SMOKE_FAIL hidden_missing_primary
```

**Phase B (after `set_visible_child_name("primary")`):**

```text
primary_mapped=yes secondary_mapped=no
a11y_doc name=stack secondary document …
a11y_doc name=stack primary document uri=… title_hit=yes
PICK primary → OK
STACK_SMOKE_NOTE visible_primary_workaround_ok
```

With a network page instead of static HTML (e.g. `https://www.google.com/?hl=en`
on the hidden primary), Phase A shows `title=Google` on the WebView but **no**
Google document in the walk — same failure class.

---

## Evidence summary (external consumer, generic)

A private GTK app hit this with the layout above. Minimal diagnostic
([smoke-hidden-stack.vala](./2026-08-28-win32atspi-hidden-stack-host-missing-document/smoke-hidden-stack.vala))
confirmed on **0.5.6** (2026-08-28 recheck):

```text
# --google  (secondary visible, primary hidden)
webview primary uri=https://www.google.com/?hl=en title=Google
a11y_doc name=stack secondary document …
a11y_doc name=stack secondary document …
PICK FAIL … title=Google
VERDICT=HIDDEN_MISS

# --google --restore-primary
a11y_doc name=Google uri=https://www.google.com/?hl=en title_hit=yes
PICK OK
VERDICT=WORKAROUND_OK
```

That consumer can short-term map the primary stack child before dump; the
long-term contract should not require it.

---

## Regression (0.5.6)

**Status claimed fixed** in 0.5.6 via title/URI scoring + parked-bounds probe
(see Fix below). **Consumer Google smoke still fails** Phase A / hidden pick:

| Check | Result on 0.5.6 |
|-------|-----------------|
| [smoke-hidden-stack.vala](./2026-08-28-win32atspi-hidden-stack-host-missing-document/smoke-hidden-stack.vala) `--google` | `VERDICT=HIDDEN_MISS` |
| same + `--restore-primary` | `VERDICT=WORKAROUND_OK` |

In-tree `webview2gtk-automation.exe --smoke-stack` (static HTML titles) may
still pass while this Google + title/URI pick path fails — treat the
subdirectory smoke as the gate for this reopen.

---

## Likely cause (for implementers)

### 1. Parked bounds break HWND ↔ document association

`WebView.sync_host_visible()` ([webview.vala](../../lib/webview2gtk/webview.vala)):

- When `!get_mapped() || !get_visible() || opacity≈0`, sets host bounds to
  `-30000,-30000,1×1` (parking).
- Keeps `ICoreWebView2Controller.put_IsVisible(true)` for DevTools capture.

`find_page_document()` ([win32-ui-webview2-a11y.c](../../lib/host/win32-ui-webview2-a11y.c)):

- Reads controller `Bounds`, converts to screen rect `want`.
- Enumerates descendant `Chrome_WidgetWin_1` HWNDs under the GTK parent.
- Picks the HWND whose window rect has **maximum overlap** with `want`.
- Finds `UIA_DocumentControlTypeId` under that HWND.

When the host is parked at `-30000`, overlap with the real `Chrome_WidgetWin_1`
for that controller is **zero** (or the wrong sibling wins). `find_page_document`
returns **NULL** → `a11y_walk_into` returns false → `Bridge.rebuild` skips that
host silently (`continue` when walk empty).

### 2. `--smoke` does not cover Stack

Side-by-side `--smoke` keeps **both** views mapped; both walks succeed. This
regression is **not** caught by current automation smoke.

### 3. Not the old single-host bug

[2026-08-27-win32atspi-single-host](./done/2026-08-27-win32atspi-single-host.md)
and [2026-08-27-win32atspi-hosts-null](./done/2026-08-27-win32atspi-hosts-null.md)
are fixed in 0.5.4/0.5.5. `Bridge.rebuild` **does** iterate all registered hosts;
the hidden host’s walk is simply empty.

---

## Wanted

🔷 **No new public API.** Stay on `register_webview` + `get_desktop` +
  `Accessible` tree.

🔷 Every **registered + ready** host contributes one top-level `document frame`
  under the application **regardless of** `Gtk.Widget.get_mapped()` / stack
  visibility / parked bounds — matching Linux AT-SPI multi-WebKit behaviour.

🔷 Document **name** and **URI** (`Hyperlink` / ValuePattern URL) must match
  what `WebView.get_title()` / `get_uri()` report for that host.

🔷 Switching stack visibility must not be required for automation dumps.

🔷 `--smoke-stack` must **fail** on broken builds and **pass** when Phase A
  lists both `stack primary document` and `stack secondary document`.

---

## Suggested fix directions

1. **Stable host key for UIA document lookup** — do not rely on screen overlap
   with parked `-30000` bounds. Options:
   - Cache `IUIAutomationElement*` document root per `WebView2Host` when the
     page finishes loading / on `DocumentTitleChanged`, refresh on navigation.
   - Use `ICoreWebView2Environment4.GetAutomationProviderForWindow` for the
     host’s `Chrome_WidgetWin_1` HWND tied to **that** controller, not
     overlap heuristics on the shared GTK toplevel.
   - Walk from WebView2’s automation provider directly for each controller.

2. **Separate “park for display” from “a11y target HWND”** — parking may move
   the GTK allocation without losing the COM/WebView2 document provider for that
   instance.

3. **Do not require consumers to re-call `register_webview` or toggle stack**
   before dump (contrast old single-host workaround).

---

## Fix (attempted in 0.5.6 — incomplete)

`find_page_document` no longer picks the first `Chrome_WidgetWin_1` with zero
overlap. It scores each UIA Document by page **title / URI** (from
`ICoreWebView2`), then HWND distance to controller bounds, and `FindAll` under
the GTK parent so a parked host still matches. The winning HWND is cached on
the host. If bounds look parked (`-30000` / 1×1) and identity has not matched,
bounds are briefly given a real off-screen size and the search retries.

`--smoke-stack` in `examples/automation` is the Gtk.Stack HTML repro.
Interactive: `scripts/run-automation-smoke-stack-interactive.sh`.

**Still open:** consumer Google pick
([smoke-hidden-stack.vala](./2026-08-28-win32atspi-hidden-stack-host-missing-document/smoke-hidden-stack.vala)
`--google`) reports `HIDDEN_MISS` on 0.5.6.

---

## Acceptance / smoke

| Check | Criterion |
|-------|-----------|
| [smoke-hidden-stack.vala](./2026-08-28-win32atspi-hidden-stack-host-missing-document/smoke-hidden-stack.vala) `--google` | `PICK OK` + `VERDICT=HIDDEN_OK` |
| same `--restore-primary` | Still `PICK OK` (no regression when mapped) |
| `--smoke-stack` Phase A | ≥2 distinct document names; includes `stack primary document` |
| `--smoke` (HBox) | Still `TEST_PASS` / `a11y_documents>=2` |
| Extents | [2026-08-27-win32atspi-window-extents](./done/2026-08-27-win32atspi-window-extents.md) unchanged |
| Multi-host | No return to last-wins single host |

---

## Related

- Repro dir: [2026-08-28-win32atspi-hidden-stack-host-missing-document/](./2026-08-28-win32atspi-hidden-stack-host-missing-document/)  
- [docs/a11y.md](../a11y.md) — tree shape, multi-document contract  
- [plans/4.0-multi-webview-host.md](../plans/4.0-multi-webview-host.md)  
- [2026-08-27-win32atspi-single-host](./done/2026-08-27-win32atspi-single-host.md)  
- [2026-08-27-win32atspi-hosts-null](./done/2026-08-27-win32atspi-hosts-null.md)  
- [examples/paned-insert/main.vala](../../examples/paned-insert/main.vala) — Stack layout reference  
- `examples/automation/main.vala --smoke-stack` — HTML-title smoke  
