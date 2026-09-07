# Bug — No WebKit-shaped way to hide `navigator.webdriver` on controlled views

**Status:** ✅ fixed in **0.5.10** (`NavigatorWebDriverActivePolicy` + Chromium arg)  
**Date:** 2026-09-07  
**Component:** `lib/host/win32-ui-webview2-automation.c` + `WebViewSettings`  
**Related:** automation / CDP (`WEBKIT_INSPECTOR_SERVER` → `--remote-debugging-port`)  
**Smoke:** `examples/automation --smoke-webdriver`

---

## Symptom

A private app builds an automation-controlled `WebView`
(`is_controlled_by_automation: true` + `get_network_session_for_automation()`).
Page JS still sees `navigator.webdriver === true` (Blink AutomationControlled),
which breaks captcha / challenge flows that gate on that signal.

On **WebKitGTK** (webdriver package), the app can call:

```vala
set_navigator_webdriver_active_policy(
    web_view.get_settings(),
    NavigatorWebDriverActivePolicy.DISABLED
);
```

---

## Fix

| Surface | Behavior |
|---------|----------|
| `NavigatorWebDriverActivePolicy` (`AUTO` / `ENABLED` / `DISABLED`) | WebKitGTK enum names |
| `WebViewSettings.navigator_webdriver_active_policy` | property (default `AUTO`) |
| `set_navigator_webdriver_active_policy` / `get_…` | free-function twins |
| Host `DISABLED` | merges `--disable-blink-features=AutomationControlled` into `AdditionalBrowserArguments` alongside CDP / autoplay args |

Process-wide: must be set **before** WebView2 environment create (same class of
limitation as autoplay / `WEBKIT_INSPECTOR_SERVER`). Late changes warn once.

`AUTO` / `ENABLED` leave Chromium defaults (no hide flag). Plain non-automation
views are unchanged unless the app sets `DISABLED`.

---

## Acceptance / smoke

```powershell
& 'C:\msys64\tmp\webview2-gtk\portable-demos\webview2gtk-automation.exe' --smoke-webdriver
```

Expect **`TEST_PASS`**: `navigator.webdriver === true` evaluates to `false`.
CDP fill against a normal automation window still works.

---

## Out of scope

- JS redefine of `navigator.webdriver`  
- Dual-WebView “human then swap to automation” product tricks  
- Changing `is_controlled_by_automation` construct-only semantics  
