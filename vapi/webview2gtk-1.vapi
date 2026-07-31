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

	public errordomain NetworkError {
		FAILED,
		TRANSPORT,
		UNKNOWN_PROTOCOL,
		CANCELLED,
		FILE_DOES_NOT_EXIST;
	}

	public class NetworkProxySettings : GLib.Object {
		public NetworkProxySettings (string default_proxy_uri, string? http_proxy_uri = null);
	}

	public class CookieManager : GLib.Object {
		public void set_accept_policy (CookieAcceptPolicy policy);
		public void set_persistent_storage (string filename, CookiePersistentStorage storage);
		public async GLib.List<Soup.Cookie> get_cookies (
			string uri,
			GLib.Cancellable? cancellable = null
		) throws GLib.Error;
		public async bool add_cookie (
			Soup.Cookie cookie,
			GLib.Cancellable? cancellable = null
		) throws GLib.Error;
	}

	public class NetworkSession : GLib.Object {
		public signal void download_started (Download download);
		public CookieManager get_cookie_manager ();
		public void set_proxy_settings (NetworkProxyMode mode, NetworkProxySettings? settings);
		public void set_tls_errors_policy (TLSErrorsPolicy policy);
	}

	public class URIRequest : GLib.Object {
		public string uri { get; }
		public URIRequest (string uri);
	}

	public class WebResource : GLib.Object {
		public string uri { get; }
		public unowned string get_uri ();
		public signal void finished ();
		public signal void failed (GLib.Error error);
	}

	public class Download : GLib.Object {
		public URIRequest get_request ();
		public string get_uri ();
		public string? get_mime_type ();
		public int64 get_estimated_content_length ();
		public uint64 get_received_data_length ();
		public signal bool decide_destination (string? suggested_filename);
		public signal void received_data (uint64 data_length);
		public signal void finished ();
		public signal void failed (GLib.Error error);
		public void set_allow_overwrite (bool allow);
		public void set_destination (string destination_uri_or_path);
		public void cancel ();
	}

	public class WebViewSettings : GLib.Object {
		public string user_agent { get; set; }
		public HardwareAccelerationPolicy hardware_acceleration_policy { get; set; }
		public bool enable_javascript { get; set; }
	}

	public class JavaScriptResult : GLib.Object {
		public string to_json (int indent = 0);
		public string to_string ();
		public int32 to_int32 ();
	}

	public class UserContentManager : GLib.Object {
		public UserContentManager ();
		[Signal (detailed = true)]
		public signal void script_message_received (JavaScriptResult values);
		public bool register_script_message_handler (string name, string? world_name);
		public void unregister_script_message_handler (string name, string? world_name);
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
		public signal void main_document_response (
			uint status,
			Soup.MessageHeaders headers
		);
		public signal void resource_load_started (
			WebResource resource,
			URIRequest request
		);
		public signal bool load_failed (LoadEvent load_event, string failing_uri, GLib.Error error);
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
		public unowned UserContentManager get_user_content_manager ();
		public Download download_uri (string uri);
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

/* Win32 AT-SPI facade — see docs/a11y.md */
namespace Win32Atspi {
	public enum CoordType { SCREEN, WINDOW, PARENT }
	public enum ScrollType { TOP_EDGE, BOTTOM_EDGE, LEFT_EDGE, RIGHT_EDGE, ANYWHERE }
	public enum KeySynthType { PRESS, RELEASE, PRESSRELEASE, STRING }

	public class ComponentExtents : GLib.Object {
		public int x { get; set; }
		public int y { get; set; }
		public int width { get; set; }
		public int height { get; set; }
	}

	public class Text : GLib.Object {
		public int get_character_count ();
		public string get_text (int start_offset, int end_offset);
	}

	public class Hyperlink : GLib.Object {
		public int get_n_anchors ();
		public string get_uri (int i);
	}

	public class Accessible : GLib.Object {
		public string get_name ();
		public string get_role_name ();
		public string get_description ();
		public uint get_process_id ();
		public int get_child_count ();
		public Accessible get_child_at_index (int index);
		public GLib.HashTable<string, string> get_attributes ();
		public GLib.Array<string> get_interfaces ();
		public int get_n_actions ();
		public string get_action_name (int index);
		public bool do_action (int index);
		public bool grab_focus ();
		public bool set_text_contents (string text);
		public ComponentExtents get_extents (CoordType coord_type);
		public void scroll_to (ScrollType type) throws GLib.Error;
		public Text get_text_iface ();
		public Hyperlink? get_hyperlink ();
	}

	public static void init ();
	public static Accessible get_desktop (int index);
	public static void register_webview (WebView2Gtk.WebView web);
	public static void generate_keyboard_event (long keyval, string? keystring, KeySynthType synth);
}
