namespace WebView2Gtk {

public class PrintOperation : Object {
	private weak WebView? web_view;
	private Gtk.PageSetup? page_setup;
	private Gtk.PrintSettings? print_settings;

	public signal void finished();
	public signal void failed(GLib.Error error);

	public PrintOperation(WebView web_view) {
		this.web_view = web_view;
	}

	public void set_page_setup(Gtk.PageSetup page_setup) {
		this.page_setup = page_setup;
	}

	public void set_print_settings(Gtk.PrintSettings print_settings) {
		this.print_settings = print_settings;
	}

	public void print() {
		var output_path = this.output_path_from_settings();
		if (output_path == "") {
			failed(new GLib.IOError.FAILED("Missing PDF output path"));
			return;
		}
		var host = this.web_view != null ? this.web_view.get_host_handle() : null;
		if (host == null) {
			failed(new GLib.IOError.FAILED("WebView host not ready"));
			return;
		}
		var page_width = 0.0;
		var page_height = 0.0;
		var margin_top = 0.0;
		var margin_bottom = 0.0;
		var margin_left = 0.0;
		var margin_right = 0.0;
		var landscape = 0;
		if (page_setup != null) {
			page_width = page_setup.get_paper_width(Gtk.Unit.INCH);
			page_height = page_setup.get_paper_height(Gtk.Unit.INCH);
			margin_top = page_setup.get_top_margin(Gtk.Unit.INCH);
			margin_bottom = page_setup.get_bottom_margin(Gtk.Unit.INCH);
			margin_left = page_setup.get_left_margin(Gtk.Unit.INCH);
			margin_right = page_setup.get_right_margin(Gtk.Unit.INCH);
			var orientation = page_setup.get_orientation();
			landscape = (orientation == Gtk.PageOrientation.LANDSCAPE
				|| orientation == Gtk.PageOrientation.REVERSE_LANDSCAPE) ? 1 : 0;
		}
		var scale_factor = scale_factor_from_settings();
		/* PrintToPdf COM on GTK/UI thread; defer signals so async capture does not resume inside sync_await. */
		GLib.Idle.add(() => {
			var ok = wv2_print_to_pdf_sync(
				host,
				output_path,
				page_width,
				page_height,
				margin_top,
				margin_bottom,
				margin_left,
				margin_right,
				landscape,
				scale_factor
			);
			GLib.Idle.add(() => {
				if (ok) {
					finished();
				} else {
					failed(new GLib.IOError.FAILED("PrintToPdf failed"));
				}
				return Source.REMOVE;
			});
			return Source.REMOVE;
		});
	}

	private double scale_factor_from_settings() {
		var percent = print_settings != null ? print_settings.get_scale() : 100.0;
		var factor = percent / 100.0;
		if (factor < 0.1) {
			return 0.1;
		}
		if (factor > 2.0) {
			return 2.0;
		}
		return factor;
	}

	private string output_path_from_settings() {
		var uri = print_settings?.get(Gtk.PRINT_SETTINGS_OUTPUT_URI) ?? "";
		if (uri == "") {
			return "";
		}
		if (uri.has_prefix("file://")) {
			try {
				return Filename.from_uri(uri);
			} catch (GLib.Error e) {
				return "";
			}
		}
		return uri;
	}
}

}
