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
var doc = frame.get_child_at_index (0);     // "document frame"

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

### WebKitGTK 6–aligned surface

`WebView2Gtk.WebView` mirrors the common **WebKit.WebView** calls so shared `#if WINDOWS` sites stay small:

| WebKitGTK 6 | WebView2Gtk |
|-------------|-------------|
| `load_uri()` | `load_uri()` |
| `load_html()` / `load_plain_text()` | same |
| `go_back()` / `go_forward()` / `reload()` | same |
| `can_go_back()` / `can_go_forward()` | same |
| `stop_loading()` | same |
| `get_uri()` / `get_title()` | same |
| `is_loading` / `estimated_load_progress` | same (progress approximate) |
| `zoom_level` | same |
| `load_changed(LoadEvent)` | same enum names |
| `UserContentManager` / `get_user_content_manager()` | `register_script_message_handler` + detailed `script_message_received` |
| `evaluate_javascript` | same (host→page replies) |
| `download_uri` / `NetworkSession.download_started` / `Download` | same shapes (destination via `set_destination`) |
| `resource_load_started` / `WebResource` | same (`finished` / `failed` on the resource) |
| `WebContext` automation allow / `automation_started` | same names; see [automation.md](docs/automation.md) |
| `AutomationSession` / `ApplicationInfo` | same names |
| `WEBKIT_INSPECTOR_SERVER` | honored → WebView2 CDP `--remote-debugging-port` |
| `WebsitePolicies` / `autoplay` | construct on `WebView`; `DENY` → Chromium autoplay flag |
| `enable_developer_extras` / `get_inspector().show()` | Edge DevTools window |
| `enable_media_stream` / `enable_webrtc` / gesture | settings; mute + `PermissionRequested` deny on host |
| `is_muted` / `permission_request` | mute via `ICoreWebView2_8`; WebKit-shaped permission signals |

WebView2Gtk-only: `ready`. Accessibility: **`Win32Atspi`** (above), not on `WebView`.

Not implemented yet: full settings surface, policy callbacks, `register_script_message_handler_with_reply`, mute/WebRTC/permission APIs, etc. (`load_failed` and `JavaScriptResult.to_string` are implemented.)  
🚫 Public `WebView` click/type APIs are intentional omissions — fill stays with an **external** driver/CDP client ([automation.md](docs/automation.md)).

**Limitation:** each GTK `WebView` owns its own WebView2 controller (shared Environment). Cookie profile and CDP/automation remain process-scoped by design.

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
examples/consumer-meson.build
docs/               Install / build / use / deploy / a11y / automation / Valadoc
packaging/          NSIS + MSYS2 PKGBUILD
scripts/            Vendor SDK, build, package demos, sample consumer helpers
```

## Origin

Host stack from **vala.win32** (WebView2). This repo is the GTK 4 widget layer, Win32Atspi facade, and packaging.
