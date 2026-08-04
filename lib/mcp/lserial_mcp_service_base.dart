import 'package:flutter/foundation.dart';

enum McpServiceStatus { stopped, starting, running, stopping, error }

abstract class LSerialMcpService extends ChangeNotifier {
  bool get supported;

  McpServiceStatus get status;

  String get endpoint;

  String? get errorMessage;

  Future<void> setEnabled(bool enabled);

  Future<void> start();

  Future<void> stop();
}
