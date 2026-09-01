namespace WebView2Gtk {

/**
 * WebKitGTK-shaped response policy decision for main-frame document loads.
 *
 * Property accessors match WebKit's get_request / get_response.
 */
public sealed class ResponsePolicyDecision : PolicyDecision {
	public URIRequest request { get; construct; }
	public URIResponse response { get; construct; }

	public ResponsePolicyDecision(string uri, uint status_code, Soup.MessageHeaders http_headers) {
		Object(
			request: new URIRequest(uri),
			response: new URIResponse(uri, status_code, http_headers)
		);
	}

	public bool is_main_frame_main_resource() {
		return true;
	}

	public bool is_mime_type_supported() {
		return true;
	}
}

}
