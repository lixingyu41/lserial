import 'package:flutter/material.dart';

import '../../application/session_controller.dart';
import '../../domain/connection_config.dart';
import '../../domain/transport.dart';

class ConnectionPanel extends StatefulWidget {
  const ConnectionPanel({super.key, required this.controller});

  final SessionController controller;

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = controller.config;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: ListView(
        children: [
          Text('连接', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          DropdownButtonFormField<TransportType>(
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
          const SizedBox(height: 12),
          _fieldsFor(config),
          const SizedBox(height: 12),
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
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: controller.refreshSerialPorts,
            icon: const Icon(Icons.refresh),
            label: const Text('刷新串口列表'),
          ),
          const SizedBox(height: 12),
          _CapabilityBox(controller: controller),
        ],
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

  Widget _serialFields(ConnectionConfig config) {
    return Column(
      children: [
        DropdownButtonFormField<String>(
          initialValue:
              config.serial.portName.isEmpty ? null : config.serial.portName,
          decoration: const InputDecoration(labelText: '串口'),
          items: controller.serialPorts
              .map((portName) =>
                  DropdownMenuItem(value: portName, child: Text(portName)))
              .toList(),
          onChanged: controller.isConnected
              ? null
              : (value) {
                  controller.updateConfig(
                    config.copyWith(
                        serial: config.serial.copyWith(portName: value ?? '')),
                  );
                },
        ),
        const SizedBox(height: 8),
        TextField(
          controller: baudRate,
          enabled: !controller.isConnected,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: '波特率'),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: config.serial.dataBits,
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
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: config.serial.stopBits,
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
          ],
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<SerialParity>(
          initialValue: config.serial.parity,
          decoration: const InputDecoration(labelText: '校验'),
          items: SerialParity.values
              .map((parity) =>
                  DropdownMenuItem(value: parity, child: Text(parity.label)))
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
    return const Text(
      'Bluetooth adapter is isolated behind the transport interface. This MVP keeps it disabled until a target BLE/SPP plugin is chosen.',
    );
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
      ),
    );
    await controller.connect();
  }
}

class _CapabilityBox extends StatelessWidget {
  const _CapabilityBox({required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('平台能力', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            for (final capability in controller.capabilities)
              Text(
                '${capability.supported ? "OK" : "--"} ${capability.type.label}: ${capability.reason}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}
