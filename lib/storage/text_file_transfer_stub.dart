import 'log_export_result.dart';

Future<LogExportResult?> saveTextFile({
  required String content,
  required String suggestedName,
}) async {
  throw UnsupportedError('Text file export is not supported on this platform.');
}
