namespace WebView2Gtk {

/**
 * WebKitGTK-shaped policy decision for a popup.
 *
 * {@link WebView.decide_policy} emits this with
 * {@link PolicyDecisionType.NEW_WINDOW_ACTION} for ''window.open'' and
 * ''target="_blank"''. {@link request} is the URI that was refused.
 * {@link is_user_gesture} is WebView2's IsUserInitiated. WebKit exposes
 * that flag on NavigationAction; this type does not carry mouse button or
 * modifiers.
 */
public sealed class NavigationPolicyDecision : PolicyDecision {
	public URIRequest request { get; construct; }

	/** WebView2 IsUserInitiated. */
	public bool is_user_gesture { get; construct; }

	public NavigationPolicyDecision(string uri, bool is_user_gesture) {
		Object(
			request: new URIRequest(uri),
			is_user_gesture: is_user_gesture
		);
	}
}

}
