import 'package:flutter_test/flutter_test.dart';
import 'package:lserial/application/session_controller.dart';
import 'package:lserial/application/workspace_controller.dart';
import 'package:lserial/domain/data_frame.dart';
import 'package:lserial/domain/transport.dart';

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

  test('panel visibility settings can be toggled', () {
    final savedQuickPanelValues = <bool>[];
    final controller = WorkspaceController(
      saveQuickCommandsPanelVisible: (value) async {
        savedQuickPanelValues.add(value);
      },
    );
    addTearDown(controller.dispose);

    expect(controller.showConnectionPanel, isTrue);
    expect(controller.showSendPanel, isTrue);
    expect(controller.showQuickCommandsPanel, isFalse);

    controller.setConnectionPanelVisible(false);
    controller.setSendPanelVisible(false);
    controller.setQuickCommandsPanelVisible(true);

    expect(controller.showConnectionPanel, isFalse);
    expect(controller.showSendPanel, isFalse);
    expect(controller.showQuickCommandsPanel, isTrue);
    expect(savedQuickPanelValues, <bool>[true]);
  });

  test('stats filter defaults to all display stats', () {
    final controller = SessionController();
    addTearDown(controller.dispose);

    expect(controller.visibleStats, containsAll(sessionStatDisplayOrder));
    expect(controller.visibleStats, hasLength(sessionStatDisplayOrder.length));
  });
}
