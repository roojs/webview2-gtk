# Bug — `NetworkSession.set_proxy_settings` is a no-op stub

**Status:** ✅ fixed in **0.5.13** (`--proxy-server` / `--no-proxy-server` at env create)  
**Date:** 2026-09-10  
**Component:** `lib/webview2gtk/NetworkSession.vala` (+ host env options)  
**Related:** `NetworkProxyMode` / `NetworkProxySettings`; `AdditionalBrowserArguments` merge in `win32-ui-webview2-automation.c`  
**API parity:** WebKitGTK `WebKit.NetworkSession.set_proxy_settings`  
**Plan:** [5.0](../../plans/done/5.0-network-session-proxy.md)  
**Smoke:** `examples/add-cookie --smoke-proxy`

---

## Symptom

A private app calls the WebKit-shaped API before `load_uri`:

```vala
web_view.network_session.set_proxy_settings(
    NetworkProxyMode.CUSTOM,
    new NetworkProxySettings("http://127.0.0.1:8888", null)
);
web_view.load_uri("https://example.test/");
```

On **WebKitGTK** the view’s HTTP(S) traffic goes through that proxy.  
On **webview2-gtk** the call compiles and returns, but the host still uses the system / default network path — page egress never hits the proxy.

Root cause: the Vala method is an empty stub:

```vala
public void set_proxy_settings(
    NetworkProxyMode mode,
    NetworkProxySettings? settings
) {
}
```

`NetworkProxySettings` / `NetworkProxyMode` exist for API shape only.

---

## Why this should work on WebView2

WebView2 honors Chromium proxy flags via
`ICoreWebView2EnvironmentOptions::AdditionalBrowserArguments` at environment create
([browser flags](https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/webview-features-flags)):

| Mode | Suggested mapping |
|------|-------------------|
| `CUSTOM` + URI | `--proxy-server=<uri>` (HTTP/HTTPS only) |
| `NONE` | `--no-proxy-server` |
| `DEFAULT` | omit proxy flags (system / WebView2 default resolver) |

The host already builds / merges `AdditionalBrowserArguments` for CDP, autoplay, and
`AutomationControlled` hide — same channel.

Optional later: `BasicAuthenticationRequested` for authenticated proxies (out of
MVP if apps use open HTTP proxies).

---

## Constraints (document in fix)

- 🔷 Proxy flags are **environment-create** scoped (like autoplay / inspector port).
  Late `set_proxy_settings` after the WebView2 environment exists should
  **warn once** and either no-op or require a documented recreate path — match the
  pattern used for `navigator_webdriver_active_policy`.
- 🔷 First call **before** environment create should latch args for the next create.
- 💩 Per-session / mid-lifetime proxy switch without recreating the environment may
  be impossible on WebView2 — call that out in API docs if so; WebKitGTK allows
  change on a live `NetworkSession`.

---

## Acceptance

1. Demo or smoke: create a view, `set_proxy_settings(CUSTOM, …)` **before** first
   environment / navigate, load a URL that only resolves via that proxy — request
   appears on the proxy (or fails closed if proxy down).
2. `DEFAULT` / clearing back to system does not leave a stale `--proxy-server`.
3. `NONE` bypasses system proxy (`--no-proxy-server`).
4. VAPI / docs note create-time limitation vs WebKitGTK live change.

---

## Out of scope

- Local MITM / CA inject  
- PAC URL (`--proxy-pac-url`) unless trivial with the same merge path  
- Shipping a forward proxy inside this library  
