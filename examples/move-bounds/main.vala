/* Repro: a bar opens above two WebViews. One changes height, the other
 * only moves. The second page used to stay at the old screen position
 * and paint over the bar.
 *
 *   webview2gtk-move-bounds.exe
 *   webview2gtk-move-bounds.exe --smoke
 *
 * --smoke waits until both native host windows match the widgets, opens
 * the bar, and requires the fixed-height host to follow. See
 * docs/bugs/2026-11-09-webview-size-allocate-skipped.md
 */

using Gtk;
using WebView2Gtk;

private const int BAR_HEIGHT = 80;
private const int STABLE_HEIGHT = 240;
private const int SLACK = 2;
private const int MOVE_MIN = 40;

private bool smoke = false;
private int smoke_status = 1;
private bool smoke_done = false;
private int polls = 0;
private bool have_sample = false;
private bool bar_opened = false;
private ClientRect sample_stable;
private ClientRect sample_growing;
private ClientRect open_stable;
private ClientRect open_growing;

private Gtk.ApplicationWindow? window = null;
private Gtk.Box? bar = null;
private WebView? growing = null;
private WebView? stable = null;
private bool growing_finished = false;
private bool stable_finished = false;

[CCode (cheader_filename = "gdk/win32/gdkwin32.h", cname = "gdk_win32_surface_get_handle")]
extern void* gdk_win32_surface_get_handle (Gdk.Surface surface);

[CCode (cname = "RECT", cheader_filename = "windows.h", has_type_id = false)]
private struct NativeRect {
	public int left;
	public int top;
	public int right;
	public int bottom;
}

[CCode (cname = "FindWindowExA", cheader_filename = "windows.h")]
extern void* find_window_ex (void* parent, void* child_after, string class_name, void* window_name);

[CCode (cname = "GetWindowRect", cheader_filename = "windows.h")]
extern bool get_window_rect (void* hwnd, out NativeRect rect);

[CCode (cname = "MapWindowPoints", cheader_filename = "windows.h")]
extern int map_window_points (void* from, void* to, ref NativeRect rect, uint points);

private struct ClientRect {
	public int x;
	public int y;
	public int w;
	public int h;
}

private int iround (double v) {
	return (int) (v >= 0 ? v + 0.5 : v - 0.5);
}

private int abs_delta (int a, int b) {
	return a > b ? a - b : b - a;
}

/* Same mapping as webview2gtk_widget_bounds: root bounds plus the
 * native surface transform, in HWND client pixels. */
private bool widget_client_bounds (Gtk.Widget widget, out ClientRect rect) {
	rect = ClientRect ();
	var root = widget.get_root ();
	if (root == null || !(root is Gtk.Native)) {
		return false;
	}
	Graphene.Rect bounds;
	if (!widget.compute_bounds (root, out bounds)) {
		return false;
	}
	double surf_x, surf_y;
	((Gtk.Native) root).get_surface_transform (out surf_x, out surf_y);
	var surface = ((Gtk.Native) root).get_surface ();
	int scale = surface != null ? surface.get_scale_factor () : 1;
	rect.x = iround ((bounds.origin.x + surf_x) * scale);
	rect.y = iround ((bounds.origin.y + surf_y) * scale);
	rect.w = iround (bounds.size.width * scale);
	rect.h = iround (bounds.size.height * scale);
	return rect.w > 2 && rect.h > 2;
}

private void* toplevel_hwnd () {
	if (window == null) {
		return null;
	}
	var native = window.get_native ();
	if (native == null) {
		return null;
	}
	var surface = native.get_surface ();
	if (surface == null) {
		return null;
	}
	return gdk_win32_surface_get_handle (surface);
}

private ClientRect[] host_windows (void* parent) {
	ClientRect[] found = {};
	void* after = null;
	while (true) {
		var hwnd = find_window_ex (parent, after, "WebView2GtkHost", null);
		if (hwnd == null) {
			break;
		}
		after = hwnd;
		NativeRect raw;
		if (!get_window_rect (hwnd, out raw)) {
			continue;
		}
		map_window_points (null, parent, ref raw, 2);
		found += ClientRect () {
			x = raw.left,
			y = raw.top,
			w = raw.right - raw.left,
			h = raw.bottom - raw.top
		};
	}
	return found;
}

private int after_moved = 0;

private bool pair_hosts (
	ClientRect[] hosts,
	ClientRect left,
	ClientRect right,
	out ClientRect left_host,
	out ClientRect right_host
) {
	left_host = ClientRect ();
	right_host = ClientRect ();
	if (hosts.length < 2) {
		return false;
	}
	int best = int.MAX;
	bool found = false;
	for (var i = 0; i < hosts.length; i++) {
		for (var j = 0; j < hosts.length; j++) {
			if (i == j) {
				continue;
			}
			var score = abs_delta (hosts[i].h, left.h) + abs_delta (hosts[j].h, right.h);
			if (score < best) {
				best = score;
				left_host = hosts[i];
				right_host = hosts[j];
				found = true;
			}
		}
	}
	return found;
}

private string rect_text (ClientRect rect) {
	return "%d,%d %dx%d".printf (rect.x, rect.y, rect.w, rect.h);
}

private void finish_smoke (bool ok, string why) {
	if (smoke_done) {
		return;
	}
	smoke_done = true;
	if (ok) {
		smoke_status = 0;
		print ("TEST_PASS\n");
	} else {
		smoke_status = 1;
		print ("TEST_FAIL %s\n", why);
	}
	if (window != null) {
		window.close ();
	}
}

private bool rects_close (ClientRect a, ClientRect b) {
	return abs_delta (a.x, b.x) <= SLACK
		&& abs_delta (a.y, b.y) <= SLACK
		&& abs_delta (a.w, b.w) <= SLACK
		&& abs_delta (a.h, b.h) <= SLACK;
}

private void check_after_bar () {
	ClientRect stable_widget, growing_widget;
	if (stable == null || growing == null) {
		return;
	}
	if (!widget_client_bounds (stable, out stable_widget)) {
		return;
	}
	if (!widget_client_bounds (growing, out growing_widget)) {
		return;
	}
	if (stable_widget.y < open_stable.y + MOVE_MIN
	    || open_growing.h - growing_widget.h < MOVE_MIN) {
		return;
	}
	after_moved++;
	var parent = toplevel_hwnd ();
	ClientRect[] hosts = {};
	if (parent != null) {
		hosts = host_windows (parent);
	}
	ClientRect stable_host, growing_host;
	var paired = pair_hosts (hosts, stable_widget, growing_widget, out stable_host, out growing_host);
	print ("move-bounds after stable widget=%s host=%s growing widget=%s host=%s hosts=%d\n",
		rect_text (stable_widget),
		paired ? rect_text (stable_host) : "none",
		rect_text (growing_widget),
		paired ? rect_text (growing_host) : "none",
		hosts.length);
	if (!paired) {
		if (after_moved >= 10) {
			finish_smoke (false, "host window missing after bar");
		}
		return;
	}
	if (abs_delta (stable_widget.h, open_stable.h) > SLACK) {
		finish_smoke (false, "fixed-height view changed height");
		return;
	}
	if (rects_close (stable_host, stable_widget)
	    && rects_close (growing_host, growing_widget)
	    && stable_host.y >= open_stable.y + MOVE_MIN) {
		finish_smoke (true, "");
		return;
	}
	if (after_moved < 10) {
		return;
	}
	if (stable_host.y < open_stable.y + MOVE_MIN) {
		finish_smoke (false, "fixed-height native window stayed put");
		return;
	}
	finish_smoke (false, "native window did not follow the widget");
}

private bool poll_smoke () {
	if (smoke_done) {
		return Source.REMOVE;
	}
	polls++;
	if (polls > 200) {
		finish_smoke (false, "timeout");
		return Source.REMOVE;
	}
	if (bar_opened) {
		check_after_bar ();
		return smoke_done ? Source.REMOVE : Source.CONTINUE;
	}
	if (!growing_finished || !stable_finished || growing == null || stable == null
	    || !growing.ready || !stable.ready || bar == null) {
		return Source.CONTINUE;
	}
	ClientRect stable_widget, growing_widget;
	if (!widget_client_bounds (stable, out stable_widget)) {
		return Source.CONTINUE;
	}
	if (!widget_client_bounds (growing, out growing_widget)) {
		return Source.CONTINUE;
	}
	var parent = toplevel_hwnd ();
	if (parent == null) {
		return Source.CONTINUE;
	}
	var hosts = host_windows (parent);
	ClientRect stable_host, growing_host;
	if (!pair_hosts (hosts, stable_widget, growing_widget, out stable_host, out growing_host)
	    || !rects_close (stable_host, stable_widget)
	    || !rects_close (growing_host, growing_widget)) {
		have_sample = false;
		return Source.CONTINUE;
	}
	if (!have_sample
	    || !rects_close (sample_stable, stable_widget)
	    || !rects_close (sample_growing, growing_widget)) {
		sample_stable = stable_widget;
		sample_growing = growing_widget;
		have_sample = true;
		return Source.CONTINUE;
	}
	print ("move-bounds before stable widget=%s host=%s growing widget=%s host=%s\n",
		rect_text (stable_widget), rect_text (stable_host),
		rect_text (growing_widget), rect_text (growing_host));
	open_stable = stable_widget;
	open_growing = growing_widget;
	bar_opened = true;
	bar.visible = true;
	return Source.CONTINUE;
}

private string page (string heading, string color) {
	return """
<!DOCTYPE html><html><head><meta charset="utf-8"><title>%s</title></head>
<body style="margin:0;background:%s;color:#fff;font:28px sans-serif">
<p style="margin:24px">%s</p>
</body></html>
""".printf (heading, color, heading);
}

public static int main (string[] args) {
	string[] gtk_args = {};
	for (var i = 0; i < args.length; i++) {
		if (i == 0) {
			gtk_args += args[i];
			continue;
		}
		if (args[i] == "--smoke") {
			smoke = true;
			continue;
		}
		gtk_args += args[i];
	}

	var app = new Gtk.Application ("com.webview2gtk.move-bounds", ApplicationFlags.FLAGS_NONE);
	app.activate.connect (() => {
		window = new Gtk.ApplicationWindow (app);
		window.set_title ("webview2-gtk move bounds");
		window.set_default_size (960, 640);

		var header = new Gtk.HeaderBar ();
		var open = new Gtk.Button.with_label ("Open bar");
		header.pack_start (open);
		window.set_titlebar (header);

		var root = new Gtk.Box (Orientation.VERTICAL, 0);
		bar = new Gtk.Box (Orientation.HORIZONTAL, 0);
		bar.set_size_request (-1, BAR_HEIGHT);
		bar.visible = false;
		var notice = new Gtk.Label ("Bar opened above the pages");
		notice.hexpand = true;
		bar.append (notice);

		var columns = new Gtk.Box (Orientation.HORIZONTAL, 0);
		columns.hexpand = true;
		columns.vexpand = true;

		growing = new WebView ();
		growing.hexpand = true;
		growing.vexpand = true;

		var stable_slot = new Gtk.Box (Orientation.VERTICAL, 0);
		stable_slot.hexpand = true;
		stable_slot.vexpand = true;
		stable = new WebView ();
		stable.hexpand = true;
		stable.vexpand = false;
		stable.valign = Align.START;
		stable.set_size_request (-1, STABLE_HEIGHT);
		stable_slot.append (stable);

		columns.append (growing);
		columns.append (stable_slot);
		root.append (bar);
		root.append (columns);
		window.set_child (root);

		open.clicked.connect (() => {
			if (bar != null) {
				bar.visible = !bar.visible;
			}
		});

		growing.load_changed.connect ((event) => {
			if (event == LoadEvent.FINISHED) {
				growing_finished = true;
			}
		});
		stable.load_changed.connect ((event) => {
			if (event == LoadEvent.FINISHED) {
				stable_finished = true;
			}
		});
		growing.load_html (page ("grows shorter", "#c45c26"), null);
		stable.load_html (page ("same height, must move down", "#1d4e89"), null);

		if (smoke) {
			Timeout.add (50, poll_smoke);
		}
		window.present ();
	});
	app.run (gtk_args);
	return smoke ? smoke_status : 0;
}
