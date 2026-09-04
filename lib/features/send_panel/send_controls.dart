import 'package:flutter/material.dart';

import '../../application/session_controller.dart';
import '../../application/workspace_controller.dart';
import '../../core/encoding/data_format.dart';
import '../../widgets/wheel_stepper.dart';

InputDecoration _compactDecoration(String label) {
  return InputDecoration(
    labelText: label,
    floatingLabelBehavior: FloatingLabelBehavior.always,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    constraints: const BoxConstraints.tightFor(height: 40),
  );
}

InputDecoration _defaultDecoration(String label) {
  return InputDecoration(labelText: label);
}

ButtonStyle _framelessButtonStyle(BuildContext context) {
  return OutlinedButton.styleFrom(
    minimumSize: const Size(40, 40),
    padding: const EdgeInsets.symmetric(horizontal: 8),
    shape: const RoundedRectangleBorder(),
    side: BorderSide.none,
    backgroundColor: Colors.transparent,
    foregroundColor: Theme.of(context).colorScheme.onSurface,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );
}

class SendTargetField extends StatelessWidget {
  const SendTargetField({
    super.key,
    required this.controller,
    required this.width,
    this.compact = false,
    this.frameless = false,
    this.onChanged,
  });

  final WorkspaceController controller;
  final double width;
  final bool compact;
  final bool frameless;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    final connectedIndexes = controller.connectedSessionIndexes;
    final selectedValue = connectedIndexes.contains(controller.sendTargetIndex)
        ? controller.sendTargetIndex
        : null;
    if (frameless) {
      return _FramelessSendTargetMenu(
        controller: controller,
        width: width,
        connectedIndexes: connectedIndexes,
        selectedValue: selectedValue,
        onChanged: onChanged,
      );
    }
    return SizedBox(
      width: width,
      child: WheelStepper(
        enabled: connectedIndexes.length > 1,
        onStep: (step) {
          controller.stepSendTarget(step);
          onChanged?.call(controller.sendTargetIndex);
        },
        child: DropdownButtonFormField<int>(
          key: ValueKey(
            'send-target-${controller.sendTargetIndex}-${connectedIndexes.join("|")}',
          ),
          initialValue: selectedValue,
          isExpanded: true,
          decoration: compact
              ? _compactDecoration(controller.strings.sendTo)
              : _defaultDecoration(controller.strings.sendTo),
          hint: Text(controller.strings.noConnectedTarget),
          items: [
            for (final i in connectedIndexes)
              DropdownMenuItem<int>(
                value: i,
                child: Text(
                  controller.sessionLabel(i),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: connectedIndexes.isEmpty
              ? null
              : (index) {
                  if (index != null) {
                    controller.setSendTargetIndex(index);
                    onChanged?.call(index);
                  }
                },
        ),
      ),
    );
  }
}

class _FramelessSendTargetMenu extends StatelessWidget {
  const _FramelessSendTargetMenu({
    required this.controller,
    required this.width,
    required this.connectedIndexes,
    required this.selectedValue,
    required this.onChanged,
  });

  final WorkspaceController controller;
  final double width;
  final List<int> connectedIndexes;
  final int? selectedValue;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selectedLabel = selectedValue == null
        ? controller.strings.noConnectedTarget
        : controller.sessionLabel(selectedValue!);
    return SizedBox(
      width: width,
      height: 40,
      child: WheelStepper(
        enabled: connectedIndexes.length > 1,
        onStep: (step) {
          controller.stepSendTarget(step);
          onChanged?.call(controller.sendTargetIndex);
        },
        child: MenuAnchor(
          crossAxisUnconstrained: false,
          style: MenuStyle(
            padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
              EdgeInsets.symmetric(vertical: 4),
            ),
            shape: WidgetStatePropertyAll<OutlinedBorder>(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
          ),
          menuChildren: [
            for (final index in connectedIndexes)
              MenuItemButton(
                onPressed: () {
                  controller.setSendTargetIndex(index);
                  onChanged?.call(index);
                },
                leadingIcon: index == selectedValue
                    ? Icon(Icons.check, size: 18, color: scheme.primary)
                    : const SizedBox(width: 18),
                child: Text(
                  controller.sessionLabel(index),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          builder: (context, menuController, _) {
            return InkWell(
              onTap: connectedIndexes.isEmpty
                  ? null
                  : () {
                      if (menuController.isOpen) {
                        menuController.close();
                      } else {
                        menuController.open();
                      }
                    },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    const Icon(Icons.arrow_forward, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        selectedLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down, size: 20),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class SendFormatField extends StatelessWidget {
  const SendFormatField({
    super.key,
    required this.controller,
    required this.width,
    this.compact = false,
  });

  final SessionController controller;
  final double width;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: DropdownButtonFormField<PayloadFormat>(
        key: ValueKey(
          'send-format-${identityHashCode(controller)}-${controller.sendFormat}',
        ),
        initialValue: controller.sendFormat,
        isExpanded: true,
        decoration: compact
            ? _compactDecoration(controller.strings.inputFormat)
            : _defaultDecoration(controller.strings.inputFormat),
        items: PayloadFormat.values
            .map(
              (format) => DropdownMenuItem(
                value: format,
                child: Text(controller.strings.payloadFormat(format)),
              ),
            )
            .toList(),
        onChanged: (format) {
          if (format != null) {
            controller.setSendFormat(format);
          }
        },
      ),
    );
  }
}

class SendFormatToggleButton extends StatelessWidget {
  const SendFormatToggleButton({
    super.key,
    required this.controller,
    required this.width,
    this.onChanged,
  });

  final SessionController controller;
  final double width;
  final ValueChanged<PayloadFormat>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: controller.strings.inputFormat,
      child: SizedBox(
        width: width,
        height: 40,
        child: OutlinedButton.icon(
          style: _framelessButtonStyle(context),
          onPressed: () {
            final next = controller.sendFormat == PayloadFormat.ascii
                ? PayloadFormat.hex
                : PayloadFormat.ascii;
            controller.setSendFormat(next);
            onChanged?.call(next);
          },
          icon: const Icon(Icons.input),
          label: Text(controller.strings.payloadFormat(controller.sendFormat)),
        ),
      ),
    );
  }
}

class LineEndingToggleButton extends StatelessWidget {
  const LineEndingToggleButton({
    super.key,
    required this.controller,
    required this.width,
    this.onChanged,
  });

  final SessionController controller;
  final double width;
  final ValueChanged<LineEnding>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: controller.strings.lineEnding,
      child: SizedBox(
        width: width,
        height: 40,
        child: OutlinedButton(
          style: _framelessButtonStyle(context),
          onPressed: () {
            controller.toggleLineEnding();
            onChanged?.call(controller.lineEnding);
          },
          child: Text(
            controller.strings.lineEndingLabel(controller.lineEnding),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

class LineEndingField extends StatelessWidget {
  const LineEndingField({
    super.key,
    required this.controller,
    required this.width,
    this.compact = false,
  });

  final SessionController controller;
  final double width;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: DropdownButtonFormField<LineEnding>(
        key: ValueKey(
          'line-ending-${identityHashCode(controller)}-${controller.lineEnding}',
        ),
        initialValue: controller.lineEnding,
        isExpanded: true,
        decoration: compact
            ? _compactDecoration(controller.strings.lineEnding)
            : _defaultDecoration(controller.strings.lineEnding),
        items: LineEnding.values
            .map(
              (ending) => DropdownMenuItem(
                value: ending,
                child: Text(controller.strings.lineEndingLabel(ending)),
              ),
            )
            .toList(),
        onChanged: (ending) {
          if (ending != null) {
            controller.setLineEnding(ending);
          }
        },
      ),
    );
  }
}

class ShortcutModeField extends StatelessWidget {
  const ShortcutModeField({
    super.key,
    required this.controller,
    required this.width,
    this.compact = false,
  });

  final SessionController controller;
  final double width;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: DropdownButtonFormField<SendShortcutMode>(
        key: ValueKey(
          'shortcut-${identityHashCode(controller)}-${controller.sendShortcutMode}',
        ),
        initialValue: controller.sendShortcutMode,
        isExpanded: true,
        decoration: compact
            ? _compactDecoration(controller.strings.sendShortcut)
            : _defaultDecoration(controller.strings.sendShortcut),
        items: SendShortcutMode.values
            .map(
              (mode) => DropdownMenuItem(
                value: mode,
                child: Text(controller.strings.shortcutMode(mode)),
              ),
            )
            .toList(),
        onChanged: (mode) {
          if (mode != null) {
            controller.setSendShortcutMode(mode);
          }
        },
      ),
    );
  }
}

class ShortcutModeToggleButton extends StatelessWidget {
  const ShortcutModeToggleButton({
    super.key,
    required this.controller,
    required this.width,
    this.onChanged,
  });

  final SessionController controller;
  final double width;
  final ValueChanged<SendShortcutMode>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: controller.strings.shortcutMode(controller.sendShortcutMode),
      child: SizedBox(
        width: width,
        height: 40,
        child: OutlinedButton(
          style: _framelessButtonStyle(context),
          onPressed: () {
            controller.toggleSendShortcutMode();
            onChanged?.call(controller.sendShortcutMode);
          },
          child: Text(
            controller.strings.shortcutModeShort(controller.sendShortcutMode),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}
