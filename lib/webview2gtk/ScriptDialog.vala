namespace WebView2Gtk {

/**
 * WebKitGTK-shaped — kind of {@link WebView.script_dialog}.
 */
public enum ScriptDialogType {
	ALERT,
	CONFIRM,
	PROMPT,
	BEFORE_UNLOAD_CONFIRM
}

/**
 * WebKitGTK-shaped — one page ''alert'', ''confirm'', ''prompt'', or before-unload.
 *
 * Valid for the duration of {@link WebView.script_dialog}. Set confirm or prompt
 * text before the handler returns ''true''.
 *
 * == Usage Examples ==
 *
 * === Answer confirm and prompt ===
 *
 * {{{
 * web.script_dialog.connect((dialog) => {
 *     switch (dialog.get_dialog_type()) {
 *     case ScriptDialogType.CONFIRM:
 *     case ScriptDialogType.BEFORE_UNLOAD_CONFIRM:
 *         dialog.confirm_set_confirmed(true);
 *         break;
 *     case ScriptDialogType.PROMPT:
 *         dialog.prompt_set_text(dialog.prompt_get_default_text());
 *         break;
 *     default:
 *         break;
 *     }
 *     return true;
 * });
 * }}}
 */
public class ScriptDialog : Object {
	private ScriptDialogType dialog_type;
	private string message;
	private string default_text;
	private bool confirmed;
	private bool prompt_answered;
	private string result_text;

	internal ScriptDialog(ScriptDialogType dialog_type, string message, string default_text) {
		Object();
		this.dialog_type = dialog_type;
		this.message = message;
		this.default_text = default_text;
		this.result_text = "";
	}

	/** WebKitGTK-shaped — ''alert'', ''confirm'', ''prompt'', or before-unload. */
	public ScriptDialogType get_dialog_type() {
		return this.dialog_type;
	}

	/** WebKitGTK-shaped — dialog message from the page. */
	public unowned string get_message() {
		return this.message;
	}

	/**
	 * WebKitGTK-shaped — ''true'' accepts confirm and before-unload.
	 *
	 * Leaving this unset cancels both (the page sees ''false'' / stays).
	 */
	public void confirm_set_confirmed(bool confirmed) {
		this.confirmed = confirmed;
	}

	/** WebKitGTK-shaped — second argument of ''prompt'', or empty. */
	public unowned string prompt_get_default_text() {
		return this.default_text;
	}

	/**
	 * WebKitGTK-shaped — value ''prompt'' returns.
	 *
	 * An empty string is a real answer. Leaving this unset cancels the prompt.
	 */
	public void prompt_set_text(string text) {
		this.result_text = text;
		this.prompt_answered = true;
	}

	internal bool wants_accept() {
		switch (this.dialog_type) {
		case ScriptDialogType.ALERT:
			return true;
		case ScriptDialogType.CONFIRM:
		case ScriptDialogType.BEFORE_UNLOAD_CONFIRM:
			return this.confirmed;
		case ScriptDialogType.PROMPT:
			return this.prompt_answered;
		default:
			return false;
		}
	}

	internal string? prompt_result() {
		if (this.dialog_type != ScriptDialogType.PROMPT || !this.prompt_answered) {
			return null;
		}
		return this.result_text;
	}
}

}
