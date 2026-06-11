import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lserial/app/app.dart';
import 'package:lserial/app/localization.dart';
import 'package:lserial/core/encoding/data_format.dart';
import 'package:lserial/domain/data_frame.dart';
import 'package:lserial/features/console/frame_list_view.dart';
import 'package:lserial/protocol/frame_formatter.dart';
import 'package:lserial/storage/log_buffer.dart';

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

  testWidgets('console filtering preserves source and format behavior',
      (tester) async {
    final snapshot = LogSnapshot(
      revision: 1,
      frames: <DataFrame>[
        DataFrame(
          sequence: 1,
          timestamp: DateTime(2026),
          direction: FrameDirection.rx,
          bytes: 'alpha'.codeUnits,
          source: 'COM1',
        ),
        DataFrame(
          sequence: 2,
          timestamp: DateTime(2026),
          direction: FrameDirection.tx,
          bytes: <int>[0x42],
          source: 'COM2',
        ),
      ],
      totalFrames: 2,
      totalBytes: 6,
      droppedFrames: 0,
      droppedBytes: 0,
      paused: false,
    );

    await tester.pumpWidget(
      _ConsoleHarness(
        snapshot: snapshot,
        options: const ConsoleFormatOptions(
          viewMode: ConsoleViewMode.ascii,
          showTimestamp: false,
          showDirection: true,
          showSource: true,
        ),
        filter: 'COM1',
        visibleSources: const <String>{'COM1'},
      ),
    );

    expect(
      find.textContaining('COM1 R: alpha', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('COM2', findRichText: true), findsNothing);

    await tester.pumpWidget(
      _ConsoleHarness(
        snapshot: snapshot,
        options: const ConsoleFormatOptions(
          viewMode: ConsoleViewMode.hex,
          showTimestamp: false,
          showDirection: false,
          showSource: true,
        ),
        filter: '42',
        visibleSources: const <String>{'COM2'},
      ),
    );

    expect(
      find.textContaining('COM2 42', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('alpha', findRichText: true), findsNothing);
  });

  testWidgets('console can hide ASCII line ending symbols', (tester) async {
    final snapshot = LogSnapshot(
      revision: 1,
      frames: <DataFrame>[
        DataFrame(
          sequence: 1,
          timestamp: DateTime(2026),
          direction: FrameDirection.rx,
          bytes: <int>[0x6f, 0x6b, 0x0d, 0x0a],
          source: 'COM1',
        ),
      ],
      totalFrames: 1,
      totalBytes: 4,
      droppedFrames: 0,
      droppedBytes: 0,
      paused: false,
    );

    await tester.pumpWidget(
      _ConsoleHarness(
        snapshot: snapshot,
        options: const ConsoleFormatOptions(
          viewMode: ConsoleViewMode.ascii,
          showTimestamp: false,
          showDirection: true,
          showSource: true,
          showLineEndingSymbols: true,
        ),
        filter: '',
        visibleSources: const <String>{'COM1'},
      ),
    );

    expect(
      find.textContaining(r'COM1 R: ok\r\n', findRichText: true),
      findsOneWidget,
    );

    await tester.pumpWidget(
      _ConsoleHarness(
        snapshot: snapshot,
        options: const ConsoleFormatOptions(
          viewMode: ConsoleViewMode.ascii,
          showTimestamp: false,
          showDirection: true,
          showSource: true,
          showLineEndingSymbols: false,
        ),
        filter: '',
        visibleSources: const <String>{'COM1'},
      ),
    );

    expect(
      find.textContaining('COM1 R: ok', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining(r'\r\n', findRichText: true), findsNothing);
  });

  test('ASCII control bytes use terminal caret notation', () {
    const formatter = FrameFormatter();
    const options = ConsoleFormatOptions(
      viewMode: ConsoleViewMode.ascii,
      showTimestamp: false,
      showDirection: true,
      showSource: true,
    );
    final frame = DataFrame(
      sequence: 1,
      timestamp: DateTime(2026),
      direction: FrameDirection.tx,
      bytes: <int>[0x03, 0x04, 0x1b, 0x7f],
      source: 'COM1',
    );

    expect(formatter.formatPayload(frame, options), r'^C^D^[^?');
  });
}

class _ConsoleHarness extends StatelessWidget {
  const _ConsoleHarness({
    required this.snapshot,
    required this.options,
    required this.filter,
    required this.visibleSources,
  });

  final LogSnapshot snapshot;
  final ConsoleFormatOptions options;
  final String filter;
  final Set<String> visibleSources;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: SizedBox(
        width: 640,
        height: 360,
        child: FrameListView(
          snapshot: snapshot,
          formatter: const FrameFormatter(),
          options: options,
          logFontSize: 12,
          autoScroll: false,
          pauseDisplay: false,
          filter: filter,
          visibleSources: visibleSources,
        ),
      ),
    );
  }
}
