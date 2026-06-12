/* WebView2Loader.dll bootstrap only (Phase 7i). */

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <objbase.h>
#include <stdio.h>

#include "win32-ui-webview2-loader.h"
#include "win32-ui-webview2-sdk.h"

typedef HRESULT (STDMETHODCALLTYPE *PFN_CreateCoreWebView2EnvironmentWithOptions)(
	PCWSTR browserExecutableFolder,
	PCWSTR userDataFolder,
	ICoreWebView2EnvironmentOptions *environmentOptions,
	ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler *environmentCreatedHandler);

static HMODULE g_loader_module;
static PFN_CreateCoreWebView2EnvironmentWithOptions g_create_env_with_options;
static BOOL g_com_inited;

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

HRESULT vala_webview2_loader_create_environment (
	struct ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler *handler)
{
	if (g_create_env_with_options == NULL || handler == NULL) {
		return E_FAIL;
	}
	return g_create_env_with_options (NULL, NULL, NULL, handler);
}
