import 'window_title_stub.dart'
    if (dart.library.io) 'window_title_desktop.dart';

Future<void> initializeWindowTitle() => initializeWindowTitlePlatform();

Future<void> setAppWindowTitle(String title) =>
    setAppWindowTitlePlatform(title);
