class ClassicBluetoothDeviceInfo {
  const ClassicBluetoothDeviceInfo({
    required this.address,
    required this.name,
    required this.paired,
    required this.connected,
    required this.remembered,
  });

  final String address;
  final String name;
  final bool paired;
  final bool connected;
  final bool remembered;

  String get label {
    final displayName = name.trim().isEmpty ? 'Unknown device' : name.trim();
    return '$displayName\n$address';
  }
}
