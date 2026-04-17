import 'package:flutter_test/flutter_test.dart';
import 'package:lserial/application/session_controller.dart';
import 'package:lserial/application/workspace_controller.dart';
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
}
