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

`web_context`, `is_controlled_by_automation`, and `network_session` are construct-only (webkitgtk-6.0). Set them in a subclass `Object(…)` chain-up (`WebViewAuto`, same shape as Snappr `src/UI/WebViewAuto.vala`). There is no `set_controlled_by_automation`. See `examples/automation/`.

## Demo and smokes

Built demos(after `package-demos` on the Windows build machine):

`C:\msys64\tmp\webview2-gtk\portable-demos\`

### Setup only(3.2)

```powershell
& 'C:\msys64\tmp\webview2-gtk\portable-demos\webview2gtk-automation.exe' --smoke --inspector-port 19222
```

Pass: console shows `automation-started session=…`.  
Chromium may print `Failed to unregister class Chrome_WidgetWin_0` on quit — known WebView2 teardown noise.

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

- Plan: [plans/3.0-engine-fill-input.md](plans/3.0-engine-fill-input.md)
- Example source: [examples/automation/](../examples/automation/)
- Attach client: [examples/cdp-attach/](../examples/cdp-attach/)
