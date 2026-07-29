import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../application/session_controller.dart';
import '../../core/encoding/data_format.dart';
import '../../domain/quick_command.dart';
import '../../domain/send_history_entry.dart';
import '../../storage/quick_command_text_codec.dart';
import '../../storage/text_file_transfer.dart';

enum _QuickCommandFileAction {
  importReplace,
  importAppend,
  export,
}

class QuickCommandsPanel extends StatefulWidget {
  const QuickCommandsPanel({super.key, required this.controller});

  final SessionController controller;

  @override
  State<QuickCommandsPanel> createState() => _QuickCommandsPanelState();
}

class _QuickCommandsPanelState extends State<QuickCommandsPanel> {
  double _quickRatio = 0.62;

  SessionController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final hasHistory = controller.sendHistory.isNotEmpty;
        final strings = controller.strings;
        return Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(strings.quickCommands,
                      style: Theme.of(context).textTheme.titleSmall),
                  const Spacer(),
                  PopupMenuButton<_QuickCommandFileAction>(
                    tooltip: strings.quickCommandImportExport,
                    icon: const Icon(Icons.import_export, size: 20),
                    onSelected: _handleFileAction,
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
                ],
              ),
              const SizedBox(height: 8),
              if (!hasHistory)
                Expanded(
                  child: _QuickCommandList(
                    controller: controller,
                    onEdit: (command) => _openEditor(context, command),
                    onAdd: () => _openEditor(context, null),
                  ),
                )
              else
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final quickHeight = _quickHeight(constraints.maxHeight);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            height: quickHeight,
                            child: _QuickCommandList(
                              controller: controller,
                              onEdit: (command) =>
                                  _openEditor(context, command),
                              onAdd: () => _openEditor(context, null),
                            ),
                          ),
                          _HistorySplitDivider(
                            onDrag: (delta) => _resizeHistorySplit(
                              delta,
                              constraints.maxHeight,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 8, bottom: 8),
                            child: Text(
                              strings.sendHistory,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                          Expanded(child: _HistoryList(controller: controller)),
                        ],
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
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
      _quickRatio =
          (_quickRatio + delta / availableHeight).clamp(0.25, 0.82).toDouble();
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
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
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
                      decoration:
                          InputDecoration(labelText: controller.strings.name),
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
                      decoration:
                          InputDecoration(labelText: controller.strings.format),
                      items: PayloadFormat.values
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child:
                                  Text(controller.strings.payloadFormat(value)),
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
          child: Center(
            child: Container(
              height: 1,
              color: color,
            ),
          ),
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
  });

  final SessionController controller;
  final void Function(QuickCommand command) onEdit;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        if (controller.quickCommands.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(child: Text(controller.strings.noQuickCommands)),
          )
        else
          for (final command in controller.quickCommands) ...[
            _QuickCommandRow(
              controller: controller,
              command: command,
              onSend: controller.sendQuickCommand,
              onEdit: onEdit,
              onRemove: controller.removeQuickCommand,
            ),
            const Divider(height: 1),
          ],
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: OutlinedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: Text(controller.strings.addCommand),
          ),
        ),
      ],
    );
  }
}

class _HistoryList extends StatelessWidget {
  const _HistoryList({required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
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
    required this.controller,
    required this.command,
    required this.onSend,
    required this.onEdit,
    required this.onRemove,
  });

  final SessionController controller;
  final QuickCommand command;
  final Future<void> Function(QuickCommand command) onSend;
  final void Function(QuickCommand command) onEdit;
  final void Function(int id) onRemove;

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
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        command.name,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      controller.strings.payloadFormat(command.format),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  command.content,
                  softWrap: true,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: controller.strings.send,
            onPressed: () => onSend(command),
            icon: const Icon(Icons.send),
          ),
          IconButton(
            tooltip: controller.strings.edit,
            onPressed: () => onEdit(command),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: controller.strings.delete,
            onPressed: () => onRemove(command.id),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }
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
                Text(controller.strings.payloadFormat(entry.format),
                    style: Theme.of(context).textTheme.labelSmall),
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
