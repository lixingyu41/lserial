import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lserial/app/localization.dart';
import 'package:lserial/application/workspace_controller.dart';
import 'package:lserial/features/connection/workspace_settings_info.dart';
import 'package:lserial/mcp/lserial_mcp_service_base.dart';

void main() {
  testWidgets('desktop MCP setting shows enabled switch and endpoint', (
    tester,
  ) async {
    final controller = WorkspaceController();
    final service = _FakeMcpService(supported: true);
    controller.attachMcpService(service);
    addTearDown(() {
      service.dispose();
      controller.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 320,
              child: WorkspaceSettingsInfo(controller: controller),
            ),
          ),
        ),
      ),
    );

    expect(find.text(AppStrings.zh.mcpService), findsOneWidget);
    expect(find.textContaining('127.0.0.1:8765'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
  });

  testWidgets('unsupported platform shows desktop-only MCP message', (
    tester,
  ) async {
    final controller = WorkspaceController();
    final service = _FakeMcpService(supported: false);
    controller.attachMcpService(service);
    addTearDown(() {
      service.dispose();
      controller.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 320,
              child: WorkspaceSettingsInfo(controller: controller),
            ),
          ),
        ),
      ),
    );

    expect(find.text(AppStrings.zh.mcpDesktopOnly), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
  });
}

class _FakeMcpService extends LSerialMcpService {
  _FakeMcpService({required this.supported});

  @override
  final bool supported;

  @override
  String get endpoint => 'http://127.0.0.1:8765/mcp';

  @override
  String? get errorMessage => null;

  @override
  McpServiceStatus get status => McpServiceStatus.running;

  @override
  Future<void> setEnabled(bool enabled) async {}

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}
}
