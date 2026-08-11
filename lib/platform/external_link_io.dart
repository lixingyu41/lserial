import 'dart:io';

Future<void> openExternalLink(Uri uri) async {
  final target = uri.toString();
  if (Platform.isWindows) {
    await Process.start('rundll32', <String>[
      'url.dll,FileProtocolHandler',
      target,
    ], mode: ProcessStartMode.detached);
    return;
  }
  if (Platform.isMacOS) {
    await Process.start('open', <String>[
      target,
    ], mode: ProcessStartMode.detached);
    return;
  }
  if (Platform.isLinux) {
    await Process.start('xdg-open', <String>[
      target,
    ], mode: ProcessStartMode.detached);
    return;
  }
  throw UnsupportedError('Opening external links is not supported.');
}
