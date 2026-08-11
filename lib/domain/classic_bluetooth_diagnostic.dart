class ClassicBluetoothDiagnostic {
  const ClassicBluetoothDiagnostic({
    required this.id,
    required this.timestamp,
    required this.operation,
    required this.stage,
    required this.level,
    required this.message,
    this.address,
    this.nativeCodeType,
    this.nativeCode,
    this.elapsedMs,
    this.suggestion,
  });

  final int id;
  final DateTime timestamp;
  final String operation;
  final String stage;
  final String level;
  final String message;
  final String? address;
  final String? nativeCodeType;
  final int? nativeCode;
  final int? elapsedMs;
  final String? suggestion;

  ClassicBluetoothDiagnostic copyWith({int? id, DateTime? timestamp}) {
    return ClassicBluetoothDiagnostic(
      id: id ?? this.id,
      timestamp: timestamp ?? this.timestamp,
      operation: operation,
      stage: stage,
      level: level,
      message: message,
      address: address,
      nativeCodeType: nativeCodeType,
      nativeCode: nativeCode,
      elapsedMs: elapsedMs,
      suggestion: suggestion,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'timestamp': timestamp.toIso8601String(),
    'operation': operation,
    'stage': stage,
    'level': level,
    'address': address,
    'native_code_type': nativeCodeType,
    'native_code': nativeCode,
    'native_code_hex': nativeCode == null
        ? null
        : '0x${nativeCode!.toUnsigned(32).toRadixString(16).padLeft(8, '0').toUpperCase()}',
    'elapsed_ms': elapsedMs,
    'message': message,
    'suggestion': suggestion,
  };

  String toLogText() {
    final parts = <String>[
      '[经典蓝牙][${_operationLabel(operation)}][${_stageLabel(stage)}][${_levelLabel(level)}]',
      if (address != null && address!.isNotEmpty) address!,
      message,
      if (nativeCode != null)
        '${nativeCodeType ?? 'native'}=$nativeCode/${toJson()['native_code_hex']}',
      if (elapsedMs != null) '耗时=${elapsedMs}ms',
      if (suggestion != null && suggestion!.isNotEmpty) '建议：$suggestion',
    ];
    return parts.join(' ');
  }
}

class ClassicBluetoothOperationException implements Exception {
  const ClassicBluetoothOperationException(this.diagnostic);

  final ClassicBluetoothDiagnostic diagnostic;

  @override
  String toString() => diagnostic.toLogText();
}

String _operationLabel(String value) => switch (value) {
  'scan' => '扫描',
  'pair' => '配对',
  'unpair' => '解除配对',
  'connect' => 'SPP连接',
  'send' => '发送',
  'receive' => '接收',
  'disconnect' => '断开',
  _ => value,
};

String _stageLabel(String value) => switch (value) {
  'request' => '请求',
  'radio_discovery' => '查找蓝牙适配器',
  'device_discovery' => '查找设备',
  'authentication_registration' => '注册认证回调',
  'authentication' => 'Windows设备认证',
  'verification' => '验证配对状态',
  'socket_create' => '创建RFCOMM套接字',
  'service_connect' => '连接SPP服务',
  'remove_pairing' => '删除配对记录',
  'write' => '写入RFCOMM',
  'read' => '读取RFCOMM',
  'completed' => '完成',
  _ => value,
};

String _levelLabel(String value) => switch (value) {
  'info' => '进行中',
  'success' => '成功',
  'error' => '失败',
  _ => value,
};
