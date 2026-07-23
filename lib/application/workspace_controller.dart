import 'dart:async';

import 'package:flutter/foundation.dart';

import '../app/localization.dart';
import '../core/encoding/data_format.dart';
import '../domain/data_frame.dart';
import '../domain/transport.dart';
import '../protocol/frame_formatter.dart';
import '../storage/log_buffer.dart';
import '../storage/log_exporter.dart';
import '../storage/workspace_preferences.dart';
import '../transports/adapters/serial_port_options.dart';
import 'session_controller.dart';
import 'workspace_settings.dart';

class WorkspaceController extends ChangeNotifier {
  WorkspaceController({
    this.maxCombinedFrames = 30000,
    Future<WorkspaceSettings?> Function()? loadWorkspaceSettings,
    Future<void> Function(WorkspaceSettings settings)? saveWorkspaceSettings,
  })  : sessions = <SessionController>[],
        _loadWorkspaceSettings = loadWorkspaceSettings ?? readWorkspaceSettings,
        _saveWorkspaceSettings =
            saveWorkspaceSettings ?? writeWorkspaceSettings {
    _addSession(initialize: false);
    _publishSnapshot(force: true);
  }

  final int maxCombinedFrames;
  final List<SessionController> sessions;
  final Future<WorkspaceSettings?> Function() _loadWorkspaceSettings;
  final Future<void> Function(WorkspaceSettings settings)
      _saveWorkspaceSettings;
  final FrameFormatter formatter = const FrameFormatter();
  final ValueNotifier<LogSnapshot> displaySnapshot =
      ValueNotifier<LogSnapshot>(LogSnapshot.empty());

  int activeSessionIndex = 0;
  int sendTargetIndex = 0;
  ConsoleViewMode viewMode = ConsoleViewMode.ascii;
  bool showTimestamp = true;
  bool showDirection = true;
  bool showSource = true;
  bool showContent = true;
  bool showLineEndingSymbols = false;
  bool autoScroll = true;
  bool showConnectionPanel = true;
  bool showSendPanel = true;
  bool showQuickCommandsPanel = false;
  bool terminalMode = false;
  bool statsPanelExpanded = false;
  bool settingsPanelExpanded = false;
  bool pauseDisplay = false;
  double logFontSize = 12;
  AppLanguage language = AppLanguage.zh;

  final Set<String> _hiddenSources = <String>{};
  final Set<String> _sourceLabels = <String>{'SYS'};
  bool _sendPanelVisibleBeforeTerminal = true;
  int _revision = 0;
  bool _settingsChanged = false;

  SessionController get activeSession => sessions[activeSessionIndex];

  SessionController get sendTarget => sessions[sendTargetIndex];

  AppStrings get strings => AppStrings.of(language);

  String get windowTitle => activeSession.windowTitle;

  bool get canGoPrevious => activeSessionIndex > 0;

  bool get canGoNext => activeSessionIndex < sessions.length - 1;

  int get connectedSessionCount =>
      sessions.where((session) => session.isConnected).length;

  bool get allSessionsConnected =>
      sessions.isNotEmpty && sessions.every((session) => session.isConnected);

  bool get canAddSession =>
      sessions.length == 1 || activeSession.isConnected || allSessionsConnected;

  bool get canRemoveActiveSession =>
      !activeSession.isConnected && sessions.length > 1;

  String get pageIndicator {
    final total = connectedSessionCount;
    if (!activeSession.isConnected) {
      return '';
    }

    var current = 0;
    for (var i = 0; i <= activeSessionIndex; i++) {
      if (sessions[i].isConnected) {
        current++;
      }
    }
    return '$current/$total';
  }

  void setLanguage(AppLanguage next) {
    if (language == next) {
      return;
    }
    language = next;
    for (final session in sessions) {
      session.setLanguage(next);
    }
    _persistSettings();
    notifyListeners();
  }

  ConsoleFormatOptions get formatOptions => ConsoleFormatOptions(
        viewMode: viewMode,
        showTimestamp: showTimestamp,
        showDirection: showDirection,
        showSource: showSource,
        showContent: showContent,
        showLineEndingSymbols: showLineEndingSymbols,
      );

  List<String> get sourceLabels {
    _syncSourceLabels();
    return List<String>.unmodifiable(_sourceLabels);
  }

  Set<String> get visibleSources {
    _syncSourceLabels();
    return _sourceLabels
        .where((source) => !_hiddenSources.contains(source))
        .toSet();
  }

  List<int> get connectedSessionIndexes {
    final indexes = <int>[];
    for (var i = 0; i < sessions.length; i++) {
      if (sessions[i].isConnected) {
        indexes.add(i);
      }
    }
    return indexes;
  }

  Future<void> initialize() async {
    try {
      final storedSettings = await _loadWorkspaceSettings();
      if (storedSettings != null && !_settingsChanged) {
        _applySettings(storedSettings);
      }
    } on Object {
      // Preference loading must not block the communication UI.
    }
    await Future.wait(sessions.map((session) => session.initialize()));
    _publishSnapshot(force: true);
    notifyListeners();
  }

  void previousSession() {
    if (!canGoPrevious) {
      return;
    }
    activeSessionIndex--;
    _syncSendTargetIndex();
    notifyListeners();
  }

  void nextSession() {
    if (!canGoNext) {
      return;
    }
    activeSessionIndex++;
    _syncSendTargetIndex();
    notifyListeners();
  }

  Future<void> addSession() async {
    if (!canAddSession) {
      return;
    }
    final reusableIndex = _reusableEmptySessionIndex();
    if (reusableIndex != null) {
      activeSessionIndex = reusableIndex;
      _syncSendTargetIndex();
      notifyListeners();
      return;
    }
    final session = _addSession(initialize: true);
    activeSessionIndex = sessions.indexOf(session);
    _syncSendTargetIndex();
    _publishSnapshot(force: true);
    notifyListeners();
  }

  void removeActiveSession() {
    if (!canRemoveActiveSession) {
      return;
    }
    final removed = sessions.removeAt(activeSessionIndex);
    removed.removeListener(_handleSessionChanged);
    removed.displaySnapshot.removeListener(_handleSessionSnapshotChanged);
    removed.dispose();
    if (activeSessionIndex >= sessions.length) {
      activeSessionIndex = sessions.length - 1;
    }
    if (sendTargetIndex >= sessions.length) {
      sendTargetIndex = activeSessionIndex;
    }
    _syncSendTargetIndex();
    _publishSnapshot(force: true);
    notifyListeners();
  }

  void setSendTargetIndex(int index) {
    if (index < 0 ||
        index >= sessions.length ||
        !sessions[index].isConnected ||
        index == sendTargetIndex) {
      return;
    }
    sendTargetIndex = index;
    notifyListeners();
  }

  void stepSendTarget(int step) {
    final indexes = connectedSessionIndexes;
    if (indexes.isEmpty || step == 0) {
      return;
    }
    var index = indexes.indexOf(sendTargetIndex);
    if (index < 0) {
      index = step > 0 ? -1 : 0;
    }
    var nextIndex = (index + step) % indexes.length;
    if (nextIndex < 0) {
      nextIndex += indexes.length;
    }
    setSendTargetIndex(indexes[nextIndex]);
  }

  String sessionLabel(int index) {
    return sessions[index].sourceLabel;
  }

  Set<String> occupiedSerialPortsExcept(SessionController current) {
    final ports = <String>{};
    for (final session in sessions) {
      if (session == current ||
          !session.isConnected ||
          session.config.type != TransportType.serial) {
        continue;
      }
      final serial = session.config.serial;
      if (!isGenericSerialPortName(serial.portName)) {
        ports.add(serial.portName);
      }
      if (serial.forwardingEnabled &&
          !isGenericSerialPortName(serial.forwardPortName)) {
        ports.add(serial.forwardPortName);
      }
    }
    return ports;
  }

  void setViewMode(ConsoleViewMode mode) {
    if (viewMode == mode) {
      return;
    }
    viewMode = mode;
    _persistSettings();
    _publishSnapshot(force: true);
    notifyListeners();
  }

  void setTimestampVisible(bool value) {
    if (showTimestamp == value) {
      return;
    }
    showTimestamp = value;
    _persistSettings();
    _publishSnapshot(force: true);
    notifyListeners();
  }

  void setSourceVisible(bool value) {
    if (showSource == value) {
      return;
    }
    showSource = value;
    _persistSettings();
    _publishSnapshot(force: true);
    notifyListeners();
  }

  void setDirectionVisible(bool value) {
    if (showDirection == value) {
      return;
    }
    showDirection = value;
    _persistSettings();
    _publishSnapshot(force: true);
    notifyListeners();
  }

  void setContentVisible(bool value) {
    if (showContent == value) {
      return;
    }
    showContent = value;
    _persistSettings();
    _publishSnapshot(force: true);
    notifyListeners();
  }

  void setLineEndingSymbolsVisible(bool value) {
    if (showLineEndingSymbols == value) {
      return;
    }
    showLineEndingSymbols = value;
    _persistSettings();
    _publishSnapshot(force: true);
    notifyListeners();
  }

  void setAutoScroll(bool value) {
    if (autoScroll == value) {
      return;
    }
    autoScroll = value;
    _persistSettings();
    notifyListeners();
  }

  void setConnectionPanelVisible(bool value) {
    if (showConnectionPanel == value) {
      return;
    }
    showConnectionPanel = value;
    _persistSettings();
    notifyListeners();
  }

  void setSendPanelVisible(bool value) {
    if (terminalMode) {
      if (!value) {
        return;
      }
      terminalMode = false;
      showSendPanel = true;
      _sendPanelVisibleBeforeTerminal = true;
      _persistSettings();
      notifyListeners();
      return;
    }
    if (showSendPanel == value) {
      return;
    }
    showSendPanel = value;
    _sendPanelVisibleBeforeTerminal = value;
    _persistSettings();
    notifyListeners();
  }

  void setTerminalMode(bool value) {
    if (terminalMode == value) {
      return;
    }
    terminalMode = value;
    if (value) {
      _sendPanelVisibleBeforeTerminal = showSendPanel;
      showSendPanel = false;
    } else {
      showSendPanel = _sendPanelVisibleBeforeTerminal;
    }
    _persistSettings();
    notifyListeners();
  }

  void setStatsPanelExpanded(bool value) {
    if (statsPanelExpanded == value) {
      return;
    }
    statsPanelExpanded = value;
    _persistSettings();
    notifyListeners();
  }

  void setSettingsPanelExpanded(bool value) {
    if (settingsPanelExpanded == value) {
      return;
    }
    settingsPanelExpanded = value;
    _persistSettings();
    notifyListeners();
  }

  void setQuickCommandsPanelVisible(bool value) {
    if (showQuickCommandsPanel == value) {
      return;
    }
    showQuickCommandsPanel = value;
    _persistSettings();
    notifyListeners();
  }

  void setPauseDisplay(bool value) {
    if (pauseDisplay == value) {
      return;
    }
    pauseDisplay = value;
    _publishSnapshot(force: true);
    notifyListeners();
  }

  void setLogFontSize(double value) {
    final next = value.clamp(10, 22).toDouble();
    if (next == logFontSize) {
      return;
    }
    logFontSize = next;
    _persistSettings();
    notifyListeners();
  }

  void increaseLogFontSize() => setLogFontSize(logFontSize + 1);

  void decreaseLogFontSize() => setLogFontSize(logFontSize - 1);

  bool isSourceVisible(String source) => !_hiddenSources.contains(source);

  void setLogSourceVisible(String source, bool visible) {
    final wasVisible = isSourceVisible(source);
    if (wasVisible == visible) {
      return;
    }
    if (visible) {
      _hiddenSources.remove(source);
    } else {
      _hiddenSources.add(source);
    }
    _persistSettings();
    notifyListeners();
  }

  void toggleLogSource(String source) {
    setLogSourceVisible(source, !isSourceVisible(source));
  }

  void clearLog() {
    for (final session in sessions) {
      session.clearLog();
    }
    _publishSnapshot(force: true);
    notifyListeners();
  }

  Future<void> exportLog() async {
    try {
      final text = displaySnapshot.value.frames
          .where((frame) => visibleSources.contains(_sourceKey(frame)))
          .map((frame) => formatter.formatFrame(frame, formatOptions))
          .join('\n');
      final result = await exportLogText('$text\n');
      activeSession.appendSystemMessage(strings.exportResult(result));
    } on Object catch (error) {
      activeSession.appendSystemMessage(strings.exportFailed(error));
    }
  }

  void _handleSessionChanged() {
    _syncSendTargetIndex();
    _syncSourceLabels();
    notifyListeners();
  }

  void _handleSessionSnapshotChanged() {
    final sourcesChanged = _publishSnapshot();
    if (sourcesChanged) {
      notifyListeners();
    }
  }

  bool _publishSnapshot({bool force = false}) {
    final sourcesChanged = _syncSourceLabels();
    if (pauseDisplay && !force) {
      return sourcesChanged;
    }
    _revision++;
    displaySnapshot.value = _buildSnapshot(paused: pauseDisplay);
    return sourcesChanged;
  }

  LogSnapshot _buildSnapshot({required bool paused}) {
    final frames = <DataFrame>[];
    var totalFrames = 0;
    var totalBytes = 0;
    var droppedFrames = 0;
    var droppedBytes = 0;

    for (final session in sessions) {
      final snapshot = session.logBuffer.snapshot(paused: false);
      frames.addAll(snapshot.frames);
      totalFrames += snapshot.totalFrames;
      totalBytes += snapshot.totalBytes;
      droppedFrames += snapshot.droppedFrames;
      droppedBytes += snapshot.droppedBytes;
    }

    frames.sort((a, b) {
      final time = a.timestamp.compareTo(b.timestamp);
      if (time != 0) {
        return time;
      }
      final source = a.source.compareTo(b.source);
      if (source != 0) {
        return source;
      }
      return a.sequence.compareTo(b.sequence);
    });

    final overflow = frames.length - maxCombinedFrames;
    final visibleFrames = overflow > 0
        ? List<DataFrame>.unmodifiable(frames.sublist(overflow))
        : List<DataFrame>.unmodifiable(frames);

    return LogSnapshot(
      revision: _revision,
      frames: visibleFrames,
      totalFrames: totalFrames,
      totalBytes: totalBytes,
      droppedFrames: droppedFrames + (overflow > 0 ? overflow : 0),
      droppedBytes: droppedBytes,
      paused: paused,
    );
  }

  String _sourceKey(DataFrame frame) {
    return formatter.sourceToken(frame);
  }

  bool _syncSourceLabels() {
    final next = <String>{'SYS'};
    for (final session in sessions) {
      for (final source in session.logBuffer.retainedSourceLabels) {
        final label = source.trim();
        if (label.isNotEmpty) {
          next.add(label);
        }
      }
      final label = session.sourceLabel.trim();
      if (label.isNotEmpty) {
        next.add(label);
      }
    }
    if (setEquals(_sourceLabels, next)) {
      return false;
    }
    _sourceLabels
      ..clear()
      ..addAll(next);
    return true;
  }

  void _syncSendTargetIndex() {
    if (sendTargetIndex >= 0 &&
        sendTargetIndex < sessions.length &&
        sessions[sendTargetIndex].isConnected) {
      return;
    }
    final connectedIndexes = connectedSessionIndexes;
    sendTargetIndex =
        connectedIndexes.isEmpty ? activeSessionIndex : connectedIndexes.first;
  }

  SessionController _addSession({required bool initialize}) {
    final session = SessionController(
      serialAliasNumber: _nextAvailableSerialAliasNumber(),
      language: language,
    );
    session.addListener(_handleSessionChanged);
    session.displaySnapshot.addListener(_handleSessionSnapshotChanged);
    sessions.add(session);
    if (initialize) {
      unawaited(session.initialize());
    }
    return session;
  }

  int _nextAvailableSerialAliasNumber() {
    final usedNumbers = sessions
        .map((session) => session.serialAliasNumber)
        .where((number) => number > 0)
        .toSet();
    var candidate = 1;
    while (usedNumbers.contains(candidate)) {
      candidate++;
    }
    return candidate;
  }

  int? _reusableEmptySessionIndex() {
    if (!activeSession.isConnected) {
      return null;
    }
    for (var i = 0; i < sessions.length; i++) {
      if (!sessions[i].isConnected) {
        return i;
      }
    }
    return null;
  }

  WorkspaceSettings _settingsSnapshot() => WorkspaceSettings(
        viewMode: viewMode,
        showTimestamp: showTimestamp,
        showDirection: showDirection,
        showSource: showSource,
        showContent: showContent,
        showLineEndingSymbols: showLineEndingSymbols,
        autoScroll: autoScroll,
        showConnectionPanel: showConnectionPanel,
        showSendPanel: showSendPanel,
        sendPanelVisibleBeforeTerminal: _sendPanelVisibleBeforeTerminal,
        showQuickCommandsPanel: showQuickCommandsPanel,
        terminalMode: terminalMode,
        statsPanelExpanded: statsPanelExpanded,
        settingsPanelExpanded: settingsPanelExpanded,
        logFontSize: logFontSize,
        language: language,
        hiddenSources: Set<String>.unmodifiable(_hiddenSources),
      );

  void _applySettings(WorkspaceSettings settings) {
    viewMode = settings.viewMode;
    showTimestamp = settings.showTimestamp;
    showDirection = settings.showDirection;
    showSource = settings.showSource;
    showContent = settings.showContent;
    showLineEndingSymbols = settings.showLineEndingSymbols;
    autoScroll = settings.autoScroll;
    showConnectionPanel = settings.showConnectionPanel;
    terminalMode = settings.terminalMode;
    _sendPanelVisibleBeforeTerminal = settings.sendPanelVisibleBeforeTerminal;
    showSendPanel = settings.terminalMode ? false : settings.showSendPanel;
    showQuickCommandsPanel = settings.showQuickCommandsPanel;
    statsPanelExpanded = settings.statsPanelExpanded;
    settingsPanelExpanded = settings.settingsPanelExpanded;
    logFontSize = settings.logFontSize.clamp(10, 22).toDouble();
    language = settings.language;
    _hiddenSources
      ..clear()
      ..addAll(settings.hiddenSources);
    for (final session in sessions) {
      session.setLanguage(language);
    }
  }

  void _persistSettings() {
    _settingsChanged = true;
    unawaited(_saveWorkspaceSettings(_settingsSnapshot()));
  }

  @override
  void dispose() {
    for (final session in sessions) {
      session.removeListener(_handleSessionChanged);
      session.displaySnapshot.removeListener(_handleSessionSnapshotChanged);
      session.dispose();
    }
    displaySnapshot.dispose();
    super.dispose();
  }
}
