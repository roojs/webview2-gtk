/* GTK 4 widget embedding Microsoft Edge WebView2(Windows only).
 *
 * Public API follows the WebKitGTK 6 WebKit.WebView subset so apps can use:
 *
 *   #if WINDOWS
 *   using WebView2Gtk;
 *   #else
 *   using WebKit;
 *   #endif
 *
 *   var web = new WebView();
 *   web.load_uri("https://example.com/");
 */

using Graphene;

[CCode(cheader_filename = "webview2gtk-gdk-win32.h", cname = "gdk_win32_surface_get_handle")]
extern void* gdk_win32_surface_get_handle(Gdk.Surface surface);

[CCode(cheader_filename = "webview2gtk-gdk-win32.h", cname = "webview2gtk_widget_bounds_xywh")]
extern bool widget_bounds_xywh(Gtk.Widget widget, out int x, out int y, out int width, out int height);

[CCode(cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_create_with_xywh")]
extern bool wv2_host_create_with_xywh(void* parent_hwnd, int x, int y, int width, int height, uint16* url);
[CCode(cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_set_bounds_xywh")]
extern void wv2_host_set_bounds_xywh(int x, int y, int width, int height);
[CCode(cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_navigate")]
extern bool wv2_host_navigate(string url);
[CCode(cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_navigate_to_string")]
extern bool wv2_host_navigate_to_string(string html);
[CCode(cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_destroy")]
extern void wv2_host_destroy();
[CCode(cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_is_ready")]
extern bool wv2_host_is_ready();
[CCode(cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_go_back")]
extern bool wv2_host_go_back();
[CCode(cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_go_forward")]
extern bool wv2_host_go_forward();
[CCode(cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_reload")]
extern bool wv2_host_reload();
[CCode(cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_stop")]
extern bool wv2_host_stop();
[CCode(cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_get_can_go_back")]
extern bool wv2_host_get_can_go_back();
[CCode(cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_get_can_go_forward")]
extern bool wv2_host_get_can_go_forward();
[CCode(cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_get_source")]
extern string wv2_host_get_source();
[CCode(cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_get_document_title")]
extern string wv2_host_get_document_title();
[CCode(cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_get_zoom_factor")]
extern double wv2_host_get_zoom_factor();
[CCode(cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_put_zoom_factor")]
extern bool wv2_host_put_zoom_factor(double zoom);
[CCode(cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_put_is_visible")]
extern bool wv2_host_put_is_visible(bool visible);

[CCode(cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_set_autoplay_policy")]
extern void wv2_host_set_autoplay_policy(int policy);

[CCode(cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_open_dev_tools_window")]
extern bool wv2_host_open_dev_tools_window();

[CCode(cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_set_media_flags")]
extern void wv2_host_set_media_flags(bool enable_media_stream, bool enable_webrtc);

[CCode(cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_set_is_muted")]
extern bool wv2_host_set_is_muted(bool muted);

[CCode(cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_get_is_muted")]
extern bool wv2_host_get_is_muted();

[CCode(cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_set_permission_handler")]
extern void wv2_host_set_permission_handler(void* decide, void* user_data);

[CCode(cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_set_event_handlers")]
extern void wv2_host_set_event_handlers(
	void* navigation_starting,
	void* navigation_completed,
	void* document_title_changed,
	void* user_data
);

[CCode(cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_set_document_response_handler")]
extern void wv2_host_set_document_response_handler(
	void* handler,
	void* user_data
);

[CCode(cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_set_script_message_handler")]
extern void wv2_host_set_script_message_handler(
	void* handler,
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
 * **Limitation(v0.1):** one WebView2 host per process(shared COM singleton).
 */
public class WebView : Gtk.Box {
	private Gtk.Widget host;
	private void* parent_hwnd = null;
	private bool attached = false;
	private bool host_shown_on_screen = true;
	private string pending_uri = "";
	private string pending_html = "";

	private string uri = "about:blank";
	private string title = "";
	private bool load_cancelled = false;
	private double zoom_level = 1.0;
	private WebViewSettings capture_settings = new WebViewSettings();
	private UserContentManager user_content_manager = new UserContentManager();
	private Gee.HashMap<int, WebResource> resources = new Gee.HashMap<int, WebResource> ();
	private WebInspector? inspector = null;
	private bool muted = false;

	/** WebKitGTK-shaped — context for this view. */
	public WebContext web_context { owned get; construct; }

	/** WebKitGTK-shaped — network session for this view. */
	public NetworkSession network_session { get; construct; }

	/** WebKitGTK-shaped — this view is owned by an automation session. */
	public bool is_controlled_by_automation { get; construct; }

	/** WebKitGTK-shaped — website policies (autoplay, …). */
	public WebsitePolicies website_policies { get; construct; }

	/** WebKitGTK-shaped — mute page audio. */
	public bool is_muted {
		get {
			if (attached && wv2_host_is_ready()) {
				muted = wv2_host_get_is_muted();
			}
			return muted;
		}
		set {
			muted = value;
			wv2_host_set_is_muted(value);
		}
	}

	construct {
		if (this.web_context == null) {
			this.web_context = WebContext.get_default();
		}
		if (this.network_session == null) {
			this.network_session = new NetworkSession();
		}
		if (this.website_policies == null) {
			this.website_policies = new WebsitePolicies();
		}
		wv2_host_set_autoplay_policy((int) this.website_policies.autoplay);
		if (this.is_controlled_by_automation) {
			this.web_context.register_controlled_webview(this);
		}
	}

	public bool is_loading { get; private set; }

	public double estimated_load_progress { get; private set; }

	/** WebView2Gtk-specific: host COM object is attached and ready. */
	public bool ready {
		get { return attached && wv2_host_is_ready(); }
	}

	public WebView() {
		Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);

		host = new Gtk.DrawingArea();
		host.set_hexpand(true);
		host.set_vexpand(true);
		append(host);

		host.map.connect(on_host_map);
		host.add_tick_callback(on_frame_tick);

		this.notify["opacity"].connect(() => {
			this.sync_host_visible();
		});
		this.notify["visible"].connect(() => {
			this.sync_host_visible();
		});
		this.map.connect(() => {
			this.sync_host_visible();
		});
		this.unmap.connect(() => {
			this.sync_host_visible();
		});

		this.capture_settings.notify.connect(on_settings_notify);
		this.push_media_settings(false);
	}

	public signal void load_changed(LoadEvent load_event);

	/** Main-frame document HTTP response(status + headers as Soup.MessageHeaders). */
	public signal void main_document_response(
		uint status,
		Soup.MessageHeaders headers
	);

	/**
	 * WebKitGTK-shaped — a subresource load began.
	 *
	 * Connect to {@link WebResource.finished} / {@link WebResource.failed} on
	 * ''resource'' to track in-flight loads.
	 */
	public signal void resource_load_started(
		WebResource resource,
		URIRequest request
	);

	/** WebKitGTK-shaped — emitted when navigation fails or is cancelled. */
	public signal bool load_failed(
		LoadEvent load_event,
		string failing_uri,
		GLib.Error error
	);

	/** WebKitGTK-shaped — permission prompt; return true if handled. */
	public signal bool permission_request(PermissionRequest permission_request);

	/** WebKitGTK-shaped — permission-state query (API parity; host may never emit). */
	public signal bool query_permission_state(PermissionStateQuery query);

	protected override void size_allocate(int width, int height, int baseline) {
		base.size_allocate(width, height, baseline);
		if (!attached) {
			try_attach();
			return;
		}
		push_bounds();
	}

	~WebView() {
		if (attached) {
			wv2_host_set_permission_handler(null, null);
			wv2_host_set_script_message_handler(null, null);
			user_content_manager.unbind_host();
			wv2_host_set_resource_handlers(null, null, null, null);
			wv2_host_set_document_response_handler(null, null);
			wv2_host_set_event_handlers(null, null, null, null);
			wv2_host_destroy();
			attached = false;
		}
	}

	public bool can_go_back() {
		return attached && wv2_host_get_can_go_back();
	}

	public bool can_go_forward() {
		return attached && wv2_host_get_can_go_forward();
	}

	public unowned string get_uri() {
		if (attached && wv2_host_is_ready()) {
			var live = wv2_host_get_source();
			if (live.length > 0) {
				uri = live;
			}
		}
		return uri;
	}

	public unowned string get_title() {
		if (attached && wv2_host_is_ready()) {
			title = wv2_host_get_document_title();
		}
		return title;
	}

	public void load_uri(string uri) {
		this.uri = uri;
		pending_html = "";
		pending_uri = uri;
		try_navigate();
	}

	public void load_html(string content, string? base_uri = null) {
		var html = content;
		if (base_uri != null && base_uri.length > 0) {
			html = "<head><base href=\"%s\"></head>%s".printf(
				Markup.escape_text(base_uri),
				content
			);
		}
		uri = base_uri ?? "about:blank";
		/* Prefer NavigateToString — deferred data: URIs are unreliable with WebView2. */
		pending_uri = "";
		pending_html = html;
		try_navigate();
	}

	public void load_plain_text(string plain_text) {
		var escaped = Markup.escape_text(plain_text);
		load_html("<pre>%s</pre>".printf(escaped), null);
	}

	public void reload() {
		wv2_host_reload();
	}

	public void reload_bypass_cache() {
		/* WebView2 has no WebKit-style cache bypass; reload is the closest match. */
		wv2_host_reload();
	}

	public void stop_loading() {
		load_cancelled = true;
		wv2_host_stop();
		set_loading(false, 0.0);
	}

	public void go_back() {
		wv2_host_go_back();
	}

	public void go_forward() {
		wv2_host_go_forward();
	}

	public double get_zoom_level() {
		if (attached && wv2_host_is_ready()) {
			zoom_level = wv2_host_get_zoom_factor();
		}
		return zoom_level;
	}

	public void set_zoom_level(double zoom_level) {
		this.zoom_level = zoom_level;
		if (attached && wv2_host_is_ready()) {
			wv2_host_put_zoom_factor(zoom_level);
		}
	}

	public new WebViewSettings get_settings() {
		return capture_settings;
	}

	/** WebKitGTK-shaped — manager for script message handlers. */
	public unowned UserContentManager get_user_content_manager() {
		return user_content_manager;
	}

	/** WebKitGTK-shaped — page inspector (DevTools). */
	public unowned WebInspector get_inspector() {
		if (this.inspector == null) {
			this.inspector = new WebInspector(this);
		}
		return this.inspector;
	}

	internal void open_devtools_window() {
		if (!attached || !wv2_host_is_ready()) {
			return;
		}
		wv2_host_open_dev_tools_window();
	}

	/**
	 * Start a download of ''uri'' using the WebView cookie jar.
	 * Emits {@link NetworkSession.download_started} then {@link Download.decide_destination}.
	 */
	public Download download_uri(string uri) {
		var trimmed = uri.strip();
		var id = wv2_host_download_create(trimmed);
		if (id <= 0) {
			var failed = new Download(this.network_session, 0, trimmed, "download", "", -1);
			Idle.add(() => {
				failed.on_failed_message("download create failed");
				return false;
			});
			return failed;
		}
		var suggested = "download";
		try {
			var guri = GLib.Uri.parse(trimmed, GLib.UriFlags.NONE);
			var path = guri.get_path();
			if (path != null && path != "" && path != "/") {
				var leaf = GLib.Path.get_basename(path);
				if (leaf != null && leaf != "" && leaf != "/" && leaf != ".") {
					suggested = leaf;
				}
			}
		} catch (GLib.Error e) {
		}
		var dl = new Download(this.network_session, id, trimmed, suggested, "", -1);
		this.network_session.register_download(dl, id);
		this.network_session.emit_download_started(dl);
		return dl;
	}

	public async Gdk.Texture get_snapshot(
		SnapshotRegion region,
		SnapshotOptions options,
		GLib.Cancellable? cancellable = null
	) throws GLib.Error {
		/* WebView2 COM + message pump must run on the GTK/UI thread. */
		var full_document = region == SnapshotRegion.FULL_DOCUMENT;
		string? devtools_json = null;
		var capture_ok = wv2_capture_screenshot_sync(full_document, out devtools_json);
		var png_bytes = devtools_json_to_png_bytes(devtools_json);
		if (!capture_ok || png_bytes == null) {
			if (devtools_json != null) {
				GLib.warning(
					"get_snapshot: DevTools response(truncated): %s",
					devtools_json.substring(
						0,
						int.min(devtools_json.length, 200)
					)
				);
			}
			throw new GLib.IOError.FAILED("Screenshot capture failed");
		}
		return Gdk.Texture.from_bytes(new Bytes.take((owned) png_bytes));
	}

	public async JavaScriptResult evaluate_javascript(
		string script,
		ssize_t length = -1,
		string? world_name = null,
		string? source_uri = null,
		GLib.Cancellable? cancellable = null
	) throws GLib.Error {
		/* Same thread rule as get_snapshot — ExecuteScript is COM on the UI thread. */
		string? raw = null;
		var script_ok = wv2_execute_script_sync(script, out raw);
		if (!script_ok) {
			throw new GLib.IOError.FAILED("execute_script failed");
		}
		return new JavaScriptResult(raw ?? "null");
	}

	private static uint8[]? devtools_json_to_png_bytes(string? devtools_json)
	{
		if (devtools_json == null) {
			return null;
		}
		string[] markers = { "\"data\":\"", "\"data\": \"" };
		foreach (var marker in markers) {
			var start = devtools_json.index_of(marker);
			if (start < 0) {
				continue;
			}
			start += marker.length;
			var end = devtools_json.index_of_char('"', start);
			if (end < 0) {
				continue;
			}
			return Base64.decode(devtools_json.substring(start, end - start));
		}
		return null;
	}

	private Gtk.Window? toplevel_window() {
		return host.get_root() as Gtk.Window;
	}

	private void* toplevel_hwnd() {
		var native = host.get_native();
		if (native == null) {
			return null;
		}
		var surface = native.get_surface();
		if (surface == null) {
			return null;
		}
		return gdk_win32_surface_get_handle(surface);
	}

	private bool host_bounds(out int x, out int y, out int width, out int height) {
		return widget_bounds_xywh(host, out x, out y, out width, out height);
	}

	private void push_bounds() {
		if (!attached || parent_hwnd == null) {
			return;
		}
		int x;
		int y;
		int width;
		int height;
		if (!host_bounds(out x, out y, out width, out height)) {
			return;
		}
		if (!host_shown_on_screen) {
			/* Off-screen while GTK opacity is 0 — DevTools capture still needs IsVisible. */
			x = -30000;
			y = -30000;
		}
		wv2_host_set_bounds_xywh(x, y, width, height);
	}

	private void sync_host_visible() {
		if (!attached) {
			return;
		}
		host_shown_on_screen = this.get_mapped()
			&& this.get_visible()
			&& this.get_opacity() > 0.001;
		/* Keep IsVisible for DevTools capture; park off-screen when not shown. */
		wv2_host_put_is_visible(true);
		if (!host_shown_on_screen) {
			wv2_host_set_bounds_xywh(-30000, -30000, 1, 1);
			return;
		}
		push_bounds();
	}

	private void try_navigate() {
		if (!attached) {
			return;
		}
		if (pending_html.length > 0) {
			if (!wv2_host_is_ready()) {
				return;
			}
			/* Clear before navigate to avoid frame-tick re-entry storms. */
			var html = pending_html;
			pending_html = "";
			if (!wv2_host_navigate_to_string(html)) {
				warning("WebView2Gtk: NavigateToString failed");
			}
			return;
		}
		if (pending_uri.length == 0) {
			return;
		}
		if (wv2_host_navigate(pending_uri)) {
			pending_uri = "";
		}
	}

	private void try_attach() {
		if (attached) {
			return;
		}
		var window = toplevel_window();
		if (window == null) {
			return;
		}
		parent_hwnd = toplevel_hwnd();
		if (parent_hwnd == null) {
			return;
		}

		int x;
		int y;
		int width;
		int height;
		if (!host_bounds(out x, out y, out width, out height)) {
			return;
		}

		if (!wv2_host_create_with_xywh(parent_hwnd, x, y, width, height, null)) {
			warning("WebView2Gtk: create_with_xywh failed(runtime/loader missing?)");
			return;
		}
		attached = true;
		Win32Atspi.register_webview(this);
		this.push_media_settings(false);
		wv2_host_set_is_muted(this.muted);
		wv2_host_set_permission_handler(
			(void*) on_permission_decide_cb,
			this
		);
		wv2_host_set_document_response_handler(
			(void*) on_document_response_cb,
			this
		);
		wv2_host_set_resource_handlers(
			on_resource_started_cb,
			on_resource_finished_cb,
			on_resource_failed_cb,
			this
		);
		wv2_host_set_script_message_handler(
			(void*) on_script_message_cb,
			user_content_manager
		);
		user_content_manager.bind_host();
		wv2_host_set_event_handlers(
			(void*) on_navigation_starting_cb,
			(void*) on_navigation_completed_cb,
			(void*) on_document_title_changed_cb,
			this
		);
		this.sync_host_visible();
		try_navigate();
	}

	private bool on_frame_tick(Gtk.Widget widget, Gdk.FrameClock frame_clock) {
		if (!attached) {
			try_attach();
		} else {
			push_bounds();
			/* Host ready is async — retry pending HTML / URI once COM is up. */
			try_navigate();
		}
		return Source.CONTINUE;
	}

	private void on_host_map() {
		try_attach();
		Idle.add(() => {
			try_attach();
			push_bounds();
			return false;
		});
	}

	private void set_loading(bool loading, double progress) {
		if (this.is_loading == loading && (!loading || this.estimated_load_progress == progress)) {
			return;
		}
		this.is_loading = loading;
		this.estimated_load_progress = progress;
	}

	private void refresh_uri() {
		get_uri();
	}

	private void refresh_title() {
		get_title();
	}

	private void on_navigation_starting() {
		set_loading(true, 0.1);
		load_changed(LoadEvent.STARTED);
	}

	private void on_navigation_completed(bool success) {
		if (!success) {
			var fail_uri = pending_uri;
			if (fail_uri.length == 0) {
				fail_uri = this.uri;
			}
			GLib.Error err;
			if (load_cancelled) {
				load_cancelled = false;
				err = new NetworkError.CANCELLED("Load cancelled");
			} else {
				err = new NetworkError.FAILED("Navigation failed");
			}
			load_failed(LoadEvent.STARTED, fail_uri, err);
			set_loading(false, 0.0);
			return;
		}
		load_cancelled = false;
		refresh_uri();
		refresh_title();
		set_loading(false, 1.0);
		load_changed(LoadEvent.FINISHED);
	}

	private void on_document_title_changed() {
		refresh_title();
	}

	private void on_document_response(uint status, Soup.MessageHeaders headers) {
		main_document_response(status, headers);
	}

	private void on_resource_started(int id, string uri) {
		var resource = new WebResource(uri);
		var request = new URIRequest(uri);
		resources[id] = resource;
		resource_load_started(resource, request);
	}

	private void on_resource_finished(int id) {
		WebResource resource;
		if (resources.unset(id, out resource)) {
			resource.emit_finished();
		}
	}

	private void on_resource_failed(int id, string message) {
		WebResource resource;
		if (resources.unset(id, out resource)) {
			resource.emit_failed(new NetworkError.FAILED("%s", message));
		}
	}

	private void on_settings_notify(ParamSpec pspec) {
		switch (pspec.name) {
		case "enable-media-stream":
		case "enable-webrtc":
			this.push_media_settings(false);
			break;
		case "media-playback-requires-user-gesture":
			this.push_media_settings(true);
			break;
		}
	}

	private void push_media_settings(bool from_gesture_prop) {
		var s = this.capture_settings;
		wv2_host_set_media_flags(s.enable_media_stream, s.enable_webrtc);
		if (s.media_playback_requires_user_gesture) {
			if (from_gesture_prop && attached && wv2_host_is_ready()) {
				warning(
					"WebView2Gtk: media_playback_requires_user_gesture after env create — stored only; restart required for Chromium autoplay flag"
				);
			}
			wv2_host_set_autoplay_policy((int) AutoplayPolicy.DENY);
		}
	}

	[CCode(has_target = false)]
	private static int on_permission_decide_cb(
		int permission_kind,
		int* allow_out,
		void* user_data
	) {
		var view = (WebView) user_data;
		var req = new SimplePermissionRequest();
		if (view.permission_request(req) && req.decided) {
			if (allow_out != null) {
				*allow_out = req.allowed ? 1 : 0;
			}
			return 1;
		}
		/* Host applies media_stream / webrtc deny for camera/mic when undecided. */
		(void) permission_kind;
		return 0;
	}

	[CCode(has_target = false)]
	private static void on_document_response_cb(
		void* user_data,
		int status,
		[CCode(array_length = false)] string[] header_names,
		[CCode(array_length = false)] string[] header_values,
		size_t header_count
	) {
		var headers = new Soup.MessageHeaders(Soup.MessageHeadersType.RESPONSE);
		for (var i = 0; i < (int) header_count; i++) {
			headers.append(header_names[i], header_values[i]);
		}
		((WebView) user_data).on_document_response((uint) status, headers);
	}

	[CCode(has_target = false)]
	private static void on_resource_started_cb(int id, string uri, void* user_data) {
		((WebView) user_data).on_resource_started(id, uri);
	}

	[CCode(has_target = false)]
	private static void on_resource_finished_cb(int id, void* user_data) {
		((WebView) user_data).on_resource_finished(id);
	}

	[CCode(has_target = false)]
	private static void on_resource_failed_cb(int id, string message, void* user_data) {
		((WebView) user_data).on_resource_failed(id, message);
	}

	[CCode(has_target = false)]
	private static void on_navigation_starting_cb(void* user_data) {
		((WebView) user_data).on_navigation_starting();
	}

	[CCode(has_target = false)]
	private static void on_navigation_completed_cb(void* user_data, bool success) {
		((WebView) user_data).on_navigation_completed(success);
	}

	[CCode(has_target = false)]
	private static void on_document_title_changed_cb(void* user_data) {
		((WebView) user_data).on_document_title_changed();
	}

	[CCode(has_target = false)]
	private static void on_script_message_cb(
		void* user_data,
		string handler_name,
		string message_json
	) {
		((UserContentManager) user_data).emit_script_message(handler_name, message_json);
	}
}

}
