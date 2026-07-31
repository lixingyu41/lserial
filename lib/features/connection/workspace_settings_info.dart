import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../app/localization.dart';
import '../../application/workspace_controller.dart';
import '../../platform/external_link.dart';

const _settingsRowHeight = 40.0;
const _settingsTextPadding = EdgeInsets.symmetric(horizontal: 16);

class WorkspaceSettingsInfo extends StatelessWidget {
  const WorkspaceSettingsInfo({super.key, required this.controller});

  final WorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _LanguageSelector(controller: controller),
        const Divider(height: 1),
        const _AppVersionText(),
        const Divider(height: 1),
        _DownloadClientButton(controller: controller),
        const Divider(height: 1),
        const _CopyrightLink(),
      ],
    );
  }
}

class _LanguageSelector extends StatelessWidget {
  const _LanguageSelector({required this.controller});

  final WorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _settingsRowHeight,
      child: Row(
        children: [
          for (var i = 0; i < AppLanguage.values.length; i++) ...[
            if (i > 0) const _SettingsVerticalDivider(),
            Expanded(
              child: _LanguageButton(
                language: AppLanguage.values[i],
                selected: controller.language == AppLanguage.values[i],
                onPressed: () => controller.setLanguage(AppLanguage.values[i]),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LanguageButton extends StatelessWidget {
  const _LanguageButton({
    required this.language,
    required this.selected,
    required this.onPressed,
  });

  final AppLanguage language;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      style: _settingsButtonStyle(context, selected: selected),
      onPressed: onPressed,
      child: _SettingsButtonText(language.nativeLabel, selected: selected),
    );
  }
}

class _SettingsButtonText extends StatelessWidget {
  const _SettingsButtonText(this.label, {this.selected = false});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.onPrimaryContainer : scheme.onSurface;
    return SizedBox.expand(
      child: Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: _settingsTextPadding,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: color),
          ),
        ),
      ),
    );
  }
}

class _SettingsVerticalDivider extends StatelessWidget {
  const _SettingsVerticalDivider();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 1,
      height: _settingsRowHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
    );
  }
}

ButtonStyle _settingsButtonStyle(
  BuildContext context, {
  bool selected = false,
}) {
  final scheme = Theme.of(context).colorScheme;
  return TextButton.styleFrom(
    minimumSize: Size.zero,
    padding: EdgeInsets.zero,
    shape: const RoundedRectangleBorder(),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    backgroundColor: selected ? scheme.primaryContainer : Colors.transparent,
    foregroundColor: selected ? scheme.onPrimaryContainer : scheme.onSurface,
  );
}

class _SettingsTextRow extends StatelessWidget {
  const _SettingsTextRow(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _settingsRowHeight,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: _settingsTextPadding,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _DownloadTarget {
  const _DownloadTarget({
    required this.label,
    required this.icon,
    required this.url,
  });

  final String label;
  final IconData icon;
  final Uri url;
}

class _DownloadClientButton extends StatelessWidget {
  const _DownloadClientButton({required this.controller});

  final WorkspaceController controller;

  static final List<_DownloadTarget> _targets = [
    _DownloadTarget(
      label: 'macOS',
      icon: Icons.laptop_mac,
      url: Uri.parse(
        'https://github.com/lixingyu41/lserial/releases/download/v1.0.11/LSerial-v1.0.11-macOS.dmg',
      ),
    ),
    _DownloadTarget(
      label: 'Linux',
      icon: Icons.terminal,
      url: Uri.parse(
        'https://github.com/lixingyu41/lserial/releases/download/v1.0.11/LSerial-v1.0.11-Linux-x64.tar.gz',
      ),
    ),
    _DownloadTarget(
      label: 'Windows',
      icon: Icons.desktop_windows,
      url: Uri.parse(
        'https://github.com/lixingyu41/lserial/releases/download/v1.0.11/LSerial-v1.0.11-Windows-x64-Setup.exe',
      ),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _settingsRowHeight,
      child: Builder(
        builder: (context) {
          return TextButton(
            style: _settingsButtonStyle(context),
            onPressed: () => _showDownloadMenu(context),
            child: _SettingsButtonText(controller.strings.downloadClient),
          );
        },
      ),
    );
  }

  Future<void> _showDownloadMenu(BuildContext context) async {
    final buttonBox = context.findRenderObject() as RenderBox?;
    final overlayBox =
        Navigator.of(context).overlay?.context.findRenderObject() as RenderBox?;
    if (buttonBox == null || overlayBox == null) {
      return;
    }
    final topLeft = buttonBox.localToGlobal(Offset.zero, ancestor: overlayBox);
    final target = await showMenu<_DownloadTarget>(
      context: context,
      position: RelativeRect.fromRect(
        topLeft & buttonBox.size,
        Offset.zero & overlayBox.size,
      ),
      items: [
        for (final target in _targets)
          PopupMenuItem<_DownloadTarget>(
            value: target,
            child: Row(
              children: [
                Icon(target.icon, size: 18),
                const SizedBox(width: 8),
                Text(target.label),
              ],
            ),
          ),
      ],
    );
    if (target != null && context.mounted) {
      await _openFooterLink(context, target.url);
    }
  }
}

class _CopyrightLink extends StatelessWidget {
  const _CopyrightLink();

  static final Uri _url = Uri.parse('https://lixingyu.top');

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _settingsRowHeight,
      child: TextButton(
        style: _settingsButtonStyle(context),
        onPressed: () => _openFooterLink(context, _url),
        child: const _SettingsButtonText('Copyright LIXINGYU'),
      ),
    );
  }
}

class _AppVersionText extends StatelessWidget {
  const _AppVersionText();

  static final Future<String?> _label = _loadVersionLabel();

  static Future<String?> _loadVersionLabel() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final version = info.version.trim();
      final buildNumber = info.buildNumber.trim();
      if (version.isEmpty) {
        return null;
      }
      return buildNumber.isEmpty ? 'v$version' : 'v$version+$buildNumber';
    } on Object {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _label,
      builder: (context, snapshot) {
        final label = snapshot.data;
        if (label == null || label.isEmpty) {
          return const SizedBox(height: _settingsRowHeight);
        }
        return _SettingsTextRow(label);
      },
    );
  }
}

Future<void> _openFooterLink(BuildContext context, Uri url) async {
  try {
    await openExternalLink(url);
  } on Object catch (error) {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(error.toString()),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }
}
