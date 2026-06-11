import 'dart:collection';

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
    this.bottomPadding = 0,
  });

  final LogSnapshot snapshot;
  final FrameFormatter formatter;
  final ConsoleFormatOptions options;
  final double logFontSize;
  final bool autoScroll;
  final bool pauseDisplay;
  final String filter;
  final Set<String>? visibleSources;
  final double bottomPadding;

  @override
  State<FrameListView> createState() => _FrameListViewState();
}

class _FrameListViewState extends State<FrameListView> {
  final ScrollController scroll = ScrollController();
  final Map<DataFrame, String> _timestampCache =
      HashMap<DataFrame, String>.identity();
  final Map<_FrameFormatKey, String> _formattedFrameCache =
      <_FrameFormatKey, String>{};
  final Map<_FrameFormatKey, String> _lowerFormattedFrameCache =
      <_FrameFormatKey, String>{};
  final Map<_PayloadKey, String> _payloadCache = <_PayloadKey, String>{};

  List<DataFrame>? _filteredFramesCache;
  int? _filteredRevision;
  String? _filteredFilter;
  ConsoleFormatOptions? _filteredOptions;
  Set<String>? _filteredVisibleSources;
  bool _scrollPending = false;

  @override
  void didUpdateWidget(FrameListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.snapshot.revision != oldWidget.snapshot.revision) {
      _pruneFrameCaches();
    }
    if (widget.options != oldWidget.options) {
      _formattedFrameCache.clear();
      _lowerFormattedFrameCache.clear();
    }
    if (widget.options.viewMode != oldWidget.options.viewMode) {
      _payloadCache.clear();
    }
    if (widget.autoScroll &&
        !widget.pauseDisplay &&
        widget.snapshot.revision != oldWidget.snapshot.revision) {
      _scheduleScrollToBottom();
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
        padding: EdgeInsets.only(bottom: widget.bottomPadding),
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
    if (_filteredFramesCache != null &&
        _filteredRevision == widget.snapshot.revision &&
        _filteredFilter == filter &&
        _filteredOptions == widget.options &&
        _sameSources(_filteredVisibleSources, visibleSources)) {
      return _filteredFramesCache!;
    }

    final frames = _buildFilteredFrames(filter, visibleSources);
    _filteredFramesCache = frames;
    _filteredRevision = widget.snapshot.revision;
    _filteredFilter = filter;
    _filteredOptions = widget.options;
    _filteredVisibleSources = visibleSources == null
        ? null
        : Set<String>.unmodifiable(visibleSources);
    return frames;
  }

  List<DataFrame> _buildFilteredFrames(
    String filter,
    Set<String>? visibleSources,
  ) {
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
      return _lowerFormattedFrame(frame, formatter, options).contains(filter);
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
          '${_timestampText(frame, formatter)} ',
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
          _payloadText(frame, formatter, options),
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

  void _scheduleScrollToBottom() {
    if (_scrollPending) {
      return;
    }
    _scrollPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollPending = false;
      if (!mounted) {
        return;
      }
      _scrollToBottom();
    });
  }

  String _timestampText(DataFrame frame, FrameFormatter formatter) {
    return _timestampCache.putIfAbsent(
      frame,
      () => formatter.formatTimestamp(frame.timestamp),
    );
  }

  String _payloadText(
    DataFrame frame,
    FrameFormatter formatter,
    ConsoleFormatOptions options,
  ) {
    return _payloadCache.putIfAbsent(
      _PayloadKey(frame, options),
      () => formatter.formatPayload(frame, options),
    );
  }

  String _formattedFrame(
    DataFrame frame,
    FrameFormatter formatter,
    ConsoleFormatOptions options,
  ) {
    return _formattedFrameCache.putIfAbsent(
      _FrameFormatKey(frame, options),
      () => formatter.formatFrame(frame, options),
    );
  }

  String _lowerFormattedFrame(
    DataFrame frame,
    FrameFormatter formatter,
    ConsoleFormatOptions options,
  ) {
    return _lowerFormattedFrameCache.putIfAbsent(
      _FrameFormatKey(frame, options),
      () => _formattedFrame(frame, formatter, options).toLowerCase(),
    );
  }

  bool _sameSources(Set<String>? left, Set<String>? right) {
    if (left == null || right == null) {
      return left == right;
    }
    if (left.length != right.length) {
      return false;
    }
    for (final source in left) {
      if (!right.contains(source)) {
        return false;
      }
    }
    return true;
  }

  void _pruneFrameCaches() {
    final retained = HashSet<DataFrame>.identity()
      ..addAll(widget.snapshot.frames);
    _timestampCache.removeWhere((frame, _) => !retained.contains(frame));
    _formattedFrameCache.removeWhere(
      (key, _) => !retained.contains(key.frame),
    );
    _lowerFormattedFrameCache.removeWhere(
      (key, _) => !retained.contains(key.frame),
    );
    _payloadCache.removeWhere((key, _) => !retained.contains(key.frame));
    _filteredFramesCache = null;
  }
}

class _FrameFormatKey {
  const _FrameFormatKey(this.frame, this.options);

  final DataFrame frame;
  final ConsoleFormatOptions options;

  @override
  bool operator ==(Object other) {
    return other is _FrameFormatKey &&
        identical(other.frame, frame) &&
        other.options == options;
  }

  @override
  int get hashCode => Object.hash(identityHashCode(frame), options);
}

class _PayloadKey {
  const _PayloadKey(this.frame, this.options);

  final DataFrame frame;
  final ConsoleFormatOptions options;

  @override
  bool operator ==(Object other) {
    return other is _PayloadKey &&
        identical(other.frame, frame) &&
        other.options == options;
  }

  @override
  int get hashCode => Object.hash(identityHashCode(frame), options);
}
