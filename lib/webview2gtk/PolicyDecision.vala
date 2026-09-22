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
 * On Windows only {@link PolicyDecisionType.RESPONSE} is emitted today.
 * {@link ignore} on that RESPONSE cancels the document. {@link use} and
 * {@link download} remain no-ops.
 */
public abstract class PolicyDecision : Object {
	private enum Action {
		NONE,
		USE,
		IGNORE,
		DOWNLOAD
	}

	private Action chosen = Action.NONE;

	internal bool was_ignored() {
		return chosen == Action.IGNORE;
	}

	private void set_action(Action next) {
		if (chosen != Action.NONE) {
			return;
		}
		chosen = next;
	}

	public virtual void use() {
		set_action(Action.USE);
	}

	/**
	 * Refuse the load.
	 *
	 * On Windows {@link PolicyDecisionType.RESPONSE}, the host stops the
	 * document and treats the navigation as cancelled. If the engine still
	 * commits (Edge PDF viewer), the view is navigated to ''about:blank''.
	 */
	public virtual void ignore() {
		set_action(Action.IGNORE);
	}

	public virtual void download() {
		set_action(Action.DOWNLOAD);
	}
}

}
