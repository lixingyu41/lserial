import '../application/workspace_controller.dart';
import 'lserial_mcp_service_base.dart';

LSerialMcpService createLSerialMcpService(
  WorkspaceController workspace, {
  int port = 8765,
}) => _UnsupportedMcpService();

class _UnsupportedMcpService extends LSerialMcpService {
  @override
  bool get supported => false;

  @override
  McpServiceStatus get status => McpServiceStatus.stopped;

  @override
  String get endpoint => '';

  @override
  String? get errorMessage => null;

  @override
  Future<void> setEnabled(bool enabled) async {}

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}
}
