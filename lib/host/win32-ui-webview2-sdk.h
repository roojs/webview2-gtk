/* Include Microsoft WebView2.h without GCC IID spam (selectany + extern). */
#ifndef VALA_WIN32_UI_WEBVIEW2_SDK_H
#define VALA_WIN32_UI_WEBVIEW2_SDK_H

#if defined(__GNUC__)
#pragma GCC system_header
#endif

#define COBJMACROS
#include <WebView2.h>

#endif
