import 'package:flutter/material.dart';

import '../../application/session_controller.dart';
import '../../domain/data_frame.dart';
import '../../storage/log_buffer.dart';

class FrameListView extends StatefulWidget {
  const FrameListView({
    super.key,
    required this.snapshot,
    required this.controller,
    required this.filter,
  });

  final LogSnapshot snapshot;
  final SessionController controller;
  final String filter;

  @override
  State<FrameListView> createState() => _FrameListViewState();
}

class _FrameListViewState extends State<FrameListView> {
  final ScrollController scroll = ScrollController();

  @override
  void didUpdateWidget(FrameListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller.autoScroll &&
        !widget.controller.pauseDisplay &&
        widget.snapshot.revision != oldWidget.snapshot.revision) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final frames = _filteredFrames();
    final options = widget.controller.formatOptions;
    final formatter = widget.controller.formatter;
    return Column(
      children: [
        _StatsLine(snapshot: widget.snapshot, visibleFrames: frames.length),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            controller: scroll,
            itemExtent: 24,
            itemCount: frames.length,
            itemBuilder: (context, index) {
              final frame = frames[index];
              return ColoredBox(
                color: _rowColor(context, frame),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                  child: Text(
                    formatter.formatFrame(frame, options),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Consolas',
                      fontSize: 12,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  List<DataFrame> _filteredFrames() {
    final filter = widget.filter.trim().toLowerCase();
    if (filter.isEmpty) {
      return widget.snapshot.frames;
    }
    final formatter = widget.controller.formatter;
    final options = widget.controller.formatOptions;
    return widget.snapshot.frames.where((frame) {
      return formatter
          .formatFrame(frame, options)
          .toLowerCase()
          .contains(filter);
    }).toList(growable: false);
  }

  Color _rowColor(BuildContext context, DataFrame frame) {
    final scheme = Theme.of(context).colorScheme;
    return switch (frame.direction) {
      FrameDirection.rx => Colors.transparent,
      FrameDirection.tx => scheme.primary.withValues(alpha: 0.08),
      FrameDirection.system => scheme.tertiary.withValues(alpha: 0.10),
    };
  }

  void _scrollToBottom() {
    if (!scroll.hasClients) {
      return;
    }
    scroll.jumpTo(scroll.position.maxScrollExtent);
  }
}

class _StatsLine extends StatelessWidget {
  const _StatsLine({
    required this.snapshot,
    required this.visibleFrames,
  });

  final LogSnapshot snapshot;
  final int visibleFrames;

  @override
  Widget build(BuildContext context) {
    final text =
        'visible $visibleFrames | total frames ${snapshot.totalFrames} | '
        'bytes ${snapshot.totalBytes} | dropped frames ${snapshot.droppedFrames} | '
        'dropped bytes ${snapshot.droppedBytes}${snapshot.paused ? " | display paused" : ""}';
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text(text, style: Theme.of(context).textTheme.bodySmall),
      ),
    );
  }
}
