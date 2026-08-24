/* Trivial GTK 4 browser — Win32Atspi smoke(a11y is not on WebView). */

using Gtk;
using WebView2Gtk;

private WebView web;
private Gtk.Entry url_entry;

private void sync_url_entry() {
	if (web.ready) {
		var u = web.get_uri();
		if (u.length > 0) {
			url_entry.text = u;
		}
	}
}

private void show_text_window(Gtk.Window parent, string title, string text) {
	var win = new Gtk.Window() {
		title = title,
		transient_for = parent,
		modal = true,
		default_width = 780,
		default_height = 520
	};
	var scrolled = new Gtk.ScrolledWindow();
	var view = new Gtk.TextView() {
		editable = false,
		monospace = true,
		wrap_mode = Gtk.WrapMode.CHAR
	};
	view.buffer.text = text;
	scrolled.set_child(view);
	win.set_child(scrolled);
	win.present();
}

private delegate bool AccVisit(Win32Atspi.Accessible acc);

private void foreach_accessible(Win32Atspi.Accessible acc, AccVisit visit) {
	if (!visit(acc)) {
		return;
	}
	var n = acc.get_child_count();
	for (var i = 0; i < n; i++) {
		foreach_accessible(acc.get_child_at_index(i), visit);
	}
}

/* Prefer a SERP result link — not skip-to-content / chrome / # anchors. */
private bool is_result_link(Win32Atspi.Accessible acc) {
	if (acc.get_role_name() != "link" || acc.get_n_actions() == 0) {
		return false;
	}
	var name = acc.get_name();
	var href = "";
	var hl = acc.get_hyperlink();
	if (hl != null && hl.get_n_anchors() > 0) {
		href = hl.get_uri(0);
	}
	if (name.length == 0 || href.length == 0) {
		return false;
	}
	if (!href.has_prefix("http://") && !href.has_prefix("https://")) {
		return false;
	}
	if (href.contains("#") && href.index_of("#") == href.length - 1) {
		return false;
	}
	string[] skip_names = {
		"跳至主內容", "無障礙功能說明", "Google 首頁", "登入",
		"Change to English", "繼續使用", "語言設定", "翻譯這個網頁",
		"轉為繁體網頁", "說明", "發送意見", "私隱權政策", "條款",
		"下一頁", "Page "
	};
	foreach (var s in skip_names) {
		if (name.has_prefix(s) || name == s) {
			return false;
		}
	}
	if (href.has_prefix("https://www.google.com/search?")
	    || href.has_prefix("https://accounts.google.com/")
	    || href.has_prefix("https://translate.google.com/")
	    || href.has_prefix("https://support.google.com/")) {
		return false;
	}
	if (href.contains("google.com/url?") && href.contains("sa=i")) {
		return false;
	}
	return name.length >= 12;
}

private void invoke_first_hyperlink(Gtk.Window parent) {
	Win32Atspi.init();
	var desktop = Win32Atspi.get_desktop(0);
	Win32Atspi.Accessible? target = null;
	foreach_accessible(desktop, (acc) => {
		if (is_result_link(acc)) {
			target = acc;
			return false;
		}
		return true;
	});
	if (target == null) {
		show_text_window(parent, "Win32Atspi invoke",
			"no result link found\n(skip links / Google chrome ignored)");
		return;
	}

	var before = web.get_uri();
	var name = target.get_name();
	var href = target.get_hyperlink().get_uri(0);
	var ok = target.do_action(0);
	parent.title = "invoking %s…".printf(name);

	Timeout.add(1200, () => {
		sync_url_entry();
		var after = web.get_uri();
		var moved = before != after;
		show_text_window(parent, "Win32Atspi invoke",
			"""do_action → %s
name=%s
href=%s
uri before=%s
uri after =%s
navigated=%s
""".printf(ok ? "OK" : "FAIL", name, href, before, after, moved ? "YES" : "no"));
		return Source.REMOVE;
	});
}

private void fill_search_combobox(Gtk.Window parent) {
	Win32Atspi.init();
	var desktop = Win32Atspi.get_desktop(0);
	Win32Atspi.Accessible? target = null;
	foreach_accessible(desktop, (acc) => {
		if (acc.get_role_name() == "combo box" && acc.get_name().length > 0) {
			target = acc;
			return false;
		}
		return true;
	});
	if (target == null) {
		foreach_accessible(desktop, (acc) => {
			if (acc.get_role_name() == "entry" || acc.get_role_name() == "combo box") {
				target = acc;
				return false;
			}
			return true;
		});
	}
	if (target == null) {
		show_text_window(parent, "Win32Atspi fill",
			"no combo box / entry found");
		return;
	}

	var before = target.get_text_iface().get_text(0, -1);
	var want = "webview2 accessibility";
	var name = target.get_name();
	var role = target.get_role_name();
	var ok = target.set_text_contents(want);

	Timeout.add(400, () => {
		Win32Atspi.init();
		var desk2 = Win32Atspi.get_desktop(0);
		string after = "(not found after rebuild)";
		foreach_accessible(desk2, (acc) => {
			if (acc.get_role_name() == role && acc.get_name() == name) {
				after = acc.get_text_iface().get_text(0, -1);
				return false;
			}
			return true;
		});
		show_text_window(parent, "Win32Atspi fill",
			"""set_text_contents → %s
role=%s name=%s
before=%s
want  =%s
after =%s
matched=%s
""".printf(ok ? "OK" : "FAIL", role, name, before, want, after,
				after == want ? "YES" : "no"));
		return Source.REMOVE;
	});
}

private void show_atspi_tree(Gtk.Window parent) {
	Win32Atspi.init();
	var sb = new StringBuilder();
	var desktop = Win32Atspi.get_desktop(0);
	sb.append_printf("desktop children=%d\n", desktop.get_child_count());
	for (var i = 0; i < desktop.get_child_count(); i++) {
		var app = desktop.get_child_at_index(i);
		sb.append_printf("app[%d] pid=%u role=%s name=%s children=%d\n",
			i, app.get_process_id(), app.get_role_name(), app.get_name(),
			app.get_child_count());
		dump_atspi(sb, app, 1, 0);
	}
	show_text_window(parent, "Win32Atspi tree", sb.str);
}

private void dump_atspi(StringBuilder sb, Win32Atspi.Accessible acc, int depth, int max_nodes) {
	if (max_nodes > 80) {
		return;
	}
	var pad = string.nfill(depth * 2, ' ');
	sb.append_printf("%s%s name=%s actions=%d\n",
		pad, acc.get_role_name(), acc.get_name(), acc.get_n_actions());
	var n = acc.get_child_count();
	var limit = n < 12 ? n : 12;
	for (var j = 0; j < limit; j++) {
		dump_atspi(sb, acc.get_child_at_index(j), depth + 1, max_nodes + 1);
	}
	if (n > limit) {
		sb.append_printf("%s… %d more children\n", string.nfill((depth + 1) * 2, ' '), n - limit);
	}
}

private void start_sample_download(Gtk.Window parent) {
	var uri = "https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf";
	web.download_uri(uri);
}

public static int main(string[] args) {
	var start = "https://example.com/";
	if (args.length > 1) {
		start = args[1];
	}

	var app = new Gtk.Application("com.webview2gtk.browser", ApplicationFlags.FLAGS_NONE);
	app.activate.connect(() => {
		var window = new Gtk.ApplicationWindow(app);
		window.set_title("webview2-gtk browser");
		window.set_default_size(960, 640);

		var root = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
		var bar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 4);
		bar.set_margin_start(4);
		bar.set_margin_end(4);
		bar.set_margin_top(4);
		bar.set_margin_bottom(4);

		var back_btn = new Gtk.Button.from_icon_name("go-previous-symbolic");
		var fwd_btn = new Gtk.Button.from_icon_name("go-next-symbolic");
		var reload_btn = new Gtk.Button.from_icon_name("view-refresh-symbolic");
		url_entry = new Gtk.Entry() { text = start, hexpand = true };
		var go_btn = new Gtk.Button.with_label("Go");
		var inv_btn = new Gtk.Button.with_label("Invoke link");
		var fill_btn = new Gtk.Button.with_label("Fill search");
		var atspi_btn = new Gtk.Button.with_label("Win32Atspi");
		var dl_btn = new Gtk.Button.with_label("Download");

		web = new WebView();
		web.load_uri(start);
		web.set_hexpand(true);
		web.set_vexpand(true);

		var dl_dir = Environment.get_user_special_dir(UserDirectory.DOWNLOAD);
		if (dl_dir == null || dl_dir == "") {
			dl_dir = Environment.get_tmp_dir();
		}
		web.network_session.download_started.connect((download) => {
			download.decide_destination.connect((suggested) => {
				var name = suggested != null && suggested != "" ? suggested : "download";
				var dest = Path.build_filename(dl_dir, name);
				print("download decide_destination → %s\n", dest);
				download.set_allow_overwrite(true);
				download.set_destination(dest);
				return true;
			});
			download.received_data.connect((len) => {
				print("download progress %llu bytes(+%llu)\n",
					download.get_received_data_length(), len);
			});
			download.finished.connect(() => {
				print("download finished\n");
				show_text_window(window, "Download", "finished");
			});
			download.failed.connect((err) => {
				print("download failed: %s\n", err.message);
				show_text_window(window, "Download failed", err.message);
			});
		});

		back_btn.clicked.connect(() => { web.go_back(); sync_url_entry(); });
		fwd_btn.clicked.connect(() => { web.go_forward(); sync_url_entry(); });
		reload_btn.clicked.connect(() => { web.reload(); });
		go_btn.clicked.connect(() => { web.load_uri(url_entry.text); });
		url_entry.activate.connect(() => { web.load_uri(url_entry.text); });
		inv_btn.clicked.connect(() => { invoke_first_hyperlink(window); });
		fill_btn.clicked.connect(() => { fill_search_combobox(window); });
		atspi_btn.clicked.connect(() => { show_atspi_tree(window); });
		dl_btn.clicked.connect(() => { start_sample_download(window); });

		bar.append(back_btn);
		bar.append(fwd_btn);
		bar.append(reload_btn);
		bar.append(url_entry);
		bar.append(go_btn);
		bar.append(inv_btn);
		bar.append(fill_btn);
		bar.append(atspi_btn);
		bar.append(dl_btn);

		root.append(bar);
		root.append(web);
		window.set_child(root);
		window.present();
	});
	return app.run(new string[] { args[0] });
}
