namespace WebView2Gtk {

/**
 * WebKitGTK-shaped web resource — in-flight subresource for load tracking.
 *
 * Emitted from {@link WebView.resource_load_started}; connect to
 * {@link finished} / {@link failed} to count outstanding loads.
 */
public class WebResource : Object {
	private bool terminal;

	/**
	 * Resource URI(WebKit also exposes this as get_uri).
	 */
	public string uri { get; private set; }

	internal WebResource(string uri) {
		this.uri = uri ?? "";
	}

	public signal void finished();

	public signal void failed(GLib.Error error);

	internal void emit_finished() {
		if (this.terminal) {
			return;
		}
		this.terminal = true;
		this.finished();
	}

	internal void emit_failed(GLib.Error error) {
		if (this.terminal) {
			return;
		}
		this.terminal = true;
		this.failed(error);
	}
}

}
