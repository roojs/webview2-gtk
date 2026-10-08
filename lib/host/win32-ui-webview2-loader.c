/* WebView2Loader.dll bootstrap only (Phase 7i). */

#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <objbase.h>
#include <stdio.h>
#include <wchar.h>

#include "win32-ui-webview2-loader.h"
#include "win32-ui-webview2-automation.h"
#include "win32-ui-webview2-sdk.h"
#include <shlobj.h>
#include <sddl.h>
#include <aclapi.h>

typedef HRESULT (STDMETHODCALLTYPE *PFN_CreateCoreWebView2EnvironmentWithOptions)(
	PCWSTR browserExecutableFolder,
	PCWSTR userDataFolder,
	ICoreWebView2EnvironmentOptions *environmentOptions,
	ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler *environmentCreatedHandler);

static HMODULE g_loader_module;
static PFN_CreateCoreWebView2EnvironmentWithOptions g_create_env_with_options;
static BOOL g_com_inited;
static BOOL g_profiles_swept;
static DWORD g_profile_token;

BOOL vala_webview2_loader_init (void)
{
	HRESULT hr;

	if (!g_com_inited) {
		hr = CoInitializeEx (NULL, COINIT_APARTMENTTHREADED);
		if (FAILED (hr) && hr != RPC_E_CHANGED_MODE) {
			fprintf (stderr, "CoInitializeEx failed: 0x%08lx\n", (unsigned long) hr);
			return FALSE;
		}
		g_com_inited = TRUE;
	}

	if (g_create_env_with_options != NULL) {
		return TRUE;
	}

	g_loader_module = LoadLibraryW (L"WebView2Loader.dll");
	if (g_loader_module == NULL) {
		fprintf (stderr, "LoadLibrary WebView2Loader.dll failed: %lu\n", (unsigned long) GetLastError ());
		return FALSE;
	}

	g_create_env_with_options = (PFN_CreateCoreWebView2EnvironmentWithOptions) (void *) GetProcAddress (
		g_loader_module,
		"CreateCoreWebView2EnvironmentWithOptions");
	if (g_create_env_with_options == NULL) {
		fprintf (stderr, "GetProcAddress CreateCoreWebView2EnvironmentWithOptions failed\n");
		FreeLibrary (g_loader_module);
		g_loader_module = NULL;
		return FALSE;
	}
	return TRUE;
}

static BOOL make_shared_user_data_folder (wchar_t *out, size_t out_cch);

HRESULT vala_webview2_loader_create_environment (
	struct ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler *handler)
{
	ICoreWebView2EnvironmentOptions *options = NULL;
	wchar_t folder[MAX_PATH];
	HRESULT hr;

	if (g_create_env_with_options == NULL || handler == NULL) {
		return E_FAIL;
	}

	/* NULL user-data is {exe}\{exe}.WebView2. A standard user cannot write
	 * that next to an exe under Program Files. */
	if (!make_shared_user_data_folder (folder, MAX_PATH)) {
		fprintf (stderr, "webview2gtk: user data folder failed\n");
		return E_FAIL;
	}
	fprintf (stderr, "webview2gtk: user data folder %ls\n", folder);

	/* Honor WEBKIT_INSPECTOR_SERVER / autoplay DENY / webdriver DISABLED / proxy → AdditionalBrowserArguments. */
	options = vala_webview2_host_create_environment_options ();
	hr = g_create_env_with_options (NULL, folder, options, handler);
	if (options != NULL) {
		ICoreWebView2EnvironmentOptions_Release (options);
	}
	return hr;
}

static BOOL
process_still_running (DWORD pid)
{
	HANDLE process;
	DWORD status;

	if (pid == 0) {
		return FALSE;
	}
	process = OpenProcess (PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
	if (process == NULL) {
		return GetLastError () == ERROR_ACCESS_DENIED;
	}
	if (!GetExitCodeProcess (process, &status)) {
		CloseHandle (process);
		return FALSE;
	}
	CloseHandle (process);
	return status == STILL_ACTIVE;
}

static void
delete_tree (const wchar_t *path)
{
	WIN32_FIND_DATAW fd;
	wchar_t pattern[MAX_PATH];
	wchar_t child[MAX_PATH];
	HANDLE find;

	if (path == NULL || path[0] == L'\0') {
		return;
	}
	_snwprintf (pattern, MAX_PATH, L"%s\\*", path);
	pattern[MAX_PATH - 1] = L'\0';
	find = FindFirstFileW (pattern, &fd);
	if (find != INVALID_HANDLE_VALUE) {
		do {
			if (wcscmp (fd.cFileName, L".") == 0
			    || wcscmp (fd.cFileName, L"..") == 0) {
				continue;
			}
			_snwprintf (child, MAX_PATH, L"%s\\%s", path, fd.cFileName);
			child[MAX_PATH - 1] = L'\0';
			if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) {
				delete_tree (child);
			} else {
				SetFileAttributesW (child, FILE_ATTRIBUTE_NORMAL);
				DeleteFileW (child);
			}
		} while (FindNextFileW (find, &fd));
		FindClose (find);
	}
	SetFileAttributesW (path, FILE_ATTRIBUTE_NORMAL);
	RemoveDirectoryW (path);
}

static int
profile_underscores (const wchar_t *name)
{
	int n = 0;

	for (; name != NULL && *name != L'\0'; name++) {
		if (*name == L'_') {
			n++;
		}
	}
	return n;
}

/* Drop folders whose owner pid is gone. Legacy wv_<id> has no pid — try
 * delete; a live msedgewebview2 lock just fails the delete. */
static void
sweep_dead_profile_dirs (const wchar_t *profiles_root)
{
	WIN32_FIND_DATAW fd;
	wchar_t glob[MAX_PATH];
	wchar_t names[64][MAX_PATH];
	int n_names = 0;
	int i;
	HANDLE find;
	unsigned long pid;
	unsigned long token;
	int route;

	if (profiles_root == NULL || profiles_root[0] == L'\0') {
		return;
	}
	_snwprintf (glob, MAX_PATH, L"%s\\wv_*", profiles_root);
	glob[MAX_PATH - 1] = L'\0';
	find = FindFirstFileW (glob, &fd);
	if (find == INVALID_HANDLE_VALUE) {
		return;
	}
	do {
		if (!(fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)) {
			continue;
		}
		if (n_names >= (int) (sizeof (names) / sizeof (names[0]))) {
			break;
		}
		pid = 0;
		token = 0;
		route = 0;
		if (profile_underscores (fd.cFileName) == 3
		    && swscanf (fd.cFileName, L"wv_%lu_%lu_%d", &pid, &token, &route) == 3) {
			if (pid == GetCurrentProcessId () || process_still_running ((DWORD) pid)) {
				continue;
			}
		} else if (profile_underscores (fd.cFileName) == 2
		    && swscanf (fd.cFileName, L"wv_%lu_%d", &pid, &route) == 2) {
			if (pid == GetCurrentProcessId () || process_still_running ((DWORD) pid)) {
				continue;
			}
		} else if (profile_underscores (fd.cFileName) != 1) {
			continue;
		}
		wcsncpy (names[n_names], fd.cFileName, MAX_PATH);
		names[n_names][MAX_PATH - 1] = L'\0';
		n_names++;
	} while (FindNextFileW (find, &fd));
	FindClose (find);
	for (i = 0; i < n_names; i++) {
		wchar_t child[MAX_PATH];

		_snwprintf (child, MAX_PATH, L"%s\\%s", profiles_root, names[i]);
		child[MAX_PATH - 1] = L'\0';
		delete_tree (child);
	}
}

static DWORD
profile_token (void)
{
	if (g_profile_token == 0) {
		g_profile_token = GetTickCount ();
		if (g_profile_token == 0) {
			g_profile_token = 1;
		}
	}
	return g_profile_token;
}

/* Browser process is medium IL. An elevated host's LOCALAPPDATA is the
 * administrator profile, which that browser cannot write. */
typedef struct {
	wchar_t local_app_data[MAX_PATH];
	HANDLE token;
} BrowserProfile;

static void
browser_profile_close (BrowserProfile *profile)
{
	if (profile != NULL && profile->token != NULL) {
		CloseHandle (profile->token);
		profile->token = NULL;
	}
}

static BOOL
process_token_is_elevated (void)
{
	HANDLE token = NULL;
	TOKEN_ELEVATION elevation;
	DWORD len = 0;
	BOOL elevated = FALSE;

	if (!OpenProcessToken (GetCurrentProcess (), TOKEN_QUERY, &token)) {
		return FALSE;
	}
	if (GetTokenInformation (token, TokenElevation, &elevation, sizeof (elevation), &len)) {
		elevated = elevation.TokenIsElevated ? TRUE : FALSE;
	}
	CloseHandle (token);
	return elevated;
}

static BOOL
set_privilege (LPCWSTR name, BOOL enable)
{
	HANDLE token = NULL;
	TOKEN_PRIVILEGES tp;
	LUID luid;
	BOOL ok;

	if (!OpenProcessToken (GetCurrentProcess (), TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, &token)) {
		return FALSE;
	}
	if (!LookupPrivilegeValueW (NULL, name, &luid)) {
		CloseHandle (token);
		return FALSE;
	}
	ZeroMemory (&tp, sizeof (tp));
	tp.PrivilegeCount = 1;
	tp.Privileges[0].Luid = luid;
	tp.Privileges[0].Attributes = enable ? SE_PRIVILEGE_ENABLED : 0;
	if (!AdjustTokenPrivileges (token, FALSE, &tp, sizeof (tp), NULL, NULL)) {
		CloseHandle (token);
		return FALSE;
	}
	ok = (GetLastError () == ERROR_SUCCESS);
	CloseHandle (token);
	return ok;
}

/* Interactive user: explorer on this desktop. Over-the-shoulder elevation's
 * linked token is still the administrator; the browser runs as the shell user. */
static HANDLE
open_shell_token (void)
{
	HWND shell;
	DWORD pid = 0;
	HANDLE process = NULL;
	HANDLE token = NULL;

	shell = GetShellWindow ();
	if (shell == NULL) {
		return NULL;
	}
	GetWindowThreadProcessId (shell, &pid);
	if (pid == 0) {
		return NULL;
	}
	process = OpenProcess (PROCESS_QUERY_INFORMATION, FALSE, pid);
	if (process == NULL) {
		return NULL;
	}
	if (!OpenProcessToken (process, TOKEN_QUERY | TOKEN_DUPLICATE | TOKEN_IMPERSONATE, &token)) {
		token = NULL;
	}
	CloseHandle (process);
	return token;
}

static HANDLE
linked_unelevated_token (void)
{
	HANDLE process_token = NULL;
	TOKEN_LINKED_TOKEN linked;
	DWORD len = 0;

	if (!OpenProcessToken (GetCurrentProcess (), TOKEN_QUERY, &process_token)) {
		return NULL;
	}
	ZeroMemory (&linked, sizeof (linked));
	if (!GetTokenInformation (process_token, TokenLinkedToken, &linked, sizeof (linked), &len)) {
		CloseHandle (process_token);
		return NULL;
	}
	CloseHandle (process_token);
	return linked.LinkedToken;
}

static BOOL
copy_local_app_data (HANDLE token, wchar_t *out, size_t out_cch)
{
	HRESULT hr;
	BOOL impersonating = FALSE;

	if (out == NULL || out_cch < MAX_PATH) {
		return FALSE;
	}
	out[0] = L'\0';
	/* Pass NULL for the token and impersonate. SHGetFolderPathW can ignore
	 * hToken and return this process's profile — the administrator's. */
	if (token != NULL) {
		if (!ImpersonateLoggedOnUser (token)) {
			return FALSE;
		}
		impersonating = TRUE;
	}
	hr = SHGetFolderPathW (NULL, CSIDL_LOCAL_APPDATA, NULL, SHGFP_TYPE_CURRENT, out);
	if (impersonating) {
		RevertToSelf ();
	}
	if (FAILED (hr) || out[0] == L'\0') {
		out[0] = L'\0';
		return FALSE;
	}
	out[out_cch - 1] = L'\0';
	return TRUE;
}

static BOOL
open_browser_profile (BrowserProfile *profile)
{
	HANDLE shell = NULL;

	ZeroMemory (profile, sizeof (*profile));
	if (!process_token_is_elevated ()) {
		return copy_local_app_data (NULL, profile->local_app_data, MAX_PATH);
	}

	shell = open_shell_token ();
	if (shell == NULL && set_privilege (L"SeDebugPrivilege", TRUE)) {
		shell = open_shell_token ();
		set_privilege (L"SeDebugPrivilege", FALSE);
	}
	if (shell != NULL) {
		if (copy_local_app_data (shell, profile->local_app_data, MAX_PATH)) {
			profile->token = shell;
			return TRUE;
		}
		CloseHandle (shell);
	}

	profile->token = linked_unelevated_token ();
	if (profile->token != NULL
	    && copy_local_app_data (profile->token, profile->local_app_data, MAX_PATH)) {
		return TRUE;
	}
	browser_profile_close (profile);
	fprintf (stderr, "webview2gtk: elevated host could not resolve the interactive LocalAppData\n");
	return FALSE;
}

static BOOL
append_path (wchar_t *dest, size_t dest_cch, const wchar_t *base, const wchar_t *rest)
{
	int n;

	if (dest == NULL || dest_cch == 0 || base == NULL || rest == NULL) {
		return FALSE;
	}
	n = _snwprintf (dest, dest_cch, L"%s\\%s", base, rest);
	if (n < 0 || (size_t) n >= dest_cch) {
		dest[dest_cch - 1] = L'\0';
		return FALSE;
	}
	return TRUE;
}

static BOOL
directory_is_present (int rc)
{
	return rc == ERROR_SUCCESS || rc == ERROR_ALREADY_EXISTS || rc == ERROR_FILE_EXISTS;
}

static BOOL
mark_medium_integrity (const wchar_t *path)
{
	PSECURITY_DESCRIPTOR sd = NULL;
	BOOL present = FALSE;
	BOOL defaulted = FALSE;
	PACL sacl = NULL;
	wchar_t mutable_path[MAX_PATH];
	BOOL turned_on;
	DWORD err;

	if (path == NULL || path[0] == L'\0' || wcslen (path) >= MAX_PATH) {
		return FALSE;
	}
	if (!ConvertStringSecurityDescriptorToSecurityDescriptorW (
		    L"S:(ML;;NW;;;ME)",
		    SDDL_REVISION_1,
		    &sd,
		    NULL)) {
		return FALSE;
	}
	if (!GetSecurityDescriptorSacl (sd, &present, &sacl, &defaulted) || !present || sacl == NULL) {
		LocalFree (sd);
		return FALSE;
	}
	wcsncpy (mutable_path, path, MAX_PATH);
	mutable_path[MAX_PATH - 1] = L'\0';
	/* Mandatory labels live in the SACL. */
	turned_on = set_privilege (L"SeSecurityPrivilege", TRUE);
	err = SetNamedSecurityInfoW (
		mutable_path,
		SE_FILE_OBJECT,
		LABEL_SECURITY_INFORMATION,
		NULL,
		NULL,
		NULL,
		sacl);
	if (turned_on) {
		set_privilege (L"SeSecurityPrivilege", FALSE);
	}
	LocalFree (sd);
	return err == ERROR_SUCCESS;
}

static BOOL
grant_token_user (HANDLE token, wchar_t *path)
{
	DWORD len = 0;
	TOKEN_USER *user = NULL;
	EXPLICIT_ACCESS_W access;
	PACL old_dacl = NULL;
	PACL new_dacl = NULL;
	PSECURITY_DESCRIPTOR sd = NULL;
	DWORD err;
	BOOL ok = FALSE;

	if (token == NULL || path == NULL) {
		return FALSE;
	}
	GetTokenInformation (token, TokenUser, NULL, 0, &len);
	if (len == 0) {
		return FALSE;
	}
	user = (TOKEN_USER *) CoTaskMemAlloc (len);
	if (user == NULL || !GetTokenInformation (token, TokenUser, user, len, &len)) {
		CoTaskMemFree (user);
		return FALSE;
	}
	ZeroMemory (&access, sizeof (access));
	access.grfAccessPermissions = GENERIC_ALL;
	access.grfAccessMode = GRANT_ACCESS;
	access.grfInheritance = SUB_CONTAINERS_AND_OBJECTS_INHERIT;
	access.Trustee.TrusteeForm = TRUSTEE_IS_SID;
	access.Trustee.TrusteeType = TRUSTEE_IS_USER;
	access.Trustee.ptstrName = (LPWSTR) user->User.Sid;
	err = GetNamedSecurityInfoW (
		path,
		SE_FILE_OBJECT,
		DACL_SECURITY_INFORMATION,
		NULL,
		NULL,
		&old_dacl,
		NULL,
		&sd);
	if (err == ERROR_SUCCESS) {
		err = SetEntriesInAclW (1, &access, old_dacl, &new_dacl);
	}
	if (err == ERROR_SUCCESS && new_dacl != NULL) {
		err = SetNamedSecurityInfoW (
			path,
			SE_FILE_OBJECT,
			DACL_SECURITY_INFORMATION,
			NULL,
			NULL,
			new_dacl,
			NULL);
		ok = (err == ERROR_SUCCESS);
	}
	if (new_dacl != NULL) {
		LocalFree (new_dacl);
	}
	if (sd != NULL) {
		LocalFree (sd);
	}
	CoTaskMemFree (user);
	return ok;
}

/* An elevated create is high IL. Label the leaf medium and grant the
 * interactive user, or the de-elevated browser cannot write it. */
static BOOL
repair_profile_tree (HANDLE token, const wchar_t *appdata, const wchar_t *leaf)
{
	wchar_t buf[MAX_PATH];
	size_t base;
	size_t n;
	BOOL leaf_ok;

	n = (leaf != NULL) ? wcslen (leaf) : 0;
	base = (appdata != NULL) ? wcslen (appdata) : 0;
	if (token == NULL || n == 0 || n >= MAX_PATH || base == 0 || base >= n) {
		return FALSE;
	}
	wcsncpy (buf, leaf, MAX_PATH);
	buf[MAX_PATH - 1] = L'\0';
	leaf_ok = mark_medium_integrity (buf) && grant_token_user (token, buf);
	for (;;) {
		wchar_t *slash;

		slash = wcsrchr (buf, L'\\');
		if (slash == NULL || (size_t) (slash - buf) <= base) {
			break;
		}
		*slash = L'\0';
		mark_medium_integrity (buf);
		grant_token_user (token, buf);
	}
	return leaf_ok;
}

static BOOL
create_profile_directory (BrowserProfile *profile, const wchar_t *path)
{
	int rc;
	BOOL impersonated = FALSE;

	rc = SHCreateDirectoryExW (NULL, path, NULL);
	/* Admin create is high IL. If that misses (another user's profile ACL),
	 * create as that user so the browser already owns a medium folder. */
	if (!directory_is_present (rc) && profile->token != NULL
	    && ImpersonateLoggedOnUser (profile->token)) {
		impersonated = TRUE;
		rc = SHCreateDirectoryExW (NULL, path, NULL);
		RevertToSelf ();
	}
	if (!directory_is_present (rc)) {
		fprintf (stderr, "webview2gtk: profile directory failed (%d): %ls\n", rc, path);
		return FALSE;
	}
	if (profile->token == NULL) {
		return TRUE;
	}
	if (repair_profile_tree (profile->token, profile->local_app_data, path) || impersonated) {
		return TRUE;
	}
	fprintf (stderr, "webview2gtk: profile directory is not writable by the interactive user: %ls\n", path);
	return FALSE;
}

static BOOL
make_host_user_data_folder (int route_id, wchar_t *out, size_t out_cch)
{
	BrowserProfile profile;
	wchar_t profiles[MAX_PATH];
	int n;
	BOOL ok = FALSE;

	if (out == NULL || out_cch < 8 || route_id <= 0) {
		return FALSE;
	}
	if (!open_browser_profile (&profile)) {
		return FALSE;
	}
	if (!append_path (profiles, MAX_PATH, profile.local_app_data, L"webview2gtk\\profiles")) {
		browser_profile_close (&profile);
		return FALSE;
	}
	if (!g_profiles_swept) {
		g_profiles_swept = TRUE;
		sweep_dead_profile_dirs (profiles);
	}
	/* pid + start tick: never reuse wv_<id>. A leftover browser process
	 * from the previous run holds that folder and env create hangs. */
	n = _snwprintf (
		out,
		out_cch,
		L"%s\\wv_%lu_%lu_%d",
		profiles,
		(unsigned long) GetCurrentProcessId (),
		(unsigned long) profile_token (),
		route_id
	);
	if (n < 0 || (size_t) n >= out_cch) {
		out[out_cch - 1] = L'\0';
		browser_profile_close (&profile);
		return FALSE;
	}
	ok = create_profile_directory (&profile, out);
	browser_profile_close (&profile);
	return ok;
}

static BOOL
make_shared_user_data_folder (wchar_t *out, size_t out_cch)
{
	BrowserProfile profile;
	BOOL ok = FALSE;

	if (!open_browser_profile (&profile)) {
		return FALSE;
	}
	if (!append_path (out, out_cch, profile.local_app_data, L"webview2gtk\\shared")) {
		browser_profile_close (&profile);
		return FALSE;
	}
	ok = create_profile_directory (&profile, out);
	browser_profile_close (&profile);
	return ok;
}

HRESULT vala_webview2_loader_create_environment_for_host (
	int route_id,
	struct ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler *handler)
{
	ICoreWebView2EnvironmentOptions *options = NULL;
	wchar_t folder[MAX_PATH];
	HRESULT hr;

	if (g_create_env_with_options == NULL || handler == NULL || route_id <= 0) {
		return E_FAIL;
	}
	if (!make_host_user_data_folder (route_id, folder, MAX_PATH)) {
		fprintf (stderr, "webview2gtk: local host proxy UserDataFolder failed for route %d\n", route_id);
		return E_FAIL;
	}
	fprintf (stderr, "webview2gtk: local host proxy UserDataFolder %ls\n", folder);
	options = vala_webview2_host_create_environment_options_for_route (route_id);
	hr = g_create_env_with_options (NULL, folder, options, handler);
	if (options != NULL) {
		ICoreWebView2EnvironmentOptions_Release (options);
	}
	return hr;
}
