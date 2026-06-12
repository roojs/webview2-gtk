/* webview2gtk-1.vapi — WebKitGTK 6–aligned WebView2Gtk API (Windows). */

namespace WebView2Gtk {
	public enum LoadEvent {
		STARTED,
		REDIRECTED,
		COMMITTED,
		FINISHED
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
	}
}
