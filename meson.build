project(
  'webview2-gtk',
  ['c', 'vala'],
  version: '0.1.0',
  meson_version: '>= 1.0.0',
  default_options: ['buildtype=debugoptimized', 'c_std=c11'],
)

if host_machine.system() != 'windows'
  error('webview2-gtk is Windows-only (GTK 4 + WebView2 via gdk_win32_surface_get_handle)')
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
  command: [_build_bash, wv2gtk_build_sh, 'lib', build_root, lib_stage],
  build_by_default: true,
)

# Examples
hello_exe = custom_target(
  'webview2gtk-hello',
  output: 'webview2gtk-hello.exe',
  command: [_build_bash, wv2gtk_build_sh, 'hello', build_root / 'hello', '@OUTPUT@'],
  depends: lib_target,
  build_by_default: get_option('examples'),
  install: get_option('examples'),
  install_dir: get_option('bindir'),
)

browser_exe = custom_target(
  'webview2gtk-browser',
  output: 'webview2gtk-browser.exe',
  command: [_build_bash, wv2gtk_build_sh, 'browser', build_root / 'browser', '@OUTPUT@'],
  depends: lib_target,
  build_by_default: get_option('examples'),
  install: get_option('examples'),
  install_dir: get_option('bindir'),
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
  configuration: {'prefix': prefix},
  install: true,
  install_dir: get_option('libdir') / 'pkgconfig',
)
