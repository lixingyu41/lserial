import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'log_export_result.dart';

Future<LogExportResult> exportLogText(String content) async {
  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  final name = 'lserial_log_${now.year}${two(now.month)}${two(now.day)}_'
      '${two(now.hour)}${two(now.minute)}${two(now.second)}.txt';
  final directory = await _downloadsDirectory();
  await directory.create(recursive: true);
  final file = File(_joinPath(directory.path, name));
  await file.writeAsString(content, flush: true);
  return LogExportResult.saved(file.absolute.path);
}

Future<Directory> _downloadsDirectory() async {
  try {
    final directory = await getDownloadsDirectory();
    if (directory != null) {
      return directory;
    }
  } on Object {
    // Fall through to a predictable Downloads path when the platform API fails.
  }

  final home = Platform.environment['USERPROFILE'] ??
      Platform.environment['HOME'] ??
      Directory.current.path;
  return Directory(_joinPath(home, 'Downloads'));
}

String _joinPath(String directory, String child) {
  final separator = Platform.pathSeparator;
  return directory.endsWith(separator)
      ? '$directory$child'
      : '$directory$separator$child';
}
