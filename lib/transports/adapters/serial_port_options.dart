const String webSerialPickPortOption = '__web_serial_pick_port__';
const String webSerialSelectedPortOption = '__web_serial_selected_port__';

bool isSerialPickerOption(String value) => value == webSerialPickPortOption;

bool isGenericSerialPortName(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ||
      trimmed == webSerialPickPortOption ||
      trimmed == webSerialSelectedPortOption ||
      trimmed == 'Web Serial';
}

String serialPortOptionLabel(
  String value, {
  String pickLabel = 'Choose Web Serial port...',
  String selectedLabel = 'Web Serial port selected',
}) {
  return switch (value) {
    webSerialPickPortOption => pickLabel,
    webSerialSelectedPortOption => selectedLabel,
    _ => value,
  };
}
