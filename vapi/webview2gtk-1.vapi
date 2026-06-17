/* webview2gtk-1.vapi — GTK WebView2 widget + capture API (WebKitGTK-shaped names). */

namespace WebView2Gtk {
	public enum LoadEvent {
		STARTED,
		REDIRECTED,
		COMMITTED,
		FINISHED
	}

	public enum SnapshotRegion {
		VISIBLE,
		FULL_DOCUMENT
	}

	public enum SnapshotOptions {
		NONE
	}

	public enum NetworkProxyMode {
		DEFAULT,
		CUSTOM,
		NONE
	}

	public enum TLSErrorsPolicy {
		IGNORE,
		FAIL
	}

	public enum HardwareAccelerationPolicy {
		ON_DEMAND,
		ALWAYS,
		NEVER
	}

	public enum CookieAcceptPolicy {
		ALWAYS,
		NEVER,
		NO_THIRD_PARTY
	}

	public enum CookiePersistentStorage {
		TEXT,
		SQLITE
	}

	public class NetworkProxySettings : GLib.Object {
		public NetworkProxySettings (string default_proxy_uri, string? http_proxy_uri = null);
	}

	public class CookieManager : GLib.Object {
		public void set_accept_policy (CookieAcceptPolicy policy);
		public void set_persistent_storage (string filename, CookiePersistentStorage storage);
	}

	public class NetworkSession : GLib.Object {
		public CookieManager get_cookie_manager ();
		public void set_proxy_settings (NetworkProxyMode mode, NetworkProxySettings? settings);
		public void set_tls_errors_policy (TLSErrorsPolicy policy);
	}

	public class WebViewSettings : GLib.Object {
		public string user_agent { get; set; }
		public HardwareAccelerationPolicy hardware_acceleration_policy { get; set; }
		public bool enable_javascript { get; set; }
	}

	public class JavaScriptResult : GLib.Object {
		public string to_json (int indent = 0);
		public int32 to_int32 ();
	}

	public class PrintOperation : GLib.Object {
		public PrintOperation (WebView web_view);
		public signal void finished ();
		public signal void failed (GLib.Error error);
		public void set_page_setup (Gtk.PageSetup page_setup);
		public void set_print_settings (Gtk.PrintSettings print_settings);
		public void print ();
	}

	[CCode (cheader_filename = "webview2gtk.h")]
	public class WebView : Gtk.Box {
		public WebView ();
		public signal void load_changed (LoadEvent load_event);
		public bool can_go_back ();
		public bool can_go_forward ();
		public unowned string get_uri ();
		public unowned string get_title ();
		public void load_uri (string uri);
		public void load_html (string content, string? base_uri = null);
		public void load_plain_text (string plain_text);
		public void reload ();
		public void reload_bypass_cache ();
		public void stop_loading ();
		public void go_back ();
		public void go_forward ();
		public double get_zoom_level ();
		public void set_zoom_level (double zoom_level);
		protected override void size_allocate (int width, int height, int baseline);
		public bool is_loading { get; }
		public double estimated_load_progress { get; }
		public bool ready { get; }
		public new WebViewSettings get_settings ();
		public NetworkSession get_network_session ();
		public async Gdk.Texture get_snapshot (
			SnapshotRegion region,
			SnapshotOptions options,
			GLib.Cancellable? cancellable = null
		) throws GLib.Error;
		public async JavaScriptResult evaluate_javascript (
			string script,
			ssize_t length = -1,
			string? world_name = null,
			string? source_uri = null,
			GLib.Cancellable? cancellable = null
		) throws GLib.Error;
	}
}
