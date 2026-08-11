import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../application/session_controller.dart';
import '../../core/encoding/data_format.dart';
import '../../domain/quick_command.dart';
import '../../domain/send_history_entry.dart';
import '../../storage/quick_command_text_codec.dart';
import '../../storage/text_file_transfer.dart';
import '../../storage/workspace_preferences.dart';

enum _QuickCommandFileAction { importReplace, importAppend, export }

enum _QuickCommandSortColumn { name, content, format }

enum _QuickCommandColumn { name, content }

enum _QuickCommandHeaderAction { restoreSavedOrder }

enum _QuickCommandRowAction { edit, delete }

const _quickCommandBubbleHeight = 36.0;
const _quickCommandBubbleExpandedWidth = 108.0;

class QuickCommandsPanel extends StatefulWidget {
  const QuickCommandsPanel({
    super.key,
    required this.controller,
    this.loadBubblePosition = readQuickCommandBubblePosition,
    this.saveBubblePosition = writeQuickCommandBubblePosition,
  });

  final SessionController controller;
  final Future<QuickCommandBubblePosition?> Function() loadBubblePosition;
  final Future<void> Function(QuickCommandBubblePosition position)
      saveBubblePosition;

  @override
  State<QuickCommandsPanel> createState() => _QuickCommandsPanelState();
}

class _QuickCommandsPanelState extends State<QuickCommandsPanel> {
  double _quickRatio = 0.62;
  _QuickCommandSortColumn? _sortColumn;
  bool _sortAscending = true;
  _QuickCommandColumnWidths _columnWidths = const _QuickCommandColumnWidths();
  Offset _bubblePosition = Offset.zero;
  bool _bubbleExpanded = false;

  SessionController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    unawaited(_restoreBubblePosition());
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final hasHistory = controller.sendHistory.isNotEmpty;
        if (!hasHistory) {
          return _buildQuickCommandPane(context);
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            final quickHeight = _quickHeight(constraints.maxHeight);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: quickHeight,
                  child: _buildQuickCommandPane(context),
                ),
                _HistorySplitDivider(
                  onDrag: (delta) =>
                      _resizeHistorySplit(delta, constraints.maxHeight),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 8),
                  child: Text(
                    controller.strings.sendHistory,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Expanded(child: _HistoryList(controller: controller)),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildQuickCommandPane(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const collapsedSize = _quickCommandBubbleHeight;
        final bubbleWidth = _bubbleExpanded
            ? _quickCommandBubbleExpandedWidth
            : collapsedSize;
        final positionLimit = Offset(
          math.max(0, constraints.maxWidth - collapsedSize),
          math.max(0, constraints.maxHeight - collapsedSize),
        );
        final basePosition = Offset(
          _bubblePosition.dx * positionLimit.dx,
          _bubblePosition.dy * positionLimit.dy,
        );
        final displayLimit = Offset(
          math.max(0, constraints.maxWidth - bubbleWidth),
          positionLimit.dy,
        );
        final displayPosition = Offset(
          basePosition.dx.clamp(0, displayLimit.dx).toDouble(),
          basePosition.dy.clamp(0, displayLimit.dy).toDouble(),
        );

        return Stack(
          children: [
            Positioned.fill(
              child: _QuickCommandList(
                controller: controller,
                onEdit: (command) => _openEditor(context, command),
                onAdd: () => _openEditor(context, null),
                sortColumn: _sortColumn,
                sortAscending: _sortAscending,
                onSort: _sortQuickCommands,
                columnWidths: _columnWidths,
                onResizeColumn: _resizeQuickCommandColumn,
                onRestoreSavedOrder: _restoreSavedOrder,
              ),
            ),
            Positioned(
              left: displayPosition.dx,
              top: displayPosition.dy,
              child: _QuickCommandActionBubble(
                expanded: _bubbleExpanded,
                controller: controller,
                onToggle: () {
                  setState(() => _bubbleExpanded = !_bubbleExpanded);
                },
                onAdd: () => _openEditor(context, null),
                onFileAction: _handleFileAction,
                onDragUpdate: (delta) {
                  final next = Offset(
                    (displayPosition.dx + delta.dx)
                        .clamp(0, displayLimit.dx)
                        .toDouble(),
                    (displayPosition.dy + delta.dy)
                        .clamp(0, displayLimit.dy)
                        .toDouble(),
                  );
                  setState(() {
                    _bubblePosition = Offset(
                      positionLimit.dx == 0 ? 0 : next.dx / positionLimit.dx,
                      positionLimit.dy == 0 ? 0 : next.dy / positionLimit.dy,
                    );
                  });
                },
                onDragEnd: _persistBubblePosition,
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _restoreBubblePosition() async {
    final position = await widget.loadBubblePosition();
    if (!mounted || position == null) {
      return;
    }
    if (!position.x.isFinite || !position.y.isFinite) {
      return;
    }
    setState(() {
      _bubblePosition = Offset(
        position.x.clamp(0, 1).toDouble(),
        position.y.clamp(0, 1).toDouble(),
      );
    });
  }

  void _persistBubblePosition() {
    unawaited(
      widget.saveBubblePosition((x: _bubblePosition.dx, y: _bubblePosition.dy)),
    );
  }

  double _quickHeight(double availableHeight) {
    if (!availableHeight.isFinite || availableHeight <= 0) {
      return 160;
    }

    const minPaneHeight = 96.0;
    if (availableHeight <= minPaneHeight * 2) {
      return math.max(0, availableHeight * _quickRatio);
    }

    final maxQuickHeight = availableHeight - minPaneHeight;
    return (availableHeight * _quickRatio)
        .clamp(minPaneHeight, maxQuickHeight)
        .toDouble();
  }

  void _resizeHistorySplit(double delta, double availableHeight) {
    if (availableHeight <= 0 || !availableHeight.isFinite) {
      return;
    }
    setState(() {
      _quickRatio = (_quickRatio + delta / availableHeight)
          .clamp(0.25, 0.82)
          .toDouble();
    });
  }

  void _sortQuickCommands(_QuickCommandSortColumn column) {
    setState(() {
      if (_sortColumn == column) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumn = column;
        _sortAscending = true;
      }
    });
  }

  void _resizeQuickCommandColumn(_QuickCommandColumn column, double delta) {
    setState(() {
      _columnWidths = _columnWidths.resize(column, delta);
    });
  }

  void _restoreSavedOrder() {
    setState(() {
      _sortColumn = null;
      _sortAscending = true;
    });
  }

  Future<void> _handleFileAction(_QuickCommandFileAction action) async {
    switch (action) {
      case _QuickCommandFileAction.importReplace:
        await _importQuickCommands(QuickCommandImportMode.replace);
        return;
      case _QuickCommandFileAction.importAppend:
        await _importQuickCommands(QuickCommandImportMode.append);
        return;
      case _QuickCommandFileAction.export:
        await _exportQuickCommands();
        return;
    }
  }

  Future<void> _importQuickCommands(QuickCommandImportMode mode) async {
    try {
      final text = await pickTextFile();
      if (text == null) {
        return;
      }
      final commands = decodeQuickCommandsText(text);
      controller.importQuickCommands(commands, mode: mode);
      if (mounted) {
        _showMessage(controller.strings.quickCommandsImported(commands.length));
      }
    } on Object catch (error) {
      if (mounted) {
        _showMessage(controller.strings.quickCommandImportFailed(error));
      }
    }
  }

  Future<void> _exportQuickCommands() async {
    try {
      final result = await saveTextFile(
        content: encodeQuickCommandsText(controller.quickCommands),
        suggestedName: _quickCommandFileName(),
      );
      if (mounted && result != null) {
        _showMessage(controller.strings.exportResult(result));
      }
    } on Object catch (error) {
      if (mounted) {
        _showMessage(controller.strings.quickCommandExportFailed(error));
      }
    }
  }

  String _quickCommandFileName() {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return 'lserial_quick_commands_${now.year}${two(now.month)}'
        '${two(now.day)}_${two(now.hour)}${two(now.minute)}'
        '${two(now.second)}.txt';
  }

  void _showMessage(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  Future<void> _openEditor(BuildContext context, QuickCommand? command) async {
    final name = TextEditingController(text: command?.name ?? '');
    final content = TextEditingController(text: command?.content ?? '');
    var format = command?.format ?? PayloadFormat.ascii;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(
                command == null
                    ? controller.strings.addCommand
                    : controller.strings.editCommand,
              ),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: name,
                      decoration: InputDecoration(
                        labelText: controller.strings.name,
                      ),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: content,
                      minLines: 2,
                      maxLines: 6,
                      decoration: InputDecoration(
                        labelText: controller.strings.content,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<PayloadFormat>(
                      initialValue: format,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: controller.strings.format,
                      ),
                      items: PayloadFormat.values
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(
                                controller.strings.payloadFormat(value),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => format = value);
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(controller.strings.cancel),
                ),
                FilledButton(
                  onPressed: () {
                    if (command == null) {
                      controller.addQuickCommand(
                        name: name.text,
                        content: content.text,
                        format: format,
                      );
                    } else {
                      controller.updateQuickCommand(
                        id: command.id,
                        name: name.text,
                        content: content.text,
                        format: format,
                      );
                    }
                    Navigator.of(context).pop();
                  },
                  child: Text(controller.strings.save),
                ),
              ],
            );
          },
        );
      },
    );

    name.dispose();
    content.dispose();
  }
}

class _QuickCommandActionBubble extends StatelessWidget {
  const _QuickCommandActionBubble({
    required this.expanded,
    required this.controller,
    required this.onToggle,
    required this.onAdd,
    required this.onFileAction,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final bool expanded;
  final SessionController controller;
  final VoidCallback onToggle;
  final VoidCallback onAdd;
  final ValueChanged<_QuickCommandFileAction> onFileAction;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    final strings = controller.strings;
    final buttons = <Widget>[
      SizedBox.square(
        dimension: _quickCommandBubbleHeight,
        child: IconButton(
          key: const ValueKey<String>('quick-command-bubble-toggle'),
          tooltip: strings.quickCommands,
          onPressed: onToggle,
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          icon: Icon(expanded ? Icons.close : Icons.add, size: 19),
        ),
      ),
      if (expanded)
        SizedBox.square(
          dimension: _quickCommandBubbleHeight,
          child: IconButton(
            tooltip: strings.addCommand,
            onPressed: onAdd,
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add, size: 19),
          ),
        ),
      if (expanded)
        SizedBox.square(
          dimension: _quickCommandBubbleHeight,
          child: PopupMenuButton<_QuickCommandFileAction>(
            tooltip: strings.quickCommandImportExport,
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.import_export, size: 19),
            onSelected: onFileAction,
            itemBuilder: (context) => [
              PopupMenuItem(
                value: _QuickCommandFileAction.importReplace,
                child: Row(
                  children: [
                    const Icon(Icons.file_download_outlined),
                    const SizedBox(width: 10),
                    Text(strings.importReplaceCurrent),
                  ],
                ),
              ),
              PopupMenuItem(
                value: _QuickCommandFileAction.importAppend,
                child: Row(
                  children: [
                    const Icon(Icons.playlist_add),
                    const SizedBox(width: 10),
                    Text(strings.importInsertCurrent),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: _QuickCommandFileAction.export,
                child: Row(
                  children: [
                    const Icon(Icons.file_upload_outlined),
                    const SizedBox(width: 10),
                    Text(strings.exportQuickCommands),
                  ],
                ),
              ),
            ],
          ),
        ),
    ];

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (details) => onDragUpdate(details.delta),
      onPanEnd: (_) => onDragEnd(),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 140),
        alignment: Alignment.centerLeft,
        curve: Curves.easeOutCubic,
        child: Material(
          key: const ValueKey<String>('quick-command-action-bubble'),
          elevation: 6,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: expanded
                ? _quickCommandBubbleExpandedWidth
                : _quickCommandBubbleHeight,
            height: _quickCommandBubbleHeight,
            child: Row(children: buttons),
          ),
        ),
      ),
    );
  }
}

class _HistorySplitDivider extends StatelessWidget {
  const _HistorySplitDivider({required this.onDrag});

  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outlineVariant;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeUpDown,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (details) => onDrag(details.delta.dy),
        child: SizedBox(
          height: 9,
          child: Center(child: Container(height: 1, color: color)),
        ),
      ),
    );
  }
}

class _QuickCommandList extends StatelessWidget {
  const _QuickCommandList({
    required this.controller,
    required this.onEdit,
    required this.onAdd,
    required this.sortColumn,
    required this.sortAscending,
    required this.onSort,
    required this.columnWidths,
    required this.onResizeColumn,
    required this.onRestoreSavedOrder,
  });

  final SessionController controller;
  final void Function(QuickCommand command) onEdit;
  final VoidCallback onAdd;
  final _QuickCommandSortColumn? sortColumn;
  final bool sortAscending;
  final ValueChanged<_QuickCommandSortColumn> onSort;
  final _QuickCommandColumnWidths columnWidths;
  final void Function(_QuickCommandColumn column, double delta) onResizeColumn;
  final VoidCallback onRestoreSavedOrder;

  @override
  Widget build(BuildContext context) {
    final commands = List<QuickCommand>.of(controller.quickCommands);
    final column = sortColumn;
    if (column != null) {
      commands.sort((left, right) {
        final comparison = _compareCommands(left, right, column);
        if (comparison == 0) {
          return left.id.compareTo(right.id);
        }
        return sortAscending ? comparison : -comparison;
      });
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final effectiveWidths = columnWidths.fitTo(width);
        final flexibleWidth = math.max(
          0.0,
          width - _quickCommandFixedColumnsWidth,
        );
        final scale = flexibleWidth / columnWidths.flexibleTotal;
        return SizedBox(
          width: width,
          height: constraints.maxHeight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _QuickCommandHeader(
                controller: controller,
                sortColumn: sortColumn,
                sortAscending: sortAscending,
                onSort: onSort,
                columnWidths: effectiveWidths,
                onResizeColumn: (column, delta) {
                  onResizeColumn(column, delta / scale);
                },
                onRestoreSavedOrder: onRestoreSavedOrder,
              ),
              const Divider(height: 1),
              Expanded(
                child: sortColumn == null
                    ? ReorderableListView.builder(
                        padding: EdgeInsets.zero,
                        buildDefaultDragHandles: false,
                        itemCount: commands.length + 1,
                        onReorderItem: controller.reorderQuickCommand,
                        itemBuilder: (context, index) => _buildListItem(
                          context,
                          commands,
                          index,
                          effectiveWidths,
                          reorderable: true,
                        ),
                      )
                    : ListView.builder(
                        padding: EdgeInsets.zero,
                        itemCount: commands.length + 1,
                        itemBuilder: (context, index) => _buildListItem(
                          context,
                          commands,
                          index,
                          effectiveWidths,
                          reorderable: false,
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildListItem(
    BuildContext context,
    List<QuickCommand> commands,
    int index,
    _QuickCommandColumnWidths effectiveWidths, {
    required bool reorderable,
  }) {
    if (index == commands.length) {
      return _QuickCommandAddRow(
        key: const ValueKey<String>('quick-command-add-row'),
        controller: controller,
        onAdd: onAdd,
      );
    }

    final command = commands[index];
    Widget row = _QuickCommandRow(
      key: ValueKey<String>('quick-command-row-${command.id}'),
      controller: controller,
      command: command,
      onSend: controller.sendQuickCommand,
      onEdit: onEdit,
      onRemove: controller.removeQuickCommand,
      columnWidths: effectiveWidths,
    );
    if (reorderable) {
      row = ReorderableDragStartListener(index: index, child: row);
    }
    return KeyedSubtree(
      key: ValueKey<String>('quick-command-item-${command.id}'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [row, const Divider(height: 1)],
      ),
    );
  }

  int _compareCommands(
    QuickCommand left,
    QuickCommand right,
    _QuickCommandSortColumn column,
  ) {
    final leftValue = switch (column) {
      _QuickCommandSortColumn.name => left.name,
      _QuickCommandSortColumn.content => left.content,
      _QuickCommandSortColumn.format => left.format.name,
    };
    final rightValue = switch (column) {
      _QuickCommandSortColumn.name => right.name,
      _QuickCommandSortColumn.content => right.content,
      _QuickCommandSortColumn.format => right.format.name,
    };
    return leftValue.toLowerCase().compareTo(rightValue.toLowerCase());
  }
}

const _quickCommandRowHeight = 30.0;
const _quickCommandFormatWidth = 36.0;
const _quickCommandSendWidth = 36.0;
const _quickCommandFixedColumnsWidth =
    _quickCommandFormatWidth + _quickCommandSendWidth;

class _QuickCommandColumnWidths {
  const _QuickCommandColumnWidths({this.name = 110, this.content = 180});

  final double name;
  final double content;

  double get flexibleTotal => name + content;

  double get format => _quickCommandFormatWidth;

  double get send => _quickCommandSendWidth;

  double widthOf(_QuickCommandColumn column) => switch (column) {
    _QuickCommandColumn.name => name,
    _QuickCommandColumn.content => content,
  };

  _QuickCommandColumnWidths fitTo(double targetWidth) {
    final available = math.max(
      0.0,
      targetWidth - _quickCommandFixedColumnsWidth,
    );
    final scale = available / flexibleTotal;
    return _QuickCommandColumnWidths(
      name: name * scale,
      content: content * scale,
    );
  }

  _QuickCommandColumnWidths resize(_QuickCommandColumn column, double delta) {
    final minimum = switch (column) {
      _QuickCommandColumn.name => 60.0,
      _QuickCommandColumn.content => 80.0,
    };
    final width = math.max(minimum, widthOf(column) + delta);
    return _QuickCommandColumnWidths(
      name: column == _QuickCommandColumn.name ? width : name,
      content: column == _QuickCommandColumn.content ? width : content,
    );
  }
}

class _QuickCommandHeader extends StatelessWidget {
  const _QuickCommandHeader({
    required this.controller,
    required this.sortColumn,
    required this.sortAscending,
    required this.onSort,
    required this.columnWidths,
    required this.onResizeColumn,
    required this.onRestoreSavedOrder,
  });

  final SessionController controller;
  final _QuickCommandSortColumn? sortColumn;
  final bool sortAscending;
  final ValueChanged<_QuickCommandSortColumn> onSort;
  final _QuickCommandColumnWidths columnWidths;
  final void Function(_QuickCommandColumn column, double delta) onResizeColumn;
  final VoidCallback onRestoreSavedOrder;

  @override
  Widget build(BuildContext context) {
    final strings = controller.strings;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: (details) => _showHeaderMenu(context, details),
      child: SizedBox(
        height: 28,
        child: Row(
          children: [
            _ResizableQuickCommandHeader(
              column: _QuickCommandColumn.name,
              width: columnWidths.name,
              onResize: onResizeColumn,
              child: _SortableQuickCommandHeader(
                key: const ValueKey<String>('quick-command-sort-name'),
                label: strings.name,
                column: _QuickCommandSortColumn.name,
                activeColumn: sortColumn,
                ascending: sortAscending,
                onSort: onSort,
              ),
            ),
            _ResizableQuickCommandHeader(
              column: _QuickCommandColumn.content,
              width: columnWidths.content,
              onResize: onResizeColumn,
              child: _SortableQuickCommandHeader(
                key: const ValueKey<String>('quick-command-sort-content'),
                label: strings.content,
                column: _QuickCommandSortColumn.content,
                activeColumn: sortColumn,
                ascending: sortAscending,
                onSort: onSort,
              ),
            ),
            SizedBox(
              key: const ValueKey<String>('quick-command-header-format'),
              width: _quickCommandFormatWidth,
              child: _SortableQuickCommandHeader(
                key: const ValueKey<String>('quick-command-sort-format'),
                label: strings.format,
                column: _QuickCommandSortColumn.format,
                activeColumn: sortColumn,
                ascending: sortAscending,
                onSort: onSort,
                centered: true,
                horizontalPadding: 3,
              ),
            ),
            SizedBox(
              key: const ValueKey<String>('quick-command-header-send'),
              width: _quickCommandSendWidth,
              child: _QuickCommandActionHeader(strings.send),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showHeaderMenu(
    BuildContext context,
    TapDownDetails details,
  ) async {
    final action = await showMenu<_QuickCommandHeaderAction>(
      context: context,
      position: _menuPosition(context, details.globalPosition),
      items: [
        PopupMenuItem<_QuickCommandHeaderAction>(
          value: _QuickCommandHeaderAction.restoreSavedOrder,
          child: Row(
            children: [
              const Icon(Icons.restore, size: 18),
              const SizedBox(width: 8),
              Text(controller.strings.restoreSavedOrder),
            ],
          ),
        ),
      ],
    );
    if (action == _QuickCommandHeaderAction.restoreSavedOrder) {
      onRestoreSavedOrder();
    }
  }
}

class _ResizableQuickCommandHeader extends StatelessWidget {
  const _ResizableQuickCommandHeader({
    required this.column,
    required this.width,
    required this.onResize,
    required this.child,
  });

  final _QuickCommandColumn column;
  final double width;
  final void Function(_QuickCommandColumn column, double delta) onResize;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dividerColor = Theme.of(context).dividerColor;
    return SizedBox(
      width: width,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Padding(padding: const EdgeInsets.only(right: 5), child: child),
          Positioned(
            top: 0,
            right: 0,
            bottom: 0,
            width: 9,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: GestureDetector(
                key: ValueKey<String>('quick-command-resize-${column.name}'),
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: (details) {
                  onResize(column, details.delta.dx);
                },
                child: Center(child: Container(width: 1, color: dividerColor)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SortableQuickCommandHeader extends StatelessWidget {
  const _SortableQuickCommandHeader({
    super.key,
    required this.label,
    required this.column,
    required this.activeColumn,
    required this.ascending,
    required this.onSort,
    this.centered = false,
    this.horizontalPadding = 8,
  });

  final String label;
  final _QuickCommandSortColumn column;
  final _QuickCommandSortColumn? activeColumn;
  final bool ascending;
  final ValueChanged<_QuickCommandSortColumn> onSort;
  final bool centered;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    final active = activeColumn == column;
    final color = active
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: () => onSort(column),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        child: Row(
          mainAxisAlignment: centered
              ? MainAxisAlignment.center
              : MainAxisAlignment.start,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (active) ...[
              const SizedBox(width: 3),
              Icon(
                ascending ? Icons.arrow_upward : Icons.arrow_downward,
                size: 12,
                color: color,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _QuickCommandActionHeader extends StatelessWidget {
  const _QuickCommandActionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Center(
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _HistoryList extends StatelessWidget {
  const _HistoryList({required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: controller.sendHistory.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = controller.sendHistory[index];
        return _HistoryRow(
          controller: controller,
          entry: item,
          onSend: controller.sendHistoryEntry,
        );
      },
    );
  }
}

class _QuickCommandRow extends StatelessWidget {
  const _QuickCommandRow({
    super.key,
    required this.controller,
    required this.command,
    required this.onSend,
    required this.onEdit,
    required this.onRemove,
    required this.columnWidths,
  });

  final SessionController controller;
  final QuickCommand command;
  final Future<void> Function(QuickCommand command) onSend;
  final void Function(QuickCommand command) onEdit;
  final void Function(int id) onRemove;
  final _QuickCommandColumnWidths columnWidths;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: (details) => _showRowMenu(context, details),
      child: SizedBox(
        height: _quickCommandRowHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              SizedBox(
                key: ValueKey<String>('quick-command-name-cell-${command.id}'),
                width: columnWidths.name,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: _OverflowTooltipText(
                    key: ValueKey<String>(
                      'quick-command-name-tooltip-${command.id}',
                    ),
                    overlayKey: ValueKey<String>(
                      'quick-command-name-continuation-${command.id}',
                    ),
                    overlayWidth: columnWidths.name,
                    text: command.name,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ),
              SizedBox(
                width: columnWidths.content,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    command.content,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
              SizedBox(
                width: columnWidths.format,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Text(
                    command.format == PayloadFormat.ascii ? 'A' : 'H',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ),
              _QuickCommandActionButton(
                width: columnWidths.send,
                tooltip: controller.strings.send,
                onPressed: () => onSend(command),
                icon: Icons.send,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showRowMenu(
    BuildContext context,
    TapDownDetails details,
  ) async {
    final action = await showMenu<_QuickCommandRowAction>(
      context: context,
      position: _menuPosition(context, details.globalPosition),
      items: [
        PopupMenuItem<_QuickCommandRowAction>(
          value: _QuickCommandRowAction.edit,
          child: Row(
            children: [
              const Icon(Icons.edit_outlined, size: 18),
              const SizedBox(width: 8),
              Text(controller.strings.edit),
            ],
          ),
        ),
        PopupMenuItem<_QuickCommandRowAction>(
          value: _QuickCommandRowAction.delete,
          child: Row(
            children: [
              const Icon(Icons.delete_outline, size: 18),
              const SizedBox(width: 8),
              Text(controller.strings.delete),
            ],
          ),
        ),
      ],
    );
    switch (action) {
      case _QuickCommandRowAction.edit:
        onEdit(command);
      case _QuickCommandRowAction.delete:
        onRemove(command.id);
      case null:
        return;
    }
  }
}

class _QuickCommandActionButton extends StatelessWidget {
  const _QuickCommandActionButton({
    required this.tooltip,
    required this.onPressed,
    required this.icon,
    required this.width,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final IconData icon;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 24,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          visualDensity: VisualDensity.compact,
          iconSize: 18,
          icon: Icon(icon),
        ),
      ),
    );
  }
}

class _OverflowTooltipText extends StatefulWidget {
  const _OverflowTooltipText({
    super.key,
    required this.overlayKey,
    required this.overlayWidth,
    required this.text,
    this.style,
  });

  final Key overlayKey;
  final double overlayWidth;
  final String text;
  final TextStyle? style;

  @override
  State<_OverflowTooltipText> createState() => _OverflowTooltipTextState();
}

class _OverflowTooltipTextState extends State<_OverflowTooltipText> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          textDirection: Directionality.of(context),
        )..layout(maxWidth: constraints.maxWidth);
        final lines = painter.computeLineMetrics();
        final truncated = lines.length > 1;
        final firstLineEnd = truncated
            ? painter.getLineBoundary(const TextPosition(offset: 0)).end
            : widget.text.length;
        final continuation = truncated
            ? widget.text.substring(firstLineEnd).trimLeft()
            : '';
        final label = Text(
          widget.text,
          maxLines: 1,
          softWrap: true,
          overflow: _hovered ? TextOverflow.clip : TextOverflow.ellipsis,
          style: widget.style,
        );
        return MouseRegion(
          onEnter: truncated && continuation.isNotEmpty
              ? (_) => _showContinuation(context, continuation)
              : null,
          onExit: (_) => _hideContinuation(),
          child: CompositedTransformTarget(link: _layerLink, child: label),
        );
      },
    );
  }

  void _showContinuation(BuildContext context, String continuation) {
    if (_overlayEntry != null) {
      return;
    }
    setState(() => _hovered = true);
    final colors = Theme.of(context).colorScheme;
    final dividerColor = Theme.of(context).dividerColor;
    _overlayEntry = OverlayEntry(
      builder: (context) => CompositedTransformFollower(
        link: _layerLink,
        showWhenUnlinked: false,
        targetAnchor: Alignment.bottomLeft,
        followerAnchor: Alignment.topLeft,
        offset: const Offset(-6, 0),
        child: Align(
          alignment: Alignment.topLeft,
          widthFactor: 1,
          heightFactor: 1,
          child: IgnorePointer(
            child: Material(
              key: widget.overlayKey,
              color: colors.surfaceContainerHighest,
              elevation: 6,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(4),
              ),
              child: Container(
                width: widget.overlayWidth,
                padding: const EdgeInsets.fromLTRB(6, 1, 6, 4),
                decoration: BoxDecoration(
                  border: Border.all(color: dividerColor),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(4),
                    bottomRight: Radius.circular(4),
                  ),
                ),
                child: Text(continuation, softWrap: true, style: widget.style),
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _hideContinuation() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (mounted && _hovered) {
      setState(() => _hovered = false);
    }
  }

  @override
  void didUpdateWidget(covariant _OverflowTooltipText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.style != widget.style) {
      _hideContinuation();
    }
  }

  @override
  void dispose() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    super.dispose();
  }
}

class _QuickCommandAddRow extends StatelessWidget {
  const _QuickCommandAddRow({
    super.key,
    required this.controller,
    required this.onAdd,
  });

  final SessionController controller;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _quickCommandRowHeight,
      child: InkWell(
        onTap: onAdd,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Row(
            children: [
              const Icon(Icons.add, size: 16),
              const SizedBox(width: 6),
              Text(
                controller.strings.addCommand,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

RelativeRect _menuPosition(BuildContext context, Offset globalPosition) {
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  return RelativeRect.fromLTRB(
    globalPosition.dx,
    globalPosition.dy,
    overlay.size.width - globalPosition.dx,
    overlay.size.height - globalPosition.dy,
  );
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.controller,
    required this.entry,
    required this.onSend,
  });

  final SessionController controller;
  final SendHistoryEntry entry;
  final Future<void> Function(SendHistoryEntry entry) onSend;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  controller.strings.payloadFormat(entry.format),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  entry.text,
                  softWrap: true,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: controller.strings.send,
            onPressed: () => onSend(entry),
            icon: const Icon(Icons.send),
          ),
        ],
      ),
    );
  }
}
