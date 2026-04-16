import 'package:flutter/material.dart';

import '../../domain/data_frame.dart';
import '../../protocol/frame_formatter.dart';
import '../../storage/log_buffer.dart';

class FrameListView extends StatefulWidget {
  const FrameListView({
    super.key,
    required this.snapshot,
    required this.formatter,
    required this.options,
    required this.logFontSize,
    required this.autoScroll,
    required this.pauseDisplay,
    required this.filter,
    this.visibleSources,
  });

  final LogSnapshot snapshot;
  final FrameFormatter formatter;
  final ConsoleFormatOptions options;
  final double logFontSize;
  final bool autoScroll;
  final bool pauseDisplay;
  final String filter;
  final Set<String>? visibleSources;

  @override
  State<FrameListView> createState() => _FrameListViewState();
}

class _FrameListViewState extends State<FrameListView> {
  final ScrollController scroll = ScrollController();

  @override
  void didUpdateWidget(FrameListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.autoScroll &&
        !widget.pauseDisplay &&
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
    final options = widget.options;
    final formatter = widget.formatter;
    final filter = widget.filter.trim();
    return SelectionArea(
      child: ListView.builder(
        controller: scroll,
        itemCount: frames.length,
        itemBuilder: (context, index) {
          final frame = frames[index];
          return DecoratedBox(
            decoration: BoxDecoration(
              color: _rowColor(context, frame),
              border: frame.direction == FrameDirection.system
                  ? Border(
                      left: BorderSide(
                        color: Theme.of(context).colorScheme.tertiary,
                        width: 3,
                      ),
                    )
                  : null,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Text.rich(
                TextSpan(
                  children: _spansFor(
                    context,
                    frame,
                    formatter,
                    options,
                    filter,
                  ),
                ),
                softWrap: true,
                style: TextStyle(
                  fontFamily: 'Consolas',
                  fontSize: widget.logFontSize,
                  letterSpacing: 0,
                  height: 1.35,
                  color: _textColor(context, frame),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  List<DataFrame> _filteredFrames() {
    final filter = widget.filter.trim().toLowerCase();
    final visibleSources = widget.visibleSources;
    if (filter.isEmpty && visibleSources == null) {
      return widget.snapshot.frames;
    }
    final formatter = widget.formatter;
    final options = widget.options;
    return widget.snapshot.frames.where((frame) {
      if (visibleSources != null &&
          !visibleSources.contains(formatter.sourceToken(frame))) {
        return false;
      }
      if (filter.isEmpty) {
        return true;
      }
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
      FrameDirection.system => scheme.tertiary.withValues(alpha: 0.14),
    };
  }

  Color? _textColor(BuildContext context, DataFrame frame) {
    if (frame.direction != FrameDirection.system) {
      return null;
    }
    return Theme.of(context).colorScheme.tertiary;
  }

  List<TextSpan> _spansFor(
    BuildContext context,
    DataFrame frame,
    FrameFormatter formatter,
    ConsoleFormatOptions options,
    String filter,
  ) {
    final tokenColor = _tokenColor(context, frame);
    final colonColor = Theme.of(context).colorScheme.outline;
    final highlightStyle = TextStyle(
      color: Theme.of(context).colorScheme.onTertiaryContainer,
      backgroundColor: Theme.of(context)
          .colorScheme
          .tertiaryContainer
          .withValues(alpha: 0.72),
    );
    final spans = <TextSpan>[];
    if (options.showTimestamp) {
      spans.addAll(
        _highlightedTextSpans(
          '${formatter.formatTimestamp(frame.timestamp)} ',
          filter,
          TextStyle(color: tokenColor, fontWeight: FontWeight.w600),
          highlightStyle,
        ),
      );
    }
    if (options.showSource && frame.direction != FrameDirection.system) {
      spans.addAll(
        _highlightedTextSpans(
          '${formatter.sourceToken(frame)} ',
          filter,
          TextStyle(color: tokenColor, fontWeight: FontWeight.w600),
          highlightStyle,
        ),
      );
    }
    if (options.showDirection) {
      spans
        ..addAll(
          _highlightedTextSpans(
            formatter.directionToken(frame),
            filter,
            TextStyle(color: tokenColor, fontWeight: FontWeight.w700),
            highlightStyle,
          ),
        )
        ..addAll(
          _highlightedTextSpans(
            ': ',
            filter,
            TextStyle(color: colonColor, fontWeight: FontWeight.w700),
            highlightStyle,
          ),
        );
    }
    if (options.showContent) {
      spans.addAll(
        _highlightedTextSpans(
          formatter.formatPayload(frame, options.viewMode),
          filter,
          null,
          highlightStyle,
        ),
      );
    }
    return spans;
  }

  List<TextSpan> _highlightedTextSpans(
    String text,
    String filter,
    TextStyle? baseStyle,
    TextStyle highlightStyle,
  ) {
    if (text.isEmpty || filter.isEmpty) {
      return [TextSpan(text: text, style: baseStyle)];
    }

    final haystack = text.toLowerCase();
    final needle = filter.toLowerCase();
    var cursor = 0;
    final spans = <TextSpan>[];

    while (cursor < text.length) {
      final index = haystack.indexOf(needle, cursor);
      if (index < 0) {
        spans.add(TextSpan(text: text.substring(cursor), style: baseStyle));
        break;
      }

      if (index > cursor) {
        spans.add(
            TextSpan(text: text.substring(cursor, index), style: baseStyle));
      }

      final end = index + needle.length;
      spans.add(
        TextSpan(
          text: text.substring(index, end),
          style: baseStyle?.merge(highlightStyle) ?? highlightStyle,
        ),
      );
      cursor = end;
    }

    return spans;
  }

  Color _tokenColor(BuildContext context, DataFrame frame) {
    final scheme = Theme.of(context).colorScheme;
    return switch (frame.direction) {
      FrameDirection.rx => scheme.secondary,
      FrameDirection.tx => scheme.primary,
      FrameDirection.system => scheme.tertiary,
    };
  }

  void _scrollToBottom() {
    if (!scroll.hasClients) {
      return;
    }
    scroll.jumpTo(scroll.position.maxScrollExtent);
  }
}
