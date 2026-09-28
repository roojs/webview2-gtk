/* Print a page of installed TrueType text to PDF.
 *
 * Variable webfonts (Roboto Flex) become PDF Type3. Skia decides that from
 * the font file; print settings have no switch for it. This sample uses
 * Arial and Segoe UI, which embed as CID TrueType.
 *
 *   webview2gtk-print.exe --output PATH
 *
 * Page setup is A4 portrait with 5 mm margins, scale 100.
 */

using Gtk;
using WebView2Gtk;

private int smoke_status = 1;
private bool smoke_done = false;
private string print_output_path;
private Gtk.ApplicationWindow? window = null;

private const string PRINT_HTML = """
<!DOCTYPE html>
<html><head>
<meta charset="utf-8">
<style>
  body { margin: 24px; color: #111; }
  h1 { font-family: Arial, sans-serif; font-size: 22px; font-weight: 700; margin: 0 0 12px; }
  .body { font-family: Arial, sans-serif; font-size: 16px; line-height: 1.45; }
  .ui { font-family: "Segoe UI", sans-serif; font-size: 16px; line-height: 1.45; }
</style>
</head><body>
<h1>Print sample</h1>
<p class="body">Static Arial: The quick brown fox jumps over the lazy dog. <b>Bold stays a TrueType face.</b></p>
<p class="ui">Segoe UI: Pack my box with five dozen liquor jugs. Installed static faces stay sharp when the PDF is opened in the Windows viewer.</p>
</body></html>
""";

private void finish_smoke(bool ok, string why) {
	if (smoke_done) {
		return;
	}
	smoke_done = true;
	if (ok) {
		print("TEST_PASS\n");
		smoke_status = 0;
	} else {
		print("TEST_FAIL (%s)\n", why);
		smoke_status = 1;
	}
	if (window != null) {
		window.close();
	}
}

private void start_print(WebView view) {
	var page_setup = new Gtk.PageSetup();
	page_setup.set_orientation(Gtk.PageOrientation.PORTRAIT);
	page_setup.set_paper_size(new Gtk.PaperSize(Gtk.PAPER_NAME_A4));
	page_setup.set_top_margin(5.0, Gtk.Unit.MM);
	page_setup.set_bottom_margin(5.0, Gtk.Unit.MM);
	page_setup.set_left_margin(5.0, Gtk.Unit.MM);
	page_setup.set_right_margin(5.0, Gtk.Unit.MM);

	var settings = new Gtk.PrintSettings();
	settings.set_printer("Print to File");
	settings.set("output-file-format", "pdf");
	settings.set("output-uri", print_output_path);
	settings.set_scale(100.0);
	settings.set_print_pages(Gtk.PrintPages.ALL);

	print("print output=%s paper=A4 margins=5mm scale=100\n", print_output_path);
	var op = new WebView2Gtk.PrintOperation(view);
	op.finished.connect(() => {
		print("print finished %s\n", print_output_path);
		finish_smoke(true, "");
	});
	op.failed.connect((err) => {
		print("print failed: %s\n", err.message);
		finish_smoke(false, err.message);
	});
	op.set_page_setup(page_setup);
	op.set_print_settings(settings);
	op.print();
}

private void run_print(WebView view) {
	view.load_changed.connect((load_event) => {
		if (load_event != LoadEvent.FINISHED || smoke_done) {
			return;
		}
		print("print html FINISHED\n");
		Timeout.add(300, () => {
			if (!smoke_done) {
				start_print(view);
			}
			return Source.REMOVE;
		});
	});
	view.load_failed.connect((load_event, failing_uri, error) => {
		print("print load_failed %s: %s\n", failing_uri, error.message);
		finish_smoke(false, "load_failed");
		return true;
	});
	view.load_html(PRINT_HTML, "https://example.test/");
	Timeout.add(30000, () => {
		if (!smoke_done) {
			print("print timeout\n");
			finish_smoke(false, "timeout");
		}
		return Source.REMOVE;
	});
}

public static int main(string[] args) {
	string[] gtk_args = {};
	for (var i = 0; i < args.length; i++) {
		if (i == 0) {
			gtk_args += args[i];
			continue;
		}
		if (args[i] == "--output" && i + 1 < args.length) {
			i++;
			print_output_path = args[i];
			continue;
		}
		gtk_args += args[i];
	}
	if (print_output_path == null || print_output_path == "") {
		print_output_path = Path.build_filename(
			Environment.get_tmp_dir(),
			"webview2gtk-print-sample.pdf"
		);
	}

	var app = new Gtk.Application("com.webview2gtk.print", ApplicationFlags.FLAGS_NONE);
	app.activate.connect(() => {
		window = new Gtk.ApplicationWindow(app);
		window.set_title("webview2-gtk print");
		window.set_default_size(640, 480);

		var web = new WebView();
		web.set_hexpand(true);
		web.set_vexpand(true);
		run_print(web);
		window.set_child(web);
		window.present();
	});
	app.run(gtk_args);
	return smoke_status;
}
