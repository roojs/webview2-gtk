/* Phase 7i: WebView2 glue — hand host shell(async bootstrap, layout, shared helpers).
 *
 * Sync glue methods: generated/win32-ui-webview2-host-glue.vala(WebView2MethodCatalog).
 * Ergo: generated/win32-ergo-webview2.vala → Win32.WebView. Hand C: loader + com-glue only. */

using Microsoft.Web.WebView2.Win32;
using Win32.Ui;
using Win32.Ui.WindowsAndMessaging;
using Win32.Foundation;


[CCode(cheader_filename = "win32-ui-webview2-host.h")]
namespace Win32.Ui.WebView {

[CCode(cheader_filename = "win32-ui-webview2-com-glue.h", cname = "vala_webview2_com_begin_host")]
extern bool com_begin_host(
	[CCode(type_id = "HWND")] void* parent,
	[CCode(type_id = "LPCWSTR")] uint16* url,
	Microsoft.Web.WebView2.Win32.Rect* bounds
);

[CCode(cheader_filename = "win32-ui-webview2-com-glue.h", cname = "vala_webview2_com_release_host")]
extern void com_release_host();

[CCode(cheader_filename = "win32-ui-webview2-com-glue.h", cname = "vala_webview2_com_present_webview")]
extern void com_present_webview([CCode(type_id = "HWND")] void* parent);

[CCode(cheader_filename = "objbase.h", cname = "CoTaskMemFree")]
extern void co_task_mem_free(void* ptr);

[Compact]
private struct HostState {
	public void* parent;
	public Microsoft.Web.WebView2.Win32.Rect bounds;
	/* Raw COM pointers — not Vala interface types (gobject profile would Release them). */
	public void* controller;
	public void* webview;
	public WideString? pending_url;
	public bool ready;
	public bool host_visible;
}

private HostState? g_host;

private Microsoft.Web.WebView2.Win32.Rect rect_xywh(int x, int y, int width, int height) {
	return Microsoft.Web.WebView2.Win32.Rect() {
		left = x,
		top = y,
		right = x + width,
		bottom = y + height,
	};
}

private Microsoft.Web.WebView2.Win32.Rect client_rect(void* hwnd) {
	Win32.Foundation.Rect fr;
	get_client_rect(hwnd, out fr);
	return Microsoft.Web.WebView2.Win32.Rect() {
		left = fr.left,
		top = fr.top,
		right = fr.right,
		bottom = fr.bottom,
	};
}

private bool com_ok(int hr) {
	return hr >= 0;
}

private bool webview_ready() {
	return g_host != null && g_host.ready && g_host.webview != null;
}

private bool controller_ready() {
	return g_host != null && g_host.ready && g_host.controller != null;
}

/* For generated glue — COM as void* in HostState; cast here only. */
internal unowned ICoreWebView2Controller host_controller_com() {
	return (ICoreWebView2Controller) g_host.controller;
}

internal unowned ICoreWebView2 host_webview_com() {
	return (ICoreWebView2) g_host.webview;
}

internal void set_host_visible_flag(bool visible) {
	if (g_host == null) {
		return;
	}
	g_host.host_visible = visible;
}

private string take_com_string(uint16* com_str) {
	if (com_str == null) {
		return "";
	}
	var s = utf16_ptr_to_string(com_str);
	co_task_mem_free(com_str);
	return s;
}

private string utf16_ptr_to_string(uint16* wide) {
	if (wide == null) {
		return "";
	}
	var len = 0;
	while (wide[len] != 0) {
		len++;
	}
	var buf = new uint16[len + 1];
	for (var i = 0; i <= len; i++) {
		buf[i] = wide[i];
	}
	return utf16_buffer_to_string(buf);
}

private void apply_bounds() {
	if (g_host == null || g_host.controller == null) {
		return;
	}
	var hr = com_controller_put_bounds(host_controller_com(), g_host.bounds);
	if (!com_ok(hr)) {
		stderr.printf("WebView2 put_bounds failed: 0x%08x\n", (uint) hr);
	}
	if (g_host.parent != null && g_host.host_visible) {
		com_present_webview(g_host.parent);
	}
}

private void flush_pending_navigate() {
	if (g_host == null || !g_host.ready || g_host.webview == null || g_host.pending_url == null) {
		return;
	}
	var nav = com_webview_navigate(host_webview_com(), g_host.pending_url.ptr);
	if (!com_ok(nav)) {
		stderr.printf("WebView2 navigate failed: 0x%08x\n", (uint) nav);
	}
	g_host.pending_url = null;
}

[CCode(cname = "vala_webview2_host_finish_setup")]
public void finish_setup(
	ICoreWebView2Controller controller,
	ICoreWebView2 webview,
	[CCode(type_id = "HWND")] void* parent
) {
	if (g_host == null) {
		return;
	}
	g_host.controller = (void*) controller;
	g_host.webview = (void*) webview;
	g_host.parent = parent;
	g_host.ready = true;
	apply_bounds();
	var vis = com_controller_put_is_visible(
		host_controller_com(),
		g_host.host_visible ? 1 : 0
	);
	if (!com_ok(vis)) {
		stderr.printf("WebView2 put_is_visible failed: 0x%08x\n", (uint) vis);
	}
	if (g_host.parent != null) {
		com_present_webview(g_host.parent);
	}
	flush_pending_navigate();
	events_register(host_webview_com());
	document_response_register(host_webview_com());
	/* A11y Invoke diagnostics — off in general builds.
	 * To enable: set WEBVIEW2GTK_A11Y_DIAG_COMPILE to 1 in
	 * win32-ui-webview2-a11y-diag.h, uncomment the next line, rebuild,
	 * run with WEBVIEW2GTK_A11Y_DIAG=1.
	a11y_diag_register(host_webview_com());
	*/
}

[CCode(cname = "vala_webview2_host_create_with_xywh")]
public bool create_with_xywh(
	void* parent_hwnd,
	int x, int y, int width, int height,
	uint16* url
) {
	return create_with_bounds(parent_hwnd, rect_xywh(x, y, width, height), url);
}

[CCode(cname = "vala_webview2_host_create_with_bounds")]
public bool create_with_bounds(
	void* parent_hwnd,
	Microsoft.Web.WebView2.Win32.Rect bounds,
	uint16* url
) {
	if (parent_hwnd == null) {
		return false;
	}
	var st = HostState();
	st.parent = parent_hwnd;
	st.bounds = bounds;
	st.host_visible = true;
	g_host = st;
	return com_begin_host(parent_hwnd, url, &g_host.bounds);
}

[CCode(cname = "vala_webview2_host_create")]
public bool create(void* parent_hwnd, uint16* url) {
	if (parent_hwnd == null || url == null) {
		return false;
	}
	return create_with_bounds(parent_hwnd, client_rect(parent_hwnd), url);
}

[CCode(cname = "vala_webview2_host_set_bounds_xywh")]
public void set_bounds_xywh(int x, int y, int width, int height) {
	set_bounds(rect_xywh(x, y, width, height));
}

[CCode(cname = "vala_webview2_host_set_bounds")]
public void set_bounds(Microsoft.Web.WebView2.Win32.Rect bounds) {
	if (g_host == null) {
		return;
	}
	g_host.bounds = bounds;
	if (g_host.ready) {
		apply_bounds();
	}
}

[CCode(cname = "vala_webview2_host_navigate")]
public bool navigate(string url) {
	if (g_host == null || url.length == 0) {
		return false;
	}
	g_host.pending_url = WideString(url);
	if (g_host.ready) {
		flush_pending_navigate();
	}
	return true;
}

[CCode(cname = "vala_webview2_host_on_size")]
public void on_size(void* parent_hwnd) {
	if (g_host == null || g_host.controller == null || parent_hwnd != g_host.parent) {
		return;
	}
	g_host.bounds = client_rect(parent_hwnd);
	apply_bounds();
}

[CCode(cname = "vala_webview2_host_destroy")]
public void destroy() {
	if (webview_ready()) {
		document_response_unregister(host_webview_com());
		events_unregister(host_webview_com());
	}
	com_release_host();
	g_host = null;
}

[CCode(cheader_filename = "win32-ui-webview2-events.h", cname = "vala_webview2_events_register")]
extern void events_register(ICoreWebView2 webview);

[CCode(cheader_filename = "win32-ui-webview2-events.h", cname = "vala_webview2_events_unregister")]
extern void events_unregister(ICoreWebView2 webview);

[CCode(cheader_filename = "win32-ui-webview2-document-response.h", cname = "vala_webview2_document_response_register")]
extern void document_response_register(ICoreWebView2 webview);

[CCode(cheader_filename = "win32-ui-webview2-a11y-diag.h", cname = "vala_webview2_a11y_diag_register")]
extern void a11y_diag_register(ICoreWebView2 webview);

[CCode(cheader_filename = "win32-ui-webview2-document-response.h", cname = "vala_webview2_document_response_unregister")]
extern void document_response_unregister(ICoreWebView2 webview);

[CCode(cname = "vala_webview2_host_is_ready")]
public bool is_ready() {
	return g_host != null && g_host.ready;
}

}