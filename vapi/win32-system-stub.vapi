/* Hand stub until loader JSON is vendored. */

namespace Win32.System {
	[CCode (cname = "GetModuleHandleW", cheader_filename = "windows.h")]
	public extern void* get_module_handle (void* lp_module_name);

	[CCode (cname = "GetLastError", cheader_filename = "windows.h")]
	public extern uint get_last_error ();
}
