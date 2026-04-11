import 'package:flutter/material.dart';

import '../../application/session_controller.dart';
import '../../core/encoding/data_format.dart';
import '../../storage/log_buffer.dart';
import 'frame_list_view.dart';

class ConsolePanel extends StatefulWidget {
  const ConsolePanel({super.key, required this.controller});

  final SessionController controller;

  @override
  State<ConsolePanel> createState() => _ConsolePanelState();
}

class _ConsolePanelState extends State<ConsolePanel> {
  final TextEditingController search = TextEditingController();

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ConsoleToolbar(controller: widget.controller, search: search),
        const Divider(height: 1),
        Expanded(
          child: ValueListenableBuilder<LogSnapshot>(
            valueListenable: widget.controller.displaySnapshot,
            builder: (context, snapshot, _) {
              return FrameListView(
                snapshot: snapshot,
                controller: widget.controller,
                filter: search.text,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ConsoleToolbar extends StatelessWidget {
  const _ConsoleToolbar({
    required this.controller,
    required this.search,
  });

  final SessionController controller;
  final TextEditingController search;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 150,
            child: DropdownButtonFormField<ConsoleViewMode>(
              initialValue: controller.viewMode,
              decoration: const InputDecoration(labelText: '视图'),
              items: ConsoleViewMode.values
                  .map((mode) =>
                      DropdownMenuItem(value: mode, child: Text(mode.label)))
                  .toList(),
              onChanged: (mode) {
                if (mode != null) {
                  controller.setViewMode(mode);
                }
              },
            ),
          ),
          FilterChip(
            label: const Text('时间戳'),
            selected: controller.showTimestamp,
            onSelected: controller.setTimestampVisible,
          ),
          FilterChip(
            label: const Text('收发标记'),
            selected: controller.showDirection,
            onSelected: controller.setDirectionVisible,
          ),
          FilterChip(
            label: const Text('自动滚动'),
            selected: controller.autoScroll,
            onSelected: controller.setAutoScroll,
          ),
          FilterChip(
            label: const Text('暂停显示'),
            selected: controller.pauseDisplay,
            onSelected: controller.setPauseDisplay,
          ),
          SizedBox(
            width: 220,
            child: TextField(
              controller: search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: '搜索过滤',
              ),
              onChanged: (_) {
                controller.displaySnapshot.value =
                    controller.logBuffer.snapshot(
                  paused: controller.pauseDisplay,
                );
              },
            ),
          ),
          OutlinedButton.icon(
            onPressed: controller.clearLog,
            icon: const Icon(Icons.clear_all),
            label: const Text('清空'),
          ),
          OutlinedButton.icon(
            onPressed: controller.exportLog,
            icon: const Icon(Icons.save_alt),
            label: const Text('保存日志'),
          ),
        ],
      ),
    );
  }
}
