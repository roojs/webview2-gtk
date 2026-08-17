namespace WebView2Gtk {

/**
 * WebKitGTK-shaped automation session(browser side).
 *
 * Created when automation is allowed and a controlled {@link WebView} exists.
 * Fill click/sendKeys stay HTTP → external WebKitWebDriver — not methods here.
 */
public class AutomationSession : Object {
	private ApplicationInfo app_info = new ApplicationInfo();

	/** WebKitGTK-shaped — same as {@link get_id}. */
	public string id { get; private set; }

	/**
	 * Emitted when the automation client needs a view(WebKitGTK shape).
	 * Return the primary controlled {@link WebView} (as Gtk.Widget to avoid
	 * GType cycles with WebView → WebContext → AutomationSession).
	 */
	public signal Gtk.Widget create_web_view();

	internal AutomationSession() {
		this.id = "wv2gtk-%u".printf(
			(uint) Random.next_int()
		);
	}

	public void set_application_info(ApplicationInfo info) {
		if (info != null) {
			this.app_info = info;
		}
	}

	public unowned ApplicationInfo get_application_info() {
		return this.app_info;
	}
}

}
