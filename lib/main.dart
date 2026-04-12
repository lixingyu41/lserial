import 'package:flutter/material.dart';

import 'app/app.dart';
import 'platform/window_title.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeWindowTitle();
  runApp(const CommToolApp());
}
