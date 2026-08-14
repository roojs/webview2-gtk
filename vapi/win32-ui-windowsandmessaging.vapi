/* Hand stub — host uses only client rect + window text(full JSON binding not vendored). */

namespace Win32.Ui.WindowsAndMessaging {

[CCode(cname = "SetWindowTextW", cheader_filename = "windows.h")]
public extern int set_window_text(
	[CCode(type_id = "HWND")] void* h_wnd,
	[CCode(type_id = "LPCWSTR")] uint16* lp_string
);

[CCode(cname = "GetWindowTextW", cheader_filename = "windows.h")]
public extern int get_window_text(
	[CCode(type_id = "HWND")] void* h_wnd,
	void* lp_string,
	int n_max_count
);

[CCode(cname = "GetClientRect", cheader_filename = "windows.h")]
public extern int get_client_rect(
	[CCode(type_id = "HWND")] void* h_wnd,
	out Win32.Foundation.Rect lp_rect
);

}
