import 'dart:async';
import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../application/workspace_controller.dart';
import 'lserial_mcp_api.dart';
import 'lserial_mcp_service_base.dart';

LSerialMcpService createLSerialMcpService(
  WorkspaceController workspace, {
  int port = 8765,
}) => _IoLSerialMcpService(workspace, port: port);

class _IoLSerialMcpService extends LSerialMcpService {
  _IoLSerialMcpService(this.workspace, {required this.port})
    : api = LSerialMcpApi(workspace);

  final WorkspaceController workspace;
  final int port;
  final LSerialMcpApi api;
  StreamableMcpServer? _server;
  McpServiceStatus _status = McpServiceStatus.stopped;
  String? _errorMessage;
  Future<void> _lifecycle = Future<void>.value();
  bool _disposed = false;
  String _implementationVersion = 'development';

  @override
  bool get supported => true;

  @override
  McpServiceStatus get status => _status;

  @override
  String get endpoint {
    final boundPort = _server?.boundPort ?? port;
    return 'http://127.0.0.1:$boundPort/mcp';
  }

  @override
  String? get errorMessage => _errorMessage;

  @override
  Future<void> setEnabled(bool enabled) => enabled ? start() : stop();

  @override
  Future<void> start() {
    if (_disposed) {
      return Future<void>.value();
    }
    return _serialize(() async {
      if (_server != null || _status == McpServiceStatus.running) {
        return;
      }
      _setStatus(McpServiceStatus.starting);
      try {
        _implementationVersion = (await PackageInfo.fromPlatform()).version;
      } on Object {
        // Tests and unpackaged development runs may not expose package info.
      }
      final server = StreamableMcpServer(
        serverFactory: (_) => _createProtocolServer(),
        host: '127.0.0.1',
        port: port,
        path: '/mcp',
        allowedHosts: const <String>{'localhost', '127.0.0.1'},
        enableJsonResponse: true,
      );
      try {
        await server.start();
        if (_disposed) {
          await server.stop();
          return;
        }
        _server = server;
        _setStatus(McpServiceStatus.running);
        workspace.activeSession.appendSystemMessage('MCP 服务已启动：$endpoint');
      } on Object catch (error) {
        _server = null;
        _setStatus(McpServiceStatus.error, error.toString());
      }
    });
  }

  @override
  Future<void> stop() {
    return _serialize(() async {
      final server = _server;
      if (server == null) {
        if (_status != McpServiceStatus.stopped) {
          _setStatus(McpServiceStatus.stopped);
        }
        return;
      }
      _setStatus(McpServiceStatus.stopping);
      try {
        await server.stop();
      } finally {
        _server = null;
        _setStatus(McpServiceStatus.stopped);
      }
    });
  }

  Future<void> _serialize(Future<void> Function() action) {
    final next = _lifecycle.then((_) => action());
    _lifecycle = next.catchError((Object _, StackTrace __) {});
    return next;
  }

  void _setStatus(McpServiceStatus value, [String? error]) {
    _status = value;
    _errorMessage = error;
    if (!_disposed) {
      notifyListeners();
    }
  }

  McpServer _createProtocolServer() {
    final server = McpServer(
      Implementation(name: 'lserial', version: _implementationVersion),
      options: const McpServerOptions(protocol: McpProtocol.stable),
    );
    _registerTools(server);
    _registerResources(server);
    _registerPrompt(server);
    return server;
  }

  void _registerTools(McpServer server) {
    _tool(
      server,
      'lserial_get_state',
      'Read all LSerial sessions, connection settings, capabilities, and status.',
      _emptySchema,
      (_) async => api.state(),
      readOnly: true,
    );
    _tool(
      server,
      'lserial_list_sessions',
      'List connection sessions and their stable IDs for later calls.',
      _emptySchema,
      (_) async => <String, Object?>{'sessions': api.listSessions()},
      readOnly: true,
    );
    _tool(
      server,
      'lserial_create_session',
      'Create and activate a new connection session.',
      _emptySchema,
      (_) => api.createSession(),
    );
    _tool(
      server,
      'lserial_delete_session',
      'Delete a disconnected session. The final session cannot be deleted.',
      _sessionSchema(required: true),
      (args) => api.deleteSession(args['session_id'] as String?),
      destructive: true,
    );
    _tool(
      server,
      'lserial_activate_session',
      'Make one session the active page in the LSerial UI.',
      _sessionSchema(required: true),
      (args) => api.activateSession(args['session_id'] as String?),
    );
    _tool(
      server,
      'lserial_scan_serial_ports',
      'Refresh serial ports visible to the desktop operating system.',
      _sessionSchema(),
      (args) => api.scanSerialPorts(args['session_id'] as String?),
    );
    _tool(
      server,
      'lserial_scan_bluetooth',
      'Scan BLE devices for a bounded duration and return discovered devices.',
      JsonSchema.object(
        properties: <String, JsonSchema>{
          ..._sessionProperties,
          'timeout_ms': JsonSchema.integer(
            minimum: 500,
            maximum: 30000,
            defaultValue: 5000,
          ),
        },
      ),
      (args) => api.scanBluetooth(
        args['session_id'] as String?,
        timeoutMs: (args['timeout_ms'] as num?)?.toInt() ?? 5000,
      ),
    );
    _tool(
      server,
      'lserial_configure_connection',
      'Select serial, Bluetooth, TCP client/server, or UDP and update its settings. Omitted fields remain unchanged.',
      _configureSchema,
      (args) => api.configure(args['session_id'] as String?, args),
    );
    _tool(
      server,
      'lserial_connect',
      'Open the configured connection.',
      _sessionSchema(),
      (args) => api.connect(args['session_id'] as String?),
    );
    _tool(
      server,
      'lserial_disconnect',
      'Close the configured connection.',
      _sessionSchema(),
      (args) => api.disconnect(args['session_id'] as String?),
    );
    _tool(
      server,
      'lserial_send',
      'Send ASCII, hexadecimal, or base64 bytes through a connected session. TX source is AI[1].',
      JsonSchema.object(
        properties: <String, JsonSchema>{
          ..._sessionProperties,
          'data': JsonSchema.string(description: 'Payload text.'),
          'format': JsonSchema.string(
            enumValues: const <String>['ascii', 'hex', 'base64'],
            defaultValue: 'ascii',
          ),
          'line_ending': JsonSchema.string(
            enumValues: const <String>['none', 'cr', 'lf', 'crlf'],
            defaultValue: 'none',
          ),
        },
        required: const <String>['data'],
      ),
      (args) => api.send(
        args['session_id'] as String?,
        data: args['data'] as String,
        format: args['format'] as String? ?? 'ascii',
        lineEnding: args['line_ending'] as String? ?? 'none',
      ),
    );
    _tool(
      server,
      'lserial_read_log',
      'Read retained frames incrementally. Reuse next_sequence as after_sequence.',
      JsonSchema.object(
        properties: <String, JsonSchema>{
          ..._sessionProperties,
          'after_sequence': JsonSchema.integer(minimum: 0, defaultValue: 0),
          'direction': JsonSchema.string(
            enumValues: const <String>['all', 'rx', 'tx', 'system'],
            defaultValue: 'all',
          ),
          'max_frames': JsonSchema.integer(
            minimum: 1,
            maximum: 500,
            defaultValue: 100,
          ),
          'max_bytes': JsonSchema.integer(
            minimum: 1,
            maximum: 262144,
            defaultValue: 65536,
          ),
        },
      ),
      (args) async => api.readLog(
        args['session_id'] as String?,
        afterSequence: (args['after_sequence'] as num?)?.toInt() ?? 0,
        direction: args['direction'] as String? ?? 'all',
        maxFrames: (args['max_frames'] as num?)?.toInt() ?? 100,
        maxBytes: (args['max_bytes'] as num?)?.toInt() ?? 65536,
      ),
      readOnly: true,
    );
    _tool(
      server,
      'lserial_read_statistics',
      'Read frame counts, byte counts, rates, duration, and log retention.',
      _sessionSchema(),
      (args) async => api.statistics(args['session_id'] as String?),
      readOnly: true,
    );
    _tool(
      server,
      'lserial_read_raw_receive',
      'Read the newest raw receive bytes without waiting for packet framing.',
      JsonSchema.object(
        properties: <String, JsonSchema>{
          ..._sessionProperties,
          'max_bytes': JsonSchema.integer(
            minimum: 1,
            maximum: 262144,
            defaultValue: 65536,
          ),
        },
      ),
      (args) async => api.readRawReceive(
        args['session_id'] as String?,
        maxBytes: (args['max_bytes'] as num?)?.toInt() ?? 65536,
      ),
      readOnly: true,
    );
    _tool(
      server,
      'lserial_clear_log',
      'Clear retained logs and reset statistics for one session.',
      _sessionSchema(),
      (args) => api.clearLog(args['session_id'] as String?),
      destructive: true,
    );
    _tool(
      server,
      'lserial_set_console_options',
      'Set receive display mode, send format, line ending, auto-scroll, and display pause.',
      JsonSchema.object(
        properties: <String, JsonSchema>{
          ..._sessionProperties,
          'view_mode': JsonSchema.string(
            enumValues: const <String>['ascii', 'hex'],
          ),
          'send_format': JsonSchema.string(
            enumValues: const <String>['ascii', 'hex'],
          ),
          'line_ending': JsonSchema.string(
            enumValues: const <String>['none', 'cr', 'lf', 'crlf'],
          ),
          'auto_scroll': JsonSchema.boolean(),
          'pause_display': JsonSchema.boolean(),
        },
      ),
      (args) => api.setConsoleOptions(args['session_id'] as String?, args),
    );
    _tool(
      server,
      'lserial_list_quick_commands',
      'List reusable quick commands for one session.',
      _sessionSchema(),
      (args) async => api.listQuickCommands(args['session_id'] as String?),
      readOnly: true,
    );
    _tool(
      server,
      'lserial_create_quick_command',
      'Create an ASCII or HEX quick command.',
      _quickCommandWriteSchema,
      (args) => api.createQuickCommand(
        args['session_id'] as String?,
        name: args['name'] as String,
        content: args['content'] as String,
        format: args['format'] as String? ?? 'ascii',
      ),
    );
    _tool(
      server,
      'lserial_update_quick_command',
      'Update an existing quick command.',
      JsonSchema.object(
        properties: <String, JsonSchema>{
          ..._quickCommandWriteProperties,
          'command_id': JsonSchema.integer(minimum: 1),
        },
        required: const <String>['command_id', 'name', 'content'],
      ),
      (args) => api.updateQuickCommand(
        args['session_id'] as String?,
        commandId: (args['command_id'] as num).toInt(),
        name: args['name'] as String,
        content: args['content'] as String,
        format: args['format'] as String? ?? 'ascii',
      ),
    );
    _tool(
      server,
      'lserial_delete_quick_command',
      'Delete a quick command.',
      _quickCommandIdSchema,
      (args) => api.deleteQuickCommand(
        args['session_id'] as String?,
        (args['command_id'] as num).toInt(),
      ),
      destructive: true,
    );
    _tool(
      server,
      'lserial_execute_quick_command',
      'Send one quick command through a connected session as AI[1].',
      _quickCommandIdSchema,
      (args) => api.executeQuickCommand(
        args['session_id'] as String?,
        (args['command_id'] as num).toInt(),
      ),
    );
    _tool(
      server,
      'lserial_start_auto_send',
      'Start periodic AI[1] transmission. Minimum interval is 20 ms.',
      JsonSchema.object(
        properties: <String, JsonSchema>{
          ..._sessionProperties,
          'data': JsonSchema.string(),
          'format': JsonSchema.string(
            enumValues: const <String>['ascii', 'hex'],
            defaultValue: 'ascii',
          ),
          'line_ending': JsonSchema.string(
            enumValues: const <String>['none', 'cr', 'lf', 'crlf'],
            defaultValue: 'none',
          ),
          'interval_ms': JsonSchema.integer(minimum: 20, maximum: 86400000),
        },
        required: const <String>['data', 'interval_ms'],
      ),
      (args) => api.startAutoSend(
        args['session_id'] as String?,
        data: args['data'] as String,
        format: args['format'] as String? ?? 'ascii',
        lineEnding: args['line_ending'] as String? ?? 'none',
        intervalMs: (args['interval_ms'] as num).toInt(),
      ),
    );
    _tool(
      server,
      'lserial_stop_auto_send',
      'Stop periodic transmission for one session.',
      _sessionSchema(),
      (args) => api.stopAutoSend(args['session_id'] as String?),
    );
  }

  void _registerResources(McpServer server) {
    server.registerResource(
      'LSerial MCP guide',
      'lserial://guide',
      (
        mimeType: 'text/markdown',
        description: 'AI operation guide for LSerial.',
      ),
      (uri, extra) async => ReadResourceResult(
        contents: <ResourceContents>[
          ResourceContents.fromJson(<String, dynamic>{
            'uri': uri,
            'mimeType': 'text/markdown',
            'text': lserialMcpGuide,
          }),
        ],
      ),
    );
    server.registerResource(
      'LSerial current state',
      'lserial://state',
      (
        mimeType: 'application/json',
        description: 'Live LSerial workspace state.',
      ),
      (uri, extra) async => ReadResourceResult(
        contents: <ResourceContents>[
          ResourceContents.fromJson(<String, dynamic>{
            'uri': uri,
            'mimeType': 'application/json',
            'text': jsonEncode(api.state()),
          }),
        ],
      ),
    );
  }

  void _registerPrompt(McpServer server) {
    server.registerPrompt(
      'lserial-upper-computer',
      description: 'Operate LSerial as an upper-computer communication tool.',
      callback: (args, extra) async => const GetPromptResult(
        messages: <PromptMessage>[
          PromptMessage(
            role: PromptMessageRole.user,
            content: TextContent(text: lserialMcpGuide),
          ),
        ],
      ),
    );
  }

  void _tool(
    McpServer server,
    String name,
    String description,
    JsonObject schema,
    Future<Map<String, Object?>> Function(Map<String, dynamic>) callback, {
    bool readOnly = false,
    bool destructive = false,
  }) {
    server.registerTool(
      name,
      description: description,
      inputSchema: schema,
      annotations: ToolAnnotations(
        readOnlyHint: readOnly,
        destructiveHint: destructive,
        openWorldHint: false,
      ),
      callback: (args, extra) async {
        try {
          final result = await callback(args);
          return CallToolResult.fromStructuredContent(<String, dynamic>{
            'ok': true,
            ...result,
          });
        } on Object catch (error) {
          return CallToolResult(
            content: <Content>[TextContent(text: error.toString())],
            isError: true,
            structuredContent: <String, dynamic>{
              'ok': false,
              'error': error.toString(),
            },
          );
        }
      },
    );
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    unawaited(stop());
    super.dispose();
  }
}

final JsonObject _emptySchema = JsonSchema.object();

final Map<String, JsonSchema> _sessionProperties = <String, JsonSchema>{
  'session_id': JsonSchema.string(
    description: 'Session ID from lserial_list_sessions; omit for active.',
  ),
};

JsonObject _sessionSchema({bool required = false}) => JsonSchema.object(
  properties: _sessionProperties,
  required: required ? const <String>['session_id'] : null,
);

final JsonObject _configureSchema = JsonSchema.object(
  properties: <String, JsonSchema>{
    ..._sessionProperties,
    'type': JsonSchema.string(
      enumValues: const <String>[
        'serial',
        'bluetooth',
        'tcp_client',
        'tcp_server',
        'udp',
      ],
    ),
    'port_name': JsonSchema.string(),
    'baud_rate': JsonSchema.integer(minimum: 1),
    'data_bits': JsonSchema.integer(minimum: 5, maximum: 8),
    'stop_bits': JsonSchema.integer(minimum: 1, maximum: 2),
    'parity': JsonSchema.string(
      enumValues: const <String>['none', 'odd', 'even'],
    ),
    'packet_interval_ms': JsonSchema.integer(minimum: 0, maximum: 60000),
    'packet_delimiter': JsonSchema.string(),
    'forwarding_enabled': JsonSchema.boolean(),
    'forward_port_name': JsonSchema.string(),
    'forward_baud_rate': JsonSchema.integer(minimum: 1),
    'device_id': JsonSchema.string(),
    'device_name': JsonSchema.string(),
    'service_uuid': JsonSchema.string(),
    'characteristic_uuid': JsonSchema.string(),
    'write_characteristic_uuid': JsonSchema.string(),
    'notify_characteristic_uuid': JsonSchema.string(),
    'write_without_response': JsonSchema.boolean(),
    'host': JsonSchema.string(),
    'port': JsonSchema.integer(minimum: 1, maximum: 65535),
    'bind_address': JsonSchema.string(),
    'local_port': JsonSchema.integer(minimum: 1, maximum: 65535),
    'remote_host': JsonSchema.string(),
    'remote_port': JsonSchema.integer(minimum: 1, maximum: 65535),
  },
);

final Map<String, JsonSchema> _quickCommandWriteProperties =
    <String, JsonSchema>{
      ..._sessionProperties,
      'name': JsonSchema.string(minLength: 1),
      'content': JsonSchema.string(minLength: 1),
      'format': JsonSchema.string(
        enumValues: const <String>['ascii', 'hex'],
        defaultValue: 'ascii',
      ),
    };

final JsonObject _quickCommandWriteSchema = JsonSchema.object(
  properties: _quickCommandWriteProperties,
  required: const <String>['name', 'content'],
);

final JsonObject _quickCommandIdSchema = JsonSchema.object(
  properties: <String, JsonSchema>{
    ..._sessionProperties,
    'command_id': JsonSchema.integer(minimum: 1),
  },
  required: const <String>['command_id'],
);

const String lserialMcpGuide = '''
# LSerial MCP operation guide

Use `lserial_list_sessions` first and keep its `session_id`. Scan before selecting a serial port or BLE device. Change configuration only while disconnected, then call `lserial_connect`. Use `lserial_send` for TX and poll `lserial_read_log` with the returned `next_sequence`; use `lserial_read_statistics` for counters and rates. Disconnect before deleting or reconfiguring a session.

MCP service and control operations are system logs (`SYS`). Only bytes sent by MCP use TX source `AI[1]`. MCP listens only on the desktop loopback address and does not provide remote network access.
''';
