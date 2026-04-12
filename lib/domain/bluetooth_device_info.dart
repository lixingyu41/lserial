class BluetoothDeviceInfo {
  const BluetoothDeviceInfo({
    required this.id,
    required this.name,
    required this.rssi,
  });

  final String id;
  final String name;
  final int? rssi;

  String get label {
    final displayName = name.trim().isEmpty ? 'Unknown BLE device' : name;
    final signal = rssi == null ? '' : '  $rssi dBm';
    return '$displayName$signal\n$id';
  }
}
