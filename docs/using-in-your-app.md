# Use webview2-gtk in your app

Share Vala source between Linux (**WebKitGTK**) and Windows (**webview2gtk**) with `#if WINDOWS` and matching `using` namespaces.

## Vala layout

```vala
using Gtk;

#if WINDOWS
using WebView2Gtk;
#else
using WebKit;
#endif

public class BrowserWindow : Gtk.ApplicationWindow {
	private WebView web;

	public BrowserWindow (Gtk.Application app) {
		Object (application: app);
		web = new WebView ();
		web.load_uri ("https://example.com/");
		set_child (web);
	}
}
```

On Windows, pass `-D WINDOWS` to `valac` (Meson sample below does that). Both APIs expose the common WebKitGTK 6-shaped surface (`load_uri`, `go_back`, …) — see the [README API table](../README.md#api).

**Windows-only accessibility** uses a separate namespace (not methods on `WebView`):

```vala
#if WINDOWS
using Win32Atspi;

Win32Atspi.init ();
var desktop = Win32Atspi.get_desktop (0);
// … walk Accessible tree, do_action / set_text_contents …
#endif
```

Details: [a11y.md](a11y.md). Full samples: [examples/hello](../examples/hello/), [examples/browser](../examples/browser/).

## Sample Meson (`meson.build`)

Full copy: [`examples/consumer-meson.build`](../examples/consumer-meson.build)

```meson
project('my-browser-app', ['c', 'vala'], version: '1.0.0')

gtk4 = dependency('gtk4')
win = host_machine.system() == 'windows'

if win
  # setup.exe → Program Files pkgconfig; pacman → already on PKG_CONFIG_PATH
  webview2gtk_pc = 'C:/Program Files/webview2gtk/lib/pkgconfig'
  meson.add_env('PKG_CONFIG_PATH', webview2gtk_pc, method: 'prepend')
  webview_dep = dependency('webview2gtk-1')
  vala_args = ['-D', 'WINDOWS']
else
  webview_dep = dependency('webkitgtk-6.0', version: '>= 6.0')
  vala_args = []
endif

executable(
  'my-browser-app',
  files('src/main.vala'),
  dependencies: [gtk4, webview_dep],
  vala_args: vala_args,
  install: true,
)
```

Install the library first: [install.md](install.md). Build your app on each platform locally (Linux → WebKitGTK, Windows → webview2gtk).

**Alternative:** copy [`scripts/sample-build.sh`](../scripts/sample-build.sh) into your project, edit the settings at the top, then run it under UCRT64 (see [build-this-library.md](build-this-library.md)).

Shipping the `.exe` to end users: [deploying-windows.md](deploying-windows.md).
