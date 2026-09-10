# webview2-gtk

**GTK 4** widget embedding **Microsoft Edge WebView2** on Windows — a practical substitute for WebKitGTK when you already use GTK and need a modern HTML engine.

![webview2-gtk browser demo](https://github.com/user-attachments/assets/6cbc26f0-a172-4615-ac48-70d2cc9bef53)

The widget takes the native HWND from `gdk_win32_surface_get_handle()` on the window’s `GdkSurface` and parents WebView2 there.

Build and link on **Windows**. Share Vala source with Linux via `#if WINDOWS` (WebKitGTK on Linux, this library on Windows).

| Doc | |
|-----|--|
| [Changelog](CHANGELOG.md) | Notable changes per release |
| [Install (setup.exe / pacman)](docs/install.md) | Get a prebuilt library |
| [Build this library](docs/build-this-library.md) | Clone, MSYS2, meson, demos |
| [Use in your app](docs/using-in-your-app.md) | Consumer Meson + `#if WINDOWS` |
| [Automation](docs/automation.md) | WebKit-shaped setup; fill via external CDP/driver |
| [Limitations vs WebKitGTK](#limitations-vs-webkitgtk) | Proxy / create-time flags / process scope |
| [Releasing](docs/releasing.md) | Tag-driven release flow and changelog preflight |
| [Deploying a Windows build](docs/deploying-windows.md) | Bundle GTK / WebView2Loader DLLs |
| **[API docs (Valadoc)](https://roojs.github.io/webview2-gtk/)** | Generated reference on GitHub Pages |

---

## Sample usage

### WebView — shared source (`#if WINDOWS`)

Use **`WebView2Gtk`** on Windows and **`WebKit`** on Linux. Same type name (`WebView`), same common methods:

```vala
using Gtk;

#if WINDOWS
using WebView2Gtk;
#else
using WebKit;
#endif

var web = new WebView ();
web.load_uri ("https://example.com/");
window.set_child (web);
```

Pass `-D WINDOWS` to `valac` on Windows (see [using-in-your-app.md](docs/using-in-your-app.md) for the Meson snippet).

Namespaces are parallel by design:

| Role | Windows | Linux |
|------|---------|-------|
| Widget | `WebView2Gtk.WebView` | `WebKit.WebView` |
| Accessibility | `Win32Atspi.*` | `Atspi.*` (system AT-SPI) |

### Win32Atspi — accessibility (Windows)

AT-SPI-shaped API over WebView2 UI Automation. **Not** methods on `WebView` — register happens when the widget attaches; you walk the tree via `Win32Atspi`:

```vala
using Win32Atspi;

Win32Atspi.init ();
var desktop = Win32Atspi.get_desktop (0);
var app = desktop.get_child_at_index (i);   // match your pid
var frame = app.get_child_at_index (0);
var doc = frame.get_child_at_index (0);     // "document frame" (further children if several WebViews)

acc.get_role_name ();
acc.get_name ();
acc.do_action (0);                          // Invoke / activate
acc.set_text_contents ("search text");
Win32Atspi.generate_keyboard_event (...);
```

Tree shape and notes: [docs/a11y.md](docs/a11y.md). Interactive smoke: `examples/browser` (Invoke / Fill / Win32Atspi buttons).

---

## API

Full reference: **[https://roojs.github.io/webview2-gtk/](https://roojs.github.io/webview2-gtk/)**

- [`WebView2Gtk.WebView`](https://roojs.github.io/webview2-gtk/webview2gtk/WebView2Gtk.WebView.html)
- [`Win32Atspi`](https://roojs.github.io/webview2-gtk/webview2gtk/Win32Atspi.html) / [`Accessible`](https://roojs.github.io/webview2-gtk/webview2gtk/Win32Atspi.Accessible.html)

How docs are built and marked up: [docs/code-documentation.md](docs/code-documentation.md).

Names and call shapes follow **WebKitGTK 6** so shared `#if WINDOWS` sites stay small (`load_uri`, `load_changed`, cookies, downloads, automation construct props, …). WebView2Gtk-only: `ready`. Accessibility is **`Win32Atspi`**, not methods on `WebView`.

🚫 Public `WebView` click/type APIs are intentional omissions — fill stays with an **external** driver/CDP client ([automation.md](docs/automation.md)).

Not implemented yet: full settings surface, `register_script_message_handler_with_reply`, etc. (`load_failed` and `JavaScriptResult.to_string` are implemented.)

---

## Limitations vs WebKitGTK

The API **looks** like WebKitGTK; several behaviors do **not**. Read these before porting network or automation setup.

### Proxy (`NetworkSession.set_proxy_settings`)

On **WebKitGTK**, `set_proxy_settings` applies to that `NetworkSession` and can change while the session is live.

On **Windows**, WebView2 only honors proxy via Chromium flags (`--proxy-server` / `--no-proxy-server`) at **environment create**:

- Call **before** the first WebView attaches (before first `present` / host create).
- The latch is **process-wide** (one shared WebView2 environment) — every controller from that env uses the same proxy.
- Changing proxy **after** the env exists does **not** retarget traffic (warns once; stored for a future recreate only).
- Typical app pattern: one browser window at a time; point `CUSTOM` at a **local** forwarding proxy for that window’s life; close the window (release last host → env dropped) before opening another with a different latch. Details and smoke: [automation.md](docs/automation.md).

### Other create-time Chromium flags

Same “set before first attach” class as proxy (not live mid-session toggles like some WebKit knobs):

| Surface | Windows behavior |
|---------|------------------|
| `WebsitePolicies` autoplay `DENY` / media gesture | `--autoplay-policy=…` at env create |
| `NavigatorWebDriverActivePolicy.DISABLED` | `--disable-blink-features=AutomationControlled` at env create |
| `WEBKIT_INSPECTOR_SERVER` | `--remote-debugging-port` at env create |

### Process / profile scope

Each GTK `WebView` owns its own WebView2 **controller**, but they share one **Environment**. Cookie profile and CDP/automation remain process-scoped by design.

`CookieManager.set_persistent_storage(SQLITE)` is not supported (`GLib.error`); `TEXT` path jars work. Page-driven Set-Cookie is not mirrored into `CookieManager.changed` the way a full WebKit jar observer might.

---
## Layout

```
lib/host/           WebView2 COM host
lib/webview2gtk/    Public GTK 4 widget + Win32Atspi (Vala)
vapi/               Bindings
examples/hello/     Minimal demo
examples/browser/   Browser chrome + Win32Atspi smoke
examples/automation/  Automation setup smoke (plan 3.0)
examples/paned-insert/  Login → first paned insert + load_uri (blank-pane repro)
examples/add-cookie/    add_cookie / get_all / replace; --smoke-changed; --smoke-replace-startup
examples/hidden-stack/  Win32Atspi Gtk.Stack hidden-primary document pick
examples/consumer-meson.build
docs/               Install / build / use / deploy / a11y / automation / Valadoc
packaging/          NSIS + MSYS2 PKGBUILD
scripts/            Vendor SDK, build, package demos, sample consumer helpers
```

## Origin

Host stack from **vala.win32** (WebView2). This repo is the GTK 4 widget layer, Win32Atspi facade, and packaging.

## Artificial Intelligence Usage

This project was developed with the assistance of artificial intelligence.

- Product design and code design were done by the author
- AI’s main role was writing implementation for review
- Most of the coding was performed by AI
- Vala application code was reviewed, revised, and approved by the author
- The C / C++ host and binding code, and the build system, are mainly AI-generated and only lightly reviewed
