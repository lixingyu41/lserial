import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lserial/app/app.dart';
import 'package:lserial/app/localization.dart';
import 'package:lserial/application/session_controller.dart';
import 'package:lserial/application/workspace_controller.dart';
import 'package:lserial/application/workspace_settings.dart';
import 'package:lserial/core/encoding/data_format.dart';
import 'package:lserial/domain/classic_bluetooth_device_info.dart';
import 'package:lserial/domain/connection_config.dart';
import 'package:lserial/domain/data_frame.dart';
import 'package:lserial/domain/transport.dart';
import 'package:lserial/features/console/frame_list_view.dart';
import 'package:lserial/features/console/workspace_console_panel.dart';
import 'package:lserial/features/connection/connection_panel.dart';
import 'package:lserial/features/quick_commands/quick_commands_panel.dart';
import 'package:lserial/protocol/frame_formatter.dart';
import 'package:lserial/storage/log_buffer.dart';

void main() {
  testWidgets('communication tool shell smoke test', (tester) async {
    tester.view
      ..physicalSize = const Size(1280, 800)
      ..devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const CommToolApp());
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.zh.connectionType), findsOneWidget);
    expect(find.text(AppStrings.zh.sendData), findsOneWidget);
  });

  testWidgets('baud wheel stops at the highest supported rate', (tester) async {
    final controller = WorkspaceController();
    addTearDown(controller.dispose);
    final session = controller.activeSession;
    session.updateConfig(
      session.config.copyWith(
        serial: session.config.serial.copyWith(baudRate: 921600),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 700,
            child: ConnectionPanel(
              workspaceController: controller,
              controller: session,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final baudField = find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> && key.value.startsWith('baud-');
    });
    expect(baudField, findsOneWidget);
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(baudField),
        scrollDelta: const Offset(0, 20),
      ),
    );
    await tester.pumpAndSettle();

    expect(session.config.serial.baudRate, 921600);
  });

  testWidgets('serial forwarding is offered only for a new serial session', (
    tester,
  ) async {
    final workspace = WorkspaceController();
    addTearDown(workspace.dispose);
    workspace.activeSession
      ..status = TransportStatus.connected
      ..updateConfig(
        const ConnectionConfig(
          type: TransportType.serial,
          serial: SerialConfig(portName: 'COM1'),
        ),
      );
    await workspace.addSession();
    final newSession = workspace.activeSession;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 700,
            child: ConnectionPanel(
              workspaceController: workspace,
              controller: newSession,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.zh.serialForwarding), findsOneWidget);

    newSession.status = TransportStatus.connected;
    newSession.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.zh.serialForwarding), findsNothing);
  });

  testWidgets('classic Bluetooth status and actions use aligned columns', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(520, 720)
      ..devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final workspace = WorkspaceController();
    addTearDown(workspace.dispose);
    final session = workspace.activeSession;
    session.updateConfig(
      session.config.copyWith(type: TransportType.bluetoothClassic),
    );
    session.classicBluetoothDevices = const <ClassicBluetoothDeviceInfo>[
      ClassicBluetoothDeviceInfo(
        address: '01:23:45:67:89:AB',
        name: 'Paired device',
        paired: true,
        connected: false,
        remembered: true,
      ),
      ClassicBluetoothDeviceInfo(
        address: '01:23:45:67:89:AC',
        name: 'Unpaired device',
        paired: false,
        connected: false,
        remembered: false,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 500,
            height: 700,
            child: ConnectionPanel(
              workspaceController: workspace,
              controller: session,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final address in const <String>[
      '01:23:45:67:89:AB',
      '01:23:45:67:89:AC',
    ]) {
      final status = find.byKey(
        ValueKey<String>('classic-device-status-$address'),
      );
      final action = find.byKey(
        ValueKey<String>('classic-device-action-$address'),
      );
      expect(tester.getCenter(status).dy, tester.getCenter(action).dy);
    }
    expect(
      tester
          .getCenter(
            find.byKey(
              const ValueKey<String>('classic-device-action-01:23:45:67:89:AB'),
            ),
          )
          .dx,
      tester
          .getCenter(
            find.byKey(
              const ValueKey<String>('classic-device-action-01:23:45:67:89:AC'),
            ),
          )
          .dx,
    );
  });

  testWidgets('empty console search expands on click and collapses on blur', (
    tester,
  ) async {
    final controller = WorkspaceController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 400,
            child: WorkspaceConsolePanel(controller: controller),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final toggle = find.byKey(const ValueKey<String>('console-search-toggle'));
    expect(toggle, findsOneWidget);
    expect(tester.getSize(toggle), const Size.square(40));
    expect(
      find.byKey(const ValueKey<String>('console-search-field')),
      findsNothing,
    );

    await tester.tap(toggle);
    await tester.pumpAndSettle();

    final field = find.byKey(const ValueKey<String>('console-search-field'));
    expect(field, findsOneWidget);

    await tester.enterText(field, 'COM1');
    await tester.tapAt(const Offset(300, 100));
    await tester.pumpAndSettle();
    expect(field, findsOneWidget);

    await tester.tap(field);
    await tester.enterText(field, '');
    await tester.tapAt(const Offset(300, 100));
    await tester.pumpAndSettle();
    expect(toggle, findsOneWidget);
    expect(field, findsNothing);
  });

  testWidgets('quick command bubble exposes TXT import and export actions', (
    tester,
  ) async {
    final controller = SessionController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 500,
            child: QuickCommandsPanel(
              controller: controller,
              loadBubblePosition: () async => null,
              saveBubblePosition: (_) async {},
            ),
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('quick-command-bubble-toggle')),
    );
    await tester.pumpAndSettle();
    final menu = find.byTooltip(AppStrings.zh.quickCommandImportExport);
    expect(menu, findsOneWidget);
    await tester.tap(menu);
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.zh.importReplaceCurrent), findsOneWidget);
    expect(find.text(AppStrings.zh.importInsertCurrent), findsOneWidget);
    expect(find.text(AppStrings.zh.exportQuickCommands), findsOneWidget);
  });

  testWidgets('log settings expose values and visibility for toolbar actions', (
    tester,
  ) async {
    final controller = WorkspaceController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 700,
            child: WorkspaceConsolePanel(controller: controller),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final logSettings = find.byTooltip(AppStrings.zh.logSettings);
    expect(logSettings, findsOneWidget);
    await tester.tap(logSettings);
    await tester.pumpAndSettle();

    for (final section in <String>['display', 'toolbar', 'sources']) {
      expect(
        find.byKey(ValueKey<String>('settings-section-$section')),
        findsOneWidget,
      );
    }

    for (final action in WorkspaceToolbarAction.values) {
      expect(
        find.byKey(ValueKey<String>('toolbar-visibility-${action.name}')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey<String>('toolbar-setting-row-${action.name}')),
        findsOneWidget,
      );
    }
    for (final action in WorkspaceToolbarAction.values.where(
      (action) => action != WorkspaceToolbarAction.clearLog,
    )) {
      expect(
        find.byKey(ValueKey<String>('toolbar-setting-${action.name}')),
        findsOneWidget,
      );
    }
    expect(
      find.byKey(const ValueKey<String>('toolbar-setting-clearLog')),
      findsNothing,
    );
    expect(find.text(AppStrings.zh.searchFilter), findsNothing);
    expect(find.text(AppStrings.zh.viewFormat), findsOneWidget);

    final sourceMode = find.byKey(
      ValueKey<String>(
        'source-view-mode-${controller.activeSession.sourceLabel}',
      ),
    );
    expect(sourceMode, findsOneWidget);
    expect(
      find.byKey(
        ValueKey<String>(
          'source-setting-row-${controller.activeSession.sourceLabel}',
        ),
      ),
      findsOneWidget,
    );
    await tester.ensureVisible(sourceMode);
    await tester.tap(find.descendant(of: sourceMode, matching: find.text('H')));
    await tester.pumpAndSettle();
    expect(
      controller.viewModeForSource(controller.activeSession.sourceLabel),
      ConsoleViewMode.hex,
    );

    final quickCommandsSwitch = find.byKey(
      const ValueKey<String>('toolbar-setting-quickCommandsPanel'),
    );
    await tester.ensureVisible(quickCommandsSwitch);
    await tester.tap(quickCommandsSwitch);
    await tester.pumpAndSettle();
    expect(controller.showQuickCommandsPanel, isTrue);

    final autoScrollVisibility = find.byKey(
      const ValueKey<String>('toolbar-visibility-autoScroll'),
    );
    expect(
      find.descendant(
        of: autoScrollVisibility,
        matching: find.byIcon(Icons.close),
      ),
      findsOneWidget,
    );
    await tester.ensureVisible(autoScrollVisibility);
    await tester.tap(autoScrollVisibility);
    await tester.pumpAndSettle();
    expect(
      controller.isToolbarActionVisible(WorkspaceToolbarAction.autoScroll),
      isTrue,
    );
  });

  testWidgets(
    'toolbar hides configured actions but keeps search and view mode',
    (tester) async {
      final controller = WorkspaceController();
      addTearDown(controller.dispose);
      for (final action in WorkspaceToolbarAction.values) {
        controller.setToolbarActionVisible(action, false);
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1400,
              height: 400,
              child: WorkspaceConsolePanel(controller: controller),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip(AppStrings.zh.searchFilter), findsOneWidget);
      expect(find.byTooltip(AppStrings.zh.viewFormat), findsOneWidget);
      expect(find.byTooltip(AppStrings.zh.clear), findsNothing);
      expect(find.byTooltip(AppStrings.zh.autoScroll), findsNothing);
      expect(find.byTooltip(AppStrings.zh.terminalMode), findsNothing);
      expect(find.byTooltip(AppStrings.zh.inputFormat), findsNothing);
      expect(find.byTooltip(AppStrings.zh.lineEnding), findsNothing);
      expect(
        find.byTooltip(
          AppStrings.zh.shortcutMode(controller.sendTarget.sendShortcutMode),
        ),
        findsNothing,
      );
      expect(find.byTooltip(AppStrings.zh.leftConfigPanel), findsNothing);
      expect(find.byTooltip(AppStrings.zh.quickCommands), findsNothing);
      expect(find.byTooltip(AppStrings.zh.sendData), findsNothing);
      expect(find.byTooltip(AppStrings.zh.logSettings), findsOneWidget);
    },
  );

  testWidgets('console filtering preserves source and format behavior', (
    tester,
  ) async {
    final snapshot = LogSnapshot(
      revision: 1,
      frames: <DataFrame>[
        DataFrame(
          sequence: 1,
          timestamp: DateTime(2026),
          direction: FrameDirection.rx,
          bytes: 'alpha'.codeUnits,
          source: 'COM1',
        ),
        DataFrame(
          sequence: 2,
          timestamp: DateTime(2026),
          direction: FrameDirection.tx,
          bytes: <int>[0x42],
          source: 'COM2',
        ),
      ],
      totalFrames: 2,
      totalBytes: 6,
      droppedFrames: 0,
      droppedBytes: 0,
      paused: false,
    );

    await tester.pumpWidget(
      _ConsoleHarness(
        snapshot: snapshot,
        options: const ConsoleFormatOptions(
          viewMode: ConsoleViewMode.ascii,
          showTimestamp: false,
          showDirection: true,
          showSource: true,
        ),
        filter: 'COM1',
        visibleSources: const <String>{'COM1'},
      ),
    );

    expect(
      find.textContaining('COM1 R: alpha', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('COM2', findRichText: true), findsNothing);

    await tester.pumpWidget(
      _ConsoleHarness(
        snapshot: snapshot,
        options: const ConsoleFormatOptions(
          viewMode: ConsoleViewMode.hex,
          showTimestamp: false,
          showDirection: false,
          showSource: true,
        ),
        filter: '42',
        visibleSources: const <String>{'COM2'},
      ),
    );

    expect(find.textContaining('COM2 42', findRichText: true), findsOneWidget);
    expect(find.textContaining('alpha', findRichText: true), findsNothing);
  });

  testWidgets('console can hide ASCII line ending symbols', (tester) async {
    final snapshot = LogSnapshot(
      revision: 1,
      frames: <DataFrame>[
        DataFrame(
          sequence: 1,
          timestamp: DateTime(2026),
          direction: FrameDirection.rx,
          bytes: <int>[0x6f, 0x6b, 0x0d, 0x0a],
          source: 'COM1',
        ),
      ],
      totalFrames: 1,
      totalBytes: 4,
      droppedFrames: 0,
      droppedBytes: 0,
      paused: false,
    );

    await tester.pumpWidget(
      _ConsoleHarness(
        snapshot: snapshot,
        options: const ConsoleFormatOptions(
          viewMode: ConsoleViewMode.ascii,
          showTimestamp: false,
          showDirection: true,
          showSource: true,
          showLineEndingSymbols: true,
        ),
        filter: '',
        visibleSources: const <String>{'COM1'},
      ),
    );

    expect(
      find.textContaining(r'COM1 R: ok\r\n', findRichText: true),
      findsOneWidget,
    );

    await tester.pumpWidget(
      _ConsoleHarness(
        snapshot: snapshot,
        options: const ConsoleFormatOptions(
          viewMode: ConsoleViewMode.ascii,
          showTimestamp: false,
          showDirection: true,
          showSource: true,
          showLineEndingSymbols: false,
        ),
        filter: '',
        visibleSources: const <String>{'COM1'},
      ),
    );

    expect(
      find.textContaining('COM1 R: ok', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining(r'\r\n', findRichText: true), findsNothing);
  });

  testWidgets('console renders and searches each source in its own format', (
    tester,
  ) async {
    final snapshot = LogSnapshot(
      revision: 1,
      frames: <DataFrame>[
        DataFrame(
          sequence: 1,
          timestamp: DateTime(2026),
          direction: FrameDirection.rx,
          bytes: <int>[0x41, 0x42],
          source: 'COM17',
        ),
        DataFrame(
          sequence: 2,
          timestamp: DateTime(2026),
          direction: FrameDirection.rx,
          bytes: <int>[0x43, 0x44],
          source: 'TCP',
        ),
      ],
      totalFrames: 2,
      totalBytes: 4,
      droppedFrames: 0,
      droppedBytes: 0,
      paused: false,
    );
    const sourceViewModes = <String, ConsoleViewMode>{
      'COM17': ConsoleViewMode.ascii,
      'TCP': ConsoleViewMode.hex,
    };

    await tester.pumpWidget(
      _ConsoleHarness(
        snapshot: snapshot,
        options: const ConsoleFormatOptions(
          viewMode: ConsoleViewMode.ascii,
          showTimestamp: false,
          showDirection: true,
          showSource: true,
        ),
        filter: '',
        visibleSources: const <String>{'COM17', 'TCP'},
        sourceViewModes: sourceViewModes,
      ),
    );

    expect(
      find.textContaining('COM17 R: AB', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('TCP R: 43 44', findRichText: true),
      findsOneWidget,
    );

    await tester.pumpWidget(
      _ConsoleHarness(
        snapshot: snapshot,
        options: const ConsoleFormatOptions(
          viewMode: ConsoleViewMode.ascii,
          showTimestamp: false,
          showDirection: true,
          showSource: true,
        ),
        filter: '43 44',
        visibleSources: const <String>{'COM17', 'TCP'},
        sourceViewModes: sourceViewModes,
      ),
    );

    expect(
      find.textContaining('TCP R: 43 44', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('COM17', findRichText: true), findsNothing);
  });

  testWidgets('console fixes line metrics for mixed receive payloads', (
    tester,
  ) async {
    final frames = <DataFrame>[
      DataFrame(
        sequence: 1,
        timestamp: DateTime(2026, 1, 1, 8, 50),
        direction: FrameDirection.rx,
        bytes: utf8.encode('ASCII'),
        source: 'COM17',
      ),
      DataFrame(
        sequence: 2,
        timestamp: DateTime(2026, 1, 1, 8, 50, 0, 1),
        direction: FrameDirection.rx,
        bytes: utf8.encode('中文'),
        source: 'COM17',
      ),
      DataFrame(
        sequence: 3,
        timestamp: DateTime(2026, 1, 1, 8, 50, 0, 2),
        direction: FrameDirection.rx,
        bytes: <int>[0x0d, 0x0a],
        source: 'COM17',
      ),
    ];
    await tester.pumpWidget(
      _ConsoleHarness(
        snapshot: LogSnapshot(
          revision: 1,
          frames: frames,
          totalFrames: frames.length,
          totalBytes: frames.fold(0, (sum, frame) => sum + frame.byteLength),
          droppedFrames: 0,
          droppedBytes: 0,
          paused: false,
        ),
        options: const ConsoleFormatOptions(
          viewMode: ConsoleViewMode.ascii,
          showTimestamp: true,
          showDirection: true,
          showSource: true,
        ),
        filter: '',
        visibleSources: const <String>{'COM17'},
      ),
    );

    final logLines = tester
        .widgetList<RichText>(find.byType(RichText))
        .where((text) => text.text.toPlainText().contains('COM17'))
        .toList();
    expect(logLines, hasLength(3));
    expect(
      logLines.every((text) => text.strutStyle?.forceStrutHeight ?? false),
      isTrue,
    );
    final heights = logLines
        .map((text) => tester.getSize(find.byWidget(text)).height)
        .toSet();
    expect(heights, hasLength(1));
  });

  test('ASCII control bytes use terminal caret notation', () {
    const formatter = FrameFormatter();
    const options = ConsoleFormatOptions(
      viewMode: ConsoleViewMode.ascii,
      showTimestamp: false,
      showDirection: true,
      showSource: true,
    );
    final frame = DataFrame(
      sequence: 1,
      timestamp: DateTime(2026),
      direction: FrameDirection.tx,
      bytes: <int>[0x03, 0x04, 0x1b, 0x7f],
      source: 'COM1',
    );

    expect(formatter.formatPayload(frame, options), r'^C^D^[^?');
  });
}

class _ConsoleHarness extends StatelessWidget {
  const _ConsoleHarness({
    required this.snapshot,
    required this.options,
    required this.filter,
    required this.visibleSources,
    this.sourceViewModes = const <String, ConsoleViewMode>{},
  });

  final LogSnapshot snapshot;
  final ConsoleFormatOptions options;
  final String filter;
  final Set<String> visibleSources;
  final Map<String, ConsoleViewMode> sourceViewModes;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: SizedBox(
        width: 640,
        height: 360,
        child: FrameListView(
          snapshot: snapshot,
          formatter: const FrameFormatter(),
          options: options,
          logFontSize: 12,
          autoScroll: false,
          pauseDisplay: false,
          filter: filter,
          sourceViewModes: sourceViewModes,
          visibleSources: visibleSources,
        ),
      ),
    );
  }
}
