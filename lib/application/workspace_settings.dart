import '../app/localization.dart';
import '../core/encoding/data_format.dart';

enum WorkspaceToolbarAction {
  clearLog,
  terminalMode,
  sendFormat,
  lineEnding,
  sendShortcut,
  connectionPanel,
  quickCommandsPanel,
  sendPanel,
  autoScroll,
}

class WorkspaceSettings {
  const WorkspaceSettings({
    this.viewMode = ConsoleViewMode.ascii,
    this.showTimestamp = true,
    this.showDirection = true,
    this.showSource = true,
    this.showContent = true,
    this.showLineEndingSymbols = false,
    this.autoScroll = true,
    this.showConnectionPanel = true,
    this.showSendPanel = true,
    this.sendPanelVisibleBeforeTerminal = true,
    this.showQuickCommandsPanel = false,
    this.terminalMode = false,
    this.statsPanelExpanded = false,
    this.settingsPanelExpanded = false,
    this.mcpEnabled = true,
    this.logFontSize = 12,
    this.language = AppLanguage.zh,
    this.hiddenSources = const <String>{},
    this.sourceViewModes = const <String, ConsoleViewMode>{},
    this.hiddenToolbarActions = const <WorkspaceToolbarAction>{
      WorkspaceToolbarAction.autoScroll,
    },
  });

  final ConsoleViewMode viewMode;
  final bool showTimestamp;
  final bool showDirection;
  final bool showSource;
  final bool showContent;
  final bool showLineEndingSymbols;
  final bool autoScroll;
  final bool showConnectionPanel;
  final bool showSendPanel;
  final bool sendPanelVisibleBeforeTerminal;
  final bool showQuickCommandsPanel;
  final bool terminalMode;
  final bool statsPanelExpanded;
  final bool settingsPanelExpanded;
  final bool mcpEnabled;
  final double logFontSize;
  final AppLanguage language;
  final Set<String> hiddenSources;
  final Map<String, ConsoleViewMode> sourceViewModes;
  final Set<WorkspaceToolbarAction> hiddenToolbarActions;

  factory WorkspaceSettings.fromJson(Map<String, Object?> json) {
    const defaults = WorkspaceSettings();
    return WorkspaceSettings(
      viewMode: _enumByName(
        ConsoleViewMode.values,
        json['viewMode'],
        defaults.viewMode,
      ),
      showTimestamp: _boolValue(json['showTimestamp'], defaults.showTimestamp),
      showDirection: _boolValue(json['showDirection'], defaults.showDirection),
      showSource: _boolValue(json['showSource'], defaults.showSource),
      showContent: _boolValue(json['showContent'], defaults.showContent),
      showLineEndingSymbols: _boolValue(
        json['showLineEndingSymbols'],
        defaults.showLineEndingSymbols,
      ),
      autoScroll: _boolValue(json['autoScroll'], defaults.autoScroll),
      showConnectionPanel: _boolValue(
        json['showConnectionPanel'],
        defaults.showConnectionPanel,
      ),
      showSendPanel: _boolValue(json['showSendPanel'], defaults.showSendPanel),
      sendPanelVisibleBeforeTerminal: _boolValue(
        json['sendPanelVisibleBeforeTerminal'],
        defaults.sendPanelVisibleBeforeTerminal,
      ),
      showQuickCommandsPanel: _boolValue(
        json['showQuickCommandsPanel'],
        defaults.showQuickCommandsPanel,
      ),
      terminalMode: _boolValue(json['terminalMode'], defaults.terminalMode),
      statsPanelExpanded: _boolValue(
        json['statsPanelExpanded'],
        defaults.statsPanelExpanded,
      ),
      settingsPanelExpanded: _boolValue(
        json['settingsPanelExpanded'],
        defaults.settingsPanelExpanded,
      ),
      mcpEnabled: _boolValue(json['mcpEnabled'], defaults.mcpEnabled),
      logFontSize: _fontSizeValue(json['logFontSize'], defaults.logFontSize),
      language: _enumByName(
        AppLanguage.values,
        json['language'],
        defaults.language,
      ),
      hiddenSources: _stringSetValue(json['hiddenSources']),
      sourceViewModes: _sourceViewModeMapValue(json['sourceViewModes']),
      hiddenToolbarActions: _enumSetValue(
        WorkspaceToolbarAction.values,
        json['hiddenToolbarActions'],
        defaults.hiddenToolbarActions,
      ),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'viewMode': viewMode.name,
    'showTimestamp': showTimestamp,
    'showDirection': showDirection,
    'showSource': showSource,
    'showContent': showContent,
    'showLineEndingSymbols': showLineEndingSymbols,
    'autoScroll': autoScroll,
    'showConnectionPanel': showConnectionPanel,
    'showSendPanel': showSendPanel,
    'sendPanelVisibleBeforeTerminal': sendPanelVisibleBeforeTerminal,
    'showQuickCommandsPanel': showQuickCommandsPanel,
    'terminalMode': terminalMode,
    'statsPanelExpanded': statsPanelExpanded,
    'settingsPanelExpanded': settingsPanelExpanded,
    'mcpEnabled': mcpEnabled,
    'logFontSize': logFontSize,
    'language': language.name,
    'hiddenSources': hiddenSources.toList()..sort(),
    'sourceViewModes': <String, String>{
      for (final source in (sourceViewModes.keys.toList()..sort()))
        source: sourceViewModes[source]!.name,
    },
    'hiddenToolbarActions':
        hiddenToolbarActions.map((action) => action.name).toList()..sort(),
  };
}

bool _boolValue(Object? value, bool fallback) {
  return value is bool ? value : fallback;
}

double _fontSizeValue(Object? value, double fallback) {
  if (value is num) {
    return value.clamp(10, 22).toDouble();
  }
  return fallback;
}

T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final value in values) {
    if (value.name == name) {
      return value;
    }
  }
  return fallback;
}

Set<String> _stringSetValue(Object? value) {
  if (value is! List) {
    return const <String>{};
  }
  return value
      .whereType<String>()
      .map((source) => source.trim())
      .where((source) => source.isNotEmpty)
      .toSet();
}

Map<String, ConsoleViewMode> _sourceViewModeMapValue(Object? value) {
  if (value is! Map) {
    return const <String, ConsoleViewMode>{};
  }
  final result = <String, ConsoleViewMode>{};
  for (final entry in value.entries) {
    if (entry.key is! String || entry.value is! String) {
      continue;
    }
    final source = (entry.key as String).trim();
    if (source.isEmpty || source == 'SYS') {
      continue;
    }
    for (final mode in ConsoleViewMode.values) {
      if (mode.name == entry.value) {
        result[source] = mode;
        break;
      }
    }
  }
  return result;
}

Set<T> _enumSetValue<T extends Enum>(
  List<T> values,
  Object? names,
  Set<T> fallback,
) {
  if (names is! List) {
    return Set<T>.of(fallback);
  }
  final byName = <String, T>{for (final value in values) value.name: value};
  return names
      .whereType<String>()
      .map((name) => byName[name])
      .whereType<T>()
      .toSet();
}
