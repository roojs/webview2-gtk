# Feature: emulate `NavigatorWebDriverActivePolicy` (hide `navigator.webdriver`)

**Status:** ✅ DONE — Vala settings + Windows host blink flag (2026-09-02)

**Started:** 2026-09-02

**Area:** `WebViewSettings.navigator_webdriver_active_policy` + `vala_webview2_host_create_environment_options()`

**Related:**

- ℹ️ Linux twin: [webkitgtk-automation README — Hiding `navigator.webdriver`](https://github.com/roojs/webkitgtk-automation#hiding-navigatorwebdriver-automation-flag)
- ℹ️ Android twin (API parity): [webkitgtk-android `2026-09-02-navigator-webdriver-active-policy.md`](file:///home/alan/git/webkitgtk-android/docs/bugs/2026-09-02-navigator-webdriver-active-policy.md)
- ℹ️ Upstream WebKit: [#165269](https://bugs.webkit.org/show_bug.cgi?id=165269)
- ℹ️ [`docs/automation.md`](../../automation.md)

---

## What shipped

| Policy | Behaviour |
|--------|-----------|
| **AUTO** (default) | No blink flag — stock automation advertising |
| **ENABLED** | No blink flag (always advertise when Chromium would) |
| **DISABLED** | `--disable-blink-features=AutomationControlled` at env create |

- Enum: `NavigatorWebDriverActivePolicy` in `Enums.vala`
- Setting: `WebViewSettings.navigator_webdriver_active_policy`
- Host: `vala_webview2_host_set_navigator_webdriver_active_policy` → merged in `create_environment_options` only when **DISABLED**
- Docs: `docs/automation.md` section “Hiding `navigator.webdriver`”

**Not** tied to `WEBKIT_INSPECTOR_SERVER` alone — opt-in via the setting.

---

## Acceptance

- ✅ Default (**Auto**): no AutomationControlled disable unless the app sets **Disabled**
- ✅ **Disabled** before env create → blink flag in `AdditionalBrowserArguments`
- ✅ Combines with inspector port and/or autoplay DENY
- ✅ Late change after env create warns (stored only; restart required)
- ✅ Documented in `docs/automation.md`
