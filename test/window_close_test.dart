import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lserial/app/app.dart';
import 'package:lserial/application/workspace_controller.dart';
import 'package:lserial/mcp/lserial_mcp_service_base.dart';

const _windowChannel = MethodChannel('window_manager');

void main() {
  testWidgets(
    'window close hides before cleanup and ignores repeated close',
    (tester) async {
      final calls = <String>[];
      final workspace = _ClosingWorkspace(calls);
      final service = _ClosingMcpService(calls);
      await _mountApp(tester, calls, workspace, service);

      await _requestClose(tester);
      expect(calls, <String>['hide', 'stop', 'shutdown']);
      await _requestClose(tester);
      expect(calls, <String>['hide', 'stop', 'shutdown']);

      workspace.cleanup.complete();
      await tester.pump();
      expect(calls, <String>['hide', 'stop', 'shutdown']);
      service.cleanup.complete();
      await tester.pump();
      expect(calls, <String>[
        'hide',
        'stop',
        'shutdown',
        'allow-close',
        'destroy',
      ]);

      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'window close destroys at the cleanup deadline',
    (tester) async {
      final calls = <String>[];
      final workspace = _ClosingWorkspace(calls);
      final service = _ClosingMcpService(calls);
      await _mountApp(tester, calls, workspace, service);

      await _requestClose(tester);
      await tester.pump(const Duration(milliseconds: 1999));
      expect(calls, <String>['hide', 'stop', 'shutdown']);
      await tester.pump(const Duration(milliseconds: 1));
      expect(calls, <String>[
        'hide',
        'stop',
        'shutdown',
        'allow-close',
        'destroy',
      ]);

      workspace.cleanup.complete();
      service.cleanup.complete();
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'window close still cleans up when hiding fails',
    (tester) async {
      final calls = <String>[];
      final workspace = _ClosingWorkspace(calls);
      final service = _ClosingMcpService(calls);
      await _mountApp(tester, calls, workspace, service, hideFails: true);

      await _requestClose(tester);
      expect(calls, <String>['hide', 'stop', 'shutdown']);
      workspace.cleanup.complete();
      service.cleanup.complete();
      await tester.pump();
      expect(calls.last, 'destroy');

      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'window close destroys after cleanup reports an error',
    (tester) async {
      final calls = <String>[];
      final workspace = _ClosingWorkspace(calls);
      final service = _ClosingMcpService(calls);
      await _mountApp(tester, calls, workspace, service);

      await _requestClose(tester);
      service.cleanup.completeError(StateError('Service already stopped'));
      workspace.cleanup.complete();
      await tester.pump();
      expect(calls.last, 'destroy');

      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
  testWidgets(
    'closing during initialization cannot restart MCP',
    (tester) async {
      final calls = <String>[];
      final workspace = _ClosingWorkspace(calls)
        ..initializeGate = Completer<void>();
      final service = _ClosingMcpService(calls);
      await _mountApp(tester, calls, workspace, service);

      await _requestClose(tester);
      workspace.cleanup.complete();
      service.cleanup.complete();
      await tester.pump();
      expect(calls.last, 'destroy');

      workspace.initializeGate!.complete();
      await tester.pump();
      expect(service.enableCalls, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}

Future<void> _mountApp(
  WidgetTester tester,
  List<String> calls,
  _ClosingWorkspace workspace,
  _ClosingMcpService service, {
  bool hideFails = false,
}) async {
  tester.view
    ..physicalSize = const Size(1280, 800)
    ..devicePixelRatio = 1;
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(_windowChannel, (call) async {
    switch (call.method) {
      case 'hide':
        calls.add('hide');
        if (hideFails) {
          throw PlatformException(code: 'hide-failed');
        }
      case 'setPreventClose':
        if ((call.arguments as Map<Object?, Object?>)['isPreventClose'] ==
            false) {
          calls.add('allow-close');
        }
      case 'destroy':
        calls.add('destroy');
    }
    return null;
  });
  addTearDown(() {
    messenger.setMockMethodCallHandler(_windowChannel, null);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    CommToolApp(controller: workspace, mcpService: service),
  );
  await tester.pumpAndSettle();
  calls.clear();
}

Future<void> _requestClose(WidgetTester tester) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    _windowChannel.name,
    const StandardMethodCodec().encodeMethodCall(
      const MethodCall('onEvent', <String, Object?>{'eventName': 'close'}),
    ),
    null,
  );
  await tester.pump();
}

class _ClosingWorkspace extends WorkspaceController {
  _ClosingWorkspace(this.calls);

  final List<String> calls;
  final Completer<void> cleanup = Completer<void>();
  Completer<void>? initializeGate;

  @override
  Future<void> initialize() async {
    await initializeGate?.future;
  }

  @override
  Future<void> shutdown() {
    calls.add('shutdown');
    return cleanup.future;
  }
}

class _ClosingMcpService extends LSerialMcpService {
  _ClosingMcpService(this.calls);

  final List<String> calls;
  final Completer<void> cleanup = Completer<void>();
  int enableCalls = 0;

  @override
  bool get supported => true;

  @override
  McpServiceStatus get status => McpServiceStatus.running;

  @override
  String get endpoint => 'http://127.0.0.1:8765/mcp';

  @override
  String? get errorMessage => null;

  @override
  Future<void> setEnabled(bool enabled) async {
    enableCalls++;
  }

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() {
    calls.add('stop');
    return cleanup.future;
  }
}
