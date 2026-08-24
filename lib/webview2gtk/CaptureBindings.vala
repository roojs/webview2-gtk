/* Sync host APIs — C bindings(script / capture / print .c under lib/host/). */

[CCode(cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_execute_script_sync")]
extern bool wv2_execute_script_sync(void* host, string script_utf8, out string result_json);
[CCode(cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_capture_screenshot_sync")]
extern bool wv2_capture_screenshot_sync(void* host, bool full_document, out string devtools_json);
[CCode(cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_print_to_pdf_sync")]
extern bool wv2_print_to_pdf_sync(void* host, string output_path_utf8);
[CCode(cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_get_cookies_sync")]
extern bool wv2_get_cookies_sync(void* host, string uri_utf8, out string? cookies_text);
[CCode(cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_add_cookie_sync")]
extern bool wv2_add_cookie_sync(
	void* host,
	string name_utf8,
	string value_utf8,
	string domain_utf8,
	string path_utf8,
	bool http_only,
	bool secure
);

[CCode(cheader_filename = "webview2gtk-host-api.h", has_target = false)]
public delegate void Wv2DownloadStartedCb(
	int id,
	string uri,
	string suggested_filename,
	string mime_type,
	int64 content_length,
	void* user_data
);
[CCode(cheader_filename = "webview2gtk-host-api.h", has_target = false)]
public delegate void Wv2DownloadProgressCb(int id, uint64 received, void* user_data);
[CCode(cheader_filename = "webview2gtk-host-api.h", has_target = false)]
public delegate void Wv2DownloadFinishedCb(int id, void* user_data);
[CCode(cheader_filename = "webview2gtk-host-api.h", has_target = false)]
public delegate void Wv2DownloadFailedCb(int id, string message, void* user_data);

[CCode(cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_set_download_handlers")]
extern void wv2_host_set_download_handlers(
	void* host,
	Wv2DownloadStartedCb? started,
	Wv2DownloadProgressCb? progress,
	Wv2DownloadFinishedCb? finished,
	Wv2DownloadFailedCb? failed,
	void* user_data
);

[CCode(cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_download_create")]
extern int wv2_host_download_create(void* host, string uri);

[CCode(cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_download_start")]
extern bool wv2_host_download_start(int id, string dest_path, bool overwrite);

[CCode(cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_download_cancel")]
extern void wv2_host_download_cancel(int id);

[CCode(cheader_filename = "webview2gtk-host-api.h", has_target = false)]
public delegate void Wv2ResourceStartedCb(int id, string uri, void* user_data);
[CCode(cheader_filename = "webview2gtk-host-api.h", has_target = false)]
public delegate void Wv2ResourceFinishedCb(int id, void* user_data);
[CCode(cheader_filename = "webview2gtk-host-api.h", has_target = false)]
public delegate void Wv2ResourceFailedCb(int id, string message, void* user_data);

[CCode(cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_set_resource_handlers")]
extern void wv2_host_set_resource_handlers(
	void* host,
	Wv2ResourceStartedCb? started,
	Wv2ResourceFinishedCb? finished,
	Wv2ResourceFailedCb? failed,
	void* user_data
);
