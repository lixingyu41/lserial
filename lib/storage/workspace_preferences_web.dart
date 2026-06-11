import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import '../core/encoding/data_format.dart';
import '../domain/quick_command.dart';

@JS('localStorage')
external JSObject get _localStorage;

const _quickCommandsPanelVisibleKey = 'lserial.showQuickCommandsPanel';
const _quickCommandsKey = 'lserial.quickCommands';

Future<bool?> readQuickCommandsPanelVisible() async {
  try {
    final value = _localStorage
        .callMethod<JSString?>(
          'getItem'.toJS,
          _quickCommandsPanelVisibleKey.toJS,
        )
        ?.toDart;
    return switch (value) {
      'true' => true,
      'false' => false,
      _ => null,
    };
  } on Object {
    return null;
  }
}

Future<List<QuickCommand>?> readQuickCommands() async {
  try {
    final value = _localStorage
        .callMethod<JSString?>(
          'getItem'.toJS,
          _quickCommandsKey.toJS,
        )
        ?.toDart;
    if (value == null) {
      return null;
    }
    final decoded = jsonDecode(value);
    if (decoded is! List) {
      return null;
    }
    return _decodeQuickCommands(decoded);
  } on Object {
    return null;
  }
}

Future<void> writeQuickCommands(List<QuickCommand> commands) async {
  try {
    final value = jsonEncode(commands.map(_encodeQuickCommand).toList());
    _localStorage.callMethod<JSAny?>(
      'setItem'.toJS,
      _quickCommandsKey.toJS,
      value.toJS,
    );
  } on Object {
    return;
  }
}

Future<void> writeQuickCommandsPanelVisible(bool value) async {
  try {
    _localStorage.callMethod<JSAny?>(
      'setItem'.toJS,
      _quickCommandsPanelVisibleKey.toJS,
      value.toString().toJS,
    );
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
