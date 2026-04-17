import 'log_exporter_stub.dart'
    if (dart.library.io) 'log_exporter_io.dart'
    if (dart.library.js_interop) 'log_exporter_web.dart' as impl;
import 'log_export_result.dart';

Future<LogExportResult> exportLogText(String content) =>
    impl.exportLogText(content);
