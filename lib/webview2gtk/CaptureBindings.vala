/* Sync host APIs — C bindings (script / capture / print .c under lib/host/). */

[CCode (cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_execute_script_sync")]
extern bool wv2_execute_script_sync (string script_utf8, out string result_json);
[CCode (cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_capture_screenshot_sync")]
extern bool wv2_capture_screenshot_sync (bool full_document, out string devtools_json);
[CCode (cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_print_to_pdf_sync")]
extern bool wv2_print_to_pdf_sync (string output_path_utf8);
