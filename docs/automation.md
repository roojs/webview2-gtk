# Automation(WebKitGTK-shaped setup on Windows)

webview2-gtk emulates the **WebKitGTK automation setup** APIs so shared Vala can enable an automation-controlled `WebView` on Windows the same way as on Linux. **Fill(click / sendKeys) is not a `WebView` method** — the app talks to an **external** driver(or CDP client), which attaches to the browser.

## Two layers

```
┌─────────────────────────────────────────────────────────────┐
│  A. Fill commands(app → driver)                            │
│     HTTP / CDP client  ──►  external driver / CDP endpoint  │
│     (click, sendKeys, Actions, …)                           │
└───────────────────────────────┬─────────────────────────────┘
                                │ attach
┌───────────────────────────────▼─────────────────────────────┐
│  B. Browser setup(app → WebView2Gtk)  ← this library       │
│     set_automation_allowed, controlled WebView,             │
│     automation_started / ApplicationInfo / create_web_view  │
│     WEBKIT_INSPECTOR_SERVER → CDP --remote-debugging-port   │
└─────────────────────────────────────────────────────────────┘
```

| | Linux(WebKitGTK) | Windows(webview2-gtk) |
|--|-------------------|-------------------------|
| Browser setup | `WebContext` / `AutomationSession` / … | Same Vala names under `WebView2Gtk` |
| Inspector listen | `WEBKIT_INSPECTOR_SERVER=host:port` | Same env → WebView2 `--remote-debugging-port` + `--remote-allow-origins=*` |
| Attach | `WebKitWebDriver -t host:port` | CDP client(Playwright `connectOverCDP`, Edge WebDriver `debuggerAddress`, or any CDP tool) |
| Fill API | HTTP to `WebKitWebDriver` | HTTP/CDP to that external client — **not** `WebView.click` |

🚫 Do **not** expect public `WebView` click/type APIs(they are not in webkitgtk-6.0).  
🚫 Do **not** expect a WebDriver HTTP server inside this library(on Linux that process is external `WebKitWebDriver`).

## Browser setup(shared Vala shape)

```vala
#if WINDOWS
using WebView2Gtk;
#else
using WebKit;
#endif

var context = WebContext.get_default();
context.set_automation_allowed(true);

var ns = context.get_network_session_for_automation();
/* Subclass Object(…) chain-up — construct-only on WebKitGTK and webview2-gtk.
 * new WebView() { is_controlled_by_automation = true } does not compile. */
var view = new WebViewAuto(context, ns);

context.automation_started.connect((session) => {
	var info = new ApplicationInfo();
	info.set_name("MyApp");
	info.set_version(1, 0, 0);
	session.set_application_info(info);
	session.create_web_view.connect(() => view);
});

Environment.set_variable("WEBKIT_INSPECTOR_SERVER", "127.0.0.1:19222", true);
/* set before the WebView2 environment is created(before first present/attach) */
```

`web_context`, `is_controlled_by_automation`, `network_session`, and `website_policies` are construct-only (webkitgtk-6.0). Set them in a subclass `Object(…)` chain-up (see `WebViewAuto` in `examples/automation/`). There is no `set_controlled_by_automation`.

Also shared: `get_settings().enable_developer_extras` and `get_inspector().show()` (opens Edge DevTools when extras are enabled). Media settings, `is_muted`, and `permission_request` / `query_permission_state` match WebKitGTK shapes (mute + `PermissionRequested` on the host).

To hide Blink’s automation fingerprint on controlled views (WebKit twin of
`NavigatorWebDriverActivePolicy.DISABLED`):

```vala
set_navigator_webdriver_active_policy(
	view.get_settings(),
	NavigatorWebDriverActivePolicy.DISABLED
);
/* or: view.get_settings().navigator_webdriver_active_policy =
 *     NavigatorWebDriverActivePolicy.DISABLED; */
```

Set **before** the WebView2 environment is created (before first present/attach).
`DISABLED` merges `--disable-blink-features=AutomationControlled` into
`AdditionalBrowserArguments` alongside CDP / autoplay args.

### HTTP(S) proxy (`NetworkSession.set_proxy_settings`)

Same create-time latch as webdriver / autoplay. Typical consumer pattern: one
browser window at a time; point `CUSTOM` at a **local** forwarding proxy for the
life of that window; the local proxy routes by request host (ChatGPT → CA, etc.).
Chromium applies the flag to **all** HTTP(S) from that environment (main frame,
subresources, XHR) — not only the top-level navigation host.

```vala
web_view.network_session.set_proxy_settings(
	NetworkProxyMode.CUSTOM,
	new NetworkProxySettings("http://127.0.0.1:8888", null)
);
/* then present / load_uri — before first WebView2 env create */
```

| Mode | Chromium arg |
|------|----------------|
| `CUSTOM` | `--proxy-server=<uri>` |
| `NONE` | `--no-proxy-server` |
| `DEFAULT` | omit (system default) |

Late calls after env create warn and do not retarget a live environment. Closing
the window and creating a new one (new process env after last host release, or a
fresh process) is how you switch proxy for the next browser session.

Smoke:

```powershell
& 'C:\msys64\tmp\webview2-gtk\portable-demos\webview2gtk-add-cookie.exe' --smoke-proxy
```

Pass: `TEST_PASS` (CUSTOM to a closed local port fails closed — no “Example Domain”).

## Demo and smokes

Built demos(after `package-demos` on the Windows build machine):

`C:\msys64\tmp\webview2-gtk\portable-demos\`

### Setup only(3.2)

```powershell
& 'C:\msys64\tmp\webview2-gtk\portable-demos\webview2gtk-automation.exe' --smoke --inspector-port 19222
```

Pass: console shows `a11y_documents=2` and `TEST_PASS` (two WebViews, AT-SPI walk — **does not fill** the form).
Chromium may print `Failed to unregister class Chrome_WidgetWin_0` on quit — known WebView2 teardown noise.

### Stack (hidden host)

Same exe, `Gtk.Stack` with one unmapped child (load on the hidden view):

```powershell
& 'C:\msys64\tmp\webview2-gtk\portable-demos\webview2gtk-automation.exe' --smoke-stack
```

Pass: `STACK_SMOKE_PASS` and Phase A lists both `stack primary document` and `stack secondary document`. Interactive: `./scripts/run-automation-smoke-stack-interactive.sh`.

### Hide `navigator.webdriver` (policy)

```powershell
& 'C:\msys64\tmp\webview2-gtk\portable-demos\webview2gtk-automation.exe' --smoke-webdriver
```

Pass: `navigator.webdriver===true → false` and `TEST_PASS`.

### Attach + fill via CDP (3.3)

**Terminal 1** (leave running — no `--smoke`):

```powershell
& 'C:\msys64\tmp\webview2-gtk\portable-demos\webview2gtk-automation.exe' --inspector-port 19222
```

**Terminal 2:**

```powershell
& 'C:\msys64\tmp\webview2-gtk\portable-demos\webview2gtk-cdp-attach.exe'
```

Pass: `ATTACH_FILL_PASS` and the page’s `#q` field shows `webview2gtk-cdp-fill`.

`webview2gtk-cdp-attach` is a small Vala/libsoup CDP client (not a library fill API).

## Related

- Plan: [plans/3.0-engine-fill-input.md](plans/done/3.0-engine-fill-input.md)
- Example source: [examples/automation/](../examples/automation/)
- Attach client: [examples/cdp-attach/](../examples/cdp-attach/)
