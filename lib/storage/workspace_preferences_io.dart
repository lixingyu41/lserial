import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../application/workspace_settings.dart';
import '../core/encoding/data_format.dart';
import '../domain/quick_command.dart';

const _workspaceSettingsKey = 'workspaceSettings';
const _quickCommandsPanelVisibleKey = 'showQuickCommandsPanel';
const _quickCommandsKey = 'quickCommands';
const _quickCommandBubblePositionKey = 'quickCommandBubblePosition';

Future<WorkspaceSettings?> readWorkspaceSettings() async {
  try {
    final file = await _settingsFile();
    if (!await file.exists()) {
      return null;
    }
    final settings = await _readSettings(file);
    final value = settings[_workspaceSettingsKey];
    if (value is Map<String, Object?>) {
      return WorkspaceSettings.fromJson(value);
    }
    if (value is Map) {
      return WorkspaceSettings.fromJson(
        value.map((key, value) => MapEntry(key.toString(), value)),
      );
    }
    final legacyQuickPanelVisible = settings[_quickCommandsPanelVisibleKey];
    if (legacyQuickPanelVisible is bool) {
      return WorkspaceSettings(
        showQuickCommandsPanel: legacyQuickPanelVisible,
      );
    }
    return null;
  } on Object {
    return null;
  }
}

Future<void> writeWorkspaceSettings(WorkspaceSettings value) async {
  try {
    final file = await _settingsFile();
    final settings =
        await file.exists() ? await _readSettings(file) : <String, Object?>{};
    settings[_workspaceSettingsKey] = value.toJson();
    settings[_quickCommandsPanelVisibleKey] = value.showQuickCommandsPanel;
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(settings), flush: true);
  } on Object {
    return;
  }
}

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

Future<List<QuickCommand>?> readQuickCommands() async {
  try {
    final file = await _settingsFile();
    if (!await file.exists()) {
      return null;
    }
    final settings = await _readSettings(file);
    final value = settings[_quickCommandsKey];
    if (value is! List) {
      return null;
    }
    return _decodeQuickCommands(value);
  } on Object {
    return null;
  }
}

Future<void> writeQuickCommands(List<QuickCommand> commands) async {
  try {
    final file = await _settingsFile();
    final settings =
        await file.exists() ? await _readSettings(file) : <String, Object?>{};
    settings[_quickCommandsKey] = commands.map(_encodeQuickCommand).toList();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(settings), flush: true);
  } on Object {
    return;
  }
}

Future<({double x, double y})?> readQuickCommandBubblePosition() async {
  try {
    final file = await _settingsFile();
    if (!await file.exists()) {
      return null;
    }
    final value = (await _readSettings(file))[_quickCommandBubblePositionKey];
    if (value is! Map) {
      return null;
    }
    final x = value['x'];
    final y = value['y'];
    if (x is! num || y is! num) {
      return null;
    }
    return (x: x.toDouble(), y: y.toDouble());
  } on Object {
    return null;
  }
}

Future<void> writeQuickCommandBubblePosition(
  ({double x, double y}) position,
) async {
  try {
    final file = await _settingsFile();
    final settings =
        await file.exists() ? await _readSettings(file) : <String, Object?>{};
    settings[_quickCommandBubblePositionKey] = <String, double>{
      'x': position.x,
      'y': position.y,
    };
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(settings), flush: true);
  } on Object {
    return;
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

List<QuickCommand> _decodeQuickCommands(List<Object?> rawCommands) {
  final commands = <QuickCommand>[];
  var fallbackId = 1;
  for (final rawCommand in rawCommands) {
    if (rawCommand is! Map) {
      continue;
    }
    final name = rawCommand['name'];
    final content = rawCommand['content'];
    if (name is! String || content is! String) {
      continue;
    }
    final safeName = name.trim();
    if (safeName.isEmpty || content.isEmpty) {
      continue;
    }
    final id = rawCommand['id'];
    final format = rawCommand['format'];
    commands.add(
      QuickCommand(
        id: id is int && id > 0 ? id : fallbackId,
        name: safeName,
        content: content,
        format: _decodePayloadFormat(format),
      ),
    );
    fallbackId++;
  }
  return commands;
}

Map<String, Object?> _encodeQuickCommand(QuickCommand command) {
  return <String, Object?>{
    'id': command.id,
    'name': command.name,
    'content': command.content,
    'format': command.format.name,
  };
}

PayloadFormat _decodePayloadFormat(Object? value) {
  for (final format in PayloadFormat.values) {
    if (value == format.name) {
      return format;
    }
  }
  return PayloadFormat.ascii;
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
