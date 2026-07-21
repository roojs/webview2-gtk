/* WebView2 UIA accessibility — ControlView walk / invoke / set_value / focus. */

#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <oleauto.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <uiautomation.h>

#include "webview2gtk-host-api.h"
#include "win32-ui-webview2-a11y-diag.h"
#include "win32-ui-webview2-com-glue.h"
#include "win32-ui-webview2-sdk.h"

#define A11Y_MAX_DEPTH 20
#define A11Y_MAX_NODES 400
#define A11Y_MAX_HWNDS 64

typedef struct {
	HWND list[A11Y_MAX_HWNDS];
	int count;
} HwndList;

typedef struct {
	IUIAutomationElement **els;
	size_t count;
	size_t cap;
} A11yCache;

static A11yCache g_a11y_cache;

/* ---- string / buffer helpers ---- */

static char *
bstr_to_utf8 (BSTR wide)
{
	int wlen;
	int nbytes;
	char *utf8;

	if (wide == NULL) {
		return strdup ("");
	}
	wlen = (int) SysStringLen (wide);
	if (wlen <= 0) {
		return strdup ("");
	}
	nbytes = WideCharToMultiByte (CP_UTF8, 0, wide, wlen, NULL, 0, NULL, NULL);
	if (nbytes <= 0) {
		return strdup ("");
	}
	utf8 = malloc ((size_t) nbytes + 1);
	if (utf8 == NULL) {
		return NULL;
	}
	WideCharToMultiByte (CP_UTF8, 0, wide, wlen, utf8, nbytes, NULL, NULL);
	utf8[nbytes] = '\0';
	return utf8;
}

static char *
element_name_utf8 (IUIAutomationElement *el)
{
	BSTR name = NULL;
	char *out;

	if (FAILED (IUIAutomationElement_get_CurrentName (el, &name)) || name == NULL) {
		return strdup ("");
	}
	out = bstr_to_utf8 (name);
	SysFreeString (name);
	return out != NULL ? out : strdup ("");
}

static const char *
control_type_name (CONTROLTYPEID id)
{
	switch (id) {
	case UIA_ButtonControlTypeId: return "Button";
	case UIA_CheckBoxControlTypeId: return "CheckBox";
	case UIA_ComboBoxControlTypeId: return "ComboBox";
	case UIA_EditControlTypeId: return "Edit";
	case UIA_HyperlinkControlTypeId: return "Hyperlink";
	case UIA_ImageControlTypeId: return "Image";
	case UIA_ListItemControlTypeId: return "ListItem";
	case UIA_ListControlTypeId: return "List";
	case UIA_MenuItemControlTypeId: return "MenuItem";
	case UIA_RadioButtonControlTypeId: return "RadioButton";
	case UIA_ScrollBarControlTypeId: return "ScrollBar";
	case UIA_TabControlTypeId: return "Tab";
	case UIA_TabItemControlTypeId: return "TabItem";
	case UIA_TextControlTypeId: return "Text";
	case UIA_ToolBarControlTypeId: return "ToolBar";
	case UIA_CustomControlTypeId: return "Custom";
	case UIA_GroupControlTypeId: return "Group";
	case UIA_DataItemControlTypeId: return "DataItem";
	case UIA_DocumentControlTypeId: return "Document";
	case UIA_WindowControlTypeId: return "Window";
	case UIA_PaneControlTypeId: return "Pane";
	default: return NULL;
	}
}

static char *
element_role_utf8 (IUIAutomationElement *el)
{
	CONTROLTYPEID ctype = 0;
	const char *name;
	char buf[64];

	if (FAILED (IUIAutomationElement_get_CurrentControlType (el, &ctype))) {
		return strdup ("?");
	}
	name = control_type_name (ctype);
	if (name != NULL) {
		return strdup (name);
	}
	snprintf (buf, sizeof (buf), "ControlType=%ld", (long) ctype);
	return strdup (buf);
}

static char *
element_value_utf8 (IUIAutomationElement *el)
{
	IUnknown *unk = NULL;
	IUIAutomationValuePattern *vp = NULL;
	BSTR val = NULL;
	char *out = NULL;

	if (FAILED (IUIAutomationElement_GetCurrentPattern (el, UIA_ValuePatternId, &unk))
	    || unk == NULL) {
		return strdup ("");
	}
	if (FAILED (IUnknown_QueryInterface (unk, &IID_IUIAutomationValuePattern, (void **) &vp))
	    || vp == NULL) {
		IUnknown_Release (unk);
		return strdup ("");
	}
	IUnknown_Release (unk);
	if (SUCCEEDED (IUIAutomationValuePattern_get_CurrentValue (vp, &val)) && val != NULL) {
		out = bstr_to_utf8 (val);
		SysFreeString (val);
	}
	IUIAutomationValuePattern_Release (vp);
	return out != NULL ? out : strdup ("");
}

static bool
element_has_pattern (IUIAutomationElement *el, PATTERNID pattern)
{
	IUnknown *unk = NULL;
	bool ok;

	if (FAILED (IUIAutomationElement_GetCurrentPattern (el, pattern, &unk)) || unk == NULL) {
		return false;
	}
	ok = true;
	IUnknown_Release (unk);
	return ok;
}

static bool
element_value_writable (IUIAutomationElement *el)
{
	IUnknown *unk = NULL;
	IUIAutomationValuePattern *vp = NULL;
	BOOL readonly = TRUE;

	if (FAILED (IUIAutomationElement_GetCurrentPattern (el, UIA_ValuePatternId, &unk))
	    || unk == NULL) {
		return false;
	}
	if (FAILED (IUnknown_QueryInterface (unk, &IID_IUIAutomationValuePattern, (void **) &vp))
	    || vp == NULL) {
		IUnknown_Release (unk);
		return false;
	}
	IUnknown_Release (unk);
	if (FAILED (IUIAutomationValuePattern_get_CurrentIsReadOnly (vp, &readonly))) {
		readonly = TRUE;
	}
	IUIAutomationValuePattern_Release (vp);
	return !readonly;
}

static void
element_bounds_screen (IUIAutomationElement *el, int *x, int *y, int *w, int *h)
{
	RECT rc;

	*x = *y = *w = *h = 0;
	ZeroMemory (&rc, sizeof (rc));
	if (FAILED (IUIAutomationElement_get_CurrentBoundingRectangle (el, &rc))) {
		return;
	}
	*x = (int) rc.left;
	*y = (int) rc.top;
	*w = (int) (rc.right - rc.left);
	*h = (int) (rc.bottom - rc.top);
}

/* ---- cache (ids valid until next walk) ---- */

static void
a11y_cache_clear (void)
{
	size_t i;

	for (i = 0; i < g_a11y_cache.count; i++) {
		if (g_a11y_cache.els[i] != NULL) {
			IUIAutomationElement_Release (g_a11y_cache.els[i]);
		}
	}
	free (g_a11y_cache.els);
	g_a11y_cache.els = NULL;
	g_a11y_cache.count = 0;
	g_a11y_cache.cap = 0;
}

static bool
a11y_cache_add (IUIAutomationElement *el)
{
	if (g_a11y_cache.count >= g_a11y_cache.cap) {
		size_t ncap = g_a11y_cache.cap ? g_a11y_cache.cap * 2 : 64;
		IUIAutomationElement **nels = realloc (
			g_a11y_cache.els, ncap * sizeof (IUIAutomationElement *));
		if (nels == NULL) {
			return false;
		}
		g_a11y_cache.els = nels;
		g_a11y_cache.cap = ncap;
	}
	IUIAutomationElement_AddRef (el);
	g_a11y_cache.els[g_a11y_cache.count++] = el;
	return true;
}

static IUIAutomationElement *
a11y_cache_get (int id)
{
	if (id < 0 || (size_t) id >= g_a11y_cache.count) {
		return NULL;
	}
	return g_a11y_cache.els[id];
}

/* ---- find Document under WebView HWNDs ---- */

static BOOL CALLBACK
collect_hwnd_proc (HWND hwnd, LPARAM lparam)
{
	HwndList *hl = (HwndList *) lparam;

	if (hl->count < A11Y_MAX_HWNDS) {
		hl->list[hl->count++] = hwnd;
	}
	EnumChildWindows (hwnd, collect_hwnd_proc, lparam);
	return TRUE;
}

static void
collect_descendants (HWND root, HwndList *hl)
{
	hl->count = 0;
	if (root == NULL) {
		return;
	}
	hl->list[hl->count++] = root;
	EnumChildWindows (root, collect_hwnd_proc, (LPARAM) hl);
}

static int
interesting_hwnd (const wchar_t *cls)
{
	if (cls == NULL) {
		return 0;
	}
	return wcsstr (cls, L"Chrome") != NULL
	       || wcsstr (cls, L"WebView") != NULL
	       || wcsstr (cls, L"Render") != NULL;
}

static IUIAutomationCondition *
make_control_type_condition (IUIAutomation *uia, CONTROLTYPEID ctype)
{
	IUIAutomationCondition *cond = NULL;
	VARIANT v;

	VariantInit (&v);
	v.vt = VT_I4;
	v.lVal = (LONG) ctype;
	if (FAILED (IUIAutomation_CreatePropertyCondition (
		    uia, UIA_ControlTypePropertyId, v, &cond))) {
		return NULL;
	}
	return cond;
}

static IUIAutomationElement *
find_document_under (IUIAutomation *uia, HWND hwnd)
{
	IUIAutomationElement *root = NULL;
	IUIAutomationElement *doc = NULL;
	IUIAutomationCondition *cond;

	if (FAILED (IUIAutomation_ElementFromHandle (uia, hwnd, &root)) || root == NULL) {
		return NULL;
	}
	cond = make_control_type_condition (uia, UIA_DocumentControlTypeId);
	if (cond == NULL) {
		IUIAutomationElement_Release (root);
		return NULL;
	}
	IUIAutomationElement_FindFirst (root, TreeScope_Descendants, cond, &doc);
	IUIAutomationCondition_Release (cond);
	IUIAutomationElement_Release (root);
	return doc;
}

static IUIAutomationElement *
find_page_document (IUIAutomation *uia)
{
	HwndList hl;
	HWND parent;
	int i;

	parent = vala_webview2_com_get_parent_hwnd ();
	collect_descendants (parent, &hl);
	/* Prefer Chrome_WidgetWin_1 (phase 1 finding). */
	for (i = 0; i < hl.count; i++) {
		wchar_t cls[128];
		cls[0] = L'\0';
		GetClassNameW (hl.list[i], cls, 128);
		if (wcscmp (cls, L"Chrome_WidgetWin_1") == 0) {
			IUIAutomationElement *doc = find_document_under (uia, hl.list[i]);
			if (doc != NULL) {
				return doc;
			}
		}
	}
	for (i = 0; i < hl.count; i++) {
		wchar_t cls[128];
		IUIAutomationElement *doc;
		cls[0] = L'\0';
		GetClassNameW (hl.list[i], cls, 128);
		if (!interesting_hwnd (cls)) {
			continue;
		}
		doc = find_document_under (uia, hl.list[i]);
		if (doc != NULL) {
			return doc;
		}
	}
	return NULL;
}

static IUIAutomation *
create_uia (void)
{
	IUIAutomation *uia = NULL;
	HRESULT hr;

	hr = CoCreateInstance (
		&CLSID_CUIAutomation,
		NULL,
		CLSCTX_INPROC_SERVER,
		&IID_IUIAutomation,
		(void **) &uia);
	if (FAILED (hr)) {
		return NULL;
	}
	return uia;
}

/* ---- fill one node + recursive walk ---- */

static char *
http_uri_dup (const char *value)
{
	if (value == NULL) {
		return strdup ("");
	}
	if (strncmp (value, "http://", 7) == 0 || strncmp (value, "https://", 8) == 0) {
		return strdup (value);
	}
	return strdup ("");
}

static void
fill_node (webview2gtk_a11y_node *node, IUIAutomationElement *el, int id, int parent_id)
{
	ZeroMemory (node, sizeof (*node));
	node->id = id;
	node->parent_id = parent_id;
	element_bounds_screen (el, &node->x, &node->y, &node->w, &node->h);
	node->name = element_name_utf8 (el);
	node->role = element_role_utf8 (el);
	node->value = element_value_utf8 (el);
	/* Hyperlink / Document often expose URL via ValuePattern — copy into uri. */
	node->uri = http_uri_dup (node->value);
	node->can_invoke = element_has_pattern (el, UIA_InvokePatternId);
	node->can_set_value = element_value_writable (el);
}

static void
node_clear (webview2gtk_a11y_node *node)
{
	free (node->name);
	free (node->role);
	free (node->value);
	free (node->uri);
	ZeroMemory (node, sizeof (*node));
}

typedef struct {
	webview2gtk_a11y_node *nodes;
	size_t count;
	size_t cap;
} NodeList;

static bool
nodelist_push (
	NodeList *nl,
	IUIAutomationElement *el,
	int parent_id,
	int *out_id)
{
	webview2gtk_a11y_node *n;
	int id;

	if (nl->count >= A11Y_MAX_NODES) {
		return false;
	}
	if (nl->count >= nl->cap) {
		size_t ncap = nl->cap ? nl->cap * 2 : 64;
		webview2gtk_a11y_node *nn = realloc (nl->nodes, ncap * sizeof (webview2gtk_a11y_node));
		if (nn == NULL) {
			return false;
		}
		nl->nodes = nn;
		nl->cap = ncap;
	}
	id = (int) nl->count;
	n = &nl->nodes[id];
	fill_node (n, el, id, parent_id);
	if (!a11y_cache_add (el)) {
		node_clear (n);
		return false;
	}
	nl->count++;
	*out_id = id;
	return true;
}

static void
walk_collect (
	IUIAutomationTreeWalker *walker,
	IUIAutomationElement *el,
	int parent_id,
	int depth,
	NodeList *nl)
{
	IUIAutomationElement *child = NULL;
	IUIAutomationElement *next = NULL;
	int my_id;

	if (el == NULL || nl->count >= A11Y_MAX_NODES || depth > A11Y_MAX_DEPTH) {
		return;
	}
	if (!nodelist_push (nl, el, parent_id, &my_id)) {
		return;
	}
	if (depth >= A11Y_MAX_DEPTH) {
		return;
	}
	if (FAILED (IUIAutomationTreeWalker_GetFirstChildElement (walker, el, &child))
	    || child == NULL) {
		return;
	}
	while (child != NULL && nl->count < A11Y_MAX_NODES) {
		walk_collect (walker, child, my_id, depth + 1, nl);
		next = NULL;
		if (FAILED (IUIAutomationTreeWalker_GetNextSiblingElement (walker, child, &next))) {
			next = NULL;
		}
		IUIAutomationElement_Release (child);
		child = next;
	}
}

bool
vala_webview2_host_a11y_walk (webview2gtk_a11y_node **nodes_out, size_t *count_out)
{
	IUIAutomation *uia = NULL;
	IUIAutomationElement *doc = NULL;
	IUIAutomationTreeWalker *walker = NULL;
	NodeList nl;
	HRESULT hr;

	if (nodes_out == NULL || count_out == NULL) {
		return false;
	}
	*nodes_out = NULL;
	*count_out = 0;

	if (vala_webview2_com_get_webview () == NULL) {
		return false;
	}

	a11y_cache_clear ();
	ZeroMemory (&nl, sizeof (nl));

	uia = create_uia ();
	if (uia == NULL) {
		return false;
	}
	doc = find_page_document (uia);
	if (doc == NULL) {
		IUIAutomation_Release (uia);
		return false;
	}
	hr = IUIAutomation_get_ControlViewWalker (uia, &walker);
	if (FAILED (hr) || walker == NULL) {
		IUIAutomationElement_Release (doc);
		IUIAutomation_Release (uia);
		return false;
	}

	walk_collect (walker, doc, -1, 0, &nl);
	IUIAutomationTreeWalker_Release (walker);
	IUIAutomationElement_Release (doc);
	IUIAutomation_Release (uia);

	*nodes_out = nl.nodes;
	*count_out = nl.count;
	return nl.count > 0;
}

bool
vala_webview2_host_a11y_walk_foreach (WebView2GtkA11yForeachCb cb, void *user_data)
{
	webview2gtk_a11y_node *nodes = NULL;
	size_t count = 0;
	size_t i;

	if (cb == NULL) {
		return false;
	}
	if (!vala_webview2_host_a11y_walk (&nodes, &count)) {
		return false;
	}
	for (i = 0; i < count; i++) {
		webview2gtk_a11y_node *n = &nodes[i];
		cb (
			n->id,
			n->parent_id,
			n->x,
			n->y,
			n->w,
			n->h,
			n->name != NULL ? n->name : "",
			n->role != NULL ? n->role : "",
			n->value != NULL ? n->value : "",
			n->uri != NULL ? n->uri : "",
			n->can_invoke,
			n->can_set_value,
			user_data);
	}
	vala_webview2_host_a11y_nodes_free (nodes, count);
	return true;
}

void
vala_webview2_host_a11y_nodes_free (webview2gtk_a11y_node *nodes, size_t count)
{
	size_t i;

	if (nodes == NULL) {
		return;
	}
	for (i = 0; i < count; i++) {
		node_clear (&nodes[i]);
	}
	free (nodes);
}

bool
vala_webview2_host_a11y_invoke (int id)
{
	IUIAutomationElement *el;
	IUnknown *unk = NULL;
	IUIAutomationInvokePattern *inv = NULL;
	CONTROLTYPEID ctype = 0;
	char *href = NULL;
	char *name = NULL;
	char *role = NULL;
	HRESULT hr;
	bool ok = false;

	el = a11y_cache_get (id);
	if (el == NULL) {
		vala_webview2_a11y_diag_log ("INVOKE id=%d FAIL cache miss", id);
		return false;
	}

	IUIAutomationElement_get_CurrentControlType (el, &ctype);
	href = element_value_utf8 (el);
	name = element_name_utf8 (el);
	role = element_role_utf8 (el);
	vala_webview2_a11y_diag_log (
		"INVOKE begin id=%d role=%s ctype=%ld name=%s value=%s — UIA only (no navigate shortcut)",
		id,
		role != NULL ? role : "?",
		(long) ctype,
		name != NULL ? name : "",
		href != NULL ? href : "");
	free (href);
	free (name);
	free (role);

	/* Do not substitute host navigate(href) for press — use InvokePattern only. */
	if (vala_webview2_a11y_diag_enabled ()) {
		vala_webview2_a11y_diag_hwnd_snap_begin ();
	}
	hr = IUIAutomationElement_SetFocus (el);
	vala_webview2_a11y_diag_log ("INVOKE SetFocus hr=0x%08lx", (unsigned long) hr);

	if (FAILED (IUIAutomationElement_GetCurrentPattern (el, UIA_InvokePatternId, &unk))
	    || unk == NULL) {
		vala_webview2_a11y_diag_log ("INVOKE GetCurrentPattern(Invoke) FAILED / null");
		return false;
	}
	hr = IUnknown_QueryInterface (unk, &IID_IUIAutomationInvokePattern, (void **) &inv);
	IUnknown_Release (unk);
	if (FAILED (hr) || inv == NULL) {
		vala_webview2_a11y_diag_log ("INVOKE QI InvokePattern FAILED 0x%08lx", (unsigned long) hr);
		return false;
	}
	hr = IUIAutomationInvokePattern_Invoke (inv);
	ok = SUCCEEDED (hr);
	vala_webview2_a11y_diag_log (
		"INVOKE InvokePattern_Invoke hr=0x%08lx ok=%d",
		(unsigned long) hr,
		ok ? 1 : 0);
	IUIAutomationInvokePattern_Release (inv);
	if (vala_webview2_a11y_diag_enabled ()) {
		vala_webview2_a11y_diag_hwnd_snap_end (2000);
	}
	return ok;
}

static bool
try_value_pattern_set (IUIAutomationElement *el, const char *utf8, HRESULT *hr_out)
{
	IUnknown *unk = NULL;
	IUIAutomationValuePattern *vp = NULL;
	uint16_t *wide;
	BSTR bstr;
	HRESULT hr;
	BOOL readonly = FALSE;

	*hr_out = E_FAIL;
	if (FAILED (IUIAutomationElement_GetCurrentPattern (el, UIA_ValuePatternId, &unk))
	    || unk == NULL) {
		vala_webview2_a11y_diag_log ("SETVALUE ValuePattern missing");
		return false;
	}
	hr = IUnknown_QueryInterface (unk, &IID_IUIAutomationValuePattern, (void **) &vp);
	IUnknown_Release (unk);
	if (FAILED (hr) || vp == NULL) {
		vala_webview2_a11y_diag_log ("SETVALUE QI ValuePattern FAILED 0x%08lx", (unsigned long) hr);
		return false;
	}
	IUIAutomationValuePattern_get_CurrentIsReadOnly (vp, &readonly);
	vala_webview2_a11y_diag_log ("SETVALUE ValuePattern IsReadOnly=%d", (int) readonly);
	wide = win32_ui_utf8_to_utf16 (utf8, NULL);
	if (wide == NULL) {
		IUIAutomationValuePattern_Release (vp);
		return false;
	}
	bstr = SysAllocString ((const OLECHAR *) wide);
	free (wide);
	if (bstr == NULL) {
		IUIAutomationValuePattern_Release (vp);
		return false;
	}
	hr = IUIAutomationValuePattern_SetValue (vp, bstr);
	*hr_out = hr;
	SysFreeString (bstr);
	IUIAutomationValuePattern_Release (vp);
	vala_webview2_a11y_diag_log ("SETVALUE ValuePattern_SetValue hr=0x%08lx", (unsigned long) hr);
	return SUCCEEDED (hr);
}

static bool
try_legacy_set (IUIAutomationElement *el, const char *utf8, HRESULT *hr_out)
{
	IUnknown *unk = NULL;
	IUIAutomationLegacyIAccessiblePattern *leg = NULL;
	uint16_t *wide;
	BSTR bstr;
	HRESULT hr;

	*hr_out = E_FAIL;
	if (FAILED (IUIAutomationElement_GetCurrentPattern (el, UIA_LegacyIAccessiblePatternId, &unk))
	    || unk == NULL) {
		vala_webview2_a11y_diag_log ("SETVALUE LegacyIAccessible missing");
		return false;
	}
	hr = IUnknown_QueryInterface (unk, &IID_IUIAutomationLegacyIAccessiblePattern, (void **) &leg);
	IUnknown_Release (unk);
	if (FAILED (hr) || leg == NULL) {
		vala_webview2_a11y_diag_log ("SETVALUE QI LegacyIAccessible FAILED 0x%08lx", (unsigned long) hr);
		return false;
	}
	wide = win32_ui_utf8_to_utf16 (utf8, NULL);
	if (wide == NULL) {
		IUIAutomationLegacyIAccessiblePattern_Release (leg);
		return false;
	}
	bstr = SysAllocString ((const OLECHAR *) wide);
	free (wide);
	if (bstr == NULL) {
		IUIAutomationLegacyIAccessiblePattern_Release (leg);
		return false;
	}
	hr = IUIAutomationLegacyIAccessiblePattern_SetValue (leg, bstr);
	*hr_out = hr;
	SysFreeString (bstr);
	IUIAutomationLegacyIAccessiblePattern_Release (leg);
	vala_webview2_a11y_diag_log ("SETVALUE LegacyIAccessible_SetValue hr=0x%08lx", (unsigned long) hr);
	return SUCCEEDED (hr);
}

bool
vala_webview2_host_a11y_set_value (int id, const char *utf8)
{
	IUIAutomationElement *el;
	CONTROLTYPEID ctype = 0;
	char *before = NULL;
	char *after = NULL;
	char *name = NULL;
	char *role = NULL;
	HRESULT hr = E_FAIL;
	bool ok = false;

	if (utf8 == NULL) {
		return false;
	}
	el = a11y_cache_get (id);
	if (el == NULL) {
		vala_webview2_a11y_diag_log ("SETVALUE id=%d FAIL cache miss", id);
		return false;
	}

	IUIAutomationElement_get_CurrentControlType (el, &ctype);
	before = element_value_utf8 (el);
	name = element_name_utf8 (el);
	role = element_role_utf8 (el);
	vala_webview2_a11y_diag_log (
		"SETVALUE begin id=%d role=%s ctype=%ld name=%s before=%s want=%s",
		id,
		role != NULL ? role : "?",
		(long) ctype,
		name != NULL ? name : "",
		before != NULL ? before : "",
		utf8);
	free (name);
	free (role);

	hr = IUIAutomationElement_SetFocus (el);
	vala_webview2_a11y_diag_log ("SETVALUE SetFocus hr=0x%08lx", (unsigned long) hr);

	ok = try_value_pattern_set (el, utf8, &hr);
	after = element_value_utf8 (el);
	if (ok && (after == NULL || strcmp (after, utf8) != 0)) {
		/* Chromium often returns S_OK before ValuePattern reflects the new text. */
		Sleep (150);
		free (after);
		after = element_value_utf8 (el);
		vala_webview2_a11y_diag_log (
			"SETVALUE after+150ms=%s matched=%d",
			after != NULL ? after : "",
			(after != NULL && strcmp (after, utf8) == 0) ? 1 : 0);
	}
	if (!ok || after == NULL || strcmp (after, utf8) != 0) {
		bool leg_ok = try_legacy_set (el, utf8, &hr);
		Sleep (100);
		free (after);
		after = element_value_utf8 (el);
		if (leg_ok && after != NULL && strcmp (after, utf8) == 0) {
			ok = true;
		} else if (after != NULL && strcmp (after, utf8) == 0) {
			ok = true; /* ValuePattern S_OK caught up after delay */
		} else {
			ok = false;
		}
	}

	vala_webview2_a11y_diag_log (
		"SETVALUE end ok=%d after=%s matched=%d",
		ok ? 1 : 0,
		after != NULL ? after : "",
		(after != NULL && strcmp (after, utf8) == 0) ? 1 : 0);
	free (before);
	free (after);
	return ok;
}

bool
vala_webview2_host_a11y_focus (int id)
{
	IUIAutomationElement *el;
	HRESULT hr;

	el = a11y_cache_get (id);
	if (el == NULL) {
		return false;
	}
	hr = IUIAutomationElement_SetFocus (el);
	vala_webview2_a11y_diag_log ("FOCUS id=%d hr=0x%08lx", id, (unsigned long) hr);
	return SUCCEEDED (hr);
}

bool
vala_webview2_host_a11y_key_vk (unsigned short vk)
{
	INPUT in[2];

	ZeroMemory (in, sizeof (in));
	in[0].type = INPUT_KEYBOARD;
	in[0].ki.wVk = vk;
	in[1].type = INPUT_KEYBOARD;
	in[1].ki.wVk = vk;
	in[1].ki.dwFlags = KEYEVENTF_KEYUP;
	return SendInput (2, in, sizeof (INPUT)) == 2;
}

bool
vala_webview2_host_a11y_type_text (const char *utf8)
{
	uint16_t *wide;
	size_t i;
	size_t n;

	if (utf8 == NULL) {
		return false;
	}
	wide = win32_ui_utf8_to_utf16 (utf8, NULL);
	if (wide == NULL) {
		return false;
	}
	for (n = 0; wide[n] != 0; n++) {
	}
	for (i = 0; i < n; i++) {
		INPUT in[2];
		ZeroMemory (in, sizeof (in));
		in[0].type = INPUT_KEYBOARD;
		in[0].ki.wScan = wide[i];
		in[0].ki.dwFlags = KEYEVENTF_UNICODE;
		in[1].type = INPUT_KEYBOARD;
		in[1].ki.wScan = wide[i];
		in[1].ki.dwFlags = KEYEVENTF_UNICODE | KEYEVENTF_KEYUP;
		if (SendInput (2, in, sizeof (INPUT)) != 2) {
			free (wide);
			return false;
		}
	}
	free (wide);
	return true;
}
