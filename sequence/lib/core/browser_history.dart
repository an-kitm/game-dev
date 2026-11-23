/// Steps through the browser's own session history (the Back / Forward
/// buttons) and reports whether Back would stay in the app. No-ops when not
/// running in a browser, so code and tests on the Dart VM still compile.
library;

export 'browser_history_stub.dart'
    if (dart.library.js_interop) 'browser_history_web.dart';
