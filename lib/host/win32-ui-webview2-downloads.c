/* Downloads: ICoreWebView2_4 DownloadStarting + WinHTTP for download_uri. */

#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winhttp.h>
#include <shlobj.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <shlwapi.h>

#include "webview2gtk-host-api.h"
#include "win32-ui-webview2-downloads.h"
#include "win32-ui-webview2-com-glue.h"
#include "win32-ui-webview2-sdk.h"

#define MAX_JOBS 64
#define JOB_HTTP 0
#define JOB_NATIVE 1

typedef struct DownloadJob DownloadJob;

typedef struct {
	ICoreWebView2DownloadStartingEventHandler iface;
	ICoreWebView2DownloadStartingEventHandlerVtbl vtbl;
	LONG ref_count;
} StartingHandler;

typedef struct {
	ICoreWebView2BytesReceivedChangedEventHandler iface;
	ICoreWebView2BytesReceivedChangedEventHandlerVtbl vtbl;
	LONG ref_count;
	int job_id;
} BytesHandler;

typedef struct {
	ICoreWebView2StateChangedEventHandler iface;
	ICoreWebView2StateChangedEventHandlerVtbl vtbl;
	LONG ref_count;
	int job_id;
} StateHandler;

struct DownloadJob {
	int id;
	int kind;
	char *uri;
	char *suggested;
	char *mime;
	INT64 content_length;
	char *dest;
	BOOL overwrite;
	BOOL started;
	volatile LONG cancelled;
	volatile LONG terminal;
	ICoreWebView2DownloadStartingEventArgs *args;
	ICoreWebView2Deferral *deferral;
	ICoreWebView2DownloadOperation *op;
	EventRegistrationToken bytes_token;
	EventRegistrationToken state_token;
	BOOL op_events;
	BytesHandler *bytes_handler;
	StateHandler *state_handler;
	HANDLE thread;
};

static DownloadJob *g_jobs[MAX_JOBS];
static volatile LONG g_next_id = 1;
static EventRegistrationToken g_start_token;
static BOOL g_start_registered;
static StartingHandler *g_start_handler;

static WebView2GtkDownloadStartedCb g_started_cb;
static WebView2GtkDownloadProgressCb g_progress_cb;
static WebView2GtkDownloadFinishedCb g_finished_cb;
static WebView2GtkDownloadFailedCb g_failed_cb;
static void *g_cb_ctx;

static DownloadJob *
job_find (int id)
{
	int i;

	for (i = 0; i < MAX_JOBS; i++) {
		if (g_jobs[i] != NULL && g_jobs[i]->id == id) {
			return g_jobs[i];
		}
	}
	return NULL;
}

static int
job_slot (void)
{
	int i;

	for (i = 0; i < MAX_JOBS; i++) {
		if (g_jobs[i] == NULL) {
			return i;
		}
	}
	return -1;
}

static void
job_free (DownloadJob *job)
{
	if (job == NULL) {
		return;
	}
	free (job->uri);
	free (job->suggested);
	free (job->mime);
	free (job->dest);
	if (job->args != NULL) {
		ICoreWebView2DownloadStartingEventArgs_Release (job->args);
	}
	if (job->deferral != NULL) {
		ICoreWebView2Deferral_Release (job->deferral);
	}
	if (job->op != NULL) {
		if (job->op_events) {
			ICoreWebView2DownloadOperation_remove_BytesReceivedChanged (
				job->op, job->bytes_token);
			ICoreWebView2DownloadOperation_remove_StateChanged (
				job->op, job->state_token);
		}
		ICoreWebView2DownloadOperation_Release (job->op);
	}
	if (job->bytes_handler != NULL) {
		ICoreWebView2BytesReceivedChangedEventHandler_Release (
			&job->bytes_handler->iface);
	}
	if (job->state_handler != NULL) {
		ICoreWebView2StateChangedEventHandler_Release (
			&job->state_handler->iface);
	}
	if (job->thread != NULL && job->thread != INVALID_HANDLE_VALUE) {
		CloseHandle (job->thread);
	}
	free (job);
}

static void
job_remove (int id)
{
	int i;

	for (i = 0; i < MAX_JOBS; i++) {
		if (g_jobs[i] != NULL && g_jobs[i]->id == id) {
			job_free (g_jobs[i]);
			g_jobs[i] = NULL;
			return;
		}
	}
}

static char *
basename_from_path_utf8 (const char *path)
{
	const char *base;
	const char *p;

	if (path == NULL || path[0] == '\0') {
		return strdup ("download");
	}
	base = path;
	for (p = path; *p != '\0'; p++) {
		if (*p == '/' || *p == '\\') {
			base = p + 1;
		}
	}
	if (base[0] == '\0') {
		return strdup ("download");
	}
	return strdup (base);
}

static char *
cookie_header_from_jar (const char *uri)
{
	char *raw = NULL;
	char *out = NULL;
	size_t len = 0;
	size_t cap = 0;
	char *p;
	char *line_start;

	if (!vala_webview2_host_get_cookies_sync (uri, &raw) || raw == NULL) {
		return strdup ("");
	}
	p = raw;
	while (*p != '\0') {
		char *semi;
		size_t part;

		line_start = p;
		while (*p != '\0' && *p != '\n' && *p != '\r') {
			p++;
		}
		while (*line_start == ' ' || *line_start == '\t') {
			line_start++;
		}
		if (line_start < p) {
			semi = line_start;
			while (semi < p && *semi != ';') {
				semi++;
			}
			part = (size_t) (semi - line_start);
			if (part > 0) {
				if (len > 0) {
					if (len + 2 > cap) {
						cap = cap == 0 ? 256 : cap * 2;
						out = realloc (out, cap);
					}
					out[len++] = ';';
					out[len++] = ' ';
					out[len] = '\0';
				}
				if (len + part + 1 > cap) {
					cap = (len + part + 1) * 2;
					out = realloc (out, cap);
				}
				memcpy (out + len, line_start, part);
				len += part;
				out[len] = '\0';
			}
		}
		while (*p == '\n' || *p == '\r') {
			p++;
		}
	}
	free (raw);
	return out != NULL ? out : strdup ("");
}

static void
emit_failed (DownloadJob *job, const char *message)
{
	if (InterlockedExchange (&job->terminal, 1) != 0) {
		return;
	}
	if (g_failed_cb != NULL) {
		g_failed_cb (job->id, message != NULL ? message : "download failed", g_cb_ctx);
	}
	job_remove (job->id);
}

static void
emit_finished (DownloadJob *job)
{
	if (InterlockedExchange (&job->terminal, 1) != 0) {
		return;
	}
	if (g_finished_cb != NULL) {
		g_finished_cb (job->id, g_cb_ctx);
	}
	job_remove (job->id);
}

static void
emit_progress (DownloadJob *job, UINT64 received)
{
	if (job->terminal) {
		return;
	}
	if (g_progress_cb != NULL) {
		g_progress_cb (job->id, (uint64_t) received, g_cb_ctx);
	}
}

/* ---- DownloadOperation event handlers ---- */

static HRESULT STDMETHODCALLTYPE
bytes_qi (ICoreWebView2BytesReceivedChangedEventHandler *This, REFIID riid, void **ppv)
{
	if (IsEqualIID (riid, &IID_IUnknown)
	    || IsEqualIID (riid, &IID_ICoreWebView2BytesReceivedChangedEventHandler)) {
		*ppv = This;
		ICoreWebView2BytesReceivedChangedEventHandler_AddRef (This);
		return S_OK;
	}
	*ppv = NULL;
	return E_NOINTERFACE;
}

static ULONG STDMETHODCALLTYPE
bytes_addref (ICoreWebView2BytesReceivedChangedEventHandler *This)
{
	BytesHandler *self = (BytesHandler *) This;
	return (ULONG) InterlockedIncrement (&self->ref_count);
}

static ULONG STDMETHODCALLTYPE
bytes_release (ICoreWebView2BytesReceivedChangedEventHandler *This)
{
	BytesHandler *self = (BytesHandler *) This;
	LONG count = InterlockedDecrement (&self->ref_count);
	if (count == 0) {
		CoTaskMemFree (self);
	}
	return (ULONG) count;
}

static HRESULT STDMETHODCALLTYPE
bytes_invoke (
	ICoreWebView2BytesReceivedChangedEventHandler *This,
	ICoreWebView2DownloadOperation *sender,
	IUnknown *args)
{
	BytesHandler *self = (BytesHandler *) This;
	DownloadJob *job;
	INT64 received = 0;

	(void) args;
	job = job_find (self->job_id);
	if (job == NULL || sender == NULL) {
		return S_OK;
	}
	if (SUCCEEDED (ICoreWebView2DownloadOperation_get_BytesReceived (sender, &received))) {
		emit_progress (job, (UINT64) received);
	}
	return S_OK;
}

static HRESULT STDMETHODCALLTYPE
state_qi (ICoreWebView2StateChangedEventHandler *This, REFIID riid, void **ppv)
{
	if (IsEqualIID (riid, &IID_IUnknown)
	    || IsEqualIID (riid, &IID_ICoreWebView2StateChangedEventHandler)) {
		*ppv = This;
		ICoreWebView2StateChangedEventHandler_AddRef (This);
		return S_OK;
	}
	*ppv = NULL;
	return E_NOINTERFACE;
}

static ULONG STDMETHODCALLTYPE
state_addref (ICoreWebView2StateChangedEventHandler *This)
{
	StateHandler *self = (StateHandler *) This;
	return (ULONG) InterlockedIncrement (&self->ref_count);
}

static ULONG STDMETHODCALLTYPE
state_release (ICoreWebView2StateChangedEventHandler *This)
{
	StateHandler *self = (StateHandler *) This;
	LONG count = InterlockedDecrement (&self->ref_count);
	if (count == 0) {
		CoTaskMemFree (self);
	}
	return (ULONG) count;
}

static HRESULT STDMETHODCALLTYPE
state_invoke (
	ICoreWebView2StateChangedEventHandler *This,
	ICoreWebView2DownloadOperation *sender,
	IUnknown *args)
{
	StateHandler *self = (StateHandler *) This;
	DownloadJob *job;
	COREWEBVIEW2_DOWNLOAD_STATE state = COREWEBVIEW2_DOWNLOAD_STATE_IN_PROGRESS;

	(void) args;
	job = job_find (self->job_id);
	if (job == NULL || sender == NULL) {
		return S_OK;
	}
	if (FAILED (ICoreWebView2DownloadOperation_get_State (sender, &state))) {
		return S_OK;
	}
	if (state == COREWEBVIEW2_DOWNLOAD_STATE_COMPLETED) {
		INT64 received = 0;
		ICoreWebView2DownloadOperation_get_BytesReceived (sender, &received);
		emit_progress (job, (UINT64) received);
		emit_finished (job);
	} else if (state == COREWEBVIEW2_DOWNLOAD_STATE_INTERRUPTED) {
		if (job->cancelled) {
			emit_failed (job, "Download cancelled");
		} else {
			emit_failed (job, "Download interrupted");
		}
	}
	return S_OK;
}

static bool
wire_operation_events (DownloadJob *job)
{
	HRESULT hr;

	if (job->op == NULL) {
		return false;
	}
	job->bytes_handler = (BytesHandler *) CoTaskMemAlloc (sizeof (BytesHandler));
	job->state_handler = (StateHandler *) CoTaskMemAlloc (sizeof (StateHandler));
	if (job->bytes_handler == NULL || job->state_handler == NULL) {
		return false;
	}
	ZeroMemory (job->bytes_handler, sizeof (*job->bytes_handler));
	ZeroMemory (job->state_handler, sizeof (*job->state_handler));
	job->bytes_handler->iface.lpVtbl = &job->bytes_handler->vtbl;
	job->bytes_handler->vtbl.QueryInterface = bytes_qi;
	job->bytes_handler->vtbl.AddRef = bytes_addref;
	job->bytes_handler->vtbl.Release = bytes_release;
	job->bytes_handler->vtbl.Invoke = bytes_invoke;
	job->bytes_handler->ref_count = 1;
	job->bytes_handler->job_id = job->id;

	job->state_handler->iface.lpVtbl = &job->state_handler->vtbl;
	job->state_handler->vtbl.QueryInterface = state_qi;
	job->state_handler->vtbl.AddRef = state_addref;
	job->state_handler->vtbl.Release = state_release;
	job->state_handler->vtbl.Invoke = state_invoke;
	job->state_handler->ref_count = 1;
	job->state_handler->job_id = job->id;

	hr = ICoreWebView2DownloadOperation_add_BytesReceivedChanged (
		job->op, &job->bytes_handler->iface, &job->bytes_token);
	if (FAILED (hr)) {
		return false;
	}
	hr = ICoreWebView2DownloadOperation_add_StateChanged (
		job->op, &job->state_handler->iface, &job->state_token);
	if (FAILED (hr)) {
		return false;
	}
	job->op_events = TRUE;
	return true;
}

/* ---- WinHTTP tool-path transfer ---- */

static DWORD WINAPI
http_transfer_thread (LPVOID param)
{
	DownloadJob *job = (DownloadJob *) param;
	URL_COMPONENTS uc;
	wchar_t host[256];
	wchar_t path[2048];
	wchar_t extra[1024];
	uint16_t *uri_wide = NULL;
	uint16_t *dest_wide = NULL;
	HINTERNET session = NULL;
	HINTERNET connect = NULL;
	HINTERNET request = NULL;
	char *cookie_hdr = NULL;
	uint16_t *cookie_wide = NULL;
	DWORD status = 0;
	DWORD status_size = sizeof (status);
	HANDLE file = INVALID_HANDLE_VALUE;
	BYTE buf[65536];
	DWORD read = 0;
	UINT64 received = 0;
	BOOL ok = FALSE;

	ZeroMemory (&uc, sizeof (uc));
	uc.dwStructSize = sizeof (uc);
	uc.lpszHostName = host;
	uc.dwHostNameLength = ARRAYSIZE (host);
	uc.lpszUrlPath = path;
	uc.dwUrlPathLength = ARRAYSIZE (path);
	uc.lpszExtraInfo = extra;
	uc.dwExtraInfoLength = ARRAYSIZE (extra);

	uri_wide = win32_ui_utf8_to_utf16 (job->uri, NULL);
	if (uri_wide == NULL
	    || !WinHttpCrackUrl ((LPCWSTR) uri_wide, 0, 0, &uc)) {
		emit_failed (job, "Invalid URL");
		goto out;
	}

	{
		char *parent;
		char *slash;
		parent = strdup (job->dest);
		if (parent != NULL) {
			slash = strrchr (parent, '\\');
			if (slash == NULL) {
				slash = strrchr (parent, '/');
			}
			if (slash != NULL) {
				*slash = '\0';
				if (parent[0] != '\0') {
					SHCreateDirectoryExA (NULL, parent, NULL);
				}
			}
			free (parent);
		}
	}

	if (!job->overwrite && GetFileAttributesA (job->dest) != INVALID_FILE_ATTRIBUTES) {
		emit_failed (job, "File exists");
		goto out;
	}

	session = WinHttpOpen (L"webview2gtk/1.0",
	                       WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
	                       WINHTTP_NO_PROXY_NAME,
	                       WINHTTP_NO_PROXY_BYPASS, 0);
	if (session == NULL) {
		emit_failed (job, "WinHttpOpen failed");
		goto out;
	}
	connect = WinHttpConnect (session, host, uc.nPort, 0);
	if (connect == NULL) {
		emit_failed (job, "WinHttpConnect failed");
		goto out;
	}
	{
		wchar_t full_path[3072];
		_snwprintf (full_path, ARRAYSIZE (full_path), L"%s%s", path, extra);
		request = WinHttpOpenRequest (
			connect, L"GET", full_path, NULL,
			WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES,
			(uc.nScheme == INTERNET_SCHEME_HTTPS) ? WINHTTP_FLAG_SECURE : 0);
	}
	if (request == NULL) {
		emit_failed (job, "WinHttpOpenRequest failed");
		goto out;
	}

	cookie_hdr = cookie_header_from_jar (job->uri);
	if (cookie_hdr != NULL && cookie_hdr[0] != '\0') {
		cookie_wide = win32_ui_utf8_to_utf16 (cookie_hdr, NULL);
		if (cookie_wide != NULL) {
			wchar_t header[8192];
			_snwprintf (header, ARRAYSIZE (header), L"Cookie: %s\r\n",
			            (wchar_t *) cookie_wide);
			WinHttpAddRequestHeaders (request, header, (ULONG) -1L,
			                          WINHTTP_ADDREQ_FLAG_ADD);
		}
	}

	if (!WinHttpSendRequest (request, WINHTTP_NO_ADDITIONAL_HEADERS, 0,
	                         WINHTTP_NO_REQUEST_DATA, 0, 0, 0)
	    || !WinHttpReceiveResponse (request, NULL)) {
		emit_failed (job, "HTTP request failed");
		goto out;
	}
	if (job->cancelled) {
		emit_failed (job, "Download cancelled");
		goto out;
	}
	if (!WinHttpQueryHeaders (request,
	                          WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
	                          WINHTTP_HEADER_NAME_BY_INDEX, &status, &status_size,
	                          WINHTTP_NO_HEADER_INDEX)
	    || status < 200 || status >= 300) {
		char msg[64];
		snprintf (msg, sizeof (msg), "HTTP %lu", (unsigned long) status);
		emit_failed (job, msg);
		goto out;
	}

	dest_wide = win32_ui_utf8_to_utf16 (job->dest, NULL);
	file = CreateFileW ((LPCWSTR) dest_wide, GENERIC_WRITE, 0, NULL,
	                    CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
	if (file == INVALID_HANDLE_VALUE) {
		emit_failed (job, "Cannot create destination file");
		goto out;
	}

	ok = TRUE;
	while (WinHttpReadData (request, buf, sizeof (buf), &read) && read > 0) {
		DWORD written = 0;
		if (job->cancelled) {
			ok = FALSE;
			emit_failed (job, "Download cancelled");
			break;
		}
		if (!WriteFile (file, buf, read, &written, NULL) || written != read) {
			ok = FALSE;
			emit_failed (job, "Write failed");
			break;
		}
		received += read;
		emit_progress (job, received);
	}
	CloseHandle (file);
	file = INVALID_HANDLE_VALUE;
	if (ok && !job->cancelled && !job->terminal) {
		emit_progress (job, received);
		emit_finished (job);
	} else if (ok && job->cancelled) {
		DeleteFileA (job->dest);
	}

out:
	if (file != INVALID_HANDLE_VALUE) {
		CloseHandle (file);
	}
	if (request != NULL) {
		WinHttpCloseHandle (request);
	}
	if (connect != NULL) {
		WinHttpCloseHandle (connect);
	}
	if (session != NULL) {
		WinHttpCloseHandle (session);
	}
	free (uri_wide);
	free (dest_wide);
	free (cookie_hdr);
	free (cookie_wide);
	return 0;
}

static DownloadJob *
job_alloc_http (const char *uri, const char *suggested, const char *mime, INT64 content_length)
{
	int slot;
	DownloadJob *job;

	slot = job_slot ();
	if (slot < 0 || uri == NULL || uri[0] == '\0') {
		return NULL;
	}
	job = (DownloadJob *) calloc (1, sizeof (DownloadJob));
	if (job == NULL) {
		return NULL;
	}
	job->id = (int) InterlockedIncrement (&g_next_id);
	job->kind = JOB_HTTP;
	job->uri = strdup (uri);
	job->suggested = strdup (suggested != NULL && suggested[0] != '\0' ? suggested : "download");
	job->mime = strdup (mime != NULL ? mime : "");
	job->content_length = content_length;
	if (job->uri == NULL || job->suggested == NULL || job->mime == NULL) {
		job_free (job);
		return NULL;
	}
	g_jobs[slot] = job;
	return job;
}

/* ---- DownloadStarting ---- */

static HRESULT STDMETHODCALLTYPE
start_qi (ICoreWebView2DownloadStartingEventHandler *This, REFIID riid, void **ppv)
{
	if (IsEqualIID (riid, &IID_IUnknown)
	    || IsEqualIID (riid, &IID_ICoreWebView2DownloadStartingEventHandler)) {
		*ppv = This;
		ICoreWebView2DownloadStartingEventHandler_AddRef (This);
		return S_OK;
	}
	*ppv = NULL;
	return E_NOINTERFACE;
}

static ULONG STDMETHODCALLTYPE
start_addref (ICoreWebView2DownloadStartingEventHandler *This)
{
	StartingHandler *self = (StartingHandler *) This;
	return (ULONG) InterlockedIncrement (&self->ref_count);
}

static ULONG STDMETHODCALLTYPE
start_release (ICoreWebView2DownloadStartingEventHandler *This)
{
	StartingHandler *self = (StartingHandler *) This;
	LONG count = InterlockedDecrement (&self->ref_count);
	if (count == 0) {
		CoTaskMemFree (self);
	}
	return (ULONG) count;
}

static HRESULT STDMETHODCALLTYPE
start_invoke (
	ICoreWebView2DownloadStartingEventHandler *This,
	ICoreWebView2 *sender,
	ICoreWebView2DownloadStartingEventArgs *args)
{
	int slot;
	DownloadJob *job;
	ICoreWebView2Deferral *deferral = NULL;
	ICoreWebView2DownloadOperation *op = NULL;
	LPWSTR uri_w = NULL;
	LPWSTR path_w = NULL;
	LPWSTR mime_w = NULL;
	char *uri = NULL;
	char *suggested = NULL;
	char *mime = NULL;
	INT64 total = -1;

	(void) This;
	(void) sender;

	if (args == NULL) {
		return S_OK;
	}
	slot = job_slot ();
	if (slot < 0) {
		ICoreWebView2DownloadStartingEventArgs_put_Cancel (args, TRUE);
		return S_OK;
	}
	if (FAILED (ICoreWebView2DownloadStartingEventArgs_GetDeferral (args, &deferral))
	    || deferral == NULL) {
		return S_OK;
	}
	ICoreWebView2DownloadStartingEventArgs_put_Handled (args, TRUE);
	ICoreWebView2DownloadStartingEventArgs_get_DownloadOperation (args, &op);
	ICoreWebView2DownloadStartingEventArgs_get_ResultFilePath (args, &path_w);
	if (op != NULL) {
		ICoreWebView2DownloadOperation_get_Uri (op, &uri_w);
		ICoreWebView2DownloadOperation_get_MimeType (op, &mime_w);
		ICoreWebView2DownloadOperation_get_TotalBytesToReceive (op, &total);
	}
	uri = uri_w != NULL
		? win32_ui_utf16_to_utf8 ((uint16_t *) uri_w, (int) wcslen (uri_w) + 1)
		: strdup ("");
	if (path_w != NULL) {
		char *full = win32_ui_utf16_to_utf8 ((uint16_t *) path_w, (int) wcslen (path_w) + 1);
		suggested = basename_from_path_utf8 (full);
		free (full);
	} else {
		suggested = basename_from_path_utf8 (uri);
	}
	mime = mime_w != NULL
		? win32_ui_utf16_to_utf8 ((uint16_t *) mime_w, (int) wcslen (mime_w) + 1)
		: strdup ("");
	CoTaskMemFree (uri_w);
	CoTaskMemFree (path_w);
	CoTaskMemFree (mime_w);

	job = (DownloadJob *) calloc (1, sizeof (DownloadJob));
	if (job == NULL || uri == NULL || suggested == NULL || mime == NULL) {
		free (uri);
		free (suggested);
		free (mime);
		ICoreWebView2DownloadStartingEventArgs_put_Cancel (args, TRUE);
		ICoreWebView2Deferral_Complete (deferral);
		ICoreWebView2Deferral_Release (deferral);
		if (op != NULL) {
			ICoreWebView2DownloadOperation_Release (op);
		}
		free (job);
		return S_OK;
	}
	job->id = (int) InterlockedIncrement (&g_next_id);
	job->kind = JOB_NATIVE;
	job->uri = uri;
	job->suggested = suggested;
	job->mime = mime;
	job->content_length = total;
	job->args = args;
	ICoreWebView2DownloadStartingEventArgs_AddRef (args);
	job->deferral = deferral;
	job->op = op;
	g_jobs[slot] = job;

	if (g_started_cb != NULL) {
		g_started_cb (job->id, job->uri, job->suggested, job->mime,
		              job->content_length, g_cb_ctx);
	}
	return S_OK;
}

void
vala_webview2_host_set_download_handlers (
	WebView2GtkDownloadStartedCb started,
	WebView2GtkDownloadProgressCb progress,
	WebView2GtkDownloadFinishedCb finished,
	WebView2GtkDownloadFailedCb failed,
	void *user_data)
{
	g_started_cb = started;
	g_progress_cb = progress;
	g_finished_cb = finished;
	g_failed_cb = failed;
	g_cb_ctx = user_data;
}

int
vala_webview2_host_download_create (const char *uri)
{
	DownloadJob *job;
	char *suggested;

	if (uri == NULL || uri[0] == '\0') {
		return 0;
	}
	suggested = basename_from_path_utf8 (uri);
	job = job_alloc_http (uri, suggested, "", -1);
	free (suggested);
	return job != NULL ? job->id : 0;
}

bool
vala_webview2_host_download_start (int id, const char *dest_path, bool overwrite)
{
	DownloadJob *job;
	uint16_t *path_wide;

	job = job_find (id);
	if (job == NULL || dest_path == NULL || dest_path[0] == '\0' || job->started
	    || job->terminal) {
		return false;
	}
	job->dest = strdup (dest_path);
	job->overwrite = overwrite ? TRUE : FALSE;
	job->started = TRUE;
	if (job->dest == NULL) {
		return false;
	}

	if (job->kind == JOB_NATIVE) {
		if (job->args == NULL || job->deferral == NULL) {
			emit_failed (job, "download start failed");
			return false;
		}
		path_wide = win32_ui_utf8_to_utf16 (dest_path, NULL);
		if (path_wide == NULL) {
			emit_failed (job, "download start failed");
			return false;
		}
		ICoreWebView2DownloadStartingEventArgs_put_ResultFilePath (
			job->args, (LPCWSTR) path_wide);
		free (path_wide);
		if (!wire_operation_events (job)) {
			ICoreWebView2DownloadStartingEventArgs_put_Cancel (job->args, TRUE);
			ICoreWebView2Deferral_Complete (job->deferral);
			emit_failed (job, "download start failed");
			return false;
		}
		ICoreWebView2Deferral_Complete (job->deferral);
		ICoreWebView2Deferral_Release (job->deferral);
		job->deferral = NULL;
		ICoreWebView2DownloadStartingEventArgs_Release (job->args);
		job->args = NULL;
		return true;
	}

	job->thread = CreateThread (NULL, 0, http_transfer_thread, job, 0, NULL);
	if (job->thread == NULL) {
		emit_failed (job, "Cannot start download thread");
		return false;
	}
	return true;
}

void
vala_webview2_host_download_cancel (int id)
{
	DownloadJob *job;

	job = job_find (id);
	if (job == NULL || job->terminal) {
		return;
	}
	InterlockedExchange (&job->cancelled, 1);
	if (job->kind == JOB_NATIVE) {
		if (!job->started && job->args != NULL && job->deferral != NULL) {
			ICoreWebView2DownloadStartingEventArgs_put_Cancel (job->args, TRUE);
			ICoreWebView2Deferral_Complete (job->deferral);
			ICoreWebView2Deferral_Release (job->deferral);
			job->deferral = NULL;
			ICoreWebView2DownloadStartingEventArgs_Release (job->args);
			job->args = NULL;
			emit_failed (job, "Download cancelled");
			return;
		}
		if (job->op != NULL) {
			ICoreWebView2DownloadOperation_Cancel (job->op);
		}
		return;
	}
	/* HTTP: thread notices cancelled flag */
}

void
vala_webview2_downloads_register (ICoreWebView2 *webview)
{
	ICoreWebView2_4 *webview4 = NULL;
	HRESULT hr;

	if (webview == NULL || g_start_registered) {
		return;
	}
	if (FAILED (ICoreWebView2_QueryInterface (webview, &IID_ICoreWebView2_4,
	                                          (void **) &webview4))
	    || webview4 == NULL) {
		fprintf (stderr, "WebView2 ICoreWebView2_4 unavailable — downloads disabled\n");
		return;
	}
	g_start_handler = (StartingHandler *) CoTaskMemAlloc (sizeof (StartingHandler));
	if (g_start_handler == NULL) {
		ICoreWebView2_4_Release (webview4);
		return;
	}
	ZeroMemory (g_start_handler, sizeof (*g_start_handler));
	g_start_handler->iface.lpVtbl = &g_start_handler->vtbl;
	g_start_handler->vtbl.QueryInterface = start_qi;
	g_start_handler->vtbl.AddRef = start_addref;
	g_start_handler->vtbl.Release = start_release;
	g_start_handler->vtbl.Invoke = start_invoke;
	g_start_handler->ref_count = 1;
	hr = ICoreWebView2_4_add_DownloadStarting (
		webview4, &g_start_handler->iface, &g_start_token);
	ICoreWebView2_4_Release (webview4);
	if (FAILED (hr)) {
		fprintf (stderr, "WebView2 add_DownloadStarting failed: 0x%08lx\n",
		         (unsigned long) hr);
		ICoreWebView2DownloadStartingEventHandler_Release (&g_start_handler->iface);
		g_start_handler = NULL;
		return;
	}
	g_start_registered = TRUE;
}

void
vala_webview2_downloads_unregister (ICoreWebView2 *webview)
{
	ICoreWebView2_4 *webview4 = NULL;
	int i;

	if (webview != NULL && g_start_registered
	    && SUCCEEDED (ICoreWebView2_QueryInterface (webview, &IID_ICoreWebView2_4,
	                                                (void **) &webview4))
	    && webview4 != NULL) {
		ICoreWebView2_4_remove_DownloadStarting (webview4, g_start_token);
		ICoreWebView2_4_Release (webview4);
		g_start_registered = FALSE;
	}
	if (g_start_handler != NULL) {
		ICoreWebView2DownloadStartingEventHandler_Release (&g_start_handler->iface);
		g_start_handler = NULL;
	}
	for (i = 0; i < MAX_JOBS; i++) {
		if (g_jobs[i] != NULL) {
			vala_webview2_host_download_cancel (g_jobs[i]->id);
		}
	}
}
