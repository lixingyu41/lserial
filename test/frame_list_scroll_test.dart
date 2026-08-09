import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lserial/core/encoding/data_format.dart';
import 'package:lserial/domain/data_frame.dart';
import 'package:lserial/features/console/frame_list_view.dart';
import 'package:lserial/protocol/frame_formatter.dart';
import 'package:lserial/storage/log_buffer.dart';

void main() {
  testWidgets('auto scroll converges after a large burst of wrapped frames', (
    tester,
  ) async {
    final key = GlobalKey<_FrameListHarnessState>();
    await tester.pumpWidget(_FrameListHarness(key: key));

    key.currentState!.update(
      frames: _frames(0, 300, payloadLength: 180),
      revision: 1,
    );
    await tester.pumpAndSettle();

    var position = _scrollPosition(tester);
    expect(position.pixels, closeTo(position.maxScrollExtent, 0.5));

    key.currentState!.update(
      frames: _frames(0, 500, payloadLength: 240),
      revision: 2,
    );
    await tester.pumpAndSettle();

    position = _scrollPosition(tester);
    expect(position.pixels, closeTo(position.maxScrollExtent, 0.5));
  });

  testWidgets('disabling auto scroll prevents later frames from jumping down', (
    tester,
  ) async {
    final key = GlobalKey<_FrameListHarnessState>();
    await tester.pumpWidget(_FrameListHarness(key: key));

    key.currentState!.update(frames: _frames(0, 200), revision: 1);
    await tester.pumpAndSettle();

    var position = _scrollPosition(tester);
    expect(position.pixels, closeTo(position.maxScrollExtent, 0.5));

    key.currentState!.update(autoScroll: false);
    await tester.pump();
    position = _scrollPosition(tester);
    position.jumpTo(position.maxScrollExtent / 3);
    final manualOffset = position.pixels;

    key.currentState!.update(frames: _frames(0, 400), revision: 2);
    await tester.pumpAndSettle();

    position = _scrollPosition(tester);
    expect(position.pixels, closeTo(manualOffset, 0.5));
    expect(position.pixels, lessThan(position.maxScrollExtent - 1));
  });

  testWidgets(
    'head trimming keeps the visible frame fixed when auto scroll is off',
    (tester) async {
      final key = GlobalKey<_FrameListHarnessState>();
      await tester.pumpWidget(_FrameListHarness(key: key));

      final initialFrames = _frames(0, 400, payloadLength: 8);
      key.currentState!.update(
        frames: initialFrames,
        revision: 1,
        autoScroll: false,
      );
      await tester.pumpAndSettle();

      final position = _scrollPosition(tester);
      position.jumpTo(position.maxScrollExtent / 2);
      await tester.pump();
      final anchor = _middleVisibleFrame(tester, initialFrames);
      final anchorY = tester.getTopLeft(_frameFinder(anchor)).dy;
      final offsetBefore = position.pixels;

      key.currentState!.update(
        frames: <DataFrame>[
          ...initialFrames.skip(1),
          ..._frames(400, 1, payloadLength: 8),
        ],
        revision: 2,
      );
      await tester.pumpAndSettle();

      final offsetAfter = _scrollPosition(tester).pixels;
      final visibleAfter = _middleVisibleFrame(
        tester,
        key.currentState!.frames,
      );
      expect(
        _frameFinder(anchor),
        findsOneWidget,
        reason:
            'anchor=${anchor.sequence} visibleAfter=${visibleAfter.sequence} '
            'offsetBefore=$offsetBefore offsetAfter=$offsetAfter',
      );
      expect(
        tester.getTopLeft(_frameFinder(anchor)).dy,
        closeTo(anchorY, 0.5),
        reason:
            'anchor=${anchor.sequence} visibleAfter=${visibleAfter.sequence} '
            'offsetBefore=$offsetBefore offsetAfter=$offsetAfter',
      );
    },
  );
}

ScrollPosition _scrollPosition(WidgetTester tester) {
  final scrollable = find.descendant(
    of: find.byType(FrameListView),
    matching: find.byType(Scrollable),
  );
  return tester.state<ScrollableState>(scrollable).position;
}

Finder _frameFinder(DataFrame frame) {
  return find.byKey(GlobalObjectKey<State<StatefulWidget>>(frame));
}

DataFrame _middleVisibleFrame(WidgetTester tester, List<DataFrame> frames) {
  final viewport = tester.getRect(find.byType(FrameListView));
  final visible = <DataFrame>[];
  for (final frame in frames) {
    final row = _frameFinder(frame);
    if (row.evaluate().isEmpty) {
      continue;
    }
    final rect = tester.getRect(row);
    if (rect.bottom > viewport.top && rect.top < viewport.bottom) {
      visible.add(frame);
    }
  }
  if (visible.isEmpty) {
    throw StateError('No visible frame found');
  }
  return visible[visible.length ~/ 2];
}

List<DataFrame> _frames(int start, int count, {int payloadLength = 48}) {
  return List<DataFrame>.generate(count, (index) {
    final sequence = start + index;
    return DataFrame.text(
      sequence: sequence,
      direction: sequence.isEven ? FrameDirection.rx : FrameDirection.tx,
      text:
          '${sequence.toString().padLeft(4, '0')} '
          '${List<String>.filled(payloadLength, 'x').join()}',
      source: 'Serial1',
    );
  });
}

class _FrameListHarness extends StatefulWidget {
  const _FrameListHarness({super.key});

  @override
  State<_FrameListHarness> createState() => _FrameListHarnessState();
}

class _FrameListHarnessState extends State<_FrameListHarness> {
  List<DataFrame> frames = const <DataFrame>[];
  int revision = 0;
  bool autoScroll = true;

  void update({List<DataFrame>? frames, int? revision, bool? autoScroll}) {
    setState(() {
      this.frames = frames ?? this.frames;
      this.revision = revision ?? this.revision;
      this.autoScroll = autoScroll ?? this.autoScroll;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 420,
          height: 260,
          child: FrameListView(
            snapshot: LogSnapshot(
              revision: revision,
              frames: frames,
              totalFrames: frames.length,
              totalBytes: frames.fold(
                0,
                (sum, frame) => sum + frame.byteLength,
              ),
              droppedFrames: 0,
              droppedBytes: 0,
              paused: false,
            ),
            formatter: const FrameFormatter(),
            options: const ConsoleFormatOptions(
              viewMode: ConsoleViewMode.ascii,
              showTimestamp: true,
              showDirection: true,
            ),
            logFontSize: 13,
            autoScroll: autoScroll,
            pauseDisplay: false,
            filter: '',
          ),
        ),
      ),
    );
  }
}
