# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).


## [0.4.2] - Unreleased

### Added

- `WebsitePolicies` / `AutoplayPolicy` construct on `WebView` (`DENY` maps to `--autoplay-policy=user-gesture-required`) ([plan 3.7](docs/plans/3.7-website-policies.md)).
- `WebViewSettings.enable_developer_extras` and `WebInspector.show()` open the Edge DevTools window.
- Media settings on `WebViewSettings`: `enable_media_stream`, `enable_webrtc`, and `media_playback_requires_user_gesture`.
- `WebView.is_muted` (honoured via WebView2 mute).
- `permission_request` / `query_permission_state` with WebKitGTK-shaped `PermissionRequest` / `PermissionStateQuery` (host denies via `PermissionRequested` when unhandled or media is disabled).

### Fixed

- Installed `webview2gtk-1.vapi`: `Win32Atspi` now has `cheader_filename = "webview2gtk.h"`, so consumer `.vala` that only uses a11y emits `#include <webview2gtk.h>` and links without needing `WebView` in the same file ([bug](docs/bugs/2026-08-21-win32atspi-vapi-missing-cheader.md)).

## [0.4.1] - 2026-08-19

### Added

- WebKitGTK-shaped automation **setup** (`WebContext` / `AutomationSession` / `ApplicationInfo`, controlled `WebView`) and `WEBKIT_INSPECTOR_SERVER` → WebView2 CDP `--remote-debugging-port` ([plan 3.0](docs/plans/3.0-engine-fill-input.md)). Fill stays with an external driver/CDP client — see [docs/automation.md](docs/automation.md).
- `WebView` automation construct properties (`web_context`, `network_session`, `is_controlled_by_automation`) — WebKitGTK shape; `WebViewAuto` subclass in `examples/automation` ([plan 3.6](docs/plans/3.6-webview-construct-automation.md)).
- `examples/cdp-attach` (`webview2gtk-cdp-attach.exe`) for attach/fill via CDP.

## [0.4.0] - 2026-07-31

### Added

- WebKitGTK-shaped **`WebView.resource_load_started`** and **`WebResource`** (`uri` / `get_uri`, `finished`, `failed`) so shared `#if WINDOWS` apps can track in-flight subresource loads ([plan 2.1](docs/plans/2.1-webresource-load-started.md)).
- Host maps WebView2 `WebResourceRequested` + `WebResourceResponseReceived` onto that lifecycle (no Windows-only public API).

### Fixed

- UI hang when a script message handler was registered before the controller finished setup (document-created script inject is async; no `sync_await` inside the COM completion callback). Found while exercising the hello demo for 2.1.
- `load_html` waits for host ready and uses `NavigateToString` instead of deferred `data:` URIs.

## [0.3.3] - 2026-07-23

Prior releases (`v0.1.x` … `v0.3.3`) were published without a changelog in-tree.
Summaries live in [GitHub Releases](https://github.com/roojs/webview2-gtk/releases) and the plans under `docs/plans/` (script messages 2.0, downloads 1.1, a11y 1.0, pacman signatures 0.3, …).

From this file onward, each tagged release should move `[Unreleased]` into a dated section before tagging.
