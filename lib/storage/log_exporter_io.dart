import 'dart:io';

Future<String> exportLogText(String content) async {
  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  final name = 'lserial_log_${now.year}${two(now.month)}${two(now.day)}_'
      '${two(now.hour)}${two(now.minute)}${two(now.second)}.txt';
  final file = File(name);
  await file.writeAsString(content, flush: true);
  return 'Saved ${file.absolute.path}';
}
