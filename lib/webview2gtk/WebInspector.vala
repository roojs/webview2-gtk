namespace WebView2Gtk {

/**
 * WebKitGTK-shaped inspector — {@link show} opens the host DevTools window.
 */
public class WebInspector : Object {
	private weak WebView view;

	internal WebInspector(WebView view) {
		this.view = view;
	}

	public void show() {
		if (this.view == null) {
			return;
		}
		if (!this.view.get_settings().enable_developer_extras) {
			return;
		}
		this.view.open_devtools_window();
	}

	public void close() {
		/* WebView2 has no close-devtools API; no-op. */
	}
}

}
