import 'dart:convert';

import 'package:file_selector/file_selector.dart';

import 'log_export_result.dart';
import 'text_file_transfer_stub.dart'
    if (dart.library.io) 'text_file_transfer_io.dart'
    if (dart.library.js_interop) 'text_file_transfer_web.dart' as impl;

const XTypeGroup _textTypeGroup = XTypeGroup(
  label: 'TXT',
  extensions: <String>['txt'],
  mimeTypes: <String>['text/plain'],
  uniformTypeIdentifiers: <String>['public.plain-text'],
  webWildCards: <String>['text/plain'],
);

Future<String?> pickTextFile() async {
  final file = await openFile(
    acceptedTypeGroups: const <XTypeGroup>[_textTypeGroup],
  );
  if (file == null) {
    return null;
  }
  return utf8.decode(await file.readAsBytes());
}

Future<LogExportResult?> saveTextFile({
  required String content,
  required String suggestedName,
}) =>
    impl.saveTextFile(content: content, suggestedName: suggestedName);
