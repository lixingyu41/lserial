import 'workspace_preferences_stub.dart'
    if (dart.library.io) 'workspace_preferences_io.dart'
    if (dart.library.js_interop) 'workspace_preferences_web.dart' as impl;

import '../domain/quick_command.dart';

Future<bool?> readQuickCommandsPanelVisible() =>
    impl.readQuickCommandsPanelVisible();

Future<void> writeQuickCommandsPanelVisible(bool value) =>
    impl.writeQuickCommandsPanelVisible(value);

Future<List<QuickCommand>?> readQuickCommands() => impl.readQuickCommands();

Future<void> writeQuickCommands(List<QuickCommand> commands) =>
    impl.writeQuickCommands(commands);
