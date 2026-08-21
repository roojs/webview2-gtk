namespace WebView2Gtk {

/**
 * WebKitGTK-shaped website policies for a {@link WebView}.
 *
 * Construct-only {@link autoplay} matches webkitgtk-6.0.
 */
public class WebsitePolicies : Object {
	public AutoplayPolicy autoplay { get; construct; }

	public WebsitePolicies() {
	}

	public AutoplayPolicy get_autoplay_policy() {
		return this.autoplay;
	}
}

}
