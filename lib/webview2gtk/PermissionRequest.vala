namespace WebView2Gtk {

/** WebKitGTK-shaped — result of {@link PermissionStateQuery.finish}. */
public enum PermissionState {
	GRANTED,
	DENIED,
	PROMPT
}

/** WebKitGTK-shaped — allow/deny a permission prompt. */
public interface PermissionRequest : Object {
	public abstract void allow();
	public abstract void deny();
}

/** WebKitGTK-shaped — answer a permission-state query (API parity; host may never emit). */
public class PermissionStateQuery : Object {
	public PermissionStateQuery(string name) {
		Object(query_name: name);
	}

	public string query_name { get; construct; }

	public PermissionState state { get; private set; default = PermissionState.PROMPT; }

	public bool finished { get; private set; default = false; }

	public void finish(PermissionState state) {
		this.state = state;
		this.finished = true;
	}

	public unowned string get_name() {
		return this.query_name;
	}
}

internal class SimplePermissionRequest : Object, PermissionRequest {
	public bool decided { get; private set; default = false; }
	public bool allowed { get; private set; default = false; }

	public void allow() {
		this.decided = true;
		this.allowed = true;
	}

	public void deny() {
		this.decided = true;
		this.allowed = false;
	}
}

}
