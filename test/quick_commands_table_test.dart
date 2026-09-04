import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lserial/application/session_controller.dart';
import 'package:lserial/core/encoding/data_format.dart';
import 'package:lserial/domain/quick_command.dart';
import 'package:lserial/features/quick_commands/quick_commands_panel.dart';
import 'package:lserial/features/send_panel/send_panel.dart';

void main() {
  const longName = 'Charlie command name that is deliberately too long to fit';
  testWidgets('quick commands stay on one row and sort from headers', (
    tester,
  ) async {
    final controller = SessionController();
    controller.quickCommands
      ..clear()
      ..addAll(const <QuickCommand>[
        QuickCommand(
          id: 1,
          name: longName,
          content: 'CC CC CC CC CC CC CC CC',
          format: PayloadFormat.hex,
        ),
        QuickCommand(
          id: 2,
          name: 'Alpha',
          content: 'AT+ALPHA',
          format: PayloadFormat.ascii,
        ),
        QuickCommand(
          id: 3,
          name: 'Bravo',
          content: 'AT+BRAVO',
          format: PayloadFormat.ascii,
        ),
      ]);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 320,
            child: QuickCommandsPanel(
              controller: controller,
              loadBubblePosition: () async => null,
              saveBubblePosition: (_) async {},
            ),
          ),
        ),
      ),
    );

    final contentText = tester.widget<Text>(
      find.text('CC CC CC CC CC CC CC CC'),
    );
    expect(contentText.maxLines, 1);
    expect(contentText.softWrap, isFalse);
    expect(find.byTooltip(controller.strings.send), findsNWidgets(3));
    expect(find.byTooltip(controller.strings.fillSendData), findsNWidgets(3));
    expect(find.byTooltip(controller.strings.edit), findsNothing);
    expect(find.byTooltip(controller.strings.delete), findsNothing);
    final bubble = find.byKey(
      const ValueKey<String>('quick-command-action-bubble'),
    );
    final toggle = find.byKey(
      const ValueKey<String>('quick-command-bubble-toggle'),
    );
    expect(tester.getSize(bubble), const Size.square(36));
    expect(find.text(controller.strings.quickCommands), findsNothing);
    expect(find.byTooltip(controller.strings.addCommand), findsNothing);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.getSize(bubble), const Size(108, 36));
    expect(find.byTooltip(controller.strings.addCommand), findsOneWidget);
    expect(
      find.byTooltip(controller.strings.quickCommandImportExport),
      findsOneWidget,
    );
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.drag(bubble, const Offset(260, 230));
    await tester.pumpAndSettle();
    expect(find.text('A'), findsNWidgets(2));
    expect(find.text('H'), findsOneWidget);
    expect(find.byType(ReorderableListView), findsOneWidget);
    expect(
      tester.getCenter(find.byKey(const ValueKey('quick-command-add-row'))).dy,
      greaterThan(tester.getCenter(find.text('Bravo')).dy),
    );
    final longNameHost = find.byKey(
      const ValueKey<String>('quick-command-name-tooltip-1'),
    );
    final continuationLayer = find.byKey(
      const ValueKey<String>('quick-command-name-continuation-1'),
    );
    expect(continuationLayer, findsNothing);
    final bravoYBeforeHover = tester.getCenter(find.text('Bravo')).dy;
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(longNameHost));
    await tester.pump();

    expect(continuationLayer, findsOneWidget);
    expect(find.text(longName), findsOneWidget);
    expect(tester.getCenter(find.text('Bravo')).dy, bravoYBeforeHover);
    expect(
      tester.getSize(continuationLayer).width,
      tester
          .getSize(
            find.byKey(const ValueKey<String>('quick-command-name-cell-1')),
          )
          .width,
    );
    final continuationText = tester.widget<Text>(
      find.descendant(of: continuationLayer, matching: find.byType(Text)),
    );
    expect(continuationText.data, isNotEmpty);
    expect(continuationText.data, isNot(longName));
    expect(continuationText.maxLines, isNull);
    expect(
      tester.getSize(continuationLayer).height,
      greaterThan(tester.getSize(find.text(longName)).height),
    );
    final ignorePointer = tester.widget<IgnorePointer>(
      find.ancestor(
        of: continuationLayer,
        matching: find.byType(IgnorePointer),
      ),
    );
    expect(ignorePointer.ignoring, isTrue);

    await mouse.moveTo(tester.getCenter(find.text('H')));
    await tester.pump();
    expect(continuationLayer, findsNothing);
    expect(
      tester
          .getSize(find.byKey(const ValueKey<String>('quick-command-row-1')))
          .height,
      30,
    );

    for (final column in <String>['name', 'content']) {
      expect(
        find.byKey(ValueKey<String>('quick-command-resize-$column')),
        findsOneWidget,
      );
    }
    expect(
      find.byKey(const ValueKey<String>('quick-command-resize-format')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('quick-command-resize-send')),
      findsNothing,
    );
    final formatHeader = find.byKey(
      const ValueKey<String>('quick-command-header-format'),
    );
    final sendHeader = find.byKey(
      const ValueKey<String>('quick-command-header-send'),
    );
    final fillHeader = find.byKey(
      const ValueKey<String>('quick-command-header-fill'),
    );
    final formatRectBeforeResize = tester.getRect(formatHeader);
    final fillRectBeforeResize = tester.getRect(fillHeader);
    final sendRectBeforeResize = tester.getRect(sendHeader);
    expect(formatRectBeforeResize.width, closeTo(36, 0.001));
    expect(fillRectBeforeResize.width, closeTo(36, 0.001));
    expect(sendRectBeforeResize.width, closeTo(36, 0.001));
    expect(
      formatRectBeforeResize.right,
      closeTo(fillRectBeforeResize.left, 0.001),
    );
    expect(
      fillRectBeforeResize.right,
      closeTo(sendRectBeforeResize.left, 0.001),
    );

    final nameHeaderWidth = tester
        .getSize(find.byKey(const ValueKey<String>('quick-command-sort-name')))
        .width;
    await tester.drag(
      find.byKey(const ValueKey<String>('quick-command-resize-name')),
      const Offset(40, 0),
    );
    await tester.pump();
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey<String>('quick-command-sort-name')),
          )
          .width,
      greaterThan(nameHeaderWidth),
    );
    _expectRectClose(tester.getRect(formatHeader), formatRectBeforeResize);
    _expectRectClose(tester.getRect(fillHeader), fillRectBeforeResize);
    _expectRectClose(tester.getRect(sendHeader), sendRectBeforeResize);

    await tester.tap(
      find.byKey(const ValueKey<String>('quick-command-sort-name')),
    );
    await tester.pump();
    expect(_verticalOrder(tester), <String>['Alpha', 'Bravo', longName]);

    await tester.tap(
      find.byKey(const ValueKey<String>('quick-command-sort-name')),
    );
    await tester.pump();
    expect(_verticalOrder(tester), <String>[longName, 'Bravo', 'Alpha']);
    expect(find.byType(ReorderableListView), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey<String>('quick-command-sort-name')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(controller.strings.restoreSavedOrder));
    await tester.pumpAndSettle();
    expect(_verticalOrder(tester), <String>[longName, 'Alpha', 'Bravo']);
    expect(find.byType(ReorderableListView), findsOneWidget);

    await tester.drag(
      find.byKey(const ValueKey<String>('quick-command-row-1')),
      const Offset(0, 70),
    );
    await tester.pumpAndSettle();
    expect(controller.quickCommands.map((command) => command.id), <int>[
      2,
      1,
      3,
    ]);

    await tester.tap(
      find.byKey(const ValueKey<String>('quick-command-row-1')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    expect(find.text(controller.strings.edit), findsOneWidget);
    expect(find.text(controller.strings.delete), findsOneWidget);
  });

  testWidgets('quick command fills send box and applies its format', (
    tester,
  ) async {
    final controller = SessionController();
    controller.quickCommands
      ..clear()
      ..add(
        const QuickCommand(
          id: 7,
          name: 'Binary command',
          content: '01 AB FF',
          format: PayloadFormat.hex,
        ),
      );
    controller.saveSendDraftText('old text');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Expanded(
                child: QuickCommandsPanel(
                  controller: controller,
                  loadBubblePosition: () async => null,
                  saveBubblePosition: (_) async {},
                ),
              ),
              SizedBox(height: 150, child: SendPanel(controller: controller)),
            ],
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('quick-command-fill-7')),
    );
    await tester.pump();

    expect(controller.sendDraftText, '01 AB FF');
    expect(controller.sendFormat, PayloadFormat.hex);
    final input = tester.widget<TextField>(
      find.byKey(const ValueKey<String>('send-data-input')),
    );
    expect(input.controller?.text, '01 AB FF');
    expect(controller.txByteCount, 0);
  });

  testWidgets('quick command action bubble persists its dragged position', (
    tester,
  ) async {
    final controller = SessionController();
    addTearDown(controller.dispose);
    ({double x, double y})? savedPosition;

    Widget buildPanel(Key key) {
      return MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 240,
            child: QuickCommandsPanel(
              key: key,
              controller: controller,
              loadBubblePosition: () async => savedPosition,
              saveBubblePosition: (position) async {
                savedPosition = position;
              },
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(buildPanel(const ValueKey<String>('first-panel')));
    await tester.pumpAndSettle();

    final bubble = find.byKey(
      const ValueKey<String>('quick-command-action-bubble'),
    );
    expect(tester.getTopLeft(bubble), Offset.zero);
    expect(tester.getSize(bubble), const Size.square(36));
    expect(
      tester
          .widget<ReorderableListView>(find.byType(ReorderableListView))
          .padding,
      EdgeInsets.zero,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('quick-command-bubble-toggle')),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(bubble), const Size(108, 36));

    final gesture = await tester.startGesture(tester.getCenter(bubble));
    await gesture.moveTo(const Offset(420, 300));
    await tester.pump();
    await gesture.moveTo(const Offset(154, 98));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    final draggedPosition = tester.getTopLeft(bubble);
    expect(draggedPosition, const Offset(100, 80));
    expect(savedPosition, isNotNull);

    await tester.pumpWidget(
      buildPanel(const ValueKey<String>('restored-panel')),
    );
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(bubble), draggedPosition);
    expect(tester.getSize(bubble), const Size.square(36));
  });
}

List<String> _verticalOrder(WidgetTester tester) {
  const longName = 'Charlie command name that is deliberately too long to fit';
  final names = <String>['Alpha', 'Bravo', longName];
  names.sort(
    (left, right) => tester
        .getCenter(find.text(left))
        .dy
        .compareTo(tester.getCenter(find.text(right)).dy),
  );
  return names;
}

void _expectRectClose(Rect actual, Rect expected) {
  expect(actual.left, closeTo(expected.left, 0.001));
  expect(actual.top, closeTo(expected.top, 0.001));
  expect(actual.right, closeTo(expected.right, 0.001));
  expect(actual.bottom, closeTo(expected.bottom, 0.001));
}
