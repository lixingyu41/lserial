@TestOn('vm')
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lserial/application/workspace_controller.dart';
import 'package:lserial/mcp/lserial_mcp_service.dart';
import 'package:lserial/mcp/lserial_mcp_service_base.dart';
import 'package:lserial/domain/data_frame.dart';
import 'package:mcp_dart/mcp_dart.dart';

void main() {
  test('desktop MCP server negotiates and exposes LSerial tools', () async {
    final workspace = WorkspaceController(
      loadWorkspaceSettings: () async => null,
      saveWorkspaceSettings: (_) async {},
    );
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
  });
}
