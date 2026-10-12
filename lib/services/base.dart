import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vetweek/models.dart';
import 'package:vetweek/services/apps.dart';
import 'package:vetweek/services/network.dart';
import 'package:vetweek/services/system.dart';
import 'package:vetweek/services/tweaks.dart';

String _stripBom(String value) {
  if (value.startsWith('\uFEFF')) {
    return value.substring(1);
  }

  return value;
}

class AppPaths {
  static String baseDirectory() {
    final environment = Platform.environment;

    final appData = environment['APPDATA'];
    if (appData != null && appData.isNotEmpty) {
      return appData;
    }

    final userProfile = environment['USERPROFILE'];
    if (userProfile != null && userProfile.isNotEmpty) {
      return userProfile;
    }

    return Directory.current.path;
  }

  static Future<Directory> ensureVeTweekDirectory() async {
    final directory = Directory(
      '${baseDirectory()}${Platform.pathSeparator}VeTweek',
    );

    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    return directory;
  }
}

class PowerShellService {
  Future<PowerShellResult> run(
    String command, {
    Duration timeout = const Duration(minutes: 2),
  }) async {
    if (!Platform.isWindows) {
      throw 'PowerShell доступен только в Windows';
    }

    try {
      final result = await Process.run(
        'powershell.exe',
        [
          '-NoProfile',
          '-NonInteractive',
          '-WindowStyle',
          'Hidden',
          '-Command',
          command,
        ],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      ).timeout(timeout);

      return PowerShellResult(
        exitCode: result.exitCode,
        stdout: _stripBom(result.stdout.toString()),
        stderr: _stripBom(result.stderr.toString()),
      );
    } on TimeoutException catch (e) {
      throw 'Превышено время ожидания: $e';
    }
  }

  Future<void> runDetachedElevated(String command) async {
    if (!Platform.isWindows) {
      return;
    }

    await Process.start(
      'powershell.exe',
      [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        command,
      ],
      runInShell: true,
      mode: ProcessStartMode.detached,
    );
  }
}

String psQuote(String value) {
  return "'${value.replaceAll("'", "''")}'";
}

String hiveDotNet(Hive hive) {
  switch (hive) {
    case Hive.hkcu:
      return 'CurrentUser';
    case Hive.hklm:
      return 'LocalMachine';
    case Hive.hkcr:
      return 'ClassesRoot';
  }
}

class LogService extends ChangeNotifier {
  final List<LogEntry> _entries = [];

  List<LogEntry> get entries => List.unmodifiable(_entries);

  void info(String message, [String details = '']) {
    _add(LogLevel.info, message, details);
  }

  void success(String message, [String details = '']) {
    _add(LogLevel.success, message, details);
  }

  void warning(String message, [String details = '']) {
    _add(LogLevel.warning, message, details);
  }

  void error(String message, [String details = '']) {
    _add(LogLevel.error, message, details);
  }

  void _add(LogLevel level, String message, String details) {
    _entries.insert(
      0,
      LogEntry(
        time: DateTime.now(),
        level: level,
        message: message,
        details: details,
      ),
    );

    notifyListeners();
  }

  void clear() {
    _entries.clear();
    notifyListeners();
  }

  Future<String> export() async {
    final directory = await AppPaths.ensureVeTweekDirectory();

    final file = File(
      '${directory.path}${Platform.pathSeparator}vetweek_log_${DateTime.now().millisecondsSinceEpoch}.txt',
    );

    final buffer = StringBuffer();

    for (final entry in _entries.reversed) {
      buffer.writeln(
        '${entry.time.toIso8601String()} [${_levelToString(entry.level)}] ${entry.message}',
      );

      if (entry.details.isNotEmpty) {
        buffer.writeln(entry.details);
        buffer.writeln('');
      }
    }

    await file.writeAsString(buffer.toString(), flush: true);

    info('Журнал экспортирован', file.path);

    return file.path;
  }

  String _levelToString(LogLevel level) {
    switch (level) {
      case LogLevel.info:
        return 'INFO';
      case LogLevel.success:
        return 'SUCCESS';
      case LogLevel.warning:
        return 'WARNING';
      case LogLevel.error:
        return 'ERROR';
    }
  }
}

class SettingsService extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  int _seedColorValue = 0xFF0B57D0;
  bool _devModeEnabled = false;
  bool _oled = false;

  ThemeMode get themeMode => _themeMode;

  int get seedColorValue => _seedColorValue;

  Color get seedColor => Color(_seedColorValue);

  bool get devModeEnabled => _devModeEnabled;

  bool get oled => _oled;

  void setThemeMode(ThemeMode value) {
    if (_themeMode == value) {
      return;
    }

    _themeMode = value;
    notifyListeners();
    save();
  }

  void setSeedColorValue(int value) {
    if (_seedColorValue == value) {
      return;
    }

    _seedColorValue = value;
    notifyListeners();
    save();
  }

  void setDevModeEnabled(bool value) {
    if (_devModeEnabled == value) {
      return;
    }

    _devModeEnabled = value;
    notifyListeners();
    save();
  }

  void setOled(bool value) {
    if (_oled == value) {
      return;
    }

    _oled = value;
    notifyListeners();
    save();
  }

  Future<File> _file() async {
    final directory = await AppPaths.ensureVeTweekDirectory();
    return File('${directory.path}${Platform.pathSeparator}settings.json');
  }

  Future<void> load() async {
    try {
      final file = await _file();

      if (!await file.exists()) {
        return;
      }

      final content = await file.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;

      final mode = data['themeMode'];

      if (mode == 'light') {
        _themeMode = ThemeMode.light;
      } else if (mode == 'dark') {
        _themeMode = ThemeMode.dark;
      } else {
        _themeMode = ThemeMode.system;
      }

      final color = data['seedColor'];

      if (color is int) {
        _seedColorValue = color;
      }

      final dev = data['devMode'];

      if (dev is bool) {
        _devModeEnabled = dev;
      }

      final oled = data['oled'];

      if (oled is bool) {
        _oled = oled;
      }

      notifyListeners();
    } catch (_) {
      return;
    }
  }

  Future<void> save() async {
    try {
      final file = await _file();

      await file.writeAsString(
        jsonEncode({
          'themeMode': _themeModeToString(),
          'seedColor': _seedColorValue,
          'devMode': _devModeEnabled,
          'oled': _oled,
        }),
        flush: true,
      );
    } catch (_) {
      return;
    }
  }

  String _themeModeToString() {
    switch (_themeMode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }
}

class StateService {
  final Map<String, String> _tweakStatuses = {};
  final Map<String, String> _tweakErrors = {};
  final Map<String, Object?> _tweakBackups = {};
  final Map<String, Object?> _startupBackups = {};
  final Map<String, Object?> _devBackups = {};
  bool _restorePointSuggested = false;
  bool _firstLaunchCompleted = false;
  DateTime? _lastCheckTime;

  Map<String, String> get tweakStatuses => Map.unmodifiable(_tweakStatuses);

  Map<String, String> get tweakErrors => Map.unmodifiable(_tweakErrors);

  Map<String, Object?> get tweakBackups => Map.unmodifiable(_tweakBackups);

  Map<String, Object?> get startupBackups => Map.unmodifiable(_startupBackups);

  Map<String, Object?> get devBackups => Map.unmodifiable(_devBackups);

  bool get restorePointSuggested => _restorePointSuggested;

  bool get firstLaunchCompleted => _firstLaunchCompleted;

  DateTime? get lastCheckTime => _lastCheckTime;

  void setTweakStatus(String id, TweakStatus status) {
    _tweakStatuses[id] = status.name;
  }

  void setTweakError(String id, String error) {
    if (error.isEmpty) {
      _tweakErrors.remove(id);
    } else {
      _tweakErrors[id] = error;
    }
  }

  void setTweakBackup(String id, List<Object?> values) {
    _tweakBackups[id] = values;
  }

  List<Object?>? getTweakBackup(String id) {
    final value = _tweakBackups[id];

    if (value is List) {
      return value.cast<Object?>();
    }

    return null;
  }

  void setStartupBackup(String id, Object? value) {
    _startupBackups[id] = value;
  }

  Object? getStartupBackup(String id) => _startupBackups[id];

  void removeStartupBackup(String id) {
    _startupBackups.remove(id);
  }

  void setDevBackup(String id, Object? value) {
    _devBackups[id] = value;
  }

  Object? getDevBackup(String id) => _devBackups[id];

  void removeDevBackup(String id) {
    _devBackups.remove(id);
  }

  void markRestorePointSuggested() {
    _restorePointSuggested = true;
  }

  void markFirstLaunchCompleted() {
    _firstLaunchCompleted = true;
  }

  void markChecked() {
    _lastCheckTime = DateTime.now();
  }

  Future<File> _file() async {
    final directory = await AppPaths.ensureVeTweekDirectory();
    return File('${directory.path}${Platform.pathSeparator}state.json');
  }

  Future<void> load() async {
    try {
      final file = await _file();

      if (!await file.exists()) {
        return;
      }

      final data = jsonDecode(await file.readAsString())
          as Map<String, dynamic>;

      final statuses = data['tweakStatuses'];

      if (statuses is Map) {
        _tweakStatuses.clear();
        statuses.forEach((k, v) {
          _tweakStatuses[k.toString()] = v.toString();
        });
      }

      final errors = data['tweakErrors'];

      if (errors is Map) {
        _tweakErrors.clear();
        errors.forEach((k, v) {
          _tweakErrors[k.toString()] = v.toString();
        });
      }

      final tweakBackups = data['tweakBackups'];

      if (tweakBackups is Map) {
        _tweakBackups.clear();
        tweakBackups.forEach((k, v) {
          _tweakBackups[k.toString()] = v;
        });
      }

      final startupBackups = data['startupBackups'];

      if (startupBackups is Map) {
        _startupBackups.clear();
        startupBackups.forEach((k, v) {
          _startupBackups[k.toString()] = v;
        });
      }

      final devBackups = data['devBackups'];

      if (devBackups is Map) {
        _devBackups.clear();
        devBackups.forEach((k, v) {
          _devBackups[k.toString()] = v;
        });
      }

      _restorePointSuggested = data['restorePointSuggested'] == true;
      _firstLaunchCompleted = data['firstLaunchCompleted'] == true;

      final lastCheck = data['lastCheckTime'];

      if (lastCheck is String) {
        _lastCheckTime = DateTime.tryParse(lastCheck);
      }
    } catch (_) {
      return;
    }
  }

  Future<void> save() async {
    try {
      final file = await _file();

      await file.writeAsString(
        jsonEncode({
          'tweakStatuses': _tweakStatuses,
          'tweakErrors': _tweakErrors,
          'tweakBackups': _tweakBackups,
          'startupBackups': _startupBackups,
          'devBackups': _devBackups,
          'restorePointSuggested': _restorePointSuggested,
          'firstLaunchCompleted': _firstLaunchCompleted,
          'lastCheckTime': _lastCheckTime?.toIso8601String(),
        }),
        flush: true,
      );
    } catch (_) {
      return;
    }
  }
}

class AppServices {
  final PowerShellService powershell = PowerShellService();
  final SettingsService settings = SettingsService();
  final LogService log = LogService();
  final StateService state = StateService();

  late final SystemService system;
  late final RegistryService registry;
  late final TweakEngine engine;
  late final DefenderService defender;
  late final AdvertisingService advertising;
  late final WidgetsService widgets;
  late final WindowsUpdateService windowsUpdate;
  late final CleanupService cleanup;
  late final RestorePointService restorePoint;
  late final AppxService appx;
  late final StartupService startup;
  late final WingetService winget;
  late final NetworkService network;
  late final DevService dev;
  late final List<Tweak> tweaks;

  Future<void> init() async {
    await settings.load();
    await state.load();

    registry = RegistryService(shell: powershell);
    system = SystemService(shell: powershell, log: log);
    engine = TweakEngine(
      shell: powershell,
      registry: registry,
      log: log,
      state: state,
    );
    tweaks = TweakCatalog.build();
    defender = DefenderService(shell: powershell, log: log);
    advertising = AdvertisingService(
      shell: powershell,
      log: log,
      registry: registry,
    );
    widgets = WidgetsService(shell: powershell, log: log);
    windowsUpdate = WindowsUpdateService(
      shell: powershell,
      log: log,
      registry: registry,
      system: system,
    );
    cleanup = CleanupService(shell: powershell, log: log);
    restorePoint = RestorePointService(shell: powershell, log: log);
    appx = AppxService(shell: powershell, log: log);
    startup = StartupService(
      shell: powershell,
      log: log,
      registry: registry,
      state: state,
    );
    winget = WingetService(
      shell: powershell,
      log: log,
      system: system,
    );
    network = NetworkService(
      shell: powershell,
      log: log,
      system: system,
    );
    dev = DevService(
      shell: powershell,
      log: log,
      registry: registry,
      state: state,
      system: system,
      startup: startup,
    );

    log.info('Приложение запущено');
  }
}