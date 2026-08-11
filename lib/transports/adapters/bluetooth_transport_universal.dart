import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:universal_ble/universal_ble.dart';

import '../../domain/bluetooth_device_info.dart';
import '../../domain/connection_config.dart';
import '../../domain/transport.dart';

const _knownBleSerialProfiles = <_KnownBleSerialProfile>[
  _KnownBleSerialProfile(
    serviceUuid: '6e400001-b5a3-f393-e0a9-e50e24dcca9e',
    writeCharacteristicUuid: '6e400002-b5a3-f393-e0a9-e50e24dcca9e',
    notifyCharacteristicUuid: '6e400003-b5a3-f393-e0a9-e50e24dcca9e',
  ),
  _KnownBleSerialProfile(
    serviceUuid: '0000ffe0-0000-1000-8000-00805f9b34fb',
    writeCharacteristicUuid: '0000ffe1-0000-1000-8000-00805f9b34fb',
    notifyCharacteristicUuid: '0000ffe1-0000-1000-8000-00805f9b34fb',
  ),
  _KnownBleSerialProfile(
    serviceUuid: '0000fff0-0000-1000-8000-00805f9b34fb',
    writeCharacteristicUuid: '0000fff1-0000-1000-8000-00805f9b34fb',
    notifyCharacteristicUuid: '0000fff1-0000-1000-8000-00805f9b34fb',
  ),
];

TransportSession createBluetoothSession(ConnectionConfig config) {
  return UniversalBleTransportSession(config.bluetooth);
}

Future<List<BluetoothDeviceInfo>> scanBluetoothDevices({
  String? serviceUuid,
  Duration timeout = const Duration(seconds: 8),
}) async {
  final result = <BluetoothDeviceInfo>[];
  final subscription = scanBluetoothDeviceStream(serviceUuid: serviceUuid)
      .listen((devices) {
        result
          ..clear()
          ..addAll(devices);
      });
  await Future<void>.delayed(kIsWeb ? const Duration(seconds: 2) : timeout);
  await subscription.cancel();
  return List<BluetoothDeviceInfo>.unmodifiable(result);
}

Stream<List<BluetoothDeviceInfo>> scanBluetoothDeviceStream({
  String? serviceUuid,
}) {
  late StreamController<List<BluetoothDeviceInfo>> controller;
  StreamSubscription<BleDevice>? subscription;
  Timer? publishTimer;
  var stopping = false;

  controller = StreamController<List<BluetoothDeviceInfo>>.broadcast(
    onListen: () async {
      final devices = <String, BluetoothDeviceInfo>{};
      void publish() {
        if (controller.isClosed) {
          return;
        }
        controller.add(_sortedDevices(devices));
      }

      try {
        subscription = UniversalBle.scanStream.listen((device) async {
          devices[device.deviceId] = _deviceInfoFor(device);
          // Chrome Web Bluetooth is permission-picker based for this app.
          // Keep it as a one-shot browser interaction instead of pretending
          // it supports a desktop-style continuous RSSI scan.
          if (kIsWeb && !stopping) {
            publish();
            stopping = true;
            await UniversalBle.stopScan().catchError((_) {});
            await controller.close();
          }
        }, onError: controller.addError);

        final scanConfig = _scanConfig(serviceUuid);
        await UniversalBle.requestPermissions();
        publishTimer = Timer.periodic(
          const Duration(seconds: 2),
          (_) => publish(),
        );
        await UniversalBle.startScan(
          scanFilter: scanConfig.filter,
          platformConfig: scanConfig.platformConfig,
        );
      } on Object catch (error, stackTrace) {
        if (!controller.isClosed) {
          controller.addError(error, stackTrace);
        }
      }
    },
    onCancel: () async {
      stopping = true;
      publishTimer?.cancel();
      publishTimer = null;
      await UniversalBle.stopScan().catchError((_) {});
      await subscription?.cancel();
      subscription = null;
    },
  );

  return controller.stream;
}

_ScanConfig _scanConfig(String? serviceUuid) {
  final filterUuid = serviceUuid?.trim();
  final serviceFilter = filterUuid == null || filterUuid.isEmpty
      ? null
      : <String>[filterUuid];
  final optionalServices = <String>{
    for (final profile in _knownBleSerialProfiles) profile.serviceUuid,
    if (serviceFilter != null) ...serviceFilter,
  }.toList(growable: false);
  return _ScanConfig(
    filter: serviceFilter == null
        ? null
        : ScanFilter(withServices: serviceFilter),
    platformConfig: PlatformConfig(
      web: WebOptions(optionalServices: optionalServices),
    ),
  );
}

List<BluetoothDeviceInfo> _sortedDevices(
  Map<String, BluetoothDeviceInfo> devices,
) {
  return devices.values.toList(growable: false)..sort((a, b) {
    final signalCompare = (b.rssi ?? -999).compareTo(a.rssi ?? -999);
    if (signalCompare != 0) {
      return signalCompare;
    }
    return a.name.compareTo(b.name);
  });
}

BluetoothDeviceInfo _deviceInfoFor(BleDevice device) {
  return BluetoothDeviceInfo(
    id: device.deviceId,
    name: device.name ?? device.rawName ?? '',
    rssi: device.rssi,
  );
}

class UniversalBleTransportSession implements TransportSession {
  UniversalBleTransportSession(this.config);

  final BluetoothConfig config;
  final StreamController<List<int>> _incoming =
      StreamController<List<int>>.broadcast();
  StreamSubscription<Uint8List>? _valueSubscription;
  StreamSubscription<bool>? _connectionSubscription;

  late String _serviceUuid;
  late String _writeCharacteristicUuid;
  String _notifyCharacteristicUuid = '';
  bool _withoutResponse = false;
  bool _connected = false;

  @override
  TransportType get type => TransportType.bluetooth;

  @override
  String get label {
    if (config.deviceName.trim().isNotEmpty) {
      return 'BLE ${config.deviceName.trim()}';
    }
    return 'BLE ${config.deviceId}';
  }

  @override
  bool get isConnected => _connected;

  @override
  Stream<List<int>> get incoming => _incoming.stream;

  @override
  Future<void> connect() async {
    final deviceId = config.deviceId.trim();
    if (deviceId.isEmpty) {
      throw StateError('BLE device is not selected.');
    }

    await UniversalBle.requestPermissions();
    await UniversalBle.stopScan().catchError((_) {});
    await UniversalBle.connect(deviceId, timeout: const Duration(seconds: 20));
    _connected = true;

    _connectionSubscription = UniversalBle.connectionStream(deviceId).listen((
      connected,
    ) {
      _connected = connected;
      if (!connected && !_incoming.isClosed) {
        unawaited(_incoming.close());
      }
    });

    final services = await UniversalBle.discoverServices(
      deviceId,
      timeout: const Duration(seconds: 12),
    );
    final channel = _resolveChannel(services);
    _serviceUuid = channel.serviceUuid;
    _writeCharacteristicUuid = channel.writeCharacteristicUuid;
    _notifyCharacteristicUuid = channel.notifyCharacteristicUuid;
    final service = _findService(services, _serviceUuid);
    final writeCharacteristic = _findCharacteristic(
      service,
      _writeCharacteristicUuid,
    );
    _withoutResponse = _resolveWriteMode(writeCharacteristic);

    await _subscribeIncoming(
      deviceId: deviceId,
      service: service,
      characteristicUuid: _notifyCharacteristicUuid,
    );
  }

  @override
  Future<void> send(List<int> bytes) async {
    if (!_connected) {
      throw StateError('BLE session is not connected.');
    }
    await UniversalBle.write(
      config.deviceId.trim(),
      _serviceUuid,
      _writeCharacteristicUuid,
      Uint8List.fromList(bytes),
      withoutResponse: _withoutResponse,
      timeout: const Duration(seconds: 8),
    );
  }

  @override
  Future<void> disconnect() async {
    final deviceId = config.deviceId.trim();
    if (deviceId.isNotEmpty &&
        _connected &&
        _notifyCharacteristicUuid.isNotEmpty &&
        _serviceUuid.isNotEmpty) {
      await UniversalBle.unsubscribe(
        deviceId,
        _serviceUuid,
        _notifyCharacteristicUuid,
      ).catchError((_) {});
    }
    await _valueSubscription?.cancel();
    _valueSubscription = null;
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    if (deviceId.isNotEmpty && _connected) {
      await UniversalBle.disconnect(deviceId).catchError((_) {});
    }
    _connected = false;
    if (!_incoming.isClosed) {
      await _incoming.close();
    }
  }

  BleService _findService(List<BleService> services, String serviceUuid) {
    final service = _findServiceOrNull(services, serviceUuid);
    if (service != null) {
      return service;
    }
    throw StateError('BLE service not found: $serviceUuid');
  }

  BleService? _findServiceOrNull(
    List<BleService> services,
    String serviceUuid,
  ) {
    for (final service in services) {
      if (BleUuidParser.compareStrings(service.uuid, serviceUuid)) {
        return service;
      }
    }
    return null;
  }

  BleCharacteristic _findCharacteristic(
    BleService service,
    String characteristicUuid,
  ) {
    final characteristic = _findCharacteristicOrNull(
      service,
      characteristicUuid,
    );
    if (characteristic != null) {
      return characteristic;
    }
    throw StateError('BLE characteristic not found: $characteristicUuid');
  }

  BleCharacteristic? _findCharacteristicOrNull(
    BleService service,
    String characteristicUuid,
  ) {
    for (final characteristic in service.characteristics) {
      if (BleUuidParser.compareStrings(
        characteristic.uuid,
        characteristicUuid,
      )) {
        return characteristic;
      }
    }
    return null;
  }

  _BleChannelSelection _resolveChannel(List<BleService> services) {
    final requestedServiceUuid = config.serviceUuid.trim();
    final requestedWriteUuid = config.effectiveWriteCharacteristicUuid.trim();
    final requestedNotifyUuid = config.notifyCharacteristicUuid.trim();

    if (requestedServiceUuid.isNotEmpty) {
      final service = _findService(services, requestedServiceUuid);
      return _resolveChannelInService(
        service,
        requestedWriteUuid: requestedWriteUuid,
        requestedNotifyUuid: requestedNotifyUuid,
      );
    }

    if (requestedWriteUuid.isNotEmpty) {
      for (final service in services) {
        final characteristic = _findCharacteristicOrNull(
          service,
          requestedWriteUuid,
        );
        if (characteristic != null && _canWrite(characteristic)) {
          return _resolveChannelInService(
            service,
            requestedWriteUuid: requestedWriteUuid,
            requestedNotifyUuid: requestedNotifyUuid,
          );
        }
      }
      throw StateError(
        'BLE write characteristic not found: $requestedWriteUuid',
      );
    }

    for (final profile in _knownBleSerialProfiles) {
      final service = _findServiceOrNull(services, profile.serviceUuid);
      if (service == null) {
        continue;
      }
      final write = _findCharacteristicOrNull(
        service,
        profile.writeCharacteristicUuid,
      );
      if (write == null || !_canWrite(write)) {
        continue;
      }
      final notify = _findCharacteristicOrNull(
        service,
        profile.notifyCharacteristicUuid,
      );
      final notifyUuid = notify != null && _canNotify(notify)
          ? notify.uuid
          : _bestNotifyCharacteristic(service, write)?.uuid ?? '';
      return _BleChannelSelection(
        serviceUuid: service.uuid,
        writeCharacteristicUuid: write.uuid,
        notifyCharacteristicUuid: notifyUuid,
      );
    }

    for (final service in services) {
      if (_isGenericBleService(service.uuid)) {
        continue;
      }
      final write = _firstWritableCharacteristic(service);
      if (write == null) {
        continue;
      }
      return _BleChannelSelection(
        serviceUuid: service.uuid,
        writeCharacteristicUuid: write.uuid,
        notifyCharacteristicUuid:
            _bestNotifyCharacteristic(service, write)?.uuid ?? '',
      );
    }

    for (final service in services) {
      final write = _firstWritableCharacteristic(service);
      if (write == null) {
        continue;
      }
      return _BleChannelSelection(
        serviceUuid: service.uuid,
        writeCharacteristicUuid: write.uuid,
        notifyCharacteristicUuid:
            _bestNotifyCharacteristic(service, write)?.uuid ?? '',
      );
    }

    throw StateError(
      'No BLE UART writable characteristic found. This device does not expose a serial-like BLE channel.',
    );
  }

  _BleChannelSelection _resolveChannelInService(
    BleService service, {
    required String requestedWriteUuid,
    required String requestedNotifyUuid,
  }) {
    final write = requestedWriteUuid.isEmpty
        ? _firstWritableCharacteristic(service)
        : _findCharacteristic(service, requestedWriteUuid);
    if (write == null || !_canWrite(write)) {
      throw StateError(
        'No writable BLE characteristic found in ${service.uuid}.',
      );
    }

    BleCharacteristic? notify;
    if (requestedNotifyUuid.isNotEmpty) {
      notify = _findCharacteristic(service, requestedNotifyUuid);
      if (!_canNotify(notify)) {
        throw StateError(
          'BLE characteristic ${notify.uuid} does not support notify or indicate.',
        );
      }
    } else {
      notify = _bestNotifyCharacteristic(service, write);
    }

    return _BleChannelSelection(
      serviceUuid: service.uuid,
      writeCharacteristicUuid: write.uuid,
      notifyCharacteristicUuid: notify?.uuid ?? '',
    );
  }

  BleCharacteristic? _firstWritableCharacteristic(BleService service) {
    for (final characteristic in service.characteristics) {
      if (_canWrite(characteristic)) {
        return characteristic;
      }
    }
    return null;
  }

  BleCharacteristic? _bestNotifyCharacteristic(
    BleService service,
    BleCharacteristic writeCharacteristic,
  ) {
    if (_canNotify(writeCharacteristic)) {
      return writeCharacteristic;
    }
    for (final characteristic in service.characteristics) {
      if (_canNotify(characteristic)) {
        return characteristic;
      }
    }
    return null;
  }

  bool _canWrite(BleCharacteristic characteristic) {
    final properties = characteristic.properties;
    return properties.contains(CharacteristicProperty.write) ||
        properties.contains(CharacteristicProperty.writeWithoutResponse);
  }

  bool _canNotify(BleCharacteristic characteristic) {
    final properties = characteristic.properties;
    return properties.contains(CharacteristicProperty.notify) ||
        properties.contains(CharacteristicProperty.indicate);
  }

  bool _isGenericBleService(String serviceUuid) {
    final uuid = serviceUuid.toLowerCase();
    return uuid.startsWith('00001800-') ||
        uuid.startsWith('00001801-') ||
        uuid.startsWith('0000180a-');
  }

  bool _resolveWriteMode(BleCharacteristic characteristic) {
    final properties = characteristic.properties;
    final supportsWrite = properties.contains(CharacteristicProperty.write);
    final supportsWriteWithoutResponse = properties.contains(
      CharacteristicProperty.writeWithoutResponse,
    );
    if (!supportsWrite && !supportsWriteWithoutResponse) {
      throw StateError(
        'BLE characteristic ${characteristic.uuid} does not support write.',
      );
    }
    if (config.writeWithoutResponse && supportsWriteWithoutResponse) {
      return true;
    }
    if (!supportsWrite && supportsWriteWithoutResponse) {
      return true;
    }
    return false;
  }

  Future<void> _subscribeIncoming({
    required String deviceId,
    required BleService service,
    required String characteristicUuid,
  }) async {
    if (characteristicUuid.isEmpty) {
      return;
    }

    final characteristic = _findCharacteristic(service, characteristicUuid);
    _valueSubscription =
        UniversalBle.characteristicValueStream(
          deviceId,
          characteristic.uuid,
        ).listen((value) {
          if (!_incoming.isClosed) {
            _incoming.add(value);
          }
        });

    final properties = characteristic.properties;
    if (properties.contains(CharacteristicProperty.notify)) {
      await UniversalBle.subscribeNotifications(
        deviceId,
        service.uuid,
        characteristic.uuid,
        timeout: const Duration(seconds: 8),
      );
      return;
    }
    if (properties.contains(CharacteristicProperty.indicate)) {
      await UniversalBle.subscribeIndications(
        deviceId,
        service.uuid,
        characteristic.uuid,
        timeout: const Duration(seconds: 8),
      );
      return;
    }

    await _valueSubscription?.cancel();
    _valueSubscription = null;
    throw StateError(
      'BLE characteristic ${characteristic.uuid} does not support notify or indicate.',
    );
  }
}

class _KnownBleSerialProfile {
  const _KnownBleSerialProfile({
    required this.serviceUuid,
    required this.writeCharacteristicUuid,
    required this.notifyCharacteristicUuid,
  });

  final String serviceUuid;
  final String writeCharacteristicUuid;
  final String notifyCharacteristicUuid;
}

class _ScanConfig {
  const _ScanConfig({required this.filter, required this.platformConfig});

  final ScanFilter? filter;
  final PlatformConfig platformConfig;
}

class _BleChannelSelection {
  const _BleChannelSelection({
    required this.serviceUuid,
    required this.writeCharacteristicUuid,
    required this.notifyCharacteristicUuid,
  });

  final String serviceUuid;
  final String writeCharacteristicUuid;
  final String notifyCharacteristicUuid;
}
