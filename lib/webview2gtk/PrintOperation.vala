namespace WebView2Gtk {

public class PrintOperation : Object {
	private Gtk.PrintSettings? _print_settings;

	public signal void finished ();
	public signal void failed (GLib.Error error);

	public PrintOperation (WebView web_view) {
	}

	public void set_page_setup (Gtk.PageSetup page_setup) {
	}

	public void set_print_settings (Gtk.PrintSettings print_settings) {
		_print_settings = print_settings;
	}

	public void print () {
		var uri = _print_settings?.get (Gtk.PRINT_SETTINGS_OUTPUT_URI) ?? "";
		string path = uri;
		try {
			if (path.has_prefix ("file://")) {
				path = Filename.from_uri (path);
			}
		} catch (GLib.Error e) {
			failed (e);
			return;
		}
		var output_path = path;
		new Thread<void> ("wv2-print-pdf", () => {
			var ok = wv2_print_to_pdf_sync (output_path);
			Idle.add (() => {
				if (ok) {
					finished ();
				} else {
					failed (new GLib.IOError.FAILED ("PrintToPdf failed"));
				}
				return false;
			});
		});
	}
}

}
