import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../application/workspace_controller.dart';
import '../../application/session_controller.dart';
import '../../domain/connection_config.dart';
import '../../domain/transport.dart';
import '../../transports/adapters/serial_port_options.dart';
import '../../widgets/wheel_stepper.dart';
import 'workspace_settings_info.dart';

const _baudRateOptions = <int>[
  9600,
  19200,
  38400,
  57600,
  115200,
  230400,
  460800,
  921600,
];

ThemeData _framelessConnectionTheme(BuildContext context) {
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  const squareShape = RoundedRectangleBorder();
  return theme.copyWith(
    inputDecorationTheme: theme.inputDecorationTheme.copyWith(
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      disabledBorder: InputBorder.none,
      errorBorder: InputBorder.none,
      focusedErrorBorder: InputBorder.none,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 10),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: squareShape,
        side: BorderSide.none,
        minimumSize: const Size(40, 40),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        foregroundColor: scheme.onSurface,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: squareShape,
        minimumSize: const Size(40, 40),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size.square(40),
        fixedSize: const Size.square(40),
        padding: EdgeInsets.zero,
        shape: squareShape,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ),
  );
}

class _ConnectionSeparator extends StatelessWidget {
  const _ConnectionSeparator();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 1,
      height: 40,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
    );
  }
}

class ConnectionPanel extends StatefulWidget {
  const ConnectionPanel({
    super.key,
    required this.workspaceController,
    required this.controller,
    this.sessionHeader,
    this.occupiedSerialPorts = const <String>{},
    this.padding = EdgeInsets.zero,
  });

  final WorkspaceController workspaceController;
  final SessionController controller;
  final Widget? sessionHeader;
  final Set<String> occupiedSerialPorts;
  final EdgeInsetsGeometry padding;

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
  late final TextEditingController forwardBaudRate;
  late final TextEditingController packetInterval;
  late final TextEditingController packetDelimiter;
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
    forwardBaudRate = TextEditingController(
      text: config.serial.forwardBaudRate.toString(),
    );
    packetInterval = TextEditingController(
      text: config.serial.packetIntervalMs.toString(),
    );
    packetDelimiter = TextEditingController(
      text: config.serial.packetDelimiter,
    );
    bluetoothDeviceId = TextEditingController(text: config.bluetooth.deviceId);
    bluetoothServiceUuid = TextEditingController(
      text: config.bluetooth.serviceUuid,
    );
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
    forwardBaudRate.dispose();
    packetInterval.dispose();
    packetDelimiter.dispose();
    bluetoothDeviceId.dispose();
    bluetoothServiceUuid.dispose();
    bluetoothWriteCharacteristicUuid.dispose();
    bluetoothNotifyCharacteristicUuid.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final config = controller.config;
        final strings = controller.strings;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.sessionHeader != null)
              Padding(
                padding: widget.padding,
                child: Column(
                  children: [widget.sessionHeader!, const Divider(height: 1)],
                ),
              ),
            Expanded(
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(
                  context,
                ).copyWith(scrollbars: false),
                child: Theme(
                  data: _framelessConnectionTheme(context),
                  child: ListView(
                    padding: widget.padding,
                    physics: const ClampingScrollPhysics(),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    children: [
                      _StatusLine(controller: controller),
                      const Divider(height: 1),
                      _connectionActions(config),
                      const Divider(height: 1),
                      DropdownButtonFormField<TransportType>(
                        key: ValueKey(
                          'type-${identityHashCode(controller)}-${config.type}',
                        ),
                        initialValue: config.type,
                        decoration: InputDecoration(
                          labelText: strings.connectionType,
                        ),
                        items: TransportType.values.map((type) {
                          final supported = controller.isTypeSupported(type);
                          final label = supported
                              ? strings.transportType(type)
                              : strings.unsupportedTransportOption(
                                  type,
                                  controller.unsupportedReason(type),
                                );
                          return DropdownMenuItem(
                            value: type,
                            enabled: supported,
                            child: Text(label),
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
                      const Divider(height: 1),
                      _fieldsFor(config),
                      const Divider(height: 1),
                      _StatsPanel(
                        controller: controller,
                        workspace: widget.workspaceController,
                      ),
                      const Divider(height: 1),
                      _WorkspaceSettingsPanel(
                        controller: widget.workspaceController,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
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

  Widget _connectionActions(ConnectionConfig config) {
    final connecting = controller.status == TransportStatus.connecting;
    final disconnecting = controller.status == TransportStatus.disconnecting;
    final busy = connecting || disconnecting;
    final actionLabel = switch (controller.status) {
      TransportStatus.connected => controller.strings.disconnect,
      TransportStatus.connecting => controller.strings.connecting,
      TransportStatus.disconnecting => controller.strings.disconnecting,
      _ => controller.strings.connect,
    };
    final actionPressed = busy
        ? null
        : controller.isConnected
        ? controller.disconnect
        : _connect;
    final actionChild = busy
        ? Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              Text(actionLabel),
            ],
          )
        : Text(actionLabel);

    final mainAction = controller.isConnected
        ? OutlinedButton(onPressed: actionPressed, child: actionChild)
        : FilledButton(onPressed: actionPressed, child: actionChild);
    final listAction = _listActionFor(config);

    return SizedBox(
      height: 40,
      child: Row(
        children: [
          Expanded(child: mainAction),
          if (listAction != null) ...[
            const _ConnectionSeparator(),
            SizedBox(width: 116, child: listAction),
          ],
        ],
      ),
    );
  }

  Widget? _listActionFor(ConnectionConfig config) {
    final busy =
        controller.status == TransportStatus.connecting ||
        controller.status == TransportStatus.disconnecting;
    return switch (config.type) {
      TransportType.serial when !kIsWeb => OutlinedButton.icon(
        onPressed: busy ? null : controller.refreshSerialPorts,
        icon: const Icon(Icons.refresh),
        label: Text(controller.strings.refreshList),
      ),
      TransportType.bluetooth => OutlinedButton.icon(
        onPressed: controller.isConnected ? null : _scanBluetoothDevices,
        icon: controller.isScanningBluetooth
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.refresh),
        label: Text(
          controller.isScanningBluetooth
              ? controller.strings.stopScan
              : controller.strings.refreshList,
        ),
      ),
      _ => null,
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
    forwardBaudRate.text = config.serial.forwardBaudRate.toString();
    packetInterval.text = config.serial.packetIntervalMs.toString();
    packetDelimiter.text = config.serial.packetDelimiter;
    bluetoothDeviceId.text = config.bluetooth.deviceId;
    bluetoothServiceUuid.text = config.bluetooth.serviceUuid;
    bluetoothWriteCharacteristicUuid.text =
        config.bluetooth.effectiveWriteCharacteristicUuid;
    bluetoothNotifyCharacteristicUuid.text =
        config.bluetooth.notifyCharacteristicUuid;
  }

  Widget _serialFields(ConnectionConfig config) {
    if (kIsWeb) {
      return _webSerialFields(config);
    }

    final occupiedPorts = widget.occupiedSerialPorts;
    final blockedPrimaryPorts = <String>{
      ...occupiedPorts,
      if (config.serial.forwardingEnabled &&
          config.serial.forwardPortName.isNotEmpty)
        config.serial.forwardPortName,
    };
    final wheelPorts = controller.serialPorts
        .where(
          (portName) =>
              !blockedPrimaryPorts.contains(portName) &&
              !isSerialPickerOption(portName),
        )
        .toList(growable: false);
    final baudOptions = _baudOptionsFor(config.serial.baudRate);
    final selectedPort =
        controller.serialPorts.contains(config.serial.portName) &&
            !blockedPrimaryPorts.contains(config.serial.portName)
        ? config.serial.portName
        : null;
    final forwardPorts = controller.serialPorts
        .where(
          (portName) =>
              !occupiedPorts.contains(portName) &&
              portName != config.serial.portName &&
              !isSerialPickerOption(portName),
        )
        .toList(growable: false);
    final selectedForwardPort =
        forwardPorts.contains(config.serial.forwardPortName)
        ? config.serial.forwardPortName
        : null;
    return Column(
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(controller.strings.serialForwarding),
          subtitle: Text(controller.strings.serialForwardingDescription),
          value: config.serial.forwardingEnabled,
          onChanged: controller.isConnected
              ? null
              : (enabled) {
                  final current = controller.config;
                  final availablePeers = controller.serialPorts
                      .where(
                        (portName) =>
                            !occupiedPorts.contains(portName) &&
                            portName != current.serial.portName &&
                            !isSerialPickerOption(portName),
                      )
                      .toList(growable: false);
                  final availablePeer = availablePeers.isEmpty
                      ? null
                      : availablePeers.first;
                  controller.updateConfig(
                    current.copyWith(
                      serial: current.serial.copyWith(
                        forwardingEnabled: enabled,
                        forwardPortName:
                            current.serial.forwardPortName.isNotEmpty
                            ? current.serial.forwardPortName
                            : availablePeer ?? '',
                      ),
                    ),
                  );
                },
        ),
        const Divider(height: 1),
        WheelStepper(
          enabled: !controller.isConnected && wheelPorts.length > 1,
          onStep: (step) => _stepSerialPort(wheelPorts, step),
          child: DropdownButtonFormField<String>(
            key: ValueKey(
              'serial-${controller.serialPorts.join("|")}-$selectedPort',
            ),
            initialValue: selectedPort,
            decoration: InputDecoration(
              labelText: config.serial.forwardingEnabled
                  ? controller.strings.serialPortA
                  : controller.strings.serialPort,
            ),
            items: controller.serialPorts
                .map(
                  (portName) => DropdownMenuItem(
                    value: portName,
                    enabled: !blockedPrimaryPorts.contains(portName),
                    child: Text(
                      serialPortOptionLabel(
                        portName,
                        pickLabel: controller.strings.chooseWebSerialPort,
                        selectedLabel: controller.strings.webSerialSelectedPort,
                      ),
                      style: blockedPrimaryPorts.contains(portName)
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
        ),
        const Divider(height: 1),
        WheelStepper(
          enabled: !controller.isConnected && _baudRateOptions.length > 1,
          onStep: _stepBaudRate,
          child: DropdownButtonFormField<int>(
            key: ValueKey(
              'baud-${identityHashCode(controller)}-${config.serial.baudRate}',
            ),
            initialValue: config.serial.baudRate,
            isExpanded: true,
            menuMaxHeight: 260,
            decoration: InputDecoration(
              labelText: config.serial.forwardingEnabled
                  ? controller.strings.baudRateA
                  : controller.strings.baudRate,
            ),
            items: baudOptions
                .map(
                  (value) => DropdownMenuItem<int>(
                    value: value,
                    child: Text('$value'),
                  ),
                )
                .toList(),
            onChanged: controller.isConnected
                ? null
                : (value) {
                    if (value != null) {
                      baudRate.text = '$value';
                      controller.updateConfig(
                        config.copyWith(
                          serial: config.serial.copyWith(baudRate: value),
                        ),
                      );
                    }
                  },
          ),
        ),
        if (config.serial.forwardingEnabled) ...[
          const Divider(height: 1),
          DropdownButtonFormField<String>(
            key: ValueKey(
              'serial-forward-${controller.serialPorts.join("|")}-$selectedForwardPort',
            ),
            initialValue: selectedForwardPort,
            decoration: InputDecoration(
              labelText: controller.strings.serialPortB,
            ),
            items: controller.serialPorts.map((portName) {
              final blocked =
                  occupiedPorts.contains(portName) ||
                  portName == config.serial.portName ||
                  isSerialPickerOption(portName);
              return DropdownMenuItem(
                value: portName,
                enabled: !blocked,
                child: Text(
                  serialPortOptionLabel(
                    portName,
                    pickLabel: controller.strings.chooseWebSerialPort,
                    selectedLabel: controller.strings.webSerialSelectedPort,
                  ),
                  style: blocked
                      ? TextStyle(color: Theme.of(context).disabledColor)
                      : null,
                ),
              );
            }).toList(),
            onChanged: controller.isConnected
                ? null
                : (value) {
                    if (value != null) {
                      final current = controller.config;
                      controller.updateConfig(
                        current.copyWith(
                          serial: current.serial.copyWith(
                            forwardPortName: value,
                          ),
                        ),
                      );
                    }
                  },
          ),
          const Divider(height: 1),
          DropdownButtonFormField<int>(
            key: ValueKey(
              'forward-baud-${identityHashCode(controller)}-${config.serial.forwardBaudRate}',
            ),
            initialValue: config.serial.forwardBaudRate,
            isExpanded: true,
            menuMaxHeight: 260,
            decoration: InputDecoration(
              labelText: controller.strings.baudRateB,
            ),
            items: _baudOptionsFor(config.serial.forwardBaudRate)
                .map(
                  (value) => DropdownMenuItem<int>(
                    value: value,
                    child: Text('$value'),
                  ),
                )
                .toList(),
            onChanged: controller.isConnected
                ? null
                : (value) {
                    if (value != null) {
                      forwardBaudRate.text = '$value';
                      final current = controller.config;
                      controller.updateConfig(
                        current.copyWith(
                          serial: current.serial.copyWith(
                            forwardBaudRate: value,
                          ),
                        ),
                      );
                    }
                  },
          ),
        ],
        const Divider(height: 1),
        TextField(
          controller: packetInterval,
          enabled: !controller.isConnected,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: controller.strings.packetIntervalMs,
          ),
          onChanged: (value) {
            final intervalMs = int.tryParse(value.trim());
            if (intervalMs == null) {
              return;
            }
            final current = controller.config;
            controller.updateConfig(
              current.copyWith(
                serial: current.serial.copyWith(
                  packetIntervalMs: _nonNegative(intervalMs),
                ),
              ),
            );
          },
        ),
        const Divider(height: 1),
        TextField(
          controller: packetDelimiter,
          enabled: !controller.isConnected,
          decoration: InputDecoration(
            labelText: controller.strings.packetDelimiter,
            suffixIcon: PopupMenuButton<String>(
              tooltip: controller.strings.packetDelimiterPresets,
              initialValue: _delimiterPresetValue(packetDelimiter.text),
              enabled: !controller.isConnected,
              icon: const Icon(Icons.arrow_drop_down),
              onSelected: (value) {
                packetDelimiter.text = value;
                _setPacketDelimiter(value);
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: '',
                  child: Text(controller.strings.packetDelimiterNone),
                ),
                for (final value in const <String>[
                  r'\r',
                  r'\n',
                  r'\r\n',
                  '/R/N',
                  r'\x00',
                ])
                  PopupMenuItem(value: value, child: Text(value)),
              ],
            ),
          ),
          onChanged: _setPacketDelimiter,
        ),
        const Divider(height: 1),
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
                decoration: InputDecoration(
                  labelText: controller.strings.dataBits,
                ),
                items: const [5, 6, 7, 8]
                    .map(
                      (bits) =>
                          DropdownMenuItem(value: bits, child: Text('$bits')),
                    )
                    .toList(),
                onChanged: controller.isConnected
                    ? null
                    : (value) {
                        if (value != null) {
                          controller.updateConfig(
                            config.copyWith(
                              serial: config.serial.copyWith(dataBits: value),
                            ),
                          );
                        }
                      },
              ),
            ),
            const _ConnectionSeparator(),
            SizedBox(
              width: 78,
              child: DropdownButtonFormField<int>(
                key: ValueKey(
                  'stop-bits-${identityHashCode(controller)}-${config.serial.stopBits}',
                ),
                initialValue: config.serial.stopBits,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: controller.strings.stopBits,
                ),
                items: const [1, 2]
                    .map(
                      (bits) =>
                          DropdownMenuItem(value: bits, child: Text('$bits')),
                    )
                    .toList(),
                onChanged: controller.isConnected
                    ? null
                    : (value) {
                        if (value != null) {
                          controller.updateConfig(
                            config.copyWith(
                              serial: config.serial.copyWith(stopBits: value),
                            ),
                          );
                        }
                      },
              ),
            ),
            const _ConnectionSeparator(),
            Expanded(
              child: DropdownButtonFormField<SerialParity>(
                key: ValueKey(
                  'parity-${identityHashCode(controller)}-${config.serial.parity}',
                ),
                initialValue: config.serial.parity,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: controller.strings.parity,
                ),
                items: SerialParity.values
                    .map(
                      (parity) => DropdownMenuItem(
                        value: parity,
                        child: Text(controller.strings.serialParity(parity)),
                      ),
                    )
                    .toList(),
                onChanged: controller.isConnected
                    ? null
                    : (value) {
                        if (value != null) {
                          controller.updateConfig(
                            config.copyWith(
                              serial: config.serial.copyWith(parity: value),
                            ),
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

  Widget _webSerialFields(ConnectionConfig config) {
    final selected = config.serial.portName == webSerialSelectedPortOption;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 44,
          child: OutlinedButton.icon(
            onPressed: controller.isConnected
                ? null
                : () => controller.selectSerialPort(webSerialPickPortOption),
            icon: Icon(selected ? Icons.usb : Icons.usb_off),
            label: Text(
              selected
                  ? controller.strings.webSerialSelectedPort
                  : controller.strings.chooseWebSerialPort,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const Divider(height: 1),
        WheelStepper(
          enabled: !controller.isConnected && _baudRateOptions.length > 1,
          onStep: _stepBaudRate,
          child: DropdownButtonFormField<int>(
            key: ValueKey(
              'baud-${identityHashCode(controller)}-${config.serial.baudRate}',
            ),
            initialValue: config.serial.baudRate,
            isExpanded: true,
            menuMaxHeight: 260,
            decoration: InputDecoration(labelText: controller.strings.baudRate),
            items: _baudOptionsFor(config.serial.baudRate)
                .map(
                  (value) => DropdownMenuItem<int>(
                    value: value,
                    child: Text('$value'),
                  ),
                )
                .toList(),
            onChanged: controller.isConnected
                ? null
                : (value) {
                    if (value != null) {
                      baudRate.text = '$value';
                      controller.updateConfig(
                        config.copyWith(
                          serial: config.serial.copyWith(baudRate: value),
                        ),
                      );
                    }
                  },
          ),
        ),
        const Divider(height: 1),
        TextField(
          controller: packetInterval,
          enabled: !controller.isConnected,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: controller.strings.packetIntervalMs,
          ),
          onChanged: (value) {
            final intervalMs = int.tryParse(value.trim());
            if (intervalMs == null) {
              return;
            }
            final current = controller.config;
            controller.updateConfig(
              current.copyWith(
                serial: current.serial.copyWith(
                  packetIntervalMs: _nonNegative(intervalMs),
                ),
              ),
            );
          },
        ),
        const Divider(height: 1),
        TextField(
          controller: packetDelimiter,
          enabled: !controller.isConnected,
          decoration: InputDecoration(
            labelText: controller.strings.packetDelimiter,
            suffixIcon: PopupMenuButton<String>(
              tooltip: controller.strings.packetDelimiterPresets,
              initialValue: _delimiterPresetValue(packetDelimiter.text),
              enabled: !controller.isConnected,
              icon: const Icon(Icons.arrow_drop_down),
              onSelected: (value) {
                packetDelimiter.text = value;
                _setPacketDelimiter(value);
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: '',
                  child: Text(controller.strings.packetDelimiterNone),
                ),
                for (final value in const <String>[
                  r'\r',
                  r'\n',
                  r'\r\n',
                  '/R/N',
                  r'\x00',
                ])
                  PopupMenuItem(value: value, child: Text(value)),
              ],
            ),
          ),
          onChanged: _setPacketDelimiter,
        ),
        const Divider(height: 1),
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
                decoration: InputDecoration(
                  labelText: controller.strings.dataBits,
                ),
                items: const [5, 6, 7, 8]
                    .map(
                      (bits) =>
                          DropdownMenuItem(value: bits, child: Text('$bits')),
                    )
                    .toList(),
                onChanged: controller.isConnected
                    ? null
                    : (value) {
                        if (value != null) {
                          controller.updateConfig(
                            config.copyWith(
                              serial: config.serial.copyWith(dataBits: value),
                            ),
                          );
                        }
                      },
              ),
            ),
            const _ConnectionSeparator(),
            SizedBox(
              width: 78,
              child: DropdownButtonFormField<int>(
                key: ValueKey(
                  'stop-bits-${identityHashCode(controller)}-${config.serial.stopBits}',
                ),
                initialValue: config.serial.stopBits,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: controller.strings.stopBits,
                ),
                items: const [1, 2]
                    .map(
                      (bits) =>
                          DropdownMenuItem(value: bits, child: Text('$bits')),
                    )
                    .toList(),
                onChanged: controller.isConnected
                    ? null
                    : (value) {
                        if (value != null) {
                          controller.updateConfig(
                            config.copyWith(
                              serial: config.serial.copyWith(stopBits: value),
                            ),
                          );
                        }
                      },
              ),
            ),
            const _ConnectionSeparator(),
            Expanded(
              child: DropdownButtonFormField<SerialParity>(
                key: ValueKey(
                  'parity-${identityHashCode(controller)}-${config.serial.parity}',
                ),
                initialValue: config.serial.parity,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: controller.strings.parity,
                ),
                items: SerialParity.values
                    .map(
                      (parity) => DropdownMenuItem(
                        value: parity,
                        child: Text(controller.strings.serialParity(parity)),
                      ),
                    )
                    .toList(),
                onChanged: controller.isConnected
                    ? null
                    : (value) {
                        if (value != null) {
                          controller.updateConfig(
                            config.copyWith(
                              serial: config.serial.copyWith(parity: value),
                            ),
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
          decoration: InputDecoration(labelText: controller.strings.host),
        ),
        const Divider(height: 1),
        TextField(
          controller: port,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: controller.strings.port),
        ),
      ],
    );
  }

  Widget _tcpServerFields() {
    return Column(
      children: [
        TextField(
          controller: bindAddress,
          decoration: InputDecoration(
            labelText: controller.strings.bindAddress,
          ),
        ),
        const Divider(height: 1),
        TextField(
          controller: port,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: controller.strings.listenPort),
        ),
      ],
    );
  }

  Widget _udpFields() {
    return Column(
      children: [
        TextField(
          controller: bindAddress,
          decoration: InputDecoration(
            labelText: controller.strings.bindAddress,
          ),
        ),
        const Divider(height: 1),
        TextField(
          controller: localPort,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: controller.strings.localPort),
        ),
        const Divider(height: 1),
        TextField(
          controller: remoteHost,
          decoration: InputDecoration(labelText: controller.strings.remoteHost),
        ),
        const Divider(height: 1),
        TextField(
          controller: remotePort,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: controller.strings.remotePort),
        ),
      ],
    );
  }

  Widget _bluetoothFields() {
    final config = controller.config;
    final selectedDevice =
        controller.bluetoothDevices.any(
          (device) => device.id == config.bluetooth.deviceId,
        )
        ? config.bluetooth.deviceId
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          controller.strings.bluetoothInfo,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (!controller.isConnected &&
            controller.bluetoothDevices.isNotEmpty) ...[
          const Divider(height: 1),
          _BluetoothDeviceList(
            controller: controller,
            selectedDeviceId: selectedDevice,
            onSelected: (value) {
              bluetoothDeviceId.text = value;
              controller.selectBluetoothDevice(value);
            },
          ),
        ],
        const Divider(height: 1),
        TextField(
          controller: bluetoothDeviceId,
          enabled: !controller.isConnected,
          decoration: InputDecoration(labelText: controller.strings.deviceId),
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
        const Divider(height: 1),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          title: Text(controller.strings.advancedBleSettings),
          subtitle: Text(controller.strings.fillWhenAutoDetectFails),
          children: [
            TextField(
              controller: bluetoothServiceUuid,
              enabled: !controller.isConnected,
              decoration: InputDecoration(
                labelText: controller.strings.serviceUuid,
              ),
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
            const Divider(height: 1),
            TextField(
              controller: bluetoothWriteCharacteristicUuid,
              enabled: !controller.isConnected,
              decoration: InputDecoration(
                labelText: controller.strings.writeCharacteristicUuid,
              ),
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
            const Divider(height: 1),
            TextField(
              controller: bluetoothNotifyCharacteristicUuid,
              enabled: !controller.isConnected,
              decoration: InputDecoration(
                labelText: controller.strings.notifyCharacteristicUuid,
              ),
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
                  title: Text(controller.strings.writeWithoutResponse),
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
    final serialForwardBaud =
        int.tryParse(forwardBaudRate.text) ?? current.serial.forwardBaudRate;
    final serialPacketInterval = _parseNonNegativeInt(
      packetInterval.text,
      current.serial.packetIntervalMs,
    );
    final tcpPort = int.tryParse(port.text) ?? current.tcpClient.port;
    final udpLocal = int.tryParse(localPort.text) ?? current.udp.localPort;
    final udpRemote = int.tryParse(remotePort.text) ?? current.udp.remotePort;

    controller.updateConfig(
      current.copyWith(
        serial: current.serial.copyWith(
          baudRate: serialBaud,
          forwardBaudRate: serialForwardBaud,
          packetIntervalMs: serialPacketInterval,
          packetDelimiter: packetDelimiter.text,
        ),
        tcpClient: current.tcpClient.copyWith(
          host: host.text.trim(),
          port: tcpPort,
        ),
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
          notifyCharacteristicUuid: bluetoothNotifyCharacteristicUuid.text
              .trim(),
        ),
      ),
    );
    await controller.connect();
  }

  int _parseNonNegativeInt(String text, int fallback) {
    final value = int.tryParse(text.trim());
    return value == null ? fallback : _nonNegative(value);
  }

  int _nonNegative(int value) => value < 0 ? 0 : value;

  List<int> _baudOptionsFor(int current) {
    if (_baudRateOptions.contains(current)) {
      return _baudRateOptions;
    }
    return <int>[..._baudRateOptions, current]..sort();
  }

  void _stepSerialPort(List<String> ports, int step) {
    if (controller.isConnected) {
      return;
    }
    final next = _steppedValue(ports, controller.config.serial.portName, step);
    if (next != null) {
      unawaited(controller.selectSerialPort(next));
    }
  }

  void _stepBaudRate(int step) {
    if (controller.isConnected) {
      return;
    }
    final current = controller.config;
    final currentBaud = int.tryParse(baudRate.text) ?? current.serial.baudRate;
    final next = _nextBaudRate(currentBaud, step);
    baudRate.text = '$next';
    controller.updateConfig(
      current.copyWith(serial: current.serial.copyWith(baudRate: next)),
    );
  }

  int _nextBaudRate(int current, int step) {
    final exactIndex = _baudRateOptions.indexOf(current);
    if (exactIndex >= 0) {
      return _baudRateOptions[_wrappedIndex(
        exactIndex,
        step,
        _baudRateOptions.length,
      )];
    }
    if (step > 0) {
      for (final rate in _baudRateOptions) {
        if (rate > current) {
          return rate;
        }
      }
      return _baudRateOptions.first;
    }
    for (final rate in _baudRateOptions.reversed) {
      if (rate < current) {
        return rate;
      }
    }
    return _baudRateOptions.last;
  }

  T? _steppedValue<T>(List<T> values, T? current, int step) {
    if (values.isEmpty || step == 0) {
      return null;
    }
    var index = current == null ? -1 : values.indexOf(current);
    if (index < 0) {
      index = step > 0 ? -1 : 0;
    }
    return values[_wrappedIndex(index, step, values.length)];
  }

  int _wrappedIndex(int index, int step, int length) {
    var next = (index + step) % length;
    if (next < 0) {
      next += length;
    }
    return next;
  }

  void _setPacketDelimiter(String value) {
    final current = controller.config;
    controller.updateConfig(
      current.copyWith(serial: current.serial.copyWith(packetDelimiter: value)),
    );
  }

  String? _delimiterPresetValue(String value) {
    return const <String>{
          '',
          r'\r',
          r'\n',
          r'\r\n',
          '/R/N',
          r'\x00',
        }.contains(value)
        ? value
        : null;
  }

  void _syncBluetoothConfig() {
    controller.updateConfig(
      controller.config.copyWith(
        bluetooth: controller.config.bluetooth.copyWith(
          deviceId: bluetoothDeviceId.text.trim(),
          deviceName: _bluetoothDeviceNameFor(bluetoothDeviceId.text.trim()),
          serviceUuid: bluetoothServiceUuid.text.trim(),
          writeCharacteristicUuid: bluetoothWriteCharacteristicUuid.text.trim(),
          notifyCharacteristicUuid: bluetoothNotifyCharacteristicUuid.text
              .trim(),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 7,
                    ),
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
                                          ? controller.strings.unknownBleDevice
                                          : device.name,
                                      softWrap: true,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodyMedium,
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
                                style: Theme.of(context).textTheme.labelSmall
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
      decoration: BoxDecoration(color: color.withAlpha(22)),
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
      TransportStatus.disconnecting => scheme.tertiary,
      TransportStatus.error => scheme.error,
      TransportStatus.disconnected => scheme.outline,
    };
  }
}

class _CollapsiblePanel extends StatelessWidget {
  const _CollapsiblePanel({
    required this.title,
    required this.icon,
    required this.expanded,
    required this.onChanged,
    required this.expandTooltip,
    required this.collapseTooltip,
    required this.child,
    this.actions = const <Widget>[],
  });

  final String title;
  final IconData icon;
  final bool expanded;
  final ValueChanged<bool> onChanged;
  final String expandTooltip;
  final String collapseTooltip;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 40,
          child: Row(
            children: [
              Expanded(
                child: Tooltip(
                  message: expanded ? collapseTooltip : expandTooltip,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onChanged(!expanded),
                      child: Row(
                        children: [
                          Icon(icon, size: 18, color: scheme.onSurfaceVariant),
                          const SizedBox(width: 6),
                          Text(
                            title,
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (actions.isNotEmpty) ...[
                _HeaderSeparator(color: scheme.outlineVariant),
                for (var i = 0; i < actions.length; i++) ...[
                  actions[i],
                  if (i != actions.length - 1)
                    _HeaderSeparator(color: scheme.outlineVariant),
                ],
              ],
            ],
          ),
        ),
        if (expanded) ...[const Divider(height: 1), child],
      ],
    );
  }
}

class _HeaderSeparator extends StatelessWidget {
  const _HeaderSeparator({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      width: 1,
      child: DecoratedBox(decoration: BoxDecoration(color: color)),
    );
  }
}

class _StatsPanel extends StatelessWidget {
  const _StatsPanel({required this.controller, required this.workspace});

  final SessionController controller;
  final WorkspaceController workspace;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: workspace,
      builder: (context, _) {
        if (!workspace.statsPanelExpanded) {
          return _buildPanel(context, const SizedBox.shrink());
        }
        return AnimatedBuilder(
          animation: controller.statsListenable,
          builder: (context, _) => _buildPanel(context, _buildStats(context)),
        );
      },
    );
  }

  Widget _buildPanel(BuildContext context, Widget child) {
    final strings = controller.strings;
    return _CollapsiblePanel(
      title: strings.stats,
      icon: Icons.query_stats,
      expanded: workspace.statsPanelExpanded,
      onChanged: workspace.setStatsPanelExpanded,
      expandTooltip: strings.expand,
      collapseTooltip: strings.collapse,
      actions: workspace.statsPanelExpanded
          ? [
              SizedBox.square(
                dimension: 40,
                child: PopupMenuButton<SessionStat>(
                  tooltip: strings.chooseStats,
                  padding: EdgeInsets.zero,
                  iconSize: 18,
                  icon: const Icon(Icons.tune),
                  onSelected: (stat) => controller.setStatVisible(
                    stat,
                    !controller.isStatVisible(stat),
                  ),
                  itemBuilder: (context) => sessionStatDisplayOrder
                      .map(
                        (stat) => CheckedPopupMenuItem<SessionStat>(
                          value: stat,
                          checked: controller.isStatVisible(stat),
                          child: Text(strings.sessionStat(stat)),
                        ),
                      )
                      .toList(),
                ),
              ),
            ]
          : const <Widget>[],
      child: child,
    );
  }

  Widget _buildStats(BuildContext context) {
    final strings = controller.strings;
    final items = <Widget>[
      if (controller.isStatVisible(SessionStat.rxCount))
        _StatRow(
          label: strings.rxCount,
          value:
              '${controller.rxFrameCount} ${strings.framesUnit} / ${_formatBytes(controller.rxByteCount)}',
        ),
      if (controller.isStatVisible(SessionStat.txCount))
        _StatRow(
          label: strings.txCount,
          value:
              '${controller.txFrameCount} ${strings.framesUnit} / ${_formatBytes(controller.txByteCount)}',
        ),
      if (controller.isStatVisible(SessionStat.rxCurrentRate))
        _StatRow(
          label: strings.rxCurrentRate,
          value: _formatRate(controller.currentRxBytesPerSecond),
        ),
      if (controller.isStatVisible(SessionStat.txCurrentRate))
        _StatRow(
          label: strings.txCurrentRate,
          value: _formatRate(controller.currentTxBytesPerSecond),
        ),
      if (controller.isStatVisible(SessionStat.rxRate))
        _StatRow(
          label: strings.rxRate,
          value: _formatRate(controller.averageRxBytesPerSecond),
        ),
      if (controller.isStatVisible(SessionStat.txRate))
        _StatRow(
          label: strings.txRate,
          value: _formatRate(controller.averageTxBytesPerSecond),
        ),
      if (controller.isStatVisible(SessionStat.sessionDuration))
        _StatRow(
          label: strings.sessionDuration,
          value: _formatDuration(controller.sessionDuration),
        ),
      if (controller.isStatVisible(SessionStat.displayCache))
        _StatRow(
          label: strings.displayCache,
          value:
              '${controller.logBuffer.retainedDataFrames} ${strings.framesUnit} / ${_formatBytes(controller.logBuffer.retainedDataBytes)}',
        ),
      if (controller.isStatVisible(SessionStat.rawCache))
        _StatRow(
          label: strings.rawCache,
          value:
              '${_formatBytes(controller.rawBuffer.length)} / ${_formatBytes(controller.rawBuffer.capacityBytes)}',
        ),
      if (controller.isStatVisible(SessionStat.droppedData))
        _StatRow(
          label: strings.droppedData,
          value:
              '${controller.logBuffer.droppedDataFrames} ${strings.framesUnit} / ${_formatBytes(controller.logBuffer.droppedDataBytes + controller.rawBuffer.droppedBytes)}',
        ),
    ];

    if (items.isEmpty) {
      return Text(
        strings.noStatsVisible,
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const Divider(height: 1),
          items[i],
        ],
      ],
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

class _WorkspaceSettingsPanel extends StatelessWidget {
  const _WorkspaceSettingsPanel({required this.controller});

  final WorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final strings = controller.strings;
        return _CollapsiblePanel(
          title: strings.settings,
          icon: Icons.settings,
          expanded: controller.settingsPanelExpanded,
          onChanged: controller.setSettingsPanelExpanded,
          expandTooltip: strings.expand,
          collapseTooltip: strings.collapse,
          child: WorkspaceSettingsInfo(controller: controller),
        );
      },
    );
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          SizedBox(width: 44, child: Text(label, style: textStyle)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(value, textAlign: TextAlign.right, style: textStyle),
          ),
        ],
      ),
    );
  }
}
