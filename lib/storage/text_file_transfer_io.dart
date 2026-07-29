import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

import 'log_export_result.dart';

Future<LogExportResult?> saveTextFile({
  required String content,
  required String suggestedName,
}) async {
  final location = await getSaveLocation(suggestedName: suggestedName);
  if (location == null) {
    return null;
  }

  final file = XFile.fromData(
    Uint8List.fromList(utf8.encode(content)),
    mimeType: 'text/plain',
    name: suggestedName,
  );
  await file.saveTo(location.path);
  return LogExportResult.saved(location.path);
}
