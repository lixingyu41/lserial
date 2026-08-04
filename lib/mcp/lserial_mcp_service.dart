import '../application/workspace_controller.dart';
import 'lserial_mcp_service_base.dart';
import 'lserial_mcp_service_stub.dart'
    if (dart.library.io) 'lserial_mcp_service_io.dart'
    as implementation;

LSerialMcpService createLSerialMcpService(
  WorkspaceController workspace, {
  int port = 8765,
}) => implementation.createLSerialMcpService(workspace, port: port);
