import 'dart:js_interop';

@JS('window')
external _BrowserWindow get _window;

extension type _BrowserWindow(JSObject _) implements JSObject {
  external void addEventListener(String type, JSFunction listener);
  external void removeEventListener(String type, JSFunction listener);
}

extension type _BeforeUnloadEvent(JSObject _) implements JSObject {
  external void preventDefault();
  external set returnValue(String value);
}

/// Browser-native warning only. No persistence/network work during unload.
class BrowserExitGuard {
  late final JSFunction _listener = ((_BeforeUnloadEvent event) {
    event.preventDefault();
    event.returnValue = '';
  }).toJS;
  bool _enabled = false;

  void update(bool enabled) {
    if (enabled == _enabled) return;
    _enabled = enabled;
    if (enabled) {
      _window.addEventListener('beforeunload', _listener);
    } else {
      _window.removeEventListener('beforeunload', _listener);
    }
  }

  void dispose() => update(false);
}
