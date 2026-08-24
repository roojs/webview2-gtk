/* Phase 7i / plan 4.0: WebView2 host shell — per-instance handle (4.1).
 *
 * Create / destroy / navigate / bounds live in win32-ui-webview2-com-glue.c.
 * Sync glue methods: generated/win32-ui-webview2-host-glue.vala.
 * Ergo: generated/win32-ergo-webview2.vala → Win32.WebView. */

using Microsoft.Web.WebView2.Win32;
using Win32.Ui;
using Win32.Ui.WindowsAndMessaging;
using Win32.Foundation;


[CCode(cheader_filename = "win32-ui-webview2-host.h")]
namespace Win32.Ui.WebView {

[CCode(cheader_filename = "win32-ui-webview2-com-glue.h", cname = "vala_webview2_com_release_host")]
extern void com_release_host(void* host);

[CCode(cheader_filename = "win32-ui-webview2-com-glue.h", cname = "vala_webview2_com_present_webview")]
extern void com_present_webview([CCode(type_id = "HWND")] void* parent);

[CCode(cheader_filename = "win32-ui-webview2-com-glue.h", cname = "vala_webview2_com_get_webview_for")]
extern void* com_get_webview_for(void* host);

[CCode(cheader_filename = "win32-ui-webview2-com-glue.h", cname = "vala_webview2_com_get_controller_for")]
extern void* com_get_controller_for(void* host);

[CCode(cheader_filename = "win32-ui-webview2-com-glue.h", cname = "vala_webview2_com_get_parent_hwnd_for")]
extern void* com_get_parent_hwnd_for(void* host);

[CCode(cheader_filename = "win32-ui-webview2-com-glue.h", cname = "vala_webview2_host_set_ready")]
extern void host_set_ready(void* host, bool ready);

[CCode(cheader_filename = "win32-ui-webview2-com-glue.h", cname = "vala_webview2_host_set_visible_flag")]
extern void host_set_visible_flag(void* host, bool visible);

[CCode(cheader_filename = "win32-ui-webview2-com-glue.h", cname = "vala_webview2_host_flush_pending_navigate")]
extern void host_flush_pending_navigate(void* host);

[CCode(cheader_filename = "win32-ui-webview2-com-glue.h", cname = "vala_webview2_host_is_ready")]
extern bool host_is_ready_c(void* host);

[CCode(cheader_filename = "objbase.h", cname = "CoTaskMemFree")]
extern void co_task_mem_free(void* ptr);

private bool com_ok(int hr) {
	return hr >= 0;
}

private bool webview_ready(void* host) {
	return host_is_ready_c(host) && com_get_webview_for(host) != null;
}

private bool controller_ready(void* host) {
	return host_is_ready_c(host) && com_get_controller_for(host) != null;
}

/* For generated glue — COM as void*; cast here only. */
internal unowned ICoreWebView2Controller host_controller_com(void* host) {
	return (ICoreWebView2Controller) com_get_controller_for(host);
}

internal unowned ICoreWebView2 host_webview_com(void* host) {
	return (ICoreWebView2) com_get_webview_for(host);
}

internal void set_host_visible_flag(void* host, bool visible) {
	host_set_visible_flag(host, visible);
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

[CCode(cname = "vala_webview2_host_finish_setup")]
public void finish_setup(
	void* host,
	void* controller,
	void* webview,
	[CCode(type_id = "HWND")] void* parent
) {
	if (host == null || controller == null || webview == null) {
		return;
	}
	host_set_ready(host, true);
	var vis = com_controller_put_is_visible(host_controller_com(host), 1);
	if (!com_ok(vis)) {
		stderr.printf("WebView2 put_is_visible failed: 0x%08x\n", (uint) vis);
	}
	if (parent != null) {
		com_present_webview(parent);
	}
	host_flush_pending_navigate(host);
	events_register(host);
	document_response_register(host);
	script_messages_register(host);
	downloads_register(host);
	web_resources_register(host);
	permissions_register(host);
}

[CCode(cname = "vala_webview2_host_destroy")]
public void destroy(void* host) {
	if (host == null) {
		return;
	}
	if (webview_ready(host)) {
		document_response_unregister(host);
		script_messages_unregister(host);
		downloads_unregister(host);
		web_resources_unregister(host);
		permissions_unregister(host);
		events_unregister(host);
	}
	com_release_host(host);
}

[CCode(cheader_filename = "win32-ui-webview2-events.h", cname = "vala_webview2_events_register_host")]
extern void events_register(void* host);

[CCode(cheader_filename = "win32-ui-webview2-events.h", cname = "vala_webview2_events_unregister_host")]
extern void events_unregister(void* host);

[CCode(cheader_filename = "win32-ui-webview2-document-response.h", cname = "vala_webview2_document_response_register_host")]
extern void document_response_register(void* host);

[CCode(cheader_filename = "win32-ui-webview2-script-messages.h", cname = "vala_webview2_script_messages_register_host")]
extern void script_messages_register(void* host);

[CCode(cheader_filename = "win32-ui-webview2-downloads.h", cname = "vala_webview2_downloads_register_host")]
extern void downloads_register(void* host);

[CCode(cheader_filename = "win32-ui-webview2-web-resources.h", cname = "vala_webview2_web_resources_register_host")]
extern void web_resources_register(void* host);

[CCode(cheader_filename = "win32-ui-webview2-permissions.h", cname = "vala_webview2_permissions_register_host")]
extern void permissions_register(void* host);

[CCode(cheader_filename = "win32-ui-webview2-a11y-diag.h", cname = "vala_webview2_a11y_diag_register")]
extern void a11y_diag_register(ICoreWebView2 webview);

[CCode(cheader_filename = "win32-ui-webview2-document-response.h", cname = "vala_webview2_document_response_unregister_host")]
extern void document_response_unregister(void* host);

[CCode(cheader_filename = "win32-ui-webview2-script-messages.h", cname = "vala_webview2_script_messages_unregister_host")]
extern void script_messages_unregister(void* host);

[CCode(cheader_filename = "win32-ui-webview2-downloads.h", cname = "vala_webview2_downloads_unregister_host")]
extern void downloads_unregister(void* host);

[CCode(cheader_filename = "win32-ui-webview2-web-resources.h", cname = "vala_webview2_web_resources_unregister_host")]
extern void web_resources_unregister(void* host);

[CCode(cheader_filename = "win32-ui-webview2-permissions.h", cname = "vala_webview2_permissions_unregister_host")]
extern void permissions_unregister(void* host);

}
