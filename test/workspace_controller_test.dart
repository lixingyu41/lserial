import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lserial/app/localization.dart';
import 'package:lserial/application/session_controller.dart';
import 'package:lserial/application/workspace_controller.dart';
import 'package:lserial/application/workspace_settings.dart';
import 'package:lserial/core/encoding/data_format.dart';
import 'package:lserial/domain/classic_bluetooth_diagnostic.dart';
import 'package:lserial/domain/classic_bluetooth_device_info.dart';
import 'package:lserial/domain/data_frame.dart';
import 'package:lserial/domain/quick_command.dart';
import 'package:lserial/domain/transport.dart';
import 'package:lserial/storage/quick_command_text_codec.dart';
import 'package:lserial/transports/transport_registry.dart';

void main() {
  test('workspace auto scroll stays synchronized with every session', () async {
    final controller = WorkspaceController(
      loadWorkspaceSettings: () async => null,
      saveWorkspaceSettings: (_) async {},
    );
    addTearDown(controller.dispose);

    controller.setAutoScroll(false);
    expect(controller.autoScroll, isFalse);
    expect(controller.sessions.every((session) => !session.autoScroll), isTrue);

    final addedSession = await controller.createAutomationSession();
    expect(addedSession.autoScroll, isFalse);
  });

  test(
    'add action reuses existing empty page when active page is connected',
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
    },
  );

  test('session page navigation updates page indicator', () {
    final controller = WorkspaceController();
    addTearDown(controller.dispose);

    controller.activeSession.status = TransportStatus.connected;
    controller.sessions.add(
      SessionController(serialAliasNumber: 2)
        ..status = TransportStatus.connected,
    );

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

  test('source filter only changes display and preserves received history', () {
    final controller = WorkspaceController(
      loadWorkspaceSettings: () async => null,
      saveWorkspaceSettings: (_) async {},
    );
    addTearDown(controller.dispose);
    final session = controller.activeSession;
    session.status = TransportStatus.connected;

    final first = DataFrame(
      sequence: 1,
      timestamp: DateTime(2026),
      direction: FrameDirection.rx,
      bytes: <int>[0x41],
      source: 'COM17',
    );
    session.logBuffer.addAll(<DataFrame>[first]);
    session.displaySnapshot.value = session.logBuffer.snapshot(paused: false);

    controller.setLogSourceVisible('COM17', false);
    expect(session.status, TransportStatus.connected);
    expect(controller.displaySnapshot.value.frames, isEmpty);

    final second = DataFrame(
      sequence: 2,
      timestamp: DateTime(2026, 1, 1, 0, 0, 1),
      direction: FrameDirection.rx,
      bytes: <int>[0x42],
      source: 'COM17',
    );
    session.logBuffer.addAll(<DataFrame>[second]);
    session.displaySnapshot.value = session.logBuffer.snapshot(paused: false);

    expect(session.status, TransportStatus.connected);
    expect(session.logBuffer.totalFrames, 2);
    expect(controller.displaySnapshot.value.totalFrames, 2);
    expect(controller.displaySnapshot.value.frames, isEmpty);

    controller.setLogSourceVisible('COM17', true);
    expect(controller.displaySnapshot.value.frames, <DataFrame>[first, second]);
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
    controller.sessions.add(
      SessionController(serialAliasNumber: 2)
        ..status = TransportStatus.connected,
    );
    controller.sessions.add(
      SessionController(serialAliasNumber: 3)
        ..status = TransportStatus.connected,
    );

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
      controller.isToolbarActionVisible(WorkspaceToolbarAction.connectionPanel),
      isTrue,
    );

    controller.setLineEndingSymbolsVisible(false);
    controller.setLogSourceVisible('COM1', false);
    controller.setToolbarActionVisible(WorkspaceToolbarAction.autoScroll, true);

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

    expect(restored.hiddenToolbarActions, <WorkspaceToolbarAction>{
      WorkspaceToolbarAction.clearLog,
      WorkspaceToolbarAction.sendFormat,
      WorkspaceToolbarAction.sendPanel,
    });
  });

  test('source view modes are independent and persist through JSON', () {
    const settings = WorkspaceSettings(
      viewMode: ConsoleViewMode.ascii,
      sourceViewModes: <String, ConsoleViewMode>{
        'COM17': ConsoleViewMode.ascii,
        'TCP Server 0.0.0.0:9100': ConsoleViewMode.hex,
      },
    );

    final restored = WorkspaceSettings.fromJson(settings.toJson());

    expect(restored.sourceViewModes, settings.sourceViewModes);
    expect(
      WorkspaceSettings.fromJson(<String, Object?>{
        'sourceViewModes': <String, Object?>{
          'COM17': 'invalid',
          'SYS': 'hex',
          'TCP': 'hex',
        },
      }).sourceViewModes,
      <String, ConsoleViewMode>{'TCP': ConsoleViewMode.hex},
    );
  });

  test('workspace controls receive format per source', () {
    final savedSettings = <WorkspaceSettings>[];
    final controller = WorkspaceController(
      saveWorkspaceSettings: (settings) async {
        savedSettings.add(settings);
      },
    );
    addTearDown(controller.dispose);

    controller.setSourceViewMode('COM17', ConsoleViewMode.hex);

    expect(controller.viewModeForSource('COM17'), ConsoleViewMode.hex);
    expect(controller.viewModeForSource('TCP'), ConsoleViewMode.ascii);
    expect(savedSettings.last.sourceViewModes['COM17'], ConsoleViewMode.hex);

    controller.setViewMode(ConsoleViewMode.hex);

    expect(controller.viewModeForSource('COM17'), ConsoleViewMode.hex);
    expect(controller.viewModeForSource('TCP'), ConsoleViewMode.hex);
    expect(controller.sourceViewModes, isEmpty);
  });

  test('MCP is enabled by default and persists through workspace JSON', () {
    const defaults = WorkspaceSettings();
    expect(defaults.mcpEnabled, isTrue);

    final disabled = WorkspaceSettings.fromJson(<String, Object?>{
      'mcpEnabled': false,
    });
    expect(disabled.mcpEnabled, isFalse);
    expect(disabled.toJson()['mcpEnabled'], isFalse);
  });

  test('Windows socket errors distinguish reserved and occupied ports', () {
    expect(
      AppStrings.zh.windowsSocketErrorMeaning(10013),
      contains('Windows 保留'),
    );
    expect(AppStrings.zh.windowsSocketErrorMeaning(10048), contains('被占用'));
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
      controller.isToolbarActionVisible(WorkspaceToolbarAction.connectionPanel),
      isFalse,
    );

    controller.setConnectionPanelVisible(false);

    expect(controller.showConnectionPanel, isFalse);
    expect(
      controller.isToolbarActionVisible(WorkspaceToolbarAction.connectionPanel),
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

  test(
    'classic Bluetooth scan, pair, and unpair update session state',
    () async {
      final registry = _ClassicBluetoothRegistry();
      final controller = SessionController(registry: registry);
      addTearDown(controller.dispose);

      await controller.scanClassicBluetoothDevices();
      expect(
        controller.classicBluetoothDevices.single.address,
        '01:23:45:67:89:AB',
      );
      expect(controller.classicBluetoothDevices.single.paired, isFalse);

      expect(
        await controller.pairClassicBluetoothDevice('01:23:45:67:89:AB'),
        isTrue,
      );
      expect(controller.config.bluetoothClassic.address, '01:23:45:67:89:AB');
      expect(controller.config.bluetoothClassic.deviceName, 'SPP fixture');
      expect(controller.classicBluetoothDevices.single.paired, isTrue);

      expect(
        await controller.unpairClassicBluetoothDevice('01:23:45:67:89:AB'),
        isTrue,
      );
      expect(controller.classicBluetoothDevices.single.paired, isFalse);
      expect(registry.unpairedAddress, '01:23:45:67:89:AB');
    },
  );

  test(
    'classic Bluetooth failure is retained and written to SYS log',
    () async {
      final controller = SessionController(
        registry: const _FailingClassicBluetoothRegistry(),
      );
      addTearDown(controller.dispose);

      final paired = await controller.pairClassicBluetoothDevice(
        '01:23:45:67:89:AB',
      );

      expect(paired, isFalse);
      expect(controller.classicBluetoothDiagnostics, hasLength(2));
      expect(controller.classicBluetoothDiagnostics.first.level, 'info');
      final diagnostic = controller.classicBluetoothDiagnostics.last;
      expect(diagnostic.operation, 'pair');
      expect(diagnostic.stage, 'authentication');
      expect(diagnostic.nativeCodeType, 'win32');
      expect(diagnostic.nativeCode, 1460);
      expect(diagnostic.elapsedMs, 30000);
      expect(diagnostic.suggestion, contains('配对模式'));
      final systemText = controller.logBuffer
          .snapshot(paused: false)
          .frames
          .map((frame) => utf8.decode(frame.bytes))
          .join('\n');
      expect(systemText, contains('[经典蓝牙][配对][Windows设备认证][失败]'));
      expect(systemText, contains('win32=1460/0x000005B4'));
    },
  );

  test('classic Bluetooth pair retains the scanned device name', () async {
    final controller = SessionController(
      registry: _ClassicBluetoothRegistry(pairName: ''),
    );
    addTearDown(controller.dispose);

    await controller.scanClassicBluetoothDevices();
    expect(
      await controller.pairClassicBluetoothDevice('01:23:45:67:89:AB'),
      isTrue,
    );

    expect(controller.classicBluetoothDevices.single.name, 'SPP fixture');
    expect(controller.config.bluetoothClassic.deviceName, 'SPP fixture');
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
      savedCommands.map((command) => command.id),
      isNot(contains(added.id)),
    );
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

    controller.importQuickCommands(const <QuickCommand>[
      QuickCommand(
        id: 99,
        name: 'Imported',
        content: 'AA 55',
        format: PayloadFormat.hex,
      ),
    ], mode: QuickCommandImportMode.replace);
    expect(controller.quickCommands.map((command) => command.name), [
      'Imported',
    ]);
    expect(controller.quickCommands.single.id, 1);

    controller.importQuickCommands(const <QuickCommand>[
      QuickCommand(
        id: 1,
        name: 'Appended',
        content: 'AT',
        format: PayloadFormat.ascii,
      ),
    ], mode: QuickCommandImportMode.append);
    expect(controller.quickCommands.map((command) => command.name), [
      'Imported',
      'Appended',
    ]);
    expect(controller.quickCommands.last.id, 2);
    expect(savedCommands, hasLength(2));
  });

  test('quick command reorder is persisted in export order', () {
    var savedCommands = const <QuickCommand>[];
    final controller = SessionController(
      saveQuickCommands: (commands) {
        savedCommands = List<QuickCommand>.of(commands);
        return Future<void>.value();
      },
    );
    addTearDown(controller.dispose);

    controller.reorderQuickCommand(0, 2);

    expect(controller.quickCommands.map((command) => command.name), <String>[
      'Reset',
      'Ping',
      'AT',
    ]);
    expect(savedCommands.map((command) => command.name), <String>[
      'Reset',
      'Ping',
      'AT',
    ]);
    final exported = encodeQuickCommandsText(controller.quickCommands);
    expect(
      exported.indexOf('\tReset\t'),
      lessThan(exported.indexOf('\tPing\t')),
    );
    expect(exported.indexOf('\tPing\t'), lessThan(exported.indexOf('\tAT\t')));
  });
}

class _NoPortsRegistry extends TransportRegistry {
  const _NoPortsRegistry();

  @override
  Future<List<String>> serialPorts() async => const <String>[];
}

class _ClassicBluetoothRegistry extends TransportRegistry {
  _ClassicBluetoothRegistry({this.pairName = 'SPP fixture'});

  final String pairName;
  String? unpairedAddress;

  @override
  Future<List<ClassicBluetoothDeviceInfo>> classicBluetoothDevices({
    Duration timeout = const Duration(seconds: 6),
  }) async => const <ClassicBluetoothDeviceInfo>[
    ClassicBluetoothDeviceInfo(
      address: '01:23:45:67:89:AB',
      name: 'SPP fixture',
      paired: false,
      connected: false,
      remembered: false,
    ),
  ];

  @override
  Future<ClassicBluetoothDeviceInfo> pairClassicBluetoothDevice(
    String address,
  ) async => ClassicBluetoothDeviceInfo(
    address: address,
    name: pairName,
    paired: true,
    connected: false,
    remembered: true,
  );

  @override
  Future<void> unpairClassicBluetoothDevice(String address) async {
    unpairedAddress = address;
  }
}

class _FailingClassicBluetoothRegistry extends TransportRegistry {
  const _FailingClassicBluetoothRegistry();

  @override
  Future<ClassicBluetoothDeviceInfo> pairClassicBluetoothDevice(
    String address,
  ) async {
    throw ClassicBluetoothOperationException(
      ClassicBluetoothDiagnostic(
        id: 0,
        timestamp: DateTime(2026),
        operation: 'pair',
        stage: 'authentication',
        level: 'error',
        address: address,
        nativeCodeType: 'win32',
        nativeCode: 1460,
        elapsedMs: 30000,
        message: 'The operation timed out.',
        suggestion: '确认设备处于配对模式后重试。',
      ),
    );
  }
}
