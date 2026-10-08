# Bug — standard user cannot write the WebView data folder after an administrator install

**Status:** ✅ fixed in **0.6.8**  
**Date:** 2026-10-08  
**Component:** `lib/host/win32-ui-webview2-loader.c` (`vala_webview2_loader_create_environment`, `make_host_user_data_folder`); `lib/webview2gtk/NetworkSession.vala`  
**API parity:** WebKitGTK stores website data for the signed-in user (`NetworkSession` data / cache directory, otherwise that user's XDG dirs). A machine-wide install still writes the current user's profile.

A private app hit this. The log stays in that app's tree.

---

## Symptom

- The host is installed for the machine by an administrator. The exe sits in a protected directory (Program Files).
- A user who is not an administrator starts the host.
- Startup fails. The browser says it cannot write its data directory.
- The path is under the **administrator** account's AppData, not the signed-in user's profile.

---

## Cause

The shared environment is created with a null user-data folder:

```c
hr = g_create_env_with_options (NULL, NULL, options, handler);
```

(`vala_webview2_loader_create_environment` in `lib/host/win32-ui-webview2-loader.c`.)

WebView2's default is `{exe directory}\{exe name}.WebView2`. A standard user cannot create or write that next to an exe under Program Files. An elevated first launch (the installer starts the host, or any "run as administrator") creates it as the administrator.

The local-host proxy folder follows the process environment:

```c
n = GetEnvironmentVariableW (L"LOCALAPPDATA", base, MAX_PATH);
/* … */
_snwprintf (profiles, MAX_PATH, L"%s\\webview2gtk\\profiles", base);
```

(`make_host_user_data_folder` in the same file.)

An elevated process resolves `LOCALAPPDATA` to the administrator profile, for example `C:\Users\Administrator\AppData\Local\webview2gtk\profiles\…`. WebView2 then starts the browser process **without** elevation. That process is the signed-in standard user and cannot write the administrator's AppData.

`NetworkSession(data_directory, cache_directory)` accepts the WebKitGTK arguments and ignores them (`lib/webview2gtk/NetworkSession.vala`). An app cannot aim the profile at the current user's directories.

---

## Expected

- The user-data folder is under the **interactive** user's LocalAppData, and that user can create and write it.
- An elevated host must not pass the browser a path inside the administrator profile. If the browser de-elevates, resolve LocalAppData from the linked unelevated token.
- The same rule for `%LOCALAPPDATA%\webview2gtk\profiles`.
- Do not use the directory that contains the exe.

---

## Repro

1. Install a small host (the packaged hello demo is enough) under `C:\Program Files\…`, so setup requires an administrator.
2. From that elevated setup, start the host once so the data folder is created with the administrator token.
3. Sign in as a standard user (not that administrator account).
4. Start the host unelevated.

WebView creation fails. The data directory in the error is not writable by that user.

---

## Fix

- Shared environment user-data is `%LOCALAPPDATA%\webview2gtk\shared`. Local host proxy profiles stay `%LOCALAPPDATA%\webview2gtk\profiles\wv_<pid>_<tick>_<id>`. Neither path is the exe directory.
- Unelevated, LocalAppData is this process's profile.
- Elevated, LocalAppData is the interactive shell user's (explorer's token). Over-the-shoulder elevation's linked token is still the administrator, and the browser runs as the signed-in user. If the shell token cannot be opened, fall back to the linked unelevated token. Do not use the elevated process profile.
- The folder is created, then labeled medium integrity and granted to that user, so a de-elevated browser can write it.
- `NetworkSession` directory arguments stay unused. One shared environment owns the profile; the host chooses the interactive user's folder, so a machine-wide install does not need the app to pass a path.
