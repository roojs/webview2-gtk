# Bug — Win32Atspi duplicates a sibling document when the target UIA document is unavailable

**Status:** ✅ fixed in **0.6.14**, Windows smoke passed. A missing document stays missing; WebView2 does not supply a replacement tree.  
**Platform:** Windows (WebView2 + UIA)  
**Area:** [`lib/host/win32-ui-webview2-com-glue.c`](../../../lib/host/win32-ui-webview2-com-glue.c) (per-WebView native host), [`lib/host/win32-ui-webview2-a11y.c`](../../../lib/host/win32-ui-webview2-a11y.c) (`find_page_document`, `a11y_walk_into`), [`lib/webview2gtk/win32atspi/Win32Atspi.vala`](../../../lib/webview2gtk/win32atspi/Win32Atspi.vala) (`Bridge.rebuild`)  
**Seen:** 2026-11-05 — two simultaneously visible WebViews

---

## Problem

🔷 A process has two live, ready, and visible `WebView2Gtk.WebView` instances. Each instance reports its own correct `get_uri()` and `get_title()`.

🔷 `Win32Atspi.get_desktop()` emits the sibling document twice when the target WebView's page is not exposed as a `UIA_DocumentControlTypeId`.

🔷 A consumer matching by document title and URI correctly rejects the sibling documents and reports that no target document exists.

🔷 Repeated walks produce the same duplicate. Navigating the same target WebView to another page can make its document discoverable, so the WebView host itself is live and registered.

This is distinct from the fixed hidden-`Gtk.Stack` bug: both WebViews are mapped and visible when the target document is missed.

---

## Synthetic evidence

Names and URLs below are placeholders for a private consumer observation:

```text
target WebView:  title=Target Page  uri=https://target.example/
sibling WebView: title=Control Page uri=https://control.example/

a11y document name=Control Page role=document frame uri=https://control.example/
a11y document name=Control Page role=document frame uri=https://control.example/

no document matching title=Target Page url=https://target.example/
```

The target navigation completed successfully with HTTP 200. Multiple walks over roughly 30 seconds returned the same duplicate sibling document. The private consumer's full evidence remains in that project's tree.

---

## Cause direction

`find_page_document()` searches `Chrome_WidgetWin_1` descendants beneath the shared GTK parent and scores discovered UIA documents by title, URI, and geometry. If one WebView does not expose a document while its sibling does, the sibling can be selected for both host walks.

The later title/URI check prevents the consumer from operating on the wrong page, but it cannot recover the target accessibility tree.

The host-to-document association remains heuristic. It should come from the specific WebView2 host/controller rather than rediscovering a document among all Chromium children of the shared parent.

---

## Wanted

🔷 Keep the existing `Win32Atspi` / AT-SPI-shaped public surface. No consumer API change and no target-selection API.

🔷 Each registered WebView contributes only its own accessibility document. Never return a sibling document for that host.

🔷 The supported provider route was tested and does not recover a missing document. `GetAutomationProviderForWindow` returns `UIA_E_ELEMENTNOTAVAILABLE` for the per-WebView host and for each Chromium child, including when invoked from `IRawElementProviderHwndOverride` on that host.

🔷 If WebView2/UIA still exposes no document, consider a host-keyed internal fallback using the Chromium accessibility tree (`Accessibility.getFullAXTree`). This must remain an implementation detail behind the existing structured accessibility surface; no page JavaScript and no new public API.

🔷 Fail closed when the target tree genuinely cannot be read. Do not fall back to the first document in the process.

---

## Regression test

`webview2gtk-automation.exe --smoke-a11y-missing` creates two mapped, visible WebViews whose titles share a prefix. The test-only hooks remove the target document from consideration and deliberately re-enable fuzzy identity matching, so the smoke passes only when each host walk is confined to its own native HWND subtree.

1. Creates two mapped, visible WebViews under one GTK toplevel.
2. Loads target title `shared app` and sibling title `shared app control`.
3. Hides the target `UIA_DocumentControlTypeId` from the picker.
4. Walks `Win32Atspi.get_desktop()`.
5. Asserts that the sibling document is not emitted for the target host.

The expected fail-closed result is one sibling document and no target document. Reverting native host isolation makes the shared-prefix sibling count twice and fails the smoke even though production uses exact identity as a second safety guard. Run it in an interactive Windows session with `bash scripts/run-automation-smoke-a11y-missing-interactive.sh`.

---

## Investigation log

- 2026-11-05: The deterministic missing-document smoke reproduced two copies of `shared app control`; both `load_html` pages exposed `about:blank`, which was incorrectly accepted as exact URI identity.
- 2026-11-05: Restricting identity to exact title or meaningful URI and excluding `about:blank` produced `A11Y_MISSING_PASS`; the existing side-by-side and hidden-stack smokes also passed.
- 2026-11-06: Calling `ICoreWebView2Environment4.GetAutomationProviderForWindow` with each exact cached `Chrome_WidgetWin_1` still returned `0x80040201` (`UIA_E_ELEMENTNOTAVAILABLE`) outside `IRawElementProviderHwndOverride`, confirming that a direct call is not a supported shortcut.
- 2026-11-06: Attaching an incomplete `IRawElementProviderHwndOverride` fragment root to the shared GTK toplevel caused recursive `WM_GETOBJECT` walks and was removed; replacing GTK's accessibility root is unsafe.
- 2026-11-06: The available `IUIAutomation5` headers do not provide an `ElementFromProvider` conversion, so the raw WebView2 provider cannot be inserted directly into the existing `IUIAutomationElement` walk/cache; a complete `WM_GETOBJECT` fragment rooted on the per-WebView host is required.
- 2026-11-06: The underlying structural change now gives each `WebView2Host` its own native child HWND and parents its controller beneath that HWND, so accessibility discovery searches one controller subtree rather than every Chromium sibling beneath the GTK toplevel.
- 2026-11-06: The old side-by-side smoke walked UIA as soon as both controllers were ready, before both document titles had settled, which intermittently produced zero or one document; it now waits for both exact titles and asserts exactly one document for each title.
- 2026-11-06: The final isolated-host build passed the title-ready side-by-side smoke with correct window-relative bounds, the deterministic structural isolation smoke with fuzzy identity deliberately re-enabled, both phases of the hidden-stack smoke, and the paned-insert attach/navigation smoke.
- 2026-11-06: A per-host `WM_GETOBJECT` fragment on `WebView2GtkHost` did receive `UiaRootObjectId`. `GetAutomationProviderForWindow` still returned `0x80040201` (`UIA_E_ELEMENTNOTAVAILABLE`) for that host window, `Chrome_WidgetWin_0`, `Chrome_WidgetWin_1`, and `Chrome_RenderWidgetHostHWND`, both during `WM_GETOBJECT` and from the UI thread before the UIA walk. The raw provider was null, so it cannot fill in a document the HWND subtree does not expose. The fragment was removed so the host window keeps the default UI Automation provider.

---

## Fix

Keep substring title/URI matches for candidate ranking only. A candidate now establishes host identity only when its document title or URI exactly matches the target WebView, and the shared non-identifying `about:blank` URI is excluded from URI scoring. If the target document is unavailable, a sibling with a shared title or URI prefix is discarded instead of being attached to both hosts.

The structural fix isolates every WebView2 controller beneath a dedicated native child host and confines UIA enumeration to that subtree. This removes cross-WebView discovery without replacing GTK's accessibility root.

`ICoreWebView2Environment4.GetAutomationProviderForWindow` does not supply the missing tree. Called on the controller parent and on every Chromium child, it returns `UIA_E_ELEMENTNOTAVAILABLE`. The duplicate-document failure is fixed by the isolated subtree plus the exact-identity guard. A target page whose own subtree has no UIA Document still has no document.

Windows verification on 2026-11-06 after native host isolation: `A11Y_MISSING_PASS`, side-by-side `TEST_PASS`, hidden-stack `STACK_SMOKE_PASS`, and paned-insert `TEST_PASS`. The provider attempt was then removed after the HRESULT above.

---

## Acceptance

- Two visible WebViews never produce duplicate sibling documents.
- A target page whose HWND subtree lacks a discoverable UIA Document stays unreadable. WebView2's automation-provider API returns element-not-available for every window in that subtree, so fail closed rather than emit the sibling.
- Press/fill node bounds still use the target WebView's viewport coordinates.
- Existing side-by-side and hidden-`Gtk.Stack` accessibility smokes still pass.
- No public API change.

---

## Related

- [Win32Atspi only walks the last registered WebView](./2026-08-27-win32atspi-single-host.md)
- [Win32Atspi omits document for unmapped Gtk.Stack WebView host](./2026-08-28-win32atspi-hidden-stack-host-missing-document.md)
- [UIA accessibility plan](../../plans/done/1.0-uia-accessibility.md)
- [Accessibility API](../../a11y.md)
