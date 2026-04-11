import 'package:flutter/material.dart';

import '../../application/session_controller.dart';
import '../../core/encoding/data_format.dart';

class SendPanel extends StatefulWidget {
  const SendPanel({super.key, required this.controller});

  final SessionController controller;

  @override
  State<SendPanel> createState() => _SendPanelState();
}

class _SendPanelState extends State<SendPanel> {
  final TextEditingController input = TextEditingController();
  final TextEditingController interval = TextEditingController(text: '1000');

  @override
  void dispose() {
    input.dispose();
    interval.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: ListView(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final inputWidth = constraints.maxWidth < 720
                  ? constraints.maxWidth
                  : constraints.maxWidth - 420;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: inputWidth.clamp(260, constraints.maxWidth),
                    child: TextField(
                      controller: input,
                      minLines: 1,
                      maxLines: 3,
                      decoration: const InputDecoration(labelText: '发送数据'),
                      onSubmitted: (_) => controller.sendText(input.text),
                    ),
                  ),
                  SizedBox(
                    width: 160,
                    child: DropdownButtonFormField<PayloadFormat>(
                      initialValue: controller.sendFormat,
                      decoration: const InputDecoration(labelText: '输入'),
                      items: PayloadFormat.values
                          .map(
                            (format) => DropdownMenuItem(
                              value: format,
                              child: Text(format.label),
                            ),
                          )
                          .toList(),
                      onChanged: (format) {
                        if (format != null) {
                          controller.setSendFormat(format);
                        }
                      },
                    ),
                  ),
                  SizedBox(
                    width: 160,
                    child: DropdownButtonFormField<LineEnding>(
                      initialValue: controller.lineEnding,
                      decoration: const InputDecoration(labelText: '结尾'),
                      items: LineEnding.values
                          .map(
                            (ending) => DropdownMenuItem(
                              value: ending,
                              child: Text(ending.label),
                            ),
                          )
                          .toList(),
                      onChanged: (ending) {
                        if (ending != null) {
                          controller.setLineEnding(ending);
                        }
                      },
                    ),
                  ),
                  FilledButton(
                    onPressed: () => controller.sendText(input.text),
                    child: const Text('发送'),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 120,
                child: TextField(
                  controller: interval,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '定时 ms'),
                ),
              ),
              OutlinedButton.icon(
                onPressed: controller.isAutoSending
                    ? controller.stopAutoSend
                    : _startAutoSend,
                icon: Icon(controller.isAutoSending ? Icons.stop : Icons.timer),
                label: Text(controller.isAutoSending ? '停止定时' : '定时发送'),
              ),
              const SizedBox(width: 8),
              for (final command in controller.commandPresets)
                ActionChip(
                  label: Text(command),
                  onPressed: () {
                    input.text = command;
                    controller.sendText(command);
                  },
                ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final item in controller.sendHistory)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      label: Text(item, overflow: TextOverflow.ellipsis),
                      onPressed: () => input.text = item,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _startAutoSend() {
    final ms = int.tryParse(interval.text) ?? 1000;
    widget.controller.startAutoSend(input.text, Duration(milliseconds: ms));
  }
}
