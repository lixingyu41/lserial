import '../application/workspace_settings.dart';
import '../domain/quick_command.dart';

Future<WorkspaceSettings?> readWorkspaceSettings() async => null;

Future<void> writeWorkspaceSettings(WorkspaceSettings settings) async {}

Future<bool?> readQuickCommandsPanelVisible() async => null;

Future<void> writeQuickCommandsPanelVisible(bool value) async {}

Future<List<QuickCommand>?> readQuickCommands() async => null;

Future<void> writeQuickCommands(List<QuickCommand> commands) async {}
