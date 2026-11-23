import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// Same as the browser's Back button.
bool browserBack() {
  web.window.history.back();
  return true;
}

/// Same as the browser's Forward button.
bool browserForward() {
  web.window.history.forward();
  return true;
}

/// Whether the browser entry below this one is still this app — i.e. Back
/// would stay in the app rather than leave the site.
///
/// Flutter's web engine numbers its history entries: it tags each one's state
/// as `{serialCount: n, state: …}`, starting at 0 for the app's first entry
/// (and keeps the tags across a reload). So anything above 0 has an app entry
/// below it.
bool hasAppEntryBelow() {
  try {
    final state = web.window.history.state;
    if (state == null || !state.isA<JSObject>()) return false;
    final count = (state as JSObject).getProperty<JSAny?>('serialCount'.toJS);
    return count != null &&
        count.isA<JSNumber>() &&
        (count as JSNumber).toDartDouble > 0;
  } catch (_) {
    return false;
  }
}
