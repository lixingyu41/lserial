import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('Blob')
external JSFunction get _blobConstructor;

@JS('URL')
external JSObject get _url;

@JS('document')
external JSObject get _document;

Future<String> exportLogText(String content) async {
  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  final name = 'lserial_log_${now.year}${two(now.month)}${two(now.day)}_'
      '${two(now.hour)}${two(now.minute)}${two(now.second)}.txt';
  final blob = _blobConstructor.callAsConstructor<JSObject>(
    <JSAny?>[
      <JSString>[content.toJS].toJS,
      <String, Object>{'type': 'text/plain;charset=utf-8'}.jsify(),
    ].toJS,
  );
  final url = _url.callMethod<JSString>('createObjectURL'.toJS, blob);
  final anchor = _document.callMethod<JSObject>('createElement'.toJS, 'a'.toJS);
  anchor['href'] = url;
  anchor['download'] = name.toJS;
  anchor.callMethod<JSAny?>('click'.toJS);
  _url.callMethod<JSAny?>('revokeObjectURL'.toJS, url);
  return 'Started browser download: $name';
}
