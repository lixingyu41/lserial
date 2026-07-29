import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'log_export_result.dart';

@JS('Blob')
external JSFunction get _blobConstructor;

@JS('URL')
external JSObject get _url;

@JS('document')
external JSObject get _document;

Future<LogExportResult?> saveTextFile({
  required String content,
  required String suggestedName,
}) async {
  final blob = _blobConstructor.callAsConstructor<JSObject>(
    <JSAny?>[
      <JSString>[content.toJS].toJS,
      <String, Object>{'type': 'text/plain;charset=utf-8'}.jsify(),
    ].toJS,
  );
  final url = _url.callMethod<JSString>('createObjectURL'.toJS, blob);
  final anchor = _document.callMethod<JSObject>('createElement'.toJS, 'a'.toJS);
  anchor['href'] = url;
  anchor['download'] = suggestedName.toJS;
  anchor.callMethod<JSAny?>('click'.toJS);
  _url.callMethod<JSAny?>('revokeObjectURL'.toJS, url);
  return LogExportResult.downloadStarted(suggestedName);
}
