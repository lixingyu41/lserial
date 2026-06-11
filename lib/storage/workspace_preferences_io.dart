import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

const _quickCommandsPanelVisibleKey = 'showQuickCommandsPanel';

Future<bool?> readQuickCommandsPanelVisible() async {
  try {
    final file = await _settingsFile();
    if (!await file.exists()) {
      return null;
    }
    final settings = await _readSettings(file);
    final value = settings[_quickCommandsPanelVisibleKey];
    return value is bool ? value : null;
  } on Object {
    return null;
  }
}

Future<void> writeQuickCommandsPanelVisible(bool value) async {
  try {
    final file = await _settingsFile();
    final settings =
        await file.exists() ? await _readSettings(file) : <String, Object?>{};
    settings[_quickCommandsPanelVisibleKey] = value;
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(settings), flush: true);
  } on Object {
    return;
  }
}

Future<Map<String, Object?>> _readSettings(File file) async {
  final raw = await file.readAsString();
  final decoded = jsonDecode(raw);
  if (decoded is Map<String, Object?>) {
    return Map<String, Object?>.of(decoded);
  }
  if (decoded is Map) {
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  }
  return <String, Object?>{};
}

Future<File> _settingsFile() async {
  Directory directory;
  try {
    directory = await getApplicationSupportDirectory();
  } on Object {
    final basePath = Platform.environment['APPDATA'] ??
        Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        Directory.current.path;
    directory = Directory(_joinPath(basePath, 'LSerial'));
  }
  return File(_joinPath(directory.path, 'settings.json'));
}

String _joinPath(String directory, String child) {
  final separator = Platform.pathSeparator;
  return directory.endsWith(separator)
      ? '$directory$child'
      : '$directory$separator$child';
}
