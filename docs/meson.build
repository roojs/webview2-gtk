# Generate Valadoc API documentation (same pattern as OLLMchat).
#
# When adding/removing .vala under lib/webview2gtk/, update the input list below
# (include *Bindings.vala when public types call those externs).
# Markup: docs/code-documentation.md
# Local: meson setup build-docs -Ddocs=true && ninja -C build-docs docs/valadoc
#
valadoc = find_program('valadoc', required: true)
valadoc_runner = find_program(meson.current_source_dir() / 'run-valadoc.sh')

valadoc_dir = meson.project_build_root() / 'valadoc'
valadoc_clean = custom_target(
  'valadoc-clean',
  output: 'valadoc-clean',
  command: [
    find_program('sh'),
    '-c',
    'if [ -d "@0@" ]; then rm -rf "@0@"; fi'.format(valadoc_dir),
  ],
  build_by_default: false,
)

# File order: types before users. Skip host-only *Bindings.vala (C externs).
valadoc_docs = custom_target(
  'valadoc',
  input: files(
    '../lib/webview2gtk/Enums.vala',
    '../lib/webview2gtk/NetworkProxySettings.vala',
    '../lib/webview2gtk/CookieManager.vala',
    '../lib/webview2gtk/URIRequest.vala',
    '../lib/webview2gtk/WebResource.vala',
    '../lib/webview2gtk/Download.vala',
    '../lib/webview2gtk/NetworkSession.vala',
    '../lib/webview2gtk/ApplicationInfo.vala',
    '../lib/webview2gtk/AutomationSession.vala',
    '../lib/webview2gtk/WebContext.vala',
    '../lib/webview2gtk/WebsitePolicies.vala',
    '../lib/webview2gtk/Settings.vala',
    '../lib/webview2gtk/JavaScriptResult.vala',
    '../lib/webview2gtk/UserContentManager.vala',
    '../lib/webview2gtk/PrintOperation.vala',
    '../lib/webview2gtk/WebInspector.vala',
    '../lib/webview2gtk/CaptureBindings.vala',
    '../lib/webview2gtk/A11yBindings.vala',
    '../lib/webview2gtk/webview.vala',
    '../lib/webview2gtk/win32atspi/Win32AtspiWin.vala',
    '../lib/webview2gtk/win32atspi/Win32Atspi.vala',
  ),
  output: ['valadoc'],
  depends: [valadoc_clean],
  command: [
    valadoc_runner,
    valadoc_dir,
    '--package-name=webview2gtk',
    '--package-version=@0@'.format(meson.project_version()),
    '--vapidir', meson.current_source_dir() / '../vapi',
    '--vapidir', '/usr/share/vala/vapi',
    '--pkg=glib-2.0',
    '--pkg=gobject-2.0',
    '--pkg=gio-2.0',
    '--pkg=gee-0.8',
    '--pkg=gtk4',
    '--pkg=libsoup-3.0',
    '--pkg=posix',
    '--doclet=html',
    '--wiki=@0@'.format(meson.current_source_dir() / 'valadoc-wiki'),
    '--directory=' + valadoc_dir,
    '@INPUT@',
  ],
  build_by_default: false,
  install: false,
)
