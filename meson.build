project(
  'webview2-gtk',
  ['c', 'vala'],
  version: '0.5.2',
  meson_version: '>= 1.0.0',
  default_options: ['buildtype=debugoptimized', 'c_std=c11'],
)

is_windows = host_machine.system() == 'windows'
want_docs = get_option('docs')

if not is_windows and not want_docs
  error('webview2-gtk is Windows-only (GTK 4 + WebView2). Use -Ddocs=true to configure Valadoc on Linux.')
endif

if want_docs
  subdir('docs')
endif

if not is_windows
  # Docs-only configure (CI / local Valadoc). Library and demos need Windows.
  subdir_done()
endif

project_root = meson.project_source_root()
build_root = meson.project_build_root()

# Ninja on GitHub Actions may invoke the WSL bash.exe stub unless we use MSYS2 bash.
if run_command('test', '-x', '/usr/bin/bash', check: false).returncode() == 0
  _bash_win = run_command('cygpath', '-m', '/usr/bin/bash', check: true).stdout().strip()
  _build_bash = find_program(_bash_win)
else
  _build_bash = find_program('bash')
endif
vendor_webview2_sh = files('scripts/vendor-webview2-sdk.sh')
wv2gtk_build_sh = files('scripts/wv2gtk-build.sh')

webview2_sdk = project_root / 'build/vendor/webview2'
webview2_header = webview2_sdk / 'include' / 'WebView2.h'
have_webview2 = run_command('test', '-f', webview2_header, check: false).returncode() == 0

if not have_webview2
  run_command(_build_bash, vendor_webview2_sh, check: true)
endif

prefix = get_option('prefix')
lib_stage = build_root / 'install-staging'

lib_target = custom_target(
  'webview2gtk-lib',
  output: 'libwebview2gtk-1.stamp',
  command: [_build_bash, wv2gtk_build_sh, 'lib', build_root, lib_stage, '@OUTPUT@'],
  build_by_default: true,
)

# Examples link the staged static lib (do not re-valac the whole widget tree).
hello_exe = custom_target(
  'webview2gtk-hello',
  output: 'webview2gtk-hello.exe',
  command: [_build_bash, wv2gtk_build_sh, 'hello', build_root / 'hello', '@OUTPUT@', lib_stage],
  depends: lib_target,
  build_by_default: get_option('examples'),
  install: get_option('examples'),
  install_dir: get_option('bindir'),
)

browser_exe = custom_target(
  'webview2gtk-browser',
  output: 'webview2gtk-browser.exe',
  command: [_build_bash, wv2gtk_build_sh, 'browser', build_root / 'browser', '@OUTPUT@', lib_stage],
  depends: lib_target,
  build_by_default: get_option('examples'),
  install: get_option('examples'),
  install_dir: get_option('bindir'),
)

automation_exe = custom_target(
  'webview2gtk-automation',
  output: 'webview2gtk-automation.exe',
  command: [_build_bash, wv2gtk_build_sh, 'automation', build_root / 'automation', '@OUTPUT@', lib_stage],
  depends: lib_target,
  build_by_default: get_option('examples'),
  install: get_option('examples'),
  install_dir: get_option('bindir'),
)

cdp_attach_exe = custom_target(
  'webview2gtk-cdp-attach',
  output: 'webview2gtk-cdp-attach.exe',
  command: [_build_bash, wv2gtk_build_sh, 'cdp-attach', build_root / 'cdp-attach', '@OUTPUT@'],
  build_by_default: get_option('examples'),
  install: get_option('examples'),
  install_dir: get_option('bindir'),
)

paned_insert_exe = custom_target(
  'webview2gtk-paned-insert',
  output: 'webview2gtk-paned-insert.exe',
  command: [_build_bash, wv2gtk_build_sh, 'paned-insert', build_root / 'paned-insert', '@OUTPUT@', lib_stage],
  depends: lib_target,
  depend_files: files('examples/paned-insert/main.vala'),
  build_by_default: get_option('examples'),
  install: get_option('examples'),
  install_dir: get_option('bindir'),
)

add_cookie_exe = custom_target(
  'webview2gtk-add-cookie',
  output: 'webview2gtk-add-cookie.exe',
  command: [_build_bash, wv2gtk_build_sh, 'add-cookie', build_root / 'add-cookie', '@OUTPUT@', lib_stage],
  depends: lib_target,
  depend_files: files('examples/add-cookie/main.vala'),
  build_by_default: get_option('examples'),
  install: get_option('examples'),
  install_dir: get_option('bindir'),
)

multi_host_spike_exe = custom_target(
  'webview2gtk-multi-host-spike',
  output: 'webview2gtk-multi-host-spike.exe',
  command: [_build_bash, wv2gtk_build_sh, 'multi-host-spike', build_root / 'multi-host-spike', '@OUTPUT@'],
  depend_files: files('examples/multi-host-spike/main.c'),
  build_by_default: get_option('examples'),
  install: false,
)

package_demos_sh = files('scripts/package-demos.sh')
custom_target(
  'package-demos',
  output: 'package-demos.stamp',
  command: [_build_bash, package_demos_sh, '@OUTPUT@'],
  depends: [hello_exe, browser_exe, automation_exe, cdp_attach_exe, paned_insert_exe, add_cookie_exe],
  build_by_default: get_option('examples'),
)

webview2_loader = webview2_sdk / 'x64' / 'WebView2Loader.dll'
have_webview2_loader = run_command('test', '-f', webview2_loader, check: false).returncode() == 0
if get_option('examples') and have_webview2_loader
  install_data(webview2_loader, install_dir: get_option('bindir'))
endif

_py = import('python').find_installation()
meson.add_install_script(_py, files('scripts/meson-install.py'), lib_stage)
configure_file(
  input: 'webview2gtk-1.pc.in',
  output: 'webview2gtk-1.pc',
  configuration: {
    'prefix': prefix,
    'version': meson.project_version(),
  },
  install: true,
  install_dir: get_option('libdir') / 'pkgconfig',
)
