namespace WebView2Gtk {

public class PrintOperation : Object {
	private Gtk.PrintSettings? print_settings;

	public signal void finished ();
	public signal void failed (GLib.Error error);

	public PrintOperation (WebView web_view) {
	}

	public void set_page_setup (Gtk.PageSetup page_setup) {
	}

	public void set_print_settings (Gtk.PrintSettings print_settings) {
		this.print_settings = print_settings;
	}

	public void print () {
		var output_path = this.output_path_from_settings ();
		if (output_path == "") {
			failed (new GLib.IOError.FAILED ("Missing PDF output path"));
			return;
		}
		/* PrintToPdf COM on GTK/UI thread; defer signals so async capture does not resume inside sync_await. */
		GLib.Idle.add (() => {
			var ok = wv2_print_to_pdf_sync (output_path);
			GLib.Idle.add (() => {
				if (ok) {
					finished ();
				} else {
					failed (new GLib.IOError.FAILED ("PrintToPdf failed"));
				}
				return Source.REMOVE;
			});
			return Source.REMOVE;
		});
	}

	private string output_path_from_settings () {
		var uri = print_settings?.get (Gtk.PRINT_SETTINGS_OUTPUT_URI) ?? "";
		if (uri == "") {
			return "";
		}
		if (uri.has_prefix ("file://")) {
			try {
				return Filename.from_uri (uri);
			} catch (GLib.Error e) {
				return "";
			}
		}
		return uri;
	}
}

}
