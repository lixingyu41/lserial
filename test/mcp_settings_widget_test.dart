import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lserial/app/localization.dart';
import 'package:lserial/application/workspace_controller.dart';
import 'package:lserial/features/connection/workspace_settings_info.dart';
import 'package:lserial/mcp/lserial_mcp_service_base.dart';
import 'package:lserial/update/app_update_models.dart';

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

  testWidgets('one click checks downloads and launches the update', (
    tester,
  ) async {
    final controller = WorkspaceController();
    final service = _FakeUpdateService();
    var closeCalls = 0;
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: WorkspaceSettingsInfo(
              controller: controller,
              updateService: service,
              onInstallScheduled: () async => closeCalls++,
            ),
          ),
        ),
      ),
    );

    final button = find.byKey(const ValueKey<String>('update-client-button'));
    expect(button, findsOneWidget);
    expect(find.text(AppStrings.zh.updateClient), findsOneWidget);

    await tester.tap(button);
    await tester.pump();
    await tester.pump();
    expect(service.checkCalls, 1);
    expect(service.installCalls, 1);
    expect(closeCalls, 1);
  });

  testWidgets('app stays open until the installer has started', (tester) async {
    final controller = WorkspaceController();
    final service = _FakeUpdateService()..installGate = Completer<void>();
    var closeCalls = 0;
    addTearDown(controller.dispose);
    await _mountUpdater(tester, controller, service, () async => closeCalls++);
    final button = find.byKey(const ValueKey<String>('update-client-button'));

    await tester.tap(button);
    await tester.pump();
    expect(find.text(AppStrings.zh.preparingUpdateInstall), findsOneWidget);
    expect(closeCalls, 0);
    expect(tester.widget<TextButton>(button).onPressed, isNull);

    service.installGate!.complete();
    await tester.pump();
    expect(service.installCalls, 1);
    expect(closeCalls, 1);
  });

  testWidgets('installer launch failure keeps the app open and allows retry', (
    tester,
  ) async {
    final controller = WorkspaceController();
    final service = _FakeUpdateService()
      ..installError = StateError('Installer could not start');
    var closeCalls = 0;
    addTearDown(controller.dispose);
    await _mountUpdater(tester, controller, service, () async => closeCalls++);
    final button = find.byKey(const ValueKey<String>('update-client-button'));

    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(service.checkCalls, 1);
    expect(service.installCalls, 1);
    expect(closeCalls, 0);
    expect(find.textContaining('Installer could not start'), findsOneWidget);

    service.installError = null;
    await tester.tap(button);
    await tester.pump();
    expect(service.checkCalls, 1);
    expect(service.installCalls, 2);
    expect(closeCalls, 1);
  });

  testWidgets('current version does not download or close the app', (
    tester,
  ) async {
    final controller = WorkspaceController();
    final service = _FakeUpdateService()..updateAvailable = false;
    var closeCalls = 0;
    addTearDown(controller.dispose);
    await _mountUpdater(tester, controller, service, () async => closeCalls++);
    await tester.tap(
      find.byKey(const ValueKey<String>('update-client-button')),
    );
    await tester.pumpAndSettle();
    expect(service.checkCalls, 1);
    expect(service.installCalls, 0);
    expect(closeCalls, 0);
    expect(find.text(AppStrings.zh.latestVersion('1.0.19')), findsOneWidget);
  });

  testWidgets('unsupported platform does not show automatic update action', (
    tester,
  ) async {
    final controller = WorkspaceController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: WorkspaceSettingsInfo(
              controller: controller,
              updateService: const _UnsupportedUpdateService(),
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('update-client-button')),
      findsNothing,
    );
  });
}

Future<void> _mountUpdater(
  WidgetTester tester,
  WorkspaceController controller,
  AppUpdateService service,
  Future<void> Function() onInstallScheduled,
) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 320,
        child: WorkspaceSettingsInfo(
          controller: controller,
          updateService: service,
          onInstallScheduled: onInstallScheduled,
        ),
      ),
    ),
  ),
);

class _FakeUpdateService implements AppUpdateService {
  int checkCalls = 0;
  int installCalls = 0;
  Completer<void>? installGate;
  Object? installError;
  bool updateAvailable = true;

  @override
  bool get supported => true;

  @override
  Future<AppUpdateCheckResult> checkForUpdate() async {
    checkCalls++;
    return AppUpdateCheckResult(
      currentVersion: '1.0.19',
      release: updateAvailable
          ? AppUpdateRelease(
              version: '1.0.20',
              downloadUri: Uri.parse('https://example.com/installer.exe'),
              fileName: 'installer.exe',
              fileSize: 100,
              sha256: 'abc',
            )
          : null,
    );
  }

  @override
  Future<void> downloadAndScheduleInstall(
    AppUpdateRelease release, {
    required void Function(double progress) onProgress,
  }) async {
    installCalls++;
    onProgress(0.5);
    onProgress(1);
    await installGate?.future;
    if (installError != null) {
      throw installError!;
    }
  }
}

class _UnsupportedUpdateService implements AppUpdateService {
  const _UnsupportedUpdateService();

  @override
  bool get supported => false;

  @override
  Future<AppUpdateCheckResult> checkForUpdate() {
    throw UnimplementedError();
  }

  @override
  Future<void> downloadAndScheduleInstall(
    AppUpdateRelease release, {
    required void Function(double progress) onProgress,
  }) {
    throw UnimplementedError();
  }
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
