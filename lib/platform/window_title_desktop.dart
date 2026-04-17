import 'dart:io';
import 'dart:ui';

import 'package:window_manager/window_manager.dart';

bool get _isDesktop =>
    Platform.isWindows || Platform.isMacOS || Platform.isLinux;

const Size _minimumWindowSize = Size(1120, 720);

Future<void> initializeWindowTitlePlatform() async {
  if (!_isDesktop) {
    return;
  }
  await windowManager.ensureInitialized();
  await windowManager.setMinimumSize(_minimumWindowSize);

  final currentSize = await windowManager.getSize();
  if (currentSize.width < _minimumWindowSize.width ||
      currentSize.height < _minimumWindowSize.height) {
    await windowManager.setSize(_minimumWindowSize);
  }
}

Future<void> setAppWindowTitlePlatform(String title) async {
  if (!_isDesktop) {
    return;
  }
  await windowManager.setTitle(title);
}
