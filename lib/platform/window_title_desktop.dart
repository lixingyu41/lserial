import 'dart:io';

import 'package:window_manager/window_manager.dart';

bool get _isDesktop =>
    Platform.isWindows || Platform.isMacOS || Platform.isLinux;

Future<void> initializeWindowTitlePlatform() async {
  if (!_isDesktop) {
    return;
  }
  await windowManager.ensureInitialized();
}

Future<void> setAppWindowTitlePlatform(String title) async {
  if (!_isDesktop) {
    return;
  }
  await windowManager.setTitle(title);
}
