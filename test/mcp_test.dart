@TestOn('vm')
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lserial/application/session_controller.dart';
import 'package:lserial/application/workspace_controller.dart';
import 'package:lserial/domain/classic_bluetooth_diagnostic.dart';
import 'package:lserial/domain/classic_bluetooth_device_info.dart';
import 'package:lserial/mcp/lserial_mcp_service.dart';
import 'package:lserial/mcp/lserial_mcp_service_base.dart';
import 'package:lserial/domain/data_frame.dart';
import 'package:lserial/transports/transport_registry.dart';
import 'package:mcp_dart/mcp_dart.dart';

void main() {
  test('desktop MCP server negotiates and exposes LSerial tools', () async {
    final workspace = WorkspaceController(
      loadWorkspaceSettings: () async => null,
      saveWorkspaceSettings: (_) async {},
    );
    final originalSession = workspace.activeSession;
    workspace.sessions[0] = SessionController(
      registry: const _FailingClassicBluetoothRegistry(),
    );
    originalSession.dispose();
    final service = createLSerialMcpService(workspace, port: 0);
    workspace.attachMcpService(service);
    addTearDown(() async {
      await service.stop();
      service.dispose();
      workspace.dispose();
    });

    await service.start();
    expect(service.status, McpServiceStatus.running);
    final serviceLog = workspace.activeSession.logBuffer
        .snapshot(paused: false)
        .frames
        .last;
    expect(serviceLog.direction, FrameDirection.system);
    expect(serviceLog.source, 'system');
    expect(utf8.decode(serviceLog.bytes), startsWith('MCP 服务已启动'));

    final client = McpClient(
      const Implementation(name: 'lserial-test', version: '1.0.0'),
      options: const McpClientOptions(protocol: McpProtocol.stable),
    );
    addTearDown(client.close);
    await client.connect(
      StreamableHttpClientTransport(Uri.parse(service.endpoint)),
    );

    final tools = await client.listTools();
    expect(
      tools.tools.map((tool) => tool.name),
      containsAll(<String>[
        'lserial_get_state',
        'lserial_scan_serial_ports',
        'lserial_scan_bluetooth_classic',
        'lserial_pair_bluetooth_classic',
        'lserial_unpair_bluetooth_classic',
        'lserial_read_bluetooth_diagnostics',
        'lserial_clear_bluetooth_diagnostics',
        'lserial_configure_connection',
        'lserial_send',
        'lserial_read_log',
        'lserial_read_statistics',
      ]),
    );

    final result = await client.callTool(
      const CallToolRequest(name: 'lserial_get_state', arguments: {}),
    );
    expect(result.isError, isFalse);
    expect(result.structuredContent?['ok'], isTrue);
    expect(result.structuredContent?['session_count'], 1);

    workspace.setAutoScroll(false);
    final updatedState = await client.callTool(
      const CallToolRequest(name: 'lserial_get_state', arguments: {}),
    );
    final sessions = updatedState.structuredContent?['sessions'] as List;
    final session = sessions.first as Map;
    final options = session['options'] as Map;
    expect(options['auto_scroll'], isFalse);

    final pairResult = await client.callTool(
      const CallToolRequest(
        name: 'lserial_pair_bluetooth_classic',
        arguments: <String, Object?>{'address': '01:23:45:67:89:AB'},
      ),
    );
    expect(pairResult.isError, isTrue);
    final directDiagnostic =
        pairResult.structuredContent?['bluetooth_diagnostic'] as Map;
    expect(directDiagnostic['stage'], 'authentication');
    expect(directDiagnostic['native_code'], 1460);

    final diagnostics = await client.callTool(
      const CallToolRequest(
        name: 'lserial_read_bluetooth_diagnostics',
        arguments: <String, Object?>{'after_id': 0},
      ),
    );
    expect(diagnostics.isError, isFalse);
    final records = diagnostics.structuredContent?['diagnostics'] as List;
    expect(records, hasLength(2));
    final diagnostic = records.last as Map;
    expect(diagnostic['stage'], 'authentication');
    expect(diagnostic['native_code'], 1460);
    expect(diagnostics.structuredContent?['next_id'], 2);
  });
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
        message: 'Timed out.',
        suggestion: 'Retry in pairing mode.',
      ),
    );
  }
}
