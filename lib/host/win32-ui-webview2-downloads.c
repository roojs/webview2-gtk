/* Download bridge — DownloadStarting + WinHTTP transfer (WebKitGTK-shaped). */

#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winhttp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

#include <glib.h>

#include "webview2gtk-host-api.h"
#include "win32-ui-webview2-downloads.h"
#include "win32-ui-webview2-com-glue.h"
#include "win32-ui-webview2-sdk.h"

typedef struct Wv2DownloadJob Wv2DownloadJob;

struct Wv2DownloadJob {
	gint id;
	char *uri;
	char *suggested;
	char *mime;
	gint64 content_length;
	char *user_agent;
	char *dest_path;
	gboolean overwrite;
	gboolean started;
	volatile LONG cancelled;
	HINTERNET request; /* set during transfer; closed on cancel */
};

typedef struct {
	gint id;
	char *uri;
	char *suggested;
	char *mime;
	gint64 content_length;
} Wv2DlStartedData;

typedef struct {
	gint id;
	guint64 received;
} Wv2DlProgressData;

typedef struct {
	gint id;
	char *message;
} Wv2DlFailedData;

static WebView2GtkDownloadStartedCb g_dl_started_cb = NULL;
static WebView2GtkDownloadProgressCb g_dl_progress_cb = NULL;
static WebView2GtkDownloadFinishedCb g_dl_finished_cb = NULL;
static WebView2GtkDownloadFailedCb g_dl_failed_cb = NULL;
static void *g_dl_user_data = NULL;

static GHashTable *g_jobs = NULL; /* id -> Wv2DownloadJob* */
static volatile LONG g_next_id = 0;
static gboolean g_dl_registered = FALSE;

typedef struct {
	ICoreWebView2DownloadStartingEventHandler iface;
	ICoreWebView2DownloadStartingEventHandlerVtbl vtbl;
	LONG ref_count;
} DownloadStartingHandler;

static DownloadStartingHandler *g_dl_handler = NULL;
static EventRegistrationToken g_dl_token;
static BOOL g_dl_token_set = FALSE;

static void
job_free (Wv2DownloadJob *job)
{
	if (job == NULL) {
		return;
	}
	g_free (job->uri);
	g_free (job->suggested);
	g_free (job->mime);
	g_free (job->user_agent);
	g_free (job->dest_path);
	g_free (job);
}

static void
ensure_jobs (void)
{
	if (g_jobs == NULL) {
		g_jobs = g_hash_table_new_full (g_direct_hash, g_direct_equal,
			NULL, (GDestroyNotify) job_free);
	}
}

static char *
wide_to_utf8_alloc (LPWSTR wide)
{
	char *utf8;

	if (wide == NULL) {
		return g_strdup ("");
	}
	utf8 = win32_ui_utf16_to_utf8 ((uint16_t *) wide, (int) wcslen (wide) + 1);
	return utf8 != NULL ? utf8 : g_strdup ("");
}

static char *
sanitize_filename (const char *name)
{
	GString *out;
	const char *p;

	if (name == NULL || name[0] == '\0') {
		return g_strdup ("download");
	}
	out = g_string_new (NULL);
	for (p = name; *p != '\0'; p++) {
		char c = *p;
		if (c == '\\' || c == '/' || c == ':' || c == '*' || c == '?'
		    || c == '"' || c == '<' || c == '>' || c == '|') {
			g_string_append_c (out, '_');
		} else {
			g_string_append_c (out, c);
		}
	}
	g_strstrip (out->str);
	if (out->str[0] == '\0'
	    || strcmp (out->str, ".") == 0
	    || strcmp (out->str, "..") == 0) {
		g_string_free (out, TRUE);
		return g_strdup ("download");
	}
	return g_string_free (out, FALSE);
}

static char *
basename_from_url (const char *uri)
{
	const char *path;
	const char *slash;
	char *leaf;
	char *q;
	char *clean;

	if (uri == NULL || uri[0] == '\0') {
		return g_strdup ("download");
	}
	path = strstr (uri, "://");
	if (path != NULL) {
		path += 3;
		path = strchr (path, '/');
		if (path == NULL) {
			return g_strdup ("download");
		}
	} else {
		path = uri;
	}
	slash = strrchr (path, '/');
	leaf = g_strdup (slash != NULL ? slash + 1 : path);
	q = strchr (leaf, '?');
	if (q != NULL) {
		*q = '\0';
	}
	q = strchr (leaf, '#');
	if (q != NULL) {
		*q = '\0';
	}
	if (leaf[0] == '\0') {
		g_free (leaf);
		return g_strdup ("download");
	}
	clean = sanitize_filename (leaf);
	g_free (leaf);
	return clean;
}

static char *
basename_from_path (const char *path)
{
	const char *slash;
	char *clean;

	if (path == NULL || path[0] == '\0') {
		return g_strdup ("download");
	}
	slash = strrchr (path, '\\');
	if (slash == NULL) {
		slash = strrchr (path, '/');
	}
	clean = sanitize_filename (slash != NULL ? slash + 1 : path);
	return clean;
}

static char *
cookie_header_for_uri (const char *uri)
{
	char *raw = NULL;
	GString *hdr;
	char **lines;
	guint i;

	if (uri == NULL || uri[0] == '\0') {
		return g_strdup ("");
	}
	if (!vala_webview2_host_get_cookies_sync (uri, &raw) || raw == NULL) {
		g_free (raw);
		return g_strdup ("");
	}
	hdr = g_string_new (NULL);
	lines = g_strsplit (raw, "\n", -1);
	g_free (raw);
	for (i = 0; lines != NULL && lines[i] != NULL; i++) {
		char *line = g_strstrip (lines[i]);
		char *semi;
		char *pair;

		if (line[0] == '\0') {
			continue;
		}
		semi = strchr (line, ';');
		if (semi != NULL) {
			*semi = '\0';
		}
		pair = g_strstrip (line);
		if (pair[0] == '\0' || strchr (pair, '=') == NULL) {
			continue;
		}
		if (hdr->len > 0) {
			g_string_append (hdr, "; ");
		}
		g_string_append (hdr, pair);
	}
	g_strfreev (lines);
	return g_string_free (hdr, FALSE);
}

static char *
current_user_agent (void)
{
	ICoreWebView2 *webview;
	ICoreWebView2Settings *settings = NULL;
	ICoreWebView2Settings2 *settings2 = NULL;
	LPWSTR ua_w = NULL;
	char *ua = NULL;
	HRESULT hr;

	webview = vala_webview2_com_get_webview ();
	if (webview == NULL) {
		return g_strdup ("");
	}
	hr = ICoreWebView2_get_Settings (webview, &settings);
	if (FAILED (hr) || settings == NULL) {
		return g_strdup ("");
	}
	hr = ICoreWebView2Settings_QueryInterface (settings, &IID_ICoreWebView2Settings2,
		(void **) &settings2);
	ICoreWebView2Settings_Release (settings);
	if (FAILED (hr) || settings2 == NULL) {
		return g_strdup ("");
	}
	hr = ICoreWebView2Settings2_get_UserAgent (settings2, &ua_w);
	ICoreWebView2Settings2_Release (settings2);
	if (FAILED (hr) || ua_w == NULL) {
		return g_strdup ("");
	}
	ua = wide_to_utf8_alloc (ua_w);
	CoTaskMemFree (ua_w);
	return ua;
}

static gboolean
emit_dl_started_idle (gpointer data)
{
	Wv2DlStartedData *d = data;

	if (g_dl_started_cb != NULL) {
		g_dl_started_cb (d->id, d->uri, d->suggested, d->mime,
			d->content_length, g_dl_user_data);
	}
	g_free (d->uri);
	g_free (d->suggested);
	g_free (d->mime);
	g_free (d);
	return G_SOURCE_REMOVE;
}

static gboolean
emit_dl_progress_idle (gpointer data)
{
	Wv2DlProgressData *d = data;

	if (g_dl_progress_cb != NULL) {
		g_dl_progress_cb (d->id, d->received, g_dl_user_data);
	}
	g_free (d);
	return G_SOURCE_REMOVE;
}

static gboolean
emit_dl_finished_idle (gpointer data)
{
	gint id = GPOINTER_TO_INT (data);

	if (g_dl_finished_cb != NULL) {
		g_dl_finished_cb (id, g_dl_user_data);
	}
	return G_SOURCE_REMOVE;
}

static gboolean
emit_dl_failed_idle (gpointer data)
{
	Wv2DlFailedData *d = data;

	if (g_dl_failed_cb != NULL) {
		g_dl_failed_cb (d->id,
			d->message != NULL ? d->message : "download failed",
			g_dl_user_data);
	}
	g_free (d->message);
	g_free (d);
	return G_SOURCE_REMOVE;
}

static void
queue_started (Wv2DownloadJob *job)
{
	Wv2DlStartedData *d;

	d = g_new0 (Wv2DlStartedData, 1);
	d->id = job->id;
	d->uri = g_strdup (job->uri != NULL ? job->uri : "");
	d->suggested = g_strdup (job->suggested != NULL ? job->suggested : "download");
	d->mime = g_strdup (job->mime != NULL ? job->mime : "");
	d->content_length = job->content_length;
	g_idle_add (emit_dl_started_idle, d);
}

static void
queue_progress (int id, guint64 received)
{
	Wv2DlProgressData *d;

	d = g_new0 (Wv2DlProgressData, 1);
	d->id = id;
	d->received = received;
	g_idle_add (emit_dl_progress_idle, d);
}

static void
queue_finished (int id)
{
	g_idle_add (emit_dl_finished_idle, GINT_TO_POINTER (id));
}

static void
queue_failed (int id, const char *message)
{
	Wv2DlFailedData *d;

	d = g_new0 (Wv2DlFailedData, 1);
	d->id = id;
	d->message = g_strdup (message != NULL ? message : "download failed");
	g_idle_add (emit_dl_failed_idle, d);
}

static Wv2DownloadJob *
job_create (const char *uri, const char *suggested, const char *mime,
	gint64 content_length, const char *user_agent)
{
	Wv2DownloadJob *job;

	ensure_jobs ();
	job = g_new0 (Wv2DownloadJob, 1);
	job->id = (gint) InterlockedIncrement (&g_next_id);
	if (job->id <= 0) {
		job->id = (gint) InterlockedIncrement (&g_next_id);
	}
	job->uri = g_strdup (uri != NULL ? uri : "");
	job->suggested = sanitize_filename (
		suggested != NULL && suggested[0] != '\0' ? suggested : "download");
	job->mime = g_strdup (mime != NULL ? mime : "");
	job->content_length = content_length;
	job->user_agent = g_strdup (user_agent != NULL ? user_agent : "");
	g_hash_table_insert (g_jobs, GINT_TO_POINTER (job->id), job);
	return job;
}

static gboolean
ensure_parent_dir (const char *dest_path)
{
	char *parent;
	char *p;
	gboolean ok = TRUE;

	parent = g_path_get_dirname (dest_path);
	if (parent == NULL || strcmp (parent, ".") == 0) {
		g_free (parent);
		return TRUE;
	}
	/* Walk and CreateDirectoryW for each segment. */
	for (p = parent + 1; *p != '\0'; p++) {
		if (*p == '/' || *p == '\\') {
			char save = *p;
			*p = '\0';
			if (parent[0] != '\0'
			    && !(parent[1] == ':' && parent[2] == '\0')) {
				wchar_t *parent_w = (wchar_t *) win32_ui_utf8_to_utf16 (parent, NULL);
				if (parent_w != NULL) {
					if (!CreateDirectoryW (parent_w, NULL)
					    && GetLastError () != ERROR_ALREADY_EXISTS) {
						ok = FALSE;
					}
					free (parent_w);
				} else {
					ok = FALSE;
				}
			}
			*p = save;
			if (!ok) {
				break;
			}
		}
	}
	if (ok) {
		wchar_t *parent_w = (wchar_t *) win32_ui_utf8_to_utf16 (parent, NULL);
		if (parent_w != NULL) {
			if (!CreateDirectoryW (parent_w, NULL)
			    && GetLastError () != ERROR_ALREADY_EXISTS) {
				ok = FALSE;
			}
			free (parent_w);
		} else {
			ok = FALSE;
		}
	}
	g_free (parent);
	return ok;
}

static void
delete_path_utf8 (const char *path)
{
	wchar_t *path_w;

	if (path == NULL || path[0] == '\0') {
		return;
	}
	path_w = (wchar_t *) win32_ui_utf8_to_utf16 (path, NULL);
	if (path_w == NULL) {
		return;
	}
	DeleteFileW (path_w);
	free (path_w);
}

static void
fail_and_remove (Wv2DownloadJob *job, const char *message)
{
	int id = job->id;

	queue_failed (id, message);
	if (g_jobs != NULL) {
		g_hash_table_remove (g_jobs, GINT_TO_POINTER (id));
	}
}

static DWORD WINAPI
transfer_thread (LPVOID param)
{
	Wv2DownloadJob *job = (Wv2DownloadJob *) param;
	URL_COMPONENTSW uc;
	wchar_t host[256];
	wchar_t path[2048];
	wchar_t extra[1024];
	HINTERNET session = NULL;
	HINTERNET connect = NULL;
	HINTERNET request = NULL;
	DWORD flags = 0;
	char *cookie_hdr = NULL;
	wchar_t *hdr_w = NULL;
	DWORD status = 0;
	DWORD status_size = sizeof (status);
	HANDLE file = INVALID_HANDLE_VALUE;
	BYTE buf[64 * 1024];
	DWORD read = 0;
	guint64 received = 0;
	guint64 last_report = 0;
	INTERNET_PORT port;
	wchar_t *uri_w = NULL;

	ZeroMemory (&uc, sizeof (uc));
	uc.dwStructSize = sizeof (uc);
	uc.lpszHostName = host;
	uc.dwHostNameLength = (DWORD) (sizeof (host) / sizeof (host[0]));
	uc.lpszUrlPath = path;
	uc.dwUrlPathLength = (DWORD) (sizeof (path) / sizeof (path[0]));
	uc.lpszExtraInfo = extra;
	uc.dwExtraInfoLength = (DWORD) (sizeof (extra) / sizeof (extra[0]));

	if (InterlockedCompareExchange (&job->cancelled, 0, 0) != 0) {
		fail_and_remove (job, "Download cancelled");
		return 0;
	}
	if (!ensure_parent_dir (job->dest_path)) {
		fail_and_remove (job, "Cannot create destination directory");
		return 0;
	}
	if (!job->overwrite && g_file_test (job->dest_path, G_FILE_TEST_EXISTS)) {
		fail_and_remove (job, "File exists");
		return 0;
	}
	uri_w = (wchar_t *) win32_ui_utf8_to_utf16 (job->uri, NULL);
	if (uri_w == NULL || !WinHttpCrackUrl (uri_w, 0, 0, &uc)) {
		free (uri_w);
		fail_and_remove (job, "Invalid download URL");
		return 0;
	}
	free (uri_w);
	if (uc.nScheme == INTERNET_SCHEME_HTTPS) {
		flags |= WINHTTP_FLAG_SECURE;
	} else if (uc.nScheme != INTERNET_SCHEME_HTTP) {
		fail_and_remove (job, "Unsupported URL scheme");
		return 0;
	}
	port = uc.nPort;
	session = WinHttpOpen (L"webview2gtk-download/1.0",
		WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
		WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
	if (session == NULL) {
		fail_and_remove (job, "WinHttpOpen failed");
		return 0;
	}
	connect = WinHttpConnect (session, host, port, 0);
	if (connect == NULL) {
		WinHttpCloseHandle (session);
		fail_and_remove (job, "WinHttpConnect failed");
		return 0;
	}
	{
		wchar_t path_full[3072];
		path_full[0] = L'\0';
		wcsncpy (path_full, path, 2047);
		path_full[2047] = L'\0';
		if (extra[0] != L'\0') {
			wcsncat (path_full, extra, 3071 - wcslen (path_full));
		}
		request = WinHttpOpenRequest (connect, L"GET", path_full, NULL,
			WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, flags);
	}
	if (request == NULL) {
		WinHttpCloseHandle (connect);
		WinHttpCloseHandle (session);
		fail_and_remove (job, "WinHttpOpenRequest failed");
		return 0;
	}
	job->request = request;

	cookie_hdr = cookie_header_for_uri (job->uri);
	{
		GString *hdr = g_string_new (NULL);
		if (job->user_agent != NULL && job->user_agent[0] != '\0') {
			g_string_append_printf (hdr, "User-Agent: %s\r\n", job->user_agent);
		}
		if (cookie_hdr != NULL && cookie_hdr[0] != '\0') {
			g_string_append_printf (hdr, "Cookie: %s\r\n", cookie_hdr);
		}
		if (hdr->len > 0) {
			hdr_w = (wchar_t *) win32_ui_utf8_to_utf16 (hdr->str, NULL);
			if (hdr_w != NULL) {
				WinHttpAddRequestHeaders (request, hdr_w, (DWORD) -1L,
					WINHTTP_ADDREQ_FLAG_ADD);
				free (hdr_w);
			}
		}
		g_string_free (hdr, TRUE);
	}
	g_free (cookie_hdr);

	if (!WinHttpSendRequest (request, WINHTTP_NO_ADDITIONAL_HEADERS, 0,
		WINHTTP_NO_REQUEST_DATA, 0, 0, 0)
	    || !WinHttpReceiveResponse (request, NULL)) {
		job->request = NULL;
		WinHttpCloseHandle (request);
		WinHttpCloseHandle (connect);
		WinHttpCloseHandle (session);
		if (InterlockedCompareExchange (&job->cancelled, 0, 0) != 0) {
			fail_and_remove (job, "Download cancelled");
		} else {
			fail_and_remove (job, "HTTP request failed");
		}
		return 0;
	}
	if (!WinHttpQueryHeaders (request,
		WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
		WINHTTP_HEADER_NAME_BY_INDEX, &status, &status_size,
		WINHTTP_NO_HEADER_INDEX)
	    || status < 200 || status >= 300) {
		char msg[64];

		g_snprintf (msg, sizeof (msg), "HTTP %lu", (unsigned long) status);
		job->request = NULL;
		WinHttpCloseHandle (request);
		WinHttpCloseHandle (connect);
		WinHttpCloseHandle (session);
		fail_and_remove (job, msg);
		return 0;
	}

	{
		wchar_t *path_w = (wchar_t *) win32_ui_utf8_to_utf16 (job->dest_path, NULL);
		if (path_w == NULL) {
			job->request = NULL;
			WinHttpCloseHandle (request);
			WinHttpCloseHandle (connect);
			WinHttpCloseHandle (session);
			fail_and_remove (job, "Destination encode failed");
			return 0;
		}
		file = CreateFileW (path_w, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS,
			FILE_ATTRIBUTE_NORMAL, NULL);
		free (path_w);
	}
	if (file == INVALID_HANDLE_VALUE) {
		job->request = NULL;
		WinHttpCloseHandle (request);
		WinHttpCloseHandle (connect);
		WinHttpCloseHandle (session);
		fail_and_remove (job, "Cannot open destination file");
		return 0;
	}

	for (;;) {
		if (InterlockedCompareExchange (&job->cancelled, 0, 0) != 0) {
			CloseHandle (file);
			delete_path_utf8 (job->dest_path);
			job->request = NULL;
			WinHttpCloseHandle (request);
			WinHttpCloseHandle (connect);
			WinHttpCloseHandle (session);
			fail_and_remove (job, "Download cancelled");
			return 0;
		}
		if (!WinHttpReadData (request, buf, sizeof (buf), &read)) {
			CloseHandle (file);
			delete_path_utf8 (job->dest_path);
			job->request = NULL;
			WinHttpCloseHandle (request);
			WinHttpCloseHandle (connect);
			WinHttpCloseHandle (session);
			fail_and_remove (job, "Read failed");
			return 0;
		}
		if (read == 0) {
			break;
		}
		{
			DWORD written = 0;
			if (!WriteFile (file, buf, read, &written, NULL)
			    || written != read) {
				CloseHandle (file);
				delete_path_utf8 (job->dest_path);
				job->request = NULL;
				WinHttpCloseHandle (request);
				WinHttpCloseHandle (connect);
				WinHttpCloseHandle (session);
				fail_and_remove (job, "Write failed");
				return 0;
			}
		}
		received += read;
		if (received - last_report >= 64 * 1024) {
			last_report = received;
			queue_progress (job->id, received);
		}
	}
	CloseHandle (file);
	queue_progress (job->id, received);
	job->request = NULL;
	WinHttpCloseHandle (request);
	WinHttpCloseHandle (connect);
	WinHttpCloseHandle (session);

	if (InterlockedCompareExchange (&job->cancelled, 0, 0) != 0) {
		delete_path_utf8 (job->dest_path);
		fail_and_remove (job, "Download cancelled");
		return 0;
	}
	{
		int id = job->id;
		queue_finished (id);
		if (g_jobs != NULL) {
			g_hash_table_remove (g_jobs, GINT_TO_POINTER (id));
		}
	}
	return 0;
}

static HRESULT STDMETHODCALLTYPE
dl_qi (ICoreWebView2DownloadStartingEventHandler *This, REFIID riid, void **ppv)
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
dl_addref (ICoreWebView2DownloadStartingEventHandler *This)
{
	DownloadStartingHandler *self = (DownloadStartingHandler *) This;
	return (ULONG) InterlockedIncrement (&self->ref_count);
}

static ULONG STDMETHODCALLTYPE
dl_release (ICoreWebView2DownloadStartingEventHandler *This)
{
	DownloadStartingHandler *self = (DownloadStartingHandler *) This;
	LONG count = InterlockedDecrement (&self->ref_count);
	if (count == 0) {
		CoTaskMemFree (self);
	}
	return (ULONG) count;
}

static HRESULT STDMETHODCALLTYPE
dl_invoke (ICoreWebView2DownloadStartingEventHandler *This,
	ICoreWebView2 *sender,
	ICoreWebView2DownloadStartingEventArgs *args)
{
	ICoreWebView2DownloadOperation *op = NULL;
	LPWSTR uri_w = NULL;
	LPWSTR mime_w = NULL;
	LPWSTR path_w = NULL;
	INT64 total = -1;
	char *uri = NULL;
	char *mime = NULL;
	char *suggested = NULL;
	char *ua = NULL;
	Wv2DownloadJob *job;

	(void) This;
	(void) sender;
	if (args == NULL) {
		return S_OK;
	}
	ICoreWebView2DownloadStartingEventArgs_put_Handled (args, TRUE);
	ICoreWebView2DownloadStartingEventArgs_put_Cancel (args, TRUE);

	if (FAILED (ICoreWebView2DownloadStartingEventArgs_get_DownloadOperation (
		args, &op))
	    || op == NULL) {
		return S_OK;
	}
	ICoreWebView2DownloadOperation_get_Uri (op, &uri_w);
	ICoreWebView2DownloadOperation_get_MimeType (op, &mime_w);
	ICoreWebView2DownloadOperation_get_ResultFilePath (op, &path_w);
	ICoreWebView2DownloadOperation_get_TotalBytesToReceive (op, &total);
	ICoreWebView2DownloadOperation_Release (op);

	uri = wide_to_utf8_alloc (uri_w);
	mime = wide_to_utf8_alloc (mime_w);
	if (path_w != NULL && path_w[0] != L'\0') {
		char *full = wide_to_utf8_alloc (path_w);
		suggested = basename_from_path (full);
		g_free (full);
	} else {
		suggested = basename_from_url (uri);
	}
	if (uri_w != NULL) {
		CoTaskMemFree (uri_w);
	}
	if (mime_w != NULL) {
		CoTaskMemFree (mime_w);
	}
	if (path_w != NULL) {
		CoTaskMemFree (path_w);
	}
	if (uri == NULL || uri[0] == '\0') {
		g_free (uri);
		g_free (mime);
		g_free (suggested);
		return S_OK;
	}
	ua = current_user_agent ();
	job = job_create (uri, suggested, mime, total >= 0 ? total : -1, ua);
	g_free (uri);
	g_free (mime);
	g_free (suggested);
	g_free (ua);
	queue_started (job);
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
	g_dl_started_cb = started;
	g_dl_progress_cb = progress;
	g_dl_finished_cb = finished;
	g_dl_failed_cb = failed;
	g_dl_user_data = user_data;
}

int
vala_webview2_host_download_create (const char *uri)
{
	Wv2DownloadJob *job;
	char *ua;
	char *suggested;

	if (uri == NULL || uri[0] == '\0') {
		return 0;
	}
	ua = current_user_agent ();
	suggested = basename_from_url (uri);
	job = job_create (uri, suggested, "", -1, ua);
	g_free (ua);
	g_free (suggested);
	return job->id;
}

bool
vala_webview2_host_download_start (int id, const char *dest_path, bool overwrite)
{
	Wv2DownloadJob *job;
	HANDLE thread;

	if (id <= 0 || dest_path == NULL || dest_path[0] == '\0') {
		return false;
	}
	ensure_jobs ();
	job = g_hash_table_lookup (g_jobs, GINT_TO_POINTER (id));
	if (job == NULL || job->started
	    || InterlockedCompareExchange (&job->cancelled, 0, 0) != 0) {
		return false;
	}
	job->dest_path = g_strdup (dest_path);
	job->overwrite = overwrite ? TRUE : FALSE;
	job->started = TRUE;
	thread = CreateThread (NULL, 0, transfer_thread, job, 0, NULL);
	if (thread == NULL) {
		job->started = FALSE;
		g_free (job->dest_path);
		job->dest_path = NULL;
		return false;
	}
	CloseHandle (thread);
	return true;
}

void
vala_webview2_host_download_cancel (int id)
{
	Wv2DownloadJob *job;

	if (id <= 0) {
		return;
	}
	ensure_jobs ();
	job = g_hash_table_lookup (g_jobs, GINT_TO_POINTER (id));
	if (job == NULL) {
		return;
	}
	InterlockedExchange (&job->cancelled, 1);
	if (job->request != NULL) {
		WinHttpCloseHandle (job->request);
		job->request = NULL;
	}
	if (!job->started) {
		g_hash_table_remove (g_jobs, GINT_TO_POINTER (id));
	}
}

void
vala_webview2_downloads_register (ICoreWebView2 *webview)
{
	HRESULT hr;
	ICoreWebView2_4 *webview4 = NULL;

	if (webview == NULL || g_dl_registered) {
		return;
	}
	hr = ICoreWebView2_QueryInterface (webview, &IID_ICoreWebView2_4,
		(void **) &webview4);
	if (FAILED (hr) || webview4 == NULL) {
		fprintf (stderr,
			"WebView2 QueryInterface ICoreWebView2_4 failed: 0x%08lx\n",
			(unsigned long) hr);
		return;
	}
	g_dl_handler = (DownloadStartingHandler *) CoTaskMemAlloc (
		sizeof (DownloadStartingHandler));
	if (g_dl_handler == NULL) {
		ICoreWebView2_4_Release (webview4);
		return;
	}
	ZeroMemory (g_dl_handler, sizeof (*g_dl_handler));
	g_dl_handler->iface.lpVtbl = &g_dl_handler->vtbl;
	g_dl_handler->vtbl.QueryInterface = dl_qi;
	g_dl_handler->vtbl.AddRef = dl_addref;
	g_dl_handler->vtbl.Release = dl_release;
	g_dl_handler->vtbl.Invoke = dl_invoke;
	g_dl_handler->ref_count = 1;
	hr = ICoreWebView2_4_add_DownloadStarting (webview4,
		(ICoreWebView2DownloadStartingEventHandler *) g_dl_handler,
		&g_dl_token);
	ICoreWebView2_4_Release (webview4);
	if (FAILED (hr)) {
		fprintf (stderr,
			"WebView2 add_DownloadStarting failed: 0x%08lx\n",
			(unsigned long) hr);
		ICoreWebView2DownloadStartingEventHandler_Release (
			(ICoreWebView2DownloadStartingEventHandler *) g_dl_handler);
		g_dl_handler = NULL;
		return;
	}
	g_dl_token_set = TRUE;
	g_dl_registered = TRUE;
}

void
vala_webview2_downloads_unregister (ICoreWebView2 *webview)
{
	ICoreWebView2_4 *webview4 = NULL;

	if (webview == NULL || !g_dl_token_set) {
		return;
	}
	if (SUCCEEDED (ICoreWebView2_QueryInterface (webview, &IID_ICoreWebView2_4,
		(void **) &webview4))
	    && webview4 != NULL) {
		ICoreWebView2_4_remove_DownloadStarting (webview4, g_dl_token);
		ICoreWebView2_4_Release (webview4);
	}
	g_dl_token_set = FALSE;
	g_dl_registered = FALSE;
	if (g_dl_handler != NULL) {
		ICoreWebView2DownloadStartingEventHandler_Release (
			(ICoreWebView2DownloadStartingEventHandler *) g_dl_handler);
		g_dl_handler = NULL;
	}
}
