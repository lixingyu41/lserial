import 'dart:collection';

import 'package:flutter/material.dart';

import '../../core/encoding/data_format.dart';
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
    this.sourceViewModes = const <String, ConsoleViewMode>{},
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
  final Map<String, ConsoleViewMode> sourceViewModes;
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
  Map<String, ConsoleViewMode>? _filteredSourceViewModes;
  Set<String>? _filteredVisibleSources;
  final Set<DataFrame> _renderedFrames = HashSet<DataFrame>.identity();
  List<DataFrame>? _indexedFrames;
  Map<DataFrame, int>? _frameIndexes;
  bool _scrollPending = false;
  int _scrollGeneration = 0;
  int _scrollRequest = 0;
  final Key _centerKey = UniqueKey();
  DataFrame? _centerFrame;
  int _centerIndex = 0;
  int _anchorRevision = 0;
  bool _adjustingScroll = false;

  @override
  void initState() {
    super.initState();
    scroll.addListener(_handleScroll);
    _scheduleScrollToBottom();
  }

  @override
  void didUpdateWidget(FrameListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sourceViewModesChanged = !_sameSourceViewModes(
      widget.sourceViewModes,
      oldWidget.sourceViewModes,
    );
    if (!widget.autoScroll) {
      _updateAnchor(oldWidget);
    } else if (_centerFrame != null) {
      _centerFrame = null;
      _centerIndex = 0;
      _anchorRevision++;
      if (scroll.hasClients) {
        scroll.position.correctBy(-scroll.offset);
      }
    }
    if (widget.snapshot.revision != oldWidget.snapshot.revision) {
      _pruneFrameCaches();
    }
    if (widget.options != oldWidget.options || sourceViewModesChanged) {
      _formattedFrameCache.clear();
      _lowerFormattedFrameCache.clear();
    }
    if (widget.options.viewMode != oldWidget.options.viewMode ||
        sourceViewModesChanged) {
      _payloadCache.clear();
    }
    if ((!widget.autoScroll && oldWidget.autoScroll) ||
        (widget.pauseDisplay && !oldWidget.pauseDisplay)) {
      _cancelScrollToBottom();
    }
    if (widget.autoScroll &&
        !widget.pauseDisplay &&
        (widget.snapshot.revision != oldWidget.snapshot.revision ||
            !oldWidget.autoScroll ||
            oldWidget.pauseDisplay ||
            widget.options != oldWidget.options ||
            sourceViewModesChanged ||
            widget.filter != oldWidget.filter ||
            widget.logFontSize != oldWidget.logFontSize ||
            widget.bottomPadding != oldWidget.bottomPadding)) {
      _scheduleScrollToBottom();
    }
  }

  @override
  void dispose() {
    _scrollGeneration++;
    scroll.removeListener(_handleScroll);
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final frames = _filteredFrames();
    final frameIndexes = _indexesFor(frames);
    final formatter = widget.formatter;
    final filter = widget.filter.trim();
    int? childIndex(Key key, {required bool beforeCenter}) {
      if (key is! GlobalObjectKey<State<StatefulWidget>> ||
          key.value is! DataFrame) {
        return null;
      }
      final index = frameIndexes?[key.value as DataFrame];
      if (index == null) {
        return null;
      }
      return beforeCenter
          ? (index < _centerIndex ? _centerIndex - index - 1 : null)
          : (index >= _centerIndex ? index - _centerIndex : null);
    }

    Widget row(BuildContext context, int index) {
      final frame = frames[index];
      final options = _optionsForFrame(frame, formatter);
      _renderedFrames.add(frame);
      return DecoratedBox(
        key: _frameKey(frame),
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
              children: _spansFor(context, frame, formatter, options, filter),
            ),
            softWrap: true,
            style: TextStyle(
              fontFamily: 'Consolas',
              fontFamilyFallback: const <String>['Noto Sans SC'],
              fontSize: widget.logFontSize,
              letterSpacing: 0,
              height: 1.35,
              color: _textColor(context, frame),
            ),
            strutStyle: StrutStyle(
              fontFamily: 'Consolas',
              fontFamilyFallback: const <String>['Noto Sans SC'],
              fontSize: widget.logFontSize,
              height: 1.35,
              forceStrutHeight: true,
            ),
          ),
        ),
      );
    }

    return SelectionArea(
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: (_) {
          _scheduleScrollToBottom();
          return false;
        },
        child: CustomScrollView(
          controller: scroll,
          center: _centerKey,
          physics: widget.autoScroll && !widget.pauseDisplay
              ? const NeverScrollableScrollPhysics()
              : null,
          slivers: [
            SliverList.builder(
              key: ValueKey('before-$_anchorRevision'),
              itemCount: _centerIndex,
              findChildIndexCallback: frameIndexes == null
                  ? null
                  : (key) => childIndex(key, beforeCenter: true),
              itemBuilder: (context, index) =>
                  row(context, _centerIndex - index - 1),
            ),
            SliverPadding(
              key: _centerKey,
              padding: EdgeInsets.only(bottom: widget.bottomPadding),
              sliver: SliverList.builder(
                key: ValueKey('after-$_anchorRevision'),
                itemCount: frames.length - _centerIndex,
                findChildIndexCallback: frameIndexes == null
                    ? null
                    : (key) => childIndex(key, beforeCenter: false),
                itemBuilder: (context, index) =>
                    row(context, _centerIndex + index),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Map<DataFrame, int>? _indexesFor(List<DataFrame> frames) {
    if (widget.autoScroll) {
      _indexedFrames = null;
      _frameIndexes = null;
      return null;
    }
    if (identical(_indexedFrames, frames) && _frameIndexes != null) {
      return _frameIndexes;
    }
    final indexes = HashMap<DataFrame, int>.identity();
    for (var index = 0; index < frames.length; index++) {
      indexes[frames[index]] = index;
    }
    _indexedFrames = frames;
    _frameIndexes = indexes;
    return indexes;
  }

  List<DataFrame> _filteredFrames() {
    final filter = widget.filter.trim().toLowerCase();
    final visibleSources = widget.visibleSources;
    if (_filteredFramesCache != null &&
        _filteredRevision == widget.snapshot.revision &&
        _filteredFilter == filter &&
        _filteredOptions == widget.options &&
        _sameSourceViewModes(
          _filteredSourceViewModes,
          widget.sourceViewModes,
        ) &&
        _sameSources(_filteredVisibleSources, visibleSources)) {
      return _filteredFramesCache!;
    }

    final frames = _buildFilteredFrames(filter, visibleSources);
    _filteredFramesCache = frames;
    _filteredRevision = widget.snapshot.revision;
    _filteredFilter = filter;
    _filteredOptions = widget.options;
    _filteredSourceViewModes = Map<String, ConsoleViewMode>.unmodifiable(
      widget.sourceViewModes,
    );
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
    return widget.snapshot.frames
        .where((frame) {
          if (visibleSources != null &&
              !visibleSources.contains(formatter.sourceToken(frame))) {
            return false;
          }
          if (filter.isEmpty) {
            return true;
          }
          return _lowerFormattedFrame(
            frame,
            formatter,
            _optionsForFrame(frame, formatter),
          ).contains(filter);
        })
        .toList(growable: false);
  }

  ConsoleFormatOptions _optionsForFrame(
    DataFrame frame,
    FrameFormatter formatter,
  ) {
    final source = formatter.sourceToken(frame);
    final mode = widget.sourceViewModes[source];
    return mode == null
        ? widget.options
        : widget.options.copyWith(viewMode: mode);
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
      backgroundColor: Theme.of(
        context,
      ).colorScheme.tertiaryContainer.withValues(alpha: 0.72),
    );
    final spans = <TextSpan>[];
    if (options.showTimestamp) {
      spans.addAll(
        _highlightedTextSpans(
          '${_timestampText(frame, formatter)} ',
          filter,
          TextStyle(
            color: tokenColor,
            fontWeight: FontWeight.w600,
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          ),
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
          TextSpan(text: text.substring(cursor, index), style: baseStyle),
        );
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

  void _scheduleScrollToBottom() {
    if (!widget.autoScroll || widget.pauseDisplay) {
      return;
    }
    _scrollRequest++;
    if (_scrollPending) {
      return;
    }
    _scrollPending = true;
    final generation = _scrollGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _settleScrollToBottom(generation);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _settleScrollToBottom(int generation) {
    if (!_canAutoScroll(generation)) {
      _finishScrollRequest(generation);
      return;
    }
    if (!scroll.hasClients || !scroll.position.hasContentDimensions) {
      _finishScrollRequest(generation);
      return;
    }

    final request = _scrollRequest;
    final extentBefore = scroll.position.maxScrollExtent;
    if ((scroll.position.pixels - extentBefore).abs() > 0.5) {
      _adjustingScroll = true;
      try {
        scroll.jumpTo(extentBefore);
      } finally {
        _adjustingScroll = false;
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_canAutoScroll(generation)) {
        _finishScrollRequest(generation);
        return;
      }
      if (!scroll.hasClients || !scroll.position.hasContentDimensions) {
        _finishScrollRequest(generation);
        return;
      }
      final extentAfter = scroll.position.maxScrollExtent;
      final atBottom = (scroll.position.pixels - extentAfter).abs() <= 0.5;
      final layoutChanged = (extentAfter - extentBefore).abs() > 0.5;
      if (_scrollRequest != request || layoutChanged || !atBottom) {
        _settleScrollToBottom(generation);
        return;
      }
      _finishScrollRequest(generation);
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _handleScroll() {
    if (!_adjustingScroll) {
      _scheduleScrollToBottom();
    }
  }

  bool _canAutoScroll(int generation) {
    return mounted &&
        generation == _scrollGeneration &&
        widget.autoScroll &&
        !widget.pauseDisplay;
  }

  void _cancelScrollToBottom() {
    _scrollGeneration++;
    _scrollPending = false;
  }

  void _finishScrollRequest(int generation) {
    if (generation == _scrollGeneration) {
      _scrollPending = false;
    }
  }

  void _updateAnchor(FrameListView oldWidget) {
    final frames = _filteredFrames();
    final indexes = _indexesFor(frames)!;
    final centerIndex = indexes[_centerFrame];
    if (!oldWidget.autoScroll && centerIndex != null) {
      _centerIndex = centerIndex;
      return;
    }

    // Keep a retained visible row at the viewport origin. Slivers on either
    // side can then grow or be trimmed without remapping its pixel offset.
    final viewport = context.findRenderObject();
    if (!scroll.hasClients || viewport is! RenderBox || !viewport.attached) {
      _centerFrame = frames.firstOrNull;
      _centerIndex = 0;
      return;
    }

    final viewportTop = viewport.localToGlobal(Offset.zero).dy;
    final viewportBottom = viewportTop + viewport.size.height;
    final viewportCenter = (viewportTop + viewportBottom) / 2;
    DataFrame? anchor;
    double? anchorTop;
    var closestDistance = double.infinity;
    final staleFrames = <DataFrame>[];

    for (final frame in _renderedFrames) {
      final anchorContext = _frameKey(frame).currentContext;
      final renderObject = anchorContext?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.attached) {
        staleFrames.add(frame);
        continue;
      }
      if (!indexes.containsKey(frame)) {
        continue;
      }
      final top = renderObject.localToGlobal(Offset.zero).dy;
      final bottom = top + renderObject.size.height;
      if (bottom <= viewportTop || top >= viewportBottom) {
        continue;
      }
      final distance = ((top + bottom) / 2 - viewportCenter).abs();
      if (distance < closestDistance) {
        closestDistance = distance;
        anchor = frame;
        anchorTop = top;
      }
    }
    _renderedFrames.removeAll(staleFrames);
    _centerFrame = anchor ?? frames.firstOrNull;
    _centerIndex = indexes[_centerFrame] ?? 0;
    _anchorRevision++;
    final target = anchorTop == null ? 0.0 : viewportTop - anchorTop;
    scroll.position.correctBy(target - scroll.offset);
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

  bool _sameSourceViewModes(
    Map<String, ConsoleViewMode>? left,
    Map<String, ConsoleViewMode>? right,
  ) {
    if (left == null || right == null) {
      return left == right;
    }
    if (left.length != right.length) {
      return false;
    }
    for (final entry in left.entries) {
      if (right[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }

  void _pruneFrameCaches() {
    final retained = HashSet<DataFrame>.identity()
      ..addAll(widget.snapshot.frames);
    _timestampCache.removeWhere((frame, _) => !retained.contains(frame));
    _formattedFrameCache.removeWhere((key, _) => !retained.contains(key.frame));
    _lowerFormattedFrameCache.removeWhere(
      (key, _) => !retained.contains(key.frame),
    );
    _payloadCache.removeWhere((key, _) => !retained.contains(key.frame));
    _renderedFrames.removeWhere((frame) => !retained.contains(frame));
    _filteredFramesCache = null;
  }
}

GlobalObjectKey<State<StatefulWidget>> _frameKey(DataFrame frame) {
  return GlobalObjectKey<State<StatefulWidget>>(frame);
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
