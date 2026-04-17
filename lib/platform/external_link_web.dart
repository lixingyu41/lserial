import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('window')
external JSObject get _window;

Future<void> openExternalLink(Uri uri) async {
  _window.callMethod<JSAny?>(
    'open'.toJS,
    uri.toString().toJS,
    '_blank'.toJS,
    'noopener,noreferrer'.toJS,
  );
}
