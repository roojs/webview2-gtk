namespace WebView2Gtk {

/** WebKitGTK-shaped — type of {@link WebView.decide_policy} decision. */
public enum PolicyDecisionType {
	NAVIGATION_ACTION,
	NEW_WINDOW_ACTION,
	RESPONSE
}

/**
 * WebKitGTK-shaped pending policy decision.
 *
 * On Windows only {@link PolicyDecisionType.RESPONSE} is emitted today;
 * {@link use}, {@link ignore}, and {@link download} are no-ops for observe-only handlers.
 */
public abstract class PolicyDecision : Object {
	public virtual void use() {
	}

	public virtual void ignore() {
	}

	public virtual void download() {
	}
}

}
