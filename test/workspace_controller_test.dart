import 'package:flutter_test/flutter_test.dart';
import 'package:lserial/app/localization.dart';
import 'package:lserial/application/session_controller.dart';
import 'package:lserial/application/workspace_controller.dart';
import 'package:lserial/application/workspace_settings.dart';
import 'package:lserial/core/encoding/data_format.dart';
import 'package:lserial/domain/data_frame.dart';
import 'package:lserial/domain/quick_command.dart';
import 'package:lserial/domain/transport.dart';
import 'package:lserial/transports/transport_registry.dart';

void main() {
  test('add action reuses existing empty page when active page is connected',
      () async {
    final controller = WorkspaceController();
    addTearDown(controller.dispose);

    controller.activeSession.status = TransportStatus.connected;
    controller.sessions.add(SessionController(serialAliasNumber: 2));

    expect(controller.activeSessionIndex, 0);
    expect(controller.canAddSession, isTrue);

    await controller.addSession();

    expect(controller.sessions, hasLength(2));
    expect(controller.activeSessionIndex, 1);
    expect(controller.pageIndicator, isEmpty);
  });

  test('session page navigation updates page indicator', () {
    final controller = WorkspaceController();
    addTearDown(controller.dispose);

    controller.activeSession.status = TransportStatus.connected;
    controller.sessions.add(SessionController(serialAliasNumber: 2)
      ..status = TransportStatus.connected);

    controller.nextSession();

    expect(controller.activeSessionIndex, 1);
    expect(controller.pageIndicator, '2/2');

    controller.previousSession();

    expect(controller.activeSessionIndex, 0);
    expect(controller.pageIndicator, '1/2');
  });

  test('source filter keeps labels from disconnected session logs', () {
    final controller = WorkspaceController();
    addTearDown(controller.dispose);

    final session = controller.activeSession;
    session.logBuffer.addAll(<DataFrame>[
      DataFrame(
        sequence: 1,
        timestamp: DateTime(2026),
        direction: FrameDirection.rx,
        bytes: <int>[0x41],
        source: 'COM1',
      ),
    ]);

    session.status = TransportStatus.disconnected;

    expect(controller.sourceLabels, contains('COM1'));
    expect(controller.visibleSources, contains('COM1'));
  });

  test('known source snapshot updates do not notify whole workspace', () {
    final controller = WorkspaceController();
    addTearDown(controller.dispose);
    final session = controller.activeSession;

    var workspaceNotifications = 0;
    var snapshotNotifications = 0;
    controller.addListener(() => workspaceNotifications++);
    controller.displaySnapshot.addListener(() => snapshotNotifications++);

    session.logBuffer.addAll(<DataFrame>[
      DataFrame(
        sequence: 1,
        timestamp: DateTime(2026),
        direction: FrameDirection.rx,
        bytes: <int>[0x41],
        source: 'COM1',
      ),
    ]);
    session.displaySnapshot.value = session.logBuffer.snapshot(paused: false);
    expect(workspaceNotifications, 1);

    workspaceNotifications = 0;
    snapshotNotifications = 0;
    session.logBuffer.addAll(<DataFrame>[
      DataFrame(
        sequence: 2,
        timestamp: DateTime(2026),
        direction: FrameDirection.rx,
        bytes: <int>[0x42],
        source: 'COM1',
      ),
    ]);
    session.displaySnapshot.value = session.logBuffer.snapshot(paused: false);

    expect(snapshotNotifications, 1);
    expect(workspaceNotifications, 0);
  });

  test('send target can step through connected sessions', () {
    final controller = WorkspaceController();
    addTearDown(controller.dispose);

    controller.activeSession.status = TransportStatus.connected;
    controller.sessions.add(SessionController(serialAliasNumber: 2)
      ..status = TransportStatus.connected);
    controller.sessions.add(SessionController(serialAliasNumber: 3)
      ..status = TransportStatus.connected);

    controller.stepSendTarget(1);
    expect(controller.sendTargetIndex, 1);

    controller.stepSendTarget(1);
    expect(controller.sendTargetIndex, 2);

    controller.stepSendTarget(1);
    expect(controller.sendTargetIndex, 0);

    controller.stepSendTarget(-1);
    expect(controller.sendTargetIndex, 2);
  });

  test('workspace settings load and save display preferences', () async {
    final savedSettings = <WorkspaceSettings>[];
    final controller = WorkspaceController(
      loadWorkspaceSettings: () async => const WorkspaceSettings(
        viewMode: ConsoleViewMode.hex,
        showTimestamp: false,
        showDirection: false,
        showSource: false,
        showContent: false,
        showLineEndingSymbols: true,
        autoScroll: false,
        showConnectionPanel: false,
        showSendPanel: false,
        showQuickCommandsPanel: true,
        terminalMode: false,
        logFontSize: 16,
        language: AppLanguage.en,
        hiddenToolbarActions: <WorkspaceToolbarAction>{
          WorkspaceToolbarAction.clearLog,
          WorkspaceToolbarAction.autoScroll,
        },
      ),
      saveWorkspaceSettings: (settings) async {
        savedSettings.add(settings);
      },
    );
    addTearDown(controller.dispose);

    await controller.initialize();

    expect(controller.viewMode, ConsoleViewMode.hex);
    expect(controller.showTimestamp, isFalse);
    expect(controller.showDirection, isFalse);
    expect(controller.showSource, isFalse);
    expect(controller.showContent, isFalse);
    expect(controller.showLineEndingSymbols, isTrue);
    expect(controller.autoScroll, isFalse);
    expect(controller.showConnectionPanel, isFalse);
    expect(controller.showSendPanel, isFalse);
    expect(controller.showQuickCommandsPanel, isTrue);
    expect(controller.statsPanelExpanded, isFalse);
    expect(controller.settingsPanelExpanded, isFalse);
    expect(controller.logFontSize, 16);
    expect(controller.language, AppLanguage.en);
    expect(
      controller.isToolbarActionVisible(WorkspaceToolbarAction.clearLog),
      isFalse,
    );
    expect(
      controller.isToolbarActionVisible(WorkspaceToolbarAction.autoScroll),
      isFalse,
    );
    expect(
      controller.isToolbarActionVisible(
        WorkspaceToolbarAction.connectionPanel,
      ),
      isTrue,
    );

    controller.setLineEndingSymbolsVisible(false);
    controller.setLogSourceVisible('COM1', false);
    controller.setToolbarActionVisible(
      WorkspaceToolbarAction.autoScroll,
      true,
    );

    expect(savedSettings.first.showLineEndingSymbols, isFalse);
    expect(savedSettings.last.hiddenSources, contains('COM1'));
    expect(
      savedSettings.last.hiddenToolbarActions,
      isNot(contains(WorkspaceToolbarAction.autoScroll)),
    );
  });

  test('toolbar visibility settings round trip through JSON', () {
    const settings = WorkspaceSettings(
      hiddenToolbarActions: <WorkspaceToolbarAction>{
        WorkspaceToolbarAction.clearLog,
        WorkspaceToolbarAction.sendFormat,
        WorkspaceToolbarAction.sendPanel,
      },
    );

    final restored = WorkspaceSettings.fromJson(settings.toJson());

    expect(
      restored.hiddenToolbarActions,
      <WorkspaceToolbarAction>{
        WorkspaceToolbarAction.clearLog,
        WorkspaceToolbarAction.sendFormat,
        WorkspaceToolbarAction.sendPanel,
      },
    );
  });

  test('MCP is enabled by default and persists through workspace JSON', () {
    const defaults = WorkspaceSettings();
    expect(defaults.mcpEnabled, isTrue);

    final disabled = WorkspaceSettings.fromJson(
      <String, Object?>{'mcpEnabled': false},
    );
    expect(disabled.mcpEnabled, isFalse);
    expect(disabled.toJson()['mcpEnabled'], isFalse);
  });

  test('hiding connection panel restores its toolbar reopen action', () {
    final savedSettings = <WorkspaceSettings>[];
    final controller = WorkspaceController(
      saveWorkspaceSettings: (settings) async {
        savedSettings.add(settings);
      },
    );
    addTearDown(controller.dispose);

    controller.setToolbarActionVisible(
      WorkspaceToolbarAction.connectionPanel,
      false,
    );
    expect(
      controller.isToolbarActionVisible(
        WorkspaceToolbarAction.connectionPanel,
      ),
      isFalse,
    );

    controller.setConnectionPanelVisible(false);

    expect(controller.showConnectionPanel, isFalse);
    expect(
      controller.isToolbarActionVisible(
        WorkspaceToolbarAction.connectionPanel,
      ),
      isTrue,
    );
    expect(
      savedSettings.last.hiddenToolbarActions,
      isNot(contains(WorkspaceToolbarAction.connectionPanel)),
    );
  });

  test('panel visibility settings can be toggled', () {
    final savedSettings = <WorkspaceSettings>[];
    final controller = WorkspaceController(
      saveWorkspaceSettings: (settings) async {
        savedSettings.add(settings);
      },
    );
    addTearDown(controller.dispose);

    expect(controller.showConnectionPanel, isTrue);
    expect(controller.showSendPanel, isTrue);
    expect(controller.showQuickCommandsPanel, isFalse);
    expect(controller.statsPanelExpanded, isFalse);
    expect(controller.settingsPanelExpanded, isFalse);

    controller.setConnectionPanelVisible(false);
    controller.setSendPanelVisible(false);
    controller.setQuickCommandsPanelVisible(true);
    controller.setStatsPanelExpanded(true);
    controller.setSettingsPanelExpanded(true);

    expect(controller.showConnectionPanel, isFalse);
    expect(controller.showSendPanel, isFalse);
    expect(controller.showQuickCommandsPanel, isTrue);
    expect(controller.statsPanelExpanded, isTrue);
    expect(controller.settingsPanelExpanded, isTrue);
    expect(savedSettings, hasLength(5));
    expect(savedSettings.last.showConnectionPanel, isFalse);
    expect(savedSettings.last.showSendPanel, isFalse);
    expect(savedSettings.last.showQuickCommandsPanel, isTrue);
    expect(savedSettings.last.statsPanelExpanded, isTrue);
    expect(savedSettings.last.settingsPanelExpanded, isTrue);
  });

  test('terminal mode restores previous bottom send panel state', () {
    final controller = WorkspaceController();
    addTearDown(controller.dispose);

    expect(controller.terminalMode, isFalse);
    expect(controller.showSendPanel, isTrue);

    controller.setTerminalMode(true);

    expect(controller.terminalMode, isTrue);
    expect(controller.showSendPanel, isFalse);

    controller.setSendPanelVisible(true);

    expect(controller.terminalMode, isFalse);
    expect(controller.showSendPanel, isTrue);

    controller.setSendPanelVisible(false);
    controller.setTerminalMode(true);
    expect(controller.terminalMode, isTrue);
    expect(controller.showSendPanel, isFalse);

    controller.setTerminalMode(false);
    expect(controller.terminalMode, isFalse);
    expect(controller.showSendPanel, isFalse);
  });

  test('stats filter defaults to all display stats', () {
    final controller = SessionController();
    addTearDown(controller.dispose);

    expect(controller.visibleStats, containsAll(sessionStatDisplayOrder));
    expect(controller.visibleStats, hasLength(sessionStatDisplayOrder.length));
  });

  test('send line ending defaults to LF', () {
    final controller = SessionController();
    addTearDown(controller.dispose);

    expect(controller.lineEnding, LineEnding.lf);
  });

  test('quick commands load from preferences during initialization', () async {
    final controller = SessionController(
      registry: const _NoPortsRegistry(),
      loadQuickCommands: () async => const <QuickCommand>[
        QuickCommand(
          id: 8,
          name: 'Boot',
          content: 'boot',
          format: PayloadFormat.hex,
        ),
      ],
    );
    addTearDown(controller.dispose);

    await controller.initialize();

    expect(controller.quickCommands, hasLength(1));
    expect(controller.quickCommands.single.name, 'Boot');
    expect(controller.quickCommands.single.format, PayloadFormat.hex);
  });

  test('quick command edits are saved to preferences', () {
    var savedCommands = const <QuickCommand>[];
    final controller = SessionController(
      saveQuickCommands: (commands) {
        savedCommands = List<QuickCommand>.of(commands);
        return Future<void>.value();
      },
    );
    addTearDown(controller.dispose);

    controller.addQuickCommand(
      name: 'Version',
      content: 'AT+GMR',
      format: PayloadFormat.ascii,
    );
    expect(savedCommands.map((command) => command.name), contains('Version'));

    final added = savedCommands.last;
    controller.updateQuickCommand(
      id: added.id,
      name: 'Version Hex',
      content: '0A',
      format: PayloadFormat.hex,
    );
    expect(savedCommands.last.name, 'Version Hex');
    expect(savedCommands.last.format, PayloadFormat.hex);

    controller.removeQuickCommand(added.id);
    expect(
        savedCommands.map((command) => command.id), isNot(contains(added.id)));
  });

  test('quick command import supports replace and append modes', () {
    var savedCommands = const <QuickCommand>[];
    final controller = SessionController(
      saveQuickCommands: (commands) {
        savedCommands = List<QuickCommand>.of(commands);
        return Future<void>.value();
      },
    );
    addTearDown(controller.dispose);

    controller.importQuickCommands(
      const <QuickCommand>[
        QuickCommand(
          id: 99,
          name: 'Imported',
          content: 'AA 55',
          format: PayloadFormat.hex,
        ),
      ],
      mode: QuickCommandImportMode.replace,
    );
    expect(controller.quickCommands.map((command) => command.name), [
      'Imported',
    ]);
    expect(controller.quickCommands.single.id, 1);

    controller.importQuickCommands(
      const <QuickCommand>[
        QuickCommand(
          id: 1,
          name: 'Appended',
          content: 'AT',
          format: PayloadFormat.ascii,
        ),
      ],
      mode: QuickCommandImportMode.append,
    );
    expect(
      controller.quickCommands.map((command) => command.name),
      ['Imported', 'Appended'],
    );
    expect(controller.quickCommands.last.id, 2);
    expect(savedCommands, hasLength(2));
  });
}

class _NoPortsRegistry extends TransportRegistry {
  const _NoPortsRegistry();

  @override
  Future<List<String>> serialPorts() async => const <String>[];
}
