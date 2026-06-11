import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('localStorage')
external JSObject get _localStorage;

const _quickCommandsPanelVisibleKey = 'lserial.showQuickCommandsPanel';

Future<bool?> readQuickCommandsPanelVisible() async {
  try {
    final value = _localStorage
        .callMethod<JSString?>(
          'getItem'.toJS,
          _quickCommandsPanelVisibleKey.toJS,
        )
        ?.toDart;
    return switch (value) {
      'true' => true,
      'false' => false,
      _ => null,
    };
  } on Object {
    return null;
  }
}

Future<void> writeQuickCommandsPanelVisible(bool value) async {
  try {
    _localStorage.callMethod<JSAny?>(
      'setItem'.toJS,
      _quickCommandsPanelVisibleKey.toJS,
      value.toString().toJS,
    );
  } on Object {
    return;
  }
}
