# Smoke — hidden Gtk.Stack primary document pick

Standalone Vala repro for
[2026-08-28-win32atspi-hidden-stack-host-missing-document](../2026-08-28-win32atspi-hidden-stack-host-missing-document.md).

| File | Role |
|------|------|
| `smoke-hidden-stack.vala` | Gtk.Stack + title/URI pick over `Win32Atspi` |

## Run (Windows interactive session)

Compile against staged `webview2gtk-1` (Meson `examples` on):

```text
ninja -C build webview2gtk-smoke-hidden-stack.exe
./scripts/run-hidden-stack-smoke-interactive.sh
```

Or from Linux: `./scripts/agent-remote-build.sh hidden-stack`

```text
webview2gtk-smoke-hidden-stack.exe --google
webview2gtk-smoke-hidden-stack.exe --google --restore-primary
```

## Expected

| Flags | Pass criterion |
|-------|----------------|
| `--google` (primary hidden) | `PICK OK` + `VERDICT=HIDDEN_OK` |
| `--google --restore-primary` | `PICK OK` (workaround only if hidden fails) |

`VERDICT=HIDDEN_MISS` with only the secondary document in the walk = bug still open.
