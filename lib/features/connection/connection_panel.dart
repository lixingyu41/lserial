import 'package:flutter/material.dart';

import '../../application/session_controller.dart';
import '../../domain/connection_config.dart';
import '../../domain/transport.dart';
import '../../transports/adapters/serial_port_options.dart';

class ConnectionPanel extends StatefulWidget {
  const ConnectionPanel({
    super.key,
    required this.controller,
    this.sessionHeader,
    this.occupiedSerialPorts = const <String>{},
  });

  final SessionController controller;
  final Widget? sessionHeader;
  final Set<String> occupiedSerialPorts;

  @override
  State<ConnectionPanel> createState() => _ConnectionPanelState();
}

class _ConnectionPanelState extends State<ConnectionPanel> {
  late final TextEditingController host;
  late final TextEditingController port;
  late final TextEditingController bindAddress;
  late final TextEditingController localPort;
  late final TextEditingController remoteHost;
  late final TextEditingController remotePort;
  late final TextEditingController baudRate;
  late final TextEditingController bluetoothDeviceId;
  late final TextEditingController bluetoothServiceUuid;
  late final TextEditingController bluetoothWriteCharacteristicUuid;
  late final TextEditingController bluetoothNotifyCharacteristicUuid;

  SessionController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    final config = controller.config;
    host = TextEditingController(text: config.tcpClient.host);
    port = TextEditingController(text: config.tcpClient.port.toString());
    bindAddress = TextEditingController(text: config.tcpServer.bindAddress);
    localPort = TextEditingController(text: config.udp.localPort.toString());
    remoteHost = TextEditingController(text: config.udp.remoteHost);
    remotePort = TextEditingController(text: config.udp.remotePort.toString());
    baudRate = TextEditingController(text: config.serial.baudRate.toString());
    bluetoothDeviceId = TextEditingController(text: config.bluetooth.deviceId);
    bluetoothServiceUuid =
        TextEditingController(text: config.bluetooth.serviceUuid);
    bluetoothWriteCharacteristicUuid = TextEditingController(
      text: config.bluetooth.effectiveWriteCharacteristicUuid,
    );
    bluetoothNotifyCharacteristicUuid = TextEditingController(
      text: config.bluetooth.notifyCharacteristicUuid,
    );
  }

  @override
  void didUpdateWidget(ConnectionPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _syncTextFields(widget.controller.config);
    }
  }

  @override
  void dispose() {
    host.dispose();
    port.dispose();
    bindAddress.dispose();
    localPort.dispose();
    remoteHost.dispose();
    remotePort.dispose();
    baudRate.dispose();
    bluetoothDeviceId.dispose();
    bluetoothServiceUuid.dispose();
    bluetoothWriteCharacteristicUuid.dispose();
    bluetoothNotifyCharacteristicUuid.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = controller.config;
    return Padding(
      padding: const EdgeInsets.all(14),
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: ListView(
          children: [
            if (widget.sessionHeader != null) ...[
              widget.sessionHeader!,
              const SizedBox(height: 8),
            ],
            _StatusLine(controller: controller),
            const SizedBox(height: 8),
            DropdownButtonFormField<TransportType>(
              key: ValueKey(
                  'type-${identityHashCode(controller)}-${config.type}'),
              initialValue: config.type,
              decoration: const InputDecoration(labelText: '连接方式'),
              items: TransportType.values.map((type) {
                final supported = controller.isTypeSupported(type);
                return DropdownMenuItem(
                  value: type,
                  enabled: supported,
                  child:
                      Text(supported ? type.label : '${type.label} (disabled)'),
                );
              }).toList(),
              onChanged: controller.isConnected
                  ? null
                  : (type) {
                      if (type != null) {
                        controller.setTransportType(type);
                      }
                    },
            ),
            const SizedBox(height: 8),
            _fieldsFor(config),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: controller.isConnected ? null : _connect,
                    child: const Text('连接'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        controller.isConnected ? controller.disconnect : null,
                    child: const Text('断开'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: controller.refreshSerialPorts,
              icon: const Icon(Icons.refresh),
              label: const Text('刷新串口列表'),
            ),
            const SizedBox(height: 8),
            _StatsPanel(controller: controller),
          ],
        ),
      ),
    );
  }

  Widget _fieldsFor(ConnectionConfig config) {
    return switch (config.type) {
      TransportType.serial => _serialFields(config),
      TransportType.tcpClient => _tcpClientFields(),
      TransportType.tcpServer => _tcpServerFields(),
      TransportType.udp => _udpFields(),
      TransportType.bluetooth => _bluetoothFields(),
    };
  }

  void _syncTextFields(ConnectionConfig config) {
    host.text = config.tcpClient.host;
    port.text = switch (config.type) {
      TransportType.tcpServer => config.tcpServer.port.toString(),
      _ => config.tcpClient.port.toString(),
    };
    bindAddress.text = switch (config.type) {
      TransportType.udp => config.udp.bindAddress,
      _ => config.tcpServer.bindAddress,
    };
    localPort.text = config.udp.localPort.toString();
    remoteHost.text = config.udp.remoteHost;
    remotePort.text = config.udp.remotePort.toString();
    baudRate.text = config.serial.baudRate.toString();
    bluetoothDeviceId.text = config.bluetooth.deviceId;
    bluetoothServiceUuid.text = config.bluetooth.serviceUuid;
    bluetoothWriteCharacteristicUuid.text =
        config.bluetooth.effectiveWriteCharacteristicUuid;
    bluetoothNotifyCharacteristicUuid.text =
        config.bluetooth.notifyCharacteristicUuid;
  }

  Widget _serialFields(ConnectionConfig config) {
    final occupiedPorts = widget.occupiedSerialPorts;
    final selectedPort =
        controller.serialPorts.contains(config.serial.portName) &&
                !occupiedPorts.contains(config.serial.portName)
            ? config.serial.portName
            : null;
    return Column(
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey(
              'serial-${controller.serialPorts.join("|")}-$selectedPort'),
          initialValue: selectedPort,
          decoration: const InputDecoration(labelText: '串口'),
          items: controller.serialPorts
              .map(
                (portName) => DropdownMenuItem(
                  value: portName,
                  enabled: !occupiedPorts.contains(portName),
                  child: Text(
                    serialPortOptionLabel(portName),
                    style: occupiedPorts.contains(portName)
                        ? TextStyle(color: Theme.of(context).disabledColor)
                        : null,
                  ),
                ),
              )
              .toList(),
          onChanged: controller.isConnected
              ? null
              : (value) {
                  if (value != null) {
                    controller.selectSerialPort(value);
                  }
                },
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            return DropdownMenu<int>(
              controller: baudRate,
              enabled: !controller.isConnected,
              label: const Text('波特率'),
              enableFilter: true,
              requestFocusOnTap: true,
              width: constraints.maxWidth,
              menuHeight: 260,
              dropdownMenuEntries: const [
                9600,
                19200,
                38400,
                57600,
                115200,
                230400,
                460800,
                921600,
              ]
                  .map(
                    (value) => DropdownMenuEntry<int>(
                      value: value,
                      label: '$value',
                    ),
                  )
                  .toList(),
              onSelected: (value) {
                if (value != null) {
                  baudRate.text = '$value';
                  controller.updateConfig(
                    config.copyWith(
                      serial: config.serial.copyWith(baudRate: value),
                    ),
                  );
                }
              },
            );
          },
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            SizedBox(
              width: 78,
              child: DropdownButtonFormField<int>(
                key: ValueKey(
                  'data-bits-${identityHashCode(controller)}-${config.serial.dataBits}',
                ),
                initialValue: config.serial.dataBits,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '数据位'),
                items: const [5, 6, 7, 8]
                    .map((bits) =>
                        DropdownMenuItem(value: bits, child: Text('$bits')))
                    .toList(),
                onChanged: controller.isConnected
                    ? null
                    : (value) {
                        if (value != null) {
                          controller.updateConfig(
                            config.copyWith(
                                serial:
                                    config.serial.copyWith(dataBits: value)),
                          );
                        }
                      },
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 78,
              child: DropdownButtonFormField<int>(
                key: ValueKey(
                  'stop-bits-${identityHashCode(controller)}-${config.serial.stopBits}',
                ),
                initialValue: config.serial.stopBits,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '停止位'),
                items: const [1, 2]
                    .map((bits) =>
                        DropdownMenuItem(value: bits, child: Text('$bits')))
                    .toList(),
                onChanged: controller.isConnected
                    ? null
                    : (value) {
                        if (value != null) {
                          controller.updateConfig(
                            config.copyWith(
                                serial:
                                    config.serial.copyWith(stopBits: value)),
                          );
                        }
                      },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<SerialParity>(
                key: ValueKey(
                  'parity-${identityHashCode(controller)}-${config.serial.parity}',
                ),
                initialValue: config.serial.parity,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '校验'),
                items: SerialParity.values
                    .map((parity) => DropdownMenuItem(
                        value: parity, child: Text(parity.label)))
                    .toList(),
                onChanged: controller.isConnected
                    ? null
                    : (value) {
                        if (value != null) {
                          controller.updateConfig(
                            config.copyWith(
                                serial: config.serial.copyWith(parity: value)),
                          );
                        }
                      },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _tcpClientFields() {
    return Column(
      children: [
        TextField(
            controller: host,
            decoration: const InputDecoration(labelText: 'Host')),
        const SizedBox(height: 8),
        TextField(
          controller: port,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Port'),
        ),
      ],
    );
  }

  Widget _tcpServerFields() {
    return Column(
      children: [
        TextField(
          controller: bindAddress,
          decoration: const InputDecoration(labelText: 'Bind address'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: port,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Listen port'),
        ),
      ],
    );
  }

  Widget _udpFields() {
    return Column(
      children: [
        TextField(
          controller: bindAddress,
          decoration: const InputDecoration(labelText: 'Bind address'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: localPort,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Local port'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: remoteHost,
          decoration: const InputDecoration(labelText: 'Remote host'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: remotePort,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Remote port'),
        ),
      ],
    );
  }

  Widget _bluetoothFields() {
    final config = controller.config;
    final selectedDevice = controller.bluetoothDevices
            .any((device) => device.id == config.bluetooth.deviceId)
        ? config.bluetooth.deviceId
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'BLE 串口会自动识别常见 UART 通道；无法识别时再展开高级设置填写 UUID。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: controller.isConnected ? null : _scanBluetoothDevices,
          icon: controller.isScanningBluetooth
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.bluetooth_searching),
          label: Text(
            controller.isScanningBluetooth ? '停止扫描' : '扫描 BLE 设备',
          ),
        ),
        if (!controller.isConnected &&
            controller.bluetoothDevices.isNotEmpty) ...[
          const SizedBox(height: 8),
          _BluetoothDeviceList(
            controller: controller,
            selectedDeviceId: selectedDevice,
            onSelected: (value) {
              bluetoothDeviceId.text = value;
              controller.selectBluetoothDevice(value);
            },
          ),
        ],
        const SizedBox(height: 8),
        TextField(
          controller: bluetoothDeviceId,
          enabled: !controller.isConnected,
          decoration: const InputDecoration(labelText: 'Device ID'),
          onChanged: (value) {
            final deviceId = value.trim();
            controller.updateConfig(
              controller.config.copyWith(
                bluetooth: controller.config.bluetooth.copyWith(
                  deviceId: deviceId,
                  deviceName: _bluetoothDeviceNameFor(deviceId),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          title: const Text('高级 BLE 设置'),
          subtitle: const Text('自动识别失败时再填写'),
          children: [
            TextField(
              controller: bluetoothServiceUuid,
              enabled: !controller.isConnected,
              decoration: const InputDecoration(labelText: 'Service UUID'),
              onChanged: (value) {
                controller.updateConfig(
                  controller.config.copyWith(
                    bluetooth: controller.config.bluetooth.copyWith(
                      serviceUuid: value.trim(),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: bluetoothWriteCharacteristicUuid,
              enabled: !controller.isConnected,
              decoration:
                  const InputDecoration(labelText: '写入 Characteristic UUID'),
              onChanged: (value) {
                controller.updateConfig(
                  controller.config.copyWith(
                    bluetooth: controller.config.bluetooth.copyWith(
                      writeCharacteristicUuid: value.trim(),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: bluetoothNotifyCharacteristicUuid,
              enabled: !controller.isConnected,
              decoration:
                  const InputDecoration(labelText: '通知 Characteristic UUID'),
              onChanged: (value) {
                controller.updateConfig(
                  controller.config.copyWith(
                    bluetooth: controller.config.bluetooth.copyWith(
                      notifyCharacteristicUuid: value.trim(),
                    ),
                  ),
                );
              },
            ),
            AnimatedBuilder(
              animation: controller,
              builder: (context, _) {
                return SwitchListTile(
                  value: controller.config.bluetooth.writeWithoutResponse,
                  onChanged: controller.isConnected
                      ? null
                      : (value) {
                          controller.updateConfig(
                            controller.config.copyWith(
                              bluetooth: controller.config.bluetooth.copyWith(
                                writeWithoutResponse: value,
                              ),
                            ),
                          );
                        },
                  title: const Text('无响应写入'),
                  contentPadding: EdgeInsets.zero,
                );
              },
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _scanBluetoothDevices() async {
    _syncBluetoothConfig();
    await controller.scanBluetoothDevices();
    if (controller.config.bluetooth.deviceId.isNotEmpty) {
      bluetoothDeviceId.text = controller.config.bluetooth.deviceId;
    }
  }

  Future<void> _connect() async {
    final current = controller.config;
    final serialBaud = int.tryParse(baudRate.text) ?? current.serial.baudRate;
    final tcpPort = int.tryParse(port.text) ?? current.tcpClient.port;
    final udpLocal = int.tryParse(localPort.text) ?? current.udp.localPort;
    final udpRemote = int.tryParse(remotePort.text) ?? current.udp.remotePort;

    controller.updateConfig(
      current.copyWith(
        serial: current.serial.copyWith(baudRate: serialBaud),
        tcpClient:
            current.tcpClient.copyWith(host: host.text.trim(), port: tcpPort),
        tcpServer: current.tcpServer.copyWith(
          bindAddress: bindAddress.text.trim(),
          port: tcpPort,
        ),
        udp: current.udp.copyWith(
          bindAddress: bindAddress.text.trim(),
          localPort: udpLocal,
          remoteHost: remoteHost.text.trim(),
          remotePort: udpRemote,
        ),
        bluetooth: current.bluetooth.copyWith(
          deviceId: bluetoothDeviceId.text.trim(),
          deviceName: _bluetoothDeviceNameFor(bluetoothDeviceId.text.trim()),
          serviceUuid: bluetoothServiceUuid.text.trim(),
          writeCharacteristicUuid: bluetoothWriteCharacteristicUuid.text.trim(),
          notifyCharacteristicUuid:
              bluetoothNotifyCharacteristicUuid.text.trim(),
        ),
      ),
    );
    await controller.connect();
  }

  void _syncBluetoothConfig() {
    controller.updateConfig(
      controller.config.copyWith(
        bluetooth: controller.config.bluetooth.copyWith(
          deviceId: bluetoothDeviceId.text.trim(),
          deviceName: _bluetoothDeviceNameFor(bluetoothDeviceId.text.trim()),
          serviceUuid: bluetoothServiceUuid.text.trim(),
          writeCharacteristicUuid: bluetoothWriteCharacteristicUuid.text.trim(),
          notifyCharacteristicUuid:
              bluetoothNotifyCharacteristicUuid.text.trim(),
        ),
      ),
    );
  }

  String _bluetoothDeviceNameFor(String deviceId) {
    for (final device in controller.bluetoothDevices) {
      if (device.id == deviceId) {
        return device.name;
      }
    }
    if (deviceId == controller.config.bluetooth.deviceId) {
      return controller.config.bluetooth.deviceName;
    }
    return '';
  }
}

class _BluetoothDeviceList extends StatelessWidget {
  const _BluetoothDeviceList({
    required this.controller,
    required this.selectedDeviceId,
    required this.onSelected,
  });

  final SessionController controller;
  final String? selectedDeviceId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final devices = controller.bluetoothDevices;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.72),
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < devices.length; index++) ...[
            if (index > 0) const Divider(height: 1),
            Builder(
              builder: (context) {
                final device = devices[index];
                final selected = device.id == selectedDeviceId;
                return InkWell(
                  onTap: controller.isConnected
                      ? null
                      : () => onSelected(device.id),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          selected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          size: 17,
                          color: selected ? scheme.primary : scheme.outline,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      device.name.trim().isEmpty
                                          ? 'Unknown BLE device'
                                          : device.name,
                                      softWrap: true,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium,
                                    ),
                                  ),
                                  if (device.rssi != null) ...[
                                    const SizedBox(width: 8),
                                    Text(
                                      '${device.rssi} dBm',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium
                                          ?.copyWith(color: scheme.secondary),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                device.id,
                                softWrap: true,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(context, controller.status);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withAlpha(22),
        border: Border.all(color: color.withAlpha(110)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Icon(Icons.circle, size: 10, color: color),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                controller.statusMessage,
                softWrap: true,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _statusColor(BuildContext context, TransportStatus status) {
    final scheme = Theme.of(context).colorScheme;
    return switch (status) {
      TransportStatus.connected => const Color(0xff1f8a4c),
      TransportStatus.connecting ||
      TransportStatus.disconnecting =>
        scheme.tertiary,
      TransportStatus.error => scheme.error,
      TransportStatus.disconnected => scheme.outline,
    };
  }
}

class _StatsPanel extends StatelessWidget {
  const _StatsPanel({required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[
      if (controller.isStatVisible(SessionStat.rxCount))
        _StatRow(
          label: '接收',
          value:
              '${controller.rxFrameCount} 帧 / ${_formatBytes(controller.rxByteCount)}',
        ),
      if (controller.isStatVisible(SessionStat.txCount))
        _StatRow(
          label: '发送',
          value:
              '${controller.txFrameCount} 帧 / ${_formatBytes(controller.txByteCount)}',
        ),
      if (controller.isStatVisible(SessionStat.rxCurrentRate))
        _StatRow(
          label: '收速',
          value: _formatRate(controller.currentRxBytesPerSecond),
        ),
      if (controller.isStatVisible(SessionStat.txCurrentRate))
        _StatRow(
          label: '发速',
          value: _formatRate(controller.currentTxBytesPerSecond),
        ),
      if (controller.isStatVisible(SessionStat.rxRate))
        _StatRow(
          label: '均收',
          value: _formatRate(controller.averageRxBytesPerSecond),
        ),
      if (controller.isStatVisible(SessionStat.txRate))
        _StatRow(
          label: '均发',
          value: _formatRate(controller.averageTxBytesPerSecond),
        ),
      if (controller.isStatVisible(SessionStat.sessionDuration))
        _StatRow(
          label: '时长',
          value: _formatDuration(controller.sessionDuration),
        ),
      if (controller.isStatVisible(SessionStat.displayCache))
        _StatRow(
          label: '显示',
          value:
              '${controller.logBuffer.retainedDataFrames} 帧 / ${_formatBytes(controller.logBuffer.retainedDataBytes)}',
        ),
      if (controller.isStatVisible(SessionStat.rawCache))
        _StatRow(
          label: '原始',
          value:
              '${_formatBytes(controller.rawBuffer.length)} / ${_formatBytes(controller.rawBuffer.capacityBytes)}',
        ),
      if (controller.isStatVisible(SessionStat.droppedData))
        _StatRow(
          label: '丢弃',
          value:
              '${controller.logBuffer.droppedDataFrames} 帧 / ${_formatBytes(controller.logBuffer.droppedDataBytes + controller.rawBuffer.droppedBytes)}',
        ),
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('统计', style: Theme.of(context).textTheme.labelLarge),
                const Spacer(),
                PopupMenuButton<SessionStat>(
                  tooltip: '选择统计项',
                  icon: const Icon(Icons.tune, size: 18),
                  onSelected: (stat) => controller.setStatVisible(
                    stat,
                    !controller.isStatVisible(stat),
                  ),
                  itemBuilder: (context) => SessionStat.values
                      .map(
                        (stat) => CheckedPopupMenuItem<SessionStat>(
                          value: stat,
                          checked: controller.isStatVisible(stat),
                          child: Text(stat.label),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (items.isEmpty)
              Text(
                '未显示统计项',
                style: Theme.of(context).textTheme.bodySmall,
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: items,
              ),
          ],
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  String _formatRate(double bytesPerSecond) {
    return '${_formatBytes(bytesPerSecond.round())}/s';
  }

  String _formatDuration(Duration duration) {
    String two(int value) => value.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    return '${two(hours)}:${two(minutes)}:${two(seconds)}';
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          border:
              Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              SizedBox(
                width: 44,
                child: Text(
                  label,
                  style: textStyle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  style: textStyle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
