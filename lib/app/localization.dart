import '../application/session_options.dart';
import '../core/encoding/data_format.dart';
import '../domain/connection_config.dart';
import '../domain/transport.dart';
import '../storage/log_export_result.dart';

enum AppLanguage { zh, en }

extension AppLanguageLabel on AppLanguage {
  String get code => switch (this) {
    AppLanguage.zh => 'zh',
    AppLanguage.en => 'en',
  };

  String get nativeLabel => switch (this) {
    AppLanguage.zh => '中文',
    AppLanguage.en => 'English',
  };
}

class AppStrings {
  const AppStrings._(this.language);

  final AppLanguage language;

  static AppStrings of(AppLanguage language) => switch (language) {
    AppLanguage.zh => zh,
    AppLanguage.en => en,
  };

  static const zh = AppStrings._(AppLanguage.zh);
  static const en = AppStrings._(AppLanguage.en);

  bool get isZh => language == AppLanguage.zh;

  String get ready => isZh ? '就绪' : 'Ready';
  String get newSession => isZh ? '新建' : 'New';
  String newSessionWithTotal(int total) => isZh ? '新建/$total' : 'New/$total';

  String get previousSessionPage => isZh ? '上一个连接页' : 'Previous session';
  String get nextSessionPage => isZh ? '下一个连接页' : 'Next session';
  String get addSessionPage => isZh ? '新增连接页' : 'Add session';
  String get removeEmptySessionPage =>
      isZh ? '删除当前空白页' : 'Remove empty session';
  String get sendTo => isZh ? '发送到' : 'Send to';
  String get noConnectedTarget => isZh ? '无已连接目标' : 'No connected target';

  String get clear => isZh ? '清空' : 'Clear';
  String get terminalMode => isZh ? '终端模式' : 'Terminal mode';
  String get terminalInput => isZh ? '终端输入' : 'Terminal input';
  String get searchFilter => isZh ? '搜索过滤' : 'Search filter';
  String get logSettings => isZh ? '日志设置' : 'Log settings';
  String get settings => isZh ? '设置' : 'Settings';
  String get close => isZh ? '关闭' : 'Close';
  String get expand => isZh ? '展开' : 'Expand';
  String get collapse => isZh ? '折叠' : 'Collapse';
  String get viewFormat => isZh ? '视图格式' : 'View';
  String get logFontSize => isZh ? '日志文字大小' : 'Log font size';
  String get decreaseLogFontSize => isZh ? '减小日志字号' : 'Decrease log font size';
  String get increaseLogFontSize => isZh ? '增大日志字号' : 'Increase log font size';
  String get autoScroll => isZh ? '自动滚动' : 'Auto scroll';
  String get logToolbarButtons => isZh ? '日志栏按钮' : 'Log toolbar buttons';
  String get showInLogToolbar => isZh ? '显示在日志栏' : 'Show in log toolbar';
  String get hideFromLogToolbar => isZh ? '从日志栏隐藏' : 'Hide from log toolbar';
  String get exportTxt => isZh ? '导出为txt' : 'Export txt';
  String get sourceFilter => isZh ? '来源过滤' : 'Source filter';
  String get displayItems => isZh ? '显示项' : 'Display items';
  String get timestamp => isZh ? '时间戳' : 'Time';
  String get source => isZh ? '来源' : 'Source';
  String get direction => isZh ? '收发' : 'Direction';
  String get content => isZh ? '内容' : 'Content';
  String get lineEndingSymbols => isZh ? '换行符号' : 'Line endings';
  String get leftConfigPanel => isZh ? '左侧配置' : 'Left config';
  String get languageSetting => isZh ? '语言' : 'Language';
  String get downloadClient => isZh ? '下载客户端' : 'Download client';
  String get mcpService => isZh ? 'MCP 服务' : 'MCP service';
  String get mcpDesktopOnly =>
      isZh ? 'MCP 仅桌面客户端可用' : 'MCP is available in the desktop client only';
  String get mcpStarting => isZh ? '正在启动' : 'Starting';
  String get mcpRunning => isZh ? '运行中' : 'Running';
  String get mcpStopping => isZh ? '正在停止' : 'Stopping';
  String get mcpStopped => isZh ? '已停止' : 'Stopped';
  String get mcpError => isZh ? '启动失败' : 'Failed';

  String get connect => isZh ? '连接' : 'Connect';
  String get connecting => isZh ? '连接中' : 'Connecting';
  String get disconnect => isZh ? '断开' : 'Disconnect';
  String get disconnecting => isZh ? '断开中' : 'Disconnecting';
  String get refreshList => isZh ? '刷新列表' : 'Refresh';
  String get stopScan => isZh ? '停止扫描' : 'Stop scan';
  String get connectionType => isZh ? '连接方式' : 'Transport';
  String get disabled => isZh ? '不支持' : 'unsupported';
  String get serialPort => isZh ? '串口' : 'Serial port';
  String get serialPortA => isZh ? '串口 A' : 'Serial port A';
  String get serialPortB => isZh ? '串口 B' : 'Serial port B';
  String get serialForwarding => isZh ? '双向串口转发' : 'Bidirectional forwarding';
  String get serialForwardingDescription =>
      isZh ? '原始字节在 A 与 B 之间双向转发' : 'Forward raw bytes between A and B';
  String get chooseWebSerialPort =>
      isZh ? '选择 Web 串口' : 'Choose Web serial port';
  String get webSerialSelectedPort =>
      isZh ? '已选择 Web 串口' : 'Web serial port selected';
  String get baudRate => isZh ? '波特率' : 'Baud';
  String get baudRateA => isZh ? 'A 波特率' : 'Baud A';
  String get baudRateB => isZh ? 'B 波特率' : 'Baud B';
  String get packetIntervalMs => isZh ? '分包间隔 ms' : 'Packet gap ms';
  String get packetDelimiter => isZh ? '分包分隔符' : 'Packet delimiter';
  String get packetDelimiterPresets =>
      isZh ? '分包分隔符预设' : 'Packet delimiter presets';
  String get packetDelimiterNone => isZh ? '无' : 'None';
  String get dataBits => isZh ? '数据位' : 'Data';
  String get stopBits => isZh ? '停止位' : 'Stop';
  String get parity => isZh ? '校验' : 'Parity';
  String get host => isZh ? '主机' : 'Host';
  String get port => isZh ? '端口' : 'Port';
  String get bindAddress => isZh ? '绑定地址' : 'Bind address';
  String get listenPort => isZh ? '监听端口' : 'Listen port';
  String get localPort => isZh ? '本地端口' : 'Local port';
  String get remoteHost => isZh ? '远端主机' : 'Remote host';
  String get remotePort => isZh ? '远端端口' : 'Remote port';
  String get bluetoothInfo => isZh
      ? 'BLE 串口会自动识别常见 UART 通道；无法识别时再展开高级设置填写 UUID。'
      : 'BLE serial auto-detects common UART channels. Use advanced UUID settings only when detection fails.';
  String get deviceId => isZh ? '设备 ID' : 'Device ID';
  String get advancedBleSettings =>
      isZh ? '高级 BLE 设置' : 'Advanced BLE settings';
  String get fillWhenAutoDetectFails =>
      isZh ? '自动识别失败时再填写' : 'Fill only if auto-detect fails';
  String get serviceUuid => isZh ? 'Service UUID' : 'Service UUID';
  String get writeCharacteristicUuid =>
      isZh ? '写入 Characteristic UUID' : 'Write Characteristic UUID';
  String get notifyCharacteristicUuid =>
      isZh ? '通知 Characteristic UUID' : 'Notify Characteristic UUID';
  String get writeWithoutResponse => isZh ? '无响应写入' : 'Write without response';
  String get unknownBleDevice => isZh ? '未知 BLE 设备' : 'Unknown BLE device';

  String get stats => isZh ? '统计' : 'Stats';
  String get chooseStats => isZh ? '选择统计项' : 'Choose stats';
  String get noStatsVisible => isZh ? '未显示统计项' : 'No stats visible';
  String get framesUnit => isZh ? '帧' : 'frames';
  String get rxCount => isZh ? '接收' : 'RX';
  String get txCount => isZh ? '发送' : 'TX';
  String get rxCurrentRate => isZh ? '收速' : 'RX/s';
  String get txCurrentRate => isZh ? '发速' : 'TX/s';
  String get rxRate => isZh ? '均收' : 'Avg RX';
  String get txRate => isZh ? '均发' : 'Avg TX';
  String get sessionDuration => isZh ? '时长' : 'Time';
  String get displayCache => isZh ? '显示' : 'Display';
  String get rawCache => isZh ? '原始' : 'Raw';
  String get droppedData => isZh ? '丢弃' : 'Dropped';

  String get sendData => isZh ? '发送数据' : 'Send data';
  String get send => isZh ? '发送' : 'Send';
  String get inputFormat => isZh ? '输入' : 'Input';
  String get sendFormatSetting => isZh ? '发送格式' : 'Send format';
  String get lineEnding => isZh ? '结尾' : 'Ending';
  String get sendShortcut => isZh ? '发送快捷键' : 'Shortcut';
  String get autoSendMs => isZh ? '定时 ms' : 'Auto ms';
  String get stopAutoSend => isZh ? '停止定时' : 'Stop auto';
  String get startAutoSend => isZh ? '定时发送' : 'Auto send';
  String get hexNeedsEvenDigits =>
      isZh ? 'HEX 内容需要偶数个十六进制字符' : 'HEX input needs an even number of digits';
  String get hexInvalidChars =>
      isZh ? 'HEX 内容包含非法字符' : 'HEX input contains invalid characters';

  String get quickCommands => isZh ? '快捷指令' : 'Quick commands';
  String get quickCommandImportExport =>
      isZh ? '快捷指令导入导出' : 'Import or export quick commands';
  String get importReplaceCurrent =>
      isZh ? '导入：覆盖当前' : 'Import: replace current';
  String get importInsertCurrent =>
      isZh ? '导入：插入当前' : 'Import: insert into current';
  String get exportQuickCommands =>
      isZh ? '导出快捷指令 TXT' : 'Export quick commands TXT';
  String quickCommandsImported(int count) =>
      isZh ? '已导入 $count 条快捷指令' : 'Imported $count quick commands';
  String quickCommandImportFailed(Object error) =>
      isZh ? '快捷指令导入失败：$error' : 'Quick command import failed: $error';
  String quickCommandExportFailed(Object error) =>
      isZh ? '快捷指令导出失败：$error' : 'Quick command export failed: $error';
  String get sendHistory => isZh ? '历史发送记录' : 'Send history';
  String get noQuickCommands => isZh ? '暂无快捷指令' : 'No quick commands';
  String get addCommand => isZh ? '添加指令' : 'Add command';
  String get editCommand => isZh ? '编辑指令' : 'Edit command';
  String get name => isZh ? '名称' : 'Name';
  String get format => isZh ? '格式' : 'Format';
  String get cancel => isZh ? '取消' : 'Cancel';
  String get save => isZh ? '保存' : 'Save';
  String get edit => isZh ? '编辑' : 'Edit';
  String get delete => isZh ? '删除' : 'Delete';
  String get restoreSavedOrder => isZh ? '恢复默认排序' : 'Restore default order';

  String transportType(TransportType type) => switch (type) {
    TransportType.serial => isZh ? '串口' : 'Serial',
    TransportType.bluetooth => isZh ? '蓝牙' : 'Bluetooth',
    TransportType.tcpClient => isZh ? 'TCP 客户端' : 'TCP Client',
    TransportType.tcpServer => isZh ? 'TCP 服务端' : 'TCP Server',
    TransportType.udp => 'UDP',
  };

  String serialParity(SerialParity value) => switch (value) {
    SerialParity.none => isZh ? '无' : 'None',
    SerialParity.odd => isZh ? '奇' : 'Odd',
    SerialParity.even => isZh ? '偶' : 'Even',
  };

  String payloadFormat(PayloadFormat format) => switch (format) {
    PayloadFormat.ascii => 'ASCII',
    PayloadFormat.hex => 'HEX',
  };

  String consoleViewMode(ConsoleViewMode mode) => switch (mode) {
    ConsoleViewMode.ascii => 'ASCII',
    ConsoleViewMode.hex => 'HEX',
  };

  String lineEndingLabel(LineEnding ending) => switch (ending) {
    LineEnding.none => isZh ? '无' : 'None',
    LineEnding.cr => 'CR',
    LineEnding.lf => 'LF',
    LineEnding.crlf => 'CRLF',
  };

  String shortcutMode(SendShortcutMode mode) => switch (mode) {
    SendShortcutMode.enter => isZh ? '回车发送' : 'Enter sends',
    SendShortcutMode.ctrlEnter => isZh ? 'Ctrl+回车发送' : 'Ctrl+Enter sends',
  };

  String shortcutModeShort(SendShortcutMode mode) => switch (mode) {
    SendShortcutMode.enter => isZh ? '回车' : 'Enter',
    SendShortcutMode.ctrlEnter => isZh ? 'Ctrl+回车' : 'Ctrl+Enter',
  };

  String onOff(bool value) {
    if (isZh) {
      return value ? '开启' : '关闭';
    }
    return value ? 'On' : 'Off';
  }

  String settingChanged(String label, String value) =>
      isZh ? '$label：$value' : '$label: $value';

  String sessionStat(SessionStat stat) => switch (stat) {
    SessionStat.rxCount => rxCount,
    SessionStat.txCount => txCount,
    SessionStat.rxCurrentRate => rxCurrentRate,
    SessionStat.txCurrentRate => txCurrentRate,
    SessionStat.rxRate => rxRate,
    SessionStat.txRate => txRate,
    SessionStat.sessionDuration => sessionDuration,
    SessionStat.displayCache => displayCache,
    SessionStat.droppedData => droppedData,
    SessionStat.rawCache => rawCache,
  };

  String get openingWebBluetoothPicker =>
      isZh ? '正在打开 Web Bluetooth 选择器...' : 'Opening Web Bluetooth picker...';
  String get scanningBleDevices =>
      isZh ? '正在扫描 BLE 设备...' : 'Scanning BLE devices...';
  String get webBluetoothDeviceSelected =>
      isZh ? '已选择 Web Bluetooth 设备' : 'Web Bluetooth device selected.';
  String scanningBleDevicesCount(int count) =>
      isZh ? '正在扫描 BLE 设备：$count' : 'Scanning BLE devices: $count';
  String bleScanFailed(Object error) =>
      isZh ? 'BLE 扫描失败：${errorMessage(error)}' : 'BLE scan failed: $error';
  String get noBleDevicesFound => isZh ? '未发现 BLE 设备' : 'No BLE devices found.';
  String foundBleDevices(int count) =>
      isZh ? '发现 $count 个 BLE 设备' : 'Found $count BLE device(s).';
  String get bleScanStopped => isZh ? 'BLE 扫描已停止' : 'BLE scan stopped.';
  String bleScanStoppedWithCount(int count) =>
      isZh ? 'BLE 扫描已停止：$count 个设备' : 'BLE scan stopped: $count device(s).';
  String serialScanFailed(Object error) =>
      isZh ? '串口扫描失败：${errorMessage(error)}' : 'Serial scan failed: $error';
  String get webSerialPortSelected =>
      isZh ? '已选择 Web 串口' : 'Web serial port selected.';
  String serialPortSelectFailed(Object error) => isZh
      ? '选择串口失败：${errorMessage(error)}'
      : 'Serial port selection failed: $error';
  String unsupportedTransportOption(TransportType type, String reason) {
    final label = transportType(type);
    if (_isWebUnsupportedReason(reason)) {
      return isZh ? '$label（Web 不支持）' : '$label (web unsupported)';
    }
    return isZh ? '$label（不支持）' : '$label (unsupported)';
  }

  String transportDisabled(TransportType type, String reason) {
    final label = transportType(type);
    if (_isWebUnsupportedReason(reason)) {
      return isZh
          ? '$label Web 不支持：$reason'
          : '$label is not supported on web: $reason';
    }
    return isZh ? '$label 不支持：$reason' : '$label unsupported: $reason';
  }

  bool _isWebUnsupportedReason(String reason) {
    if (isZh) {
      return reason.contains('浏览器') || reason.contains('Web 不支持');
    }
    return reason.contains('Browser') ||
        reason.contains('browser') ||
        reason.contains('web app') ||
        reason.contains('Web apps') ||
        reason.contains('Static Web');
  }

  String get unsupportedPlatform => isZh ? '当前平台不支持' : 'Unsupported platform.';
  String platformReason(String reason) {
    if (!isZh) {
      return reason;
    }
    return switch (reason) {
      'Web Serial is not available in this browser.' => '当前浏览器不支持 Web Serial。',
      'Chrome Web Serial is available. Requires user gesture and HTTPS/localhost.' =>
        'Chrome Web Serial 可用，需要用户操作，并且运行在 HTTPS 或 localhost。',
      'Chrome Web Bluetooth is available for BLE GATT.' =>
        'Chrome Web Bluetooth 可用于 BLE GATT。',
      'Web Bluetooth is not available in this browser.' =>
        '当前浏览器不支持 Web Bluetooth。',
      'Browsers do not expose raw TCP sockets to static web apps.' =>
        '浏览器不开放原始 TCP Socket 给 Web 页面。',
      'Browsers cannot listen as raw TCP servers without a backend.' =>
        '浏览器页面不能监听原始 TCP 端口，需要后端服务。',
      'Browsers do not expose raw UDP sockets to static web apps.' =>
        '浏览器不开放原始 UDP Socket 给 Web 页面。',
      'Static Web apps cannot open raw TCP sockets in Chrome.' =>
        'Chrome 中的 Web 页面不能直接打开原始 TCP Socket。',
      'Static Web apps cannot listen as raw TCP servers in Chrome.' =>
        'Chrome 中的 Web 页面不能监听原始 TCP 端口。',
      'Static Web apps cannot open raw UDP sockets in Chrome.' =>
        'Chrome 中的 Web 页面不能直接打开原始 UDP Socket。',
      'Web Bluetooth capability detected; BLE GATT implementation is the next adapter step.' =>
        '检测到 Web Bluetooth 能力，但当前 Web 蓝牙适配器还未启用 BLE GATT 连接。',
      'Serial is not supported on this platform.' => '当前平台不支持串口。',
      'TCP Client is not supported on this platform.' => '当前平台不支持 TCP 客户端。',
      'TCP Server is not supported on this platform.' => '当前平台不支持 TCP 服务端。',
      'UDP is not supported on this platform.' => '当前平台不支持 UDP。',
      'Bluetooth adapter is reserved for BLE/SPP integration; not enabled in this MVP.' =>
        '蓝牙适配器预留给 BLE/SPP 集成，当前版本未启用。',
      'Log export is not supported on this platform.' => '当前平台不支持日志导出。',
      'Native serial via flutter_libserialport.' => '桌面串口支持已启用。',
      'BLE via universal_ble. Bluetooth Classic/SPP is not included.' =>
        'BLE 支持已启用，暂不包含经典蓝牙/SPP。',
      'Native sockets via dart:io.' => '桌面 Socket 支持已启用。',
      'Native UDP sockets via dart:io.' => '桌面 UDP 支持已启用。',
      'Unsupported platform.' => unsupportedPlatform,
      _ => reason,
    };
  }

  String errorMessage(Object error) {
    if (error is SerialOpenException) {
      return _serialOpenError(error);
    }
    final raw = error.toString();
    if (!isZh) {
      return raw;
    }

    final message = _stripErrorPrefix(raw);
    final known = _knownErrorMessage(message);
    if (known != null) {
      return known;
    }
    return _fallbackErrorMessage(message);
  }

  String _serialOpenError(SerialOpenException error) {
    final nativeDetails = error.nativeCode == null || error.nativeCode == 0
        ? ''
        : isZh
        ? '（系统错误 ${error.nativeCode}）'
        : ' (system error ${error.nativeCode})';
    return switch (error.failure) {
      SerialOpenFailure.busyOrPermission =>
        isZh
            ? '无法打开 ${error.portName}：串口正被其他程序占用，或当前账户没有访问权限。请关闭占用该串口的程序后重试$nativeDetails。'
            : 'Cannot open ${error.portName}: the port is in use by another program or access was denied. Close the program using the port and try again$nativeDetails.',
      SerialOpenFailure.unavailable =>
        isZh
            ? '无法打开 ${error.portName}：设备已断开、端口已失效或驱动未就绪。请重新插拔设备并刷新串口列表$nativeDetails。'
            : 'Cannot open ${error.portName}: the device is disconnected, the port is stale, or the driver is not ready. Reconnect the device and refresh the port list$nativeDetails.',
      SerialOpenFailure.driverInitialization =>
        isZh
            ? '无法打开 ${error.portName}：设备驱动无法初始化串口参数。系统已识别设备，但驱动拒绝应用通信设置。请重新插拔设备、换 USB 接口，或在设备管理器中重启/重装驱动。'
            : 'Cannot open ${error.portName}: the device driver could not initialize the serial settings. Reconnect the device, try another USB port, or restart/reinstall its driver.',
      SerialOpenFailure.timedOut =>
        isZh
            ? '无法打开 ${error.portName}：驱动响应超时。连接已在后台终止，请重新插拔设备后重试。'
            : 'Cannot open ${error.portName}: the driver timed out. The background connection attempt was stopped; reconnect the device and try again.',
      SerialOpenFailure.unknown =>
        isZh
            ? '无法打开 ${error.portName}：发生未知串口错误${_serialNativeMessage(error)}。'
            : 'Cannot open ${error.portName}: an unknown serial error occurred${_serialNativeMessage(error)}.',
    };
  }

  String _serialNativeMessage(SerialOpenException error) {
    final message = error.nativeMessage?.trim();
    final parts = <String>[
      if (error.nativeCode != null) '${error.nativeCode}',
      if (message != null && message.isNotEmpty) message,
    ];
    return parts.isEmpty ? '' : ' (${parts.join(': ')})';
  }

  String _stripErrorPrefix(String raw) {
    const prefixes = <String>[
      'Bad state: ',
      'Unsupported operation: ',
      'Exception: ',
      'FormatException: ',
    ];
    for (final prefix in prefixes) {
      if (raw.startsWith(prefix)) {
        return raw.substring(prefix.length);
      }
    }
    return raw;
  }

  String? _knownErrorMessage(String message) {
    final platform = platformReason(message);
    if (platform != message) {
      return platform;
    }

    final exact = switch (message) {
      'Select a Web Serial port first.' => '请先选择 Web Serial 串口。',
      'Web Serial port is not open.' => 'Web Serial 串口未打开。',
      'Web Serial writable stream is not available.' => 'Web Serial 写入流不可用。',
      'No serial port selected.' => '未选择串口。',
      'No forwarding serial port selected.' => '未选择转发串口。',
      'Forwarding serial ports must be different.' => '转发使用的两个串口不能相同。',
      'Serial port is not open.' => '串口未打开。',
      'TCP client is not connected.' => 'TCP 客户端未连接。',
      'TCP server has no connected clients.' => 'TCP 服务端没有已连接的客户端。',
      'UDP socket is not open.' => 'UDP Socket 未打开。',
      'BLE device is not selected.' => '未选择 BLE 设备。',
      'BLE session is not connected.' => 'BLE 会话未连接。',
      'No BLE UART writable characteristic found. This device does not expose a serial-like BLE channel.' =>
        '未找到可写 BLE UART 特征。该设备没有暴露类似串口的 BLE 通道。',
      _ => null,
    };
    if (exact != null) {
      return exact;
    }

    const failedSerialPrefix = 'Failed to open serial port ';
    if (message.startsWith(failedSerialPrefix)) {
      final port = _trimTrailingPeriod(
        message.substring(failedSerialPrefix.length),
      );
      return '打开串口失败：$port。';
    }

    const bleServicePrefix = 'BLE service not found: ';
    if (message.startsWith(bleServicePrefix)) {
      return '未找到 BLE 服务：${message.substring(bleServicePrefix.length)}';
    }

    const bleCharacteristicPrefix = 'BLE characteristic not found: ';
    if (message.startsWith(bleCharacteristicPrefix)) {
      return '未找到 BLE 特征：${message.substring(bleCharacteristicPrefix.length)}';
    }

    const bleWritePrefix = 'BLE write characteristic not found: ';
    if (message.startsWith(bleWritePrefix)) {
      return '未找到 BLE 写入特征：${message.substring(bleWritePrefix.length)}';
    }

    const noWritablePrefix = 'No writable BLE characteristic found in ';
    if (message.startsWith(noWritablePrefix)) {
      final service = _trimTrailingPeriod(
        message.substring(noWritablePrefix.length),
      );
      return '在 BLE 服务 $service 中未找到可写特征。';
    }

    final notifyMatch = RegExp(
      r'^BLE characteristic (.+) does not support notify or indicate\.$',
    ).firstMatch(message);
    if (notifyMatch != null) {
      return 'BLE 特征 ${notifyMatch.group(1)} 不支持通知或指示。';
    }

    final writeMatch = RegExp(
      r'^BLE characteristic (.+) does not support write\.$',
    ).firstMatch(message);
    if (writeMatch != null) {
      return 'BLE 特征 ${writeMatch.group(1)} 不支持写入。';
    }

    return null;
  }

  String _fallbackErrorMessage(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('permission') && lower.contains('denied')) {
      return '权限被拒绝：$message';
    }
    if (lower.contains('cancel')) {
      return '操作已取消：$message';
    }
    if (lower.contains('timeout') || lower.contains('timed out')) {
      return '操作超时：$message';
    }
    if (lower.contains('not available')) {
      return '当前不可用：$message';
    }
    if (lower.contains('not supported') || lower.contains('does not support')) {
      return '当前不支持：$message';
    }
    if (lower.contains('not connected')) {
      return '未连接：$message';
    }
    if (lower.contains('not found')) {
      return '未找到：$message';
    }
    return message;
  }

  String _trimTrailingPeriod(String value) {
    return value.endsWith('.') ? value.substring(0, value.length - 1) : value;
  }

  String get quickCommandEmpty =>
      isZh ? '快捷指令名称和内容不能为空' : 'Quick command name and content cannot be empty';
  String connectingTo(String target) =>
      isZh ? '正在连接 $target' : 'Connecting $target';
  String connectedTo(String target) =>
      isZh ? '已连接 $target' : 'Connected $target';
  String connectFailed(String error) =>
      isZh ? '连接失败：$error' : 'Connect failed: $error';
  String get disconnected => isZh ? '已断开' : 'Disconnected';
  String get disconnectingStatus => isZh ? '正在断开' : 'Disconnecting';
  String get unexpectedDisconnect =>
      isZh ? '异常断开' : 'Connection closed unexpectedly';
  String receiveError(String error) =>
      isZh ? '接收错误：$error' : 'Receive error: $error';
  String get sendSkippedNoConnection =>
      isZh ? '发送跳过：没有活动连接' : 'Send skipped: no active connection';
  String sendFailed(String error) =>
      isZh ? '发送失败：$error' : 'Send failed: $error';
  String autoSendEvery(int milliseconds) =>
      isZh ? '定时发送间隔 $milliseconds ms' : 'Auto send every $milliseconds ms';
  String exportFailed(Object error) =>
      isZh ? '导出失败：${errorMessage(error)}' : 'Export failed: $error';

  String? windowsSocketErrorMeaning(int code) => switch (code) {
    10048 => isZh ? '地址已被占用' : 'address already in use',
    10049 => isZh ? '无法分配请求的地址' : 'cannot assign requested address',
    10054 => isZh ? '连接被对端重置' : 'connection reset by peer',
    10060 => isZh ? '连接超时' : 'connection timed out',
    10061 => isZh ? '连接被拒绝' : 'connection refused',
    10065 => isZh ? '没有到主机的路由' : 'no route to host',
    1225 => isZh ? '连接被拒绝' : 'connection refused',
    _ => null,
  };

  String get socketExceptionLabel => isZh ? 'Socket 错误' : 'SocketException';
  String get socketErrnoLabel => isZh ? '错误码' : 'errno';
  String get socketAddressLabel => isZh ? '地址' : 'address';
  String get socketPortLabel => isZh ? '端口' : 'port';

  String exportResult(LogExportResult result) => switch (result.type) {
    LogExportResultType.saved =>
      isZh ? '已导出到 ${result.target}' : 'Exported to ${result.target}',
    LogExportResultType.downloadStarted =>
      isZh
          ? '已开始下载 ${result.target}'
          : 'Started browser download: ${result.target}',
  };

  String connectionSummary(ConnectionConfig config, String serialDisplayName) {
    return switch (config.type) {
      TransportType.serial =>
        config.serial.portName.isEmpty
            ? (isZh ? '串口：未选择端口' : 'Serial: no port selected')
            : '${transportType(TransportType.serial)} $serialDisplayName @ ${config.serial.baudRate}',
      TransportType.bluetooth =>
        config.bluetooth.deviceName.isEmpty
            ? 'BLE ${config.bluetooth.deviceId}'
            : 'BLE ${config.bluetooth.deviceName}',
      TransportType.tcpClient =>
        'TCP ${config.tcpClient.host}:${config.tcpClient.port}',
      TransportType.tcpServer =>
        '${transportType(TransportType.tcpServer)} ${config.tcpServer.bindAddress}:${config.tcpServer.port}',
      TransportType.udp =>
        'UDP ${config.udp.bindAddress}:${config.udp.localPort} -> ${config.udp.remoteHost}:${config.udp.remotePort}',
    };
  }
}
