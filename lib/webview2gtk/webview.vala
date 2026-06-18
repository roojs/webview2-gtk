/* GTK 4 widget embedding Microsoft Edge WebView2 (Windows only).
 *
 * Public API follows the WebKitGTK 6 WebKit.WebView subset so apps can use:
 *
 *   #if WINDOWS
 *   using WebView2Gtk;
 *   #else
 *   using WebKit;
 *   #endif
 *
 *   var web = new WebView ();
 *   web.load_uri ("https://example.com/");
 */

using Graphene;

[CCode (cheader_filename = "webview2gtk-gdk-win32.h", cname = "gdk_win32_surface_get_handle")]
extern void* gdk_win32_surface_get_handle (Gdk.Surface surface);

[CCode (cheader_filename = "webview2gtk-gdk-win32.h", cname = "webview2gtk_widget_bounds_xywh")]
extern bool widget_bounds_xywh (Gtk.Widget widget, out int x, out int y, out int width, out int height);

[CCode (cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_create_with_xywh")]
extern bool wv2_host_create_with_xywh (void* parent_hwnd, int x, int y, int width, int height, uint16* url);
[CCode (cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_set_bounds_xywh")]
extern void wv2_host_set_bounds_xywh (int x, int y, int width, int height);
[CCode (cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_navigate")]
extern bool wv2_host_navigate (string url);
[CCode (cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_navigate_to_string")]
extern bool wv2_host_navigate_to_string (string html);
[CCode (cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_destroy")]
extern void wv2_host_destroy ();
[CCode (cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_is_ready")]
extern bool wv2_host_is_ready ();
[CCode (cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_go_back")]
extern bool wv2_host_go_back ();
[CCode (cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_go_forward")]
extern bool wv2_host_go_forward ();
[CCode (cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_reload")]
extern bool wv2_host_reload ();
[CCode (cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_stop")]
extern bool wv2_host_stop ();
[CCode (cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_get_can_go_back")]
extern bool wv2_host_get_can_go_back ();
[CCode (cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_get_can_go_forward")]
extern bool wv2_host_get_can_go_forward ();
[CCode (cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_get_source")]
extern string wv2_host_get_source ();
[CCode (cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_get_document_title")]
extern string wv2_host_get_document_title ();
[CCode (cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_get_zoom_factor")]
extern double wv2_host_get_zoom_factor ();
[CCode (cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_put_zoom_factor")]
extern bool wv2_host_put_zoom_factor (double zoom);
[CCode (cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_put_is_visible")]
extern bool wv2_host_put_is_visible (bool visible);

[CCode (cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_set_event_handlers")]
extern void wv2_host_set_event_handlers (
	void* navigation_starting,
	void* navigation_completed,
	void* document_title_changed,
	void* user_data
);

namespace WebView2Gtk {

/**
 * Load lifecycle events — same names and order as WebKit.LoadEvent.
 */
public enum LoadEvent {
	STARTED,
	REDIRECTED,
	COMMITTED,
	FINISHED
}

/**
 * Embeds WebView2 in a GTK 4 window using the toplevel Win32 HWND from
 * `gdk_win32_surface_get_handle()` on the native surface.
 *
 * API surface matches WebKitGTK 6 `WebKit.WebView` for navigation, URI/title
 * queries, HTML loading, zoom, and `load_changed`.
 *
 * **Limitation (v0.1):** one WebView2 host per process (shared COM singleton).
 */
public class WebView : Gtk.Box {
	private Gtk.Widget _host;
	private void* _parent_hwnd = null;
	private bool _attached = false;
	private bool _host_shown_on_screen = true;
	private string? _pending_uri = null;

	private string _uri = "about:blank";
	private string _title = "";
	private bool _is_loading = false;
	private double _estimated_load_progress = 0.0;
	private double _zoom_level = 1.0;
	private WebViewSettings _capture_settings = new WebViewSettings ();
	private NetworkSession _network_session = new NetworkSession ();

	public bool is_loading {
		get { return _is_loading; }
	}

	public double estimated_load_progress {
		get { return _estimated_load_progress; }
	}

	/** WebView2Gtk-specific: host COM object is attached and ready. */
	public bool ready {
		get { return _attached && wv2_host_is_ready (); }
	}

	public WebView () {
		Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
		_host = new Gtk.DrawingArea ();
		_host.set_hexpand (true);
		_host.set_vexpand (true);
		append (_host);

		_host.map.connect (on_host_map);
		_host.add_tick_callback (on_frame_tick);

		this.notify["opacity"].connect (() => {
			this.sync_host_visible ();
		});
		this.notify["visible"].connect (() => {
			this.sync_host_visible ();
		});
	}

	public signal void load_changed (LoadEvent load_event);

	protected override void size_allocate (int width, int height, int baseline) {
		base.size_allocate (width, height, baseline);
		if (!_attached) {
			try_attach ();
			return;
		}
		push_bounds ();
	}

	~WebView () {
		if (_attached) {
			wv2_host_set_event_handlers (null, null, null, null);
			wv2_host_destroy ();
			_attached = false;
		}
	}

	public bool can_go_back () {
		return _attached && wv2_host_get_can_go_back ();
	}

	public bool can_go_forward () {
		return _attached && wv2_host_get_can_go_forward ();
	}

	public unowned string get_uri () {
		if (_attached && wv2_host_is_ready ()) {
			var live = wv2_host_get_source ();
			if (live.length > 0) {
				_uri = live;
			}
		}
		return _uri;
	}

	public unowned string get_title () {
		if (_attached && wv2_host_is_ready ()) {
			_title = wv2_host_get_document_title ();
		}
		return _title;
	}

	public void load_uri (string uri) {
		_uri = uri;
		_pending_uri = uri;
		try_navigate ();
	}

	public void load_html (string content, string? base_uri = null) {
		var html = content;
		if (base_uri != null && base_uri.length > 0) {
			html = "<head><base href=\"%s\"></head>%s".printf (
				Markup.escape_text (base_uri),
				content
			);
		}
		_uri = base_uri ?? "about:blank";
		if (_attached && wv2_host_is_ready ()) {
			wv2_host_navigate_to_string (html);
		} else {
			_pending_uri = "data:text/html;charset=utf-8," + Uri.escape_string (html, null);
			try_navigate ();
		}
	}

	public void load_plain_text (string plain_text) {
		var escaped = Markup.escape_text (plain_text);
		load_html ("<pre>%s</pre>".printf (escaped), null);
	}

	public void reload () {
		wv2_host_reload ();
	}

	public void reload_bypass_cache () {
		/* WebView2 has no WebKit-style cache bypass; reload is the closest match. */
		wv2_host_reload ();
	}

	public void stop_loading () {
		wv2_host_stop ();
		set_loading (false, 0.0);
	}

	public void go_back () {
		wv2_host_go_back ();
	}

	public void go_forward () {
		wv2_host_go_forward ();
	}

	public double get_zoom_level () {
		if (_attached && wv2_host_is_ready ()) {
			_zoom_level = wv2_host_get_zoom_factor ();
		}
		return _zoom_level;
	}

	public void set_zoom_level (double zoom_level) {
		_zoom_level = zoom_level;
		if (_attached && wv2_host_is_ready ()) {
			wv2_host_put_zoom_factor (zoom_level);
		}
	}

	public new WebViewSettings get_settings () {
		return _capture_settings;
	}

	public NetworkSession get_network_session () {
		return _network_session;
	}

	public async Gdk.Texture get_snapshot (
		SnapshotRegion region,
		SnapshotOptions options,
		GLib.Cancellable? cancellable = null
	) throws GLib.Error {
		/* WebView2 COM + message pump must run on the GTK/UI thread. */
		var full_document = region == SnapshotRegion.FULL_DOCUMENT;
		string? devtools_json = null;
		var capture_ok = wv2_capture_screenshot_sync (full_document, out devtools_json);
		var png_bytes = devtools_json_to_png_bytes (devtools_json);
		if (!capture_ok || png_bytes == null) {
			if (devtools_json != null) {
				GLib.warning (
					"get_snapshot: DevTools response (truncated): %s",
					devtools_json.substring (
						0,
						int.min (devtools_json.length, 200)
					)
				);
			}
			throw new GLib.IOError.FAILED ("Screenshot capture failed");
		}
		return Gdk.Texture.from_bytes (new Bytes.take ((owned) png_bytes));
	}

	public async JavaScriptResult evaluate_javascript (
		string script,
		ssize_t length = -1,
		string? world_name = null,
		string? source_uri = null,
		GLib.Cancellable? cancellable = null
	) throws GLib.Error {
		/* Same thread rule as get_snapshot — ExecuteScript is COM on the UI thread. */
		string? raw = null;
		var script_ok = wv2_execute_script_sync (script, out raw);
		if (!script_ok) {
			throw new GLib.IOError.FAILED ("execute_script failed");
		}
		return new JavaScriptResult (raw ?? "null");
	}

	private static uint8[]? devtools_json_to_png_bytes (string? devtools_json)
	{
		if (devtools_json == null) {
			return null;
		}
		try {
			string[] markers = { "\"data\":\"", "\"data\": \"" };
			foreach (var marker in markers) {
				var start = devtools_json.index_of (marker);
				if (start < 0) {
					continue;
				}
				start += marker.length;
				var end = devtools_json.index_of_char ('"', start);
				if (end < 0) {
					continue;
				}
				return Base64.decode (devtools_json.substring (start, end - start));
			}
		} catch (GLib.Error e) {
			return null;
		}
		return null;
	}

	private Gtk.Window? toplevel_window () {
		return _host.get_root () as Gtk.Window;
	}

	private void* toplevel_hwnd () {
		var native = _host.get_native ();
		if (native == null) {
			return null;
		}
		var surface = native.get_surface ();
		if (surface == null) {
			return null;
		}
		return gdk_win32_surface_get_handle (surface);
	}

	private bool host_bounds (out int x, out int y, out int width, out int height) {
		return widget_bounds_xywh (_host, out x, out y, out width, out height);
	}

	private void push_bounds () {
		if (!_attached || _parent_hwnd == null) {
			return;
		}
		int x;
		int y;
		int width;
		int height;
		if (!host_bounds (out x, out y, out width, out height)) {
			return;
		}
		if (!_host_shown_on_screen) {
			/* Off-screen while GTK opacity is 0 — DevTools capture still needs IsVisible. */
			x = -30000;
			y = -30000;
		}
		wv2_host_set_bounds_xywh (x, y, width, height);
	}

	private void sync_host_visible () {
		if (!_attached) {
			return;
		}
		_host_shown_on_screen = this.get_visible () && this.get_opacity () > 0.001;
		wv2_host_put_is_visible (true);
		push_bounds ();
	}

	private void try_navigate () {
		if (_pending_uri == null || !_attached) {
			return;
		}
		if (wv2_host_navigate (_pending_uri)) {
			_pending_uri = null;
		}
	}

	private void try_attach () {
		if (_attached) {
			return;
		}
		var window = toplevel_window ();
		if (window == null) {
			return;
		}
		_parent_hwnd = toplevel_hwnd ();
		if (_parent_hwnd == null) {
			return;
		}

		int x;
		int y;
		int width;
		int height;
		if (!host_bounds (out x, out y, out width, out height)) {
			return;
		}

		if (!wv2_host_create_with_xywh (_parent_hwnd, x, y, width, height, null)) {
			warning ("WebView2Gtk: create_with_xywh failed (runtime/loader missing?)");
			return;
		}
		_attached = true;
		wv2_host_set_event_handlers (
			(void*) on_navigation_starting_cb,
			(void*) on_navigation_completed_cb,
			(void*) on_document_title_changed_cb,
			this
		);
		this.sync_host_visible ();
		try_navigate ();
	}

	private bool on_frame_tick (Gtk.Widget widget, Gdk.FrameClock frame_clock) {
		if (!_attached) {
			try_attach ();
		} else {
			push_bounds ();
		}
		return Source.CONTINUE;
	}

	private void on_host_map () {
		try_attach ();
		Idle.add (() => {
			try_attach ();
			push_bounds ();
			return false;
		});
	}

	private void set_loading (bool loading, double progress) {
		if (_is_loading == loading && (!loading || _estimated_load_progress == progress)) {
			return;
		}
		_is_loading = loading;
		_estimated_load_progress = progress;
		notify_property ("is-loading");
		notify_property ("estimated-load-progress");
	}

	private void refresh_uri () {
		get_uri ();
	}

	private void refresh_title () {
		get_title ();
	}

	private void on_navigation_starting () {
		set_loading (true, 0.1);
		load_changed (LoadEvent.STARTED);
	}

	private void on_navigation_completed (bool success) {
		if (success) {
			refresh_uri ();
			refresh_title ();
		}
		set_loading (false, success ? 1.0 : 0.0);
		load_changed (LoadEvent.FINISHED);
	}

	private void on_document_title_changed () {
		refresh_title ();
	}

	[CCode (has_target = false)]
	private static void on_navigation_starting_cb (void* user_data) {
		((WebView) user_data).on_navigation_starting ();
	}

	[CCode (has_target = false)]
	private static void on_navigation_completed_cb (void* user_data, bool success) {
		((WebView) user_data).on_navigation_completed (success);
	}

	[CCode (has_target = false)]
	private static void on_document_title_changed_cb (void* user_data) {
		((WebView) user_data).on_document_title_changed ();
	}
}

}
