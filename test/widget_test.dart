import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:lserial/app/app.dart';
import 'package:lserial/app/localization.dart';

void main() {
  testWidgets('communication tool shell smoke test', (tester) async {
    tester.view
      ..physicalSize = const Size(1280, 800)
      ..devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const CommToolApp());
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.zh.connectionType), findsOneWidget);
    expect(find.text(AppStrings.zh.sendData), findsOneWidget);
  });
}
