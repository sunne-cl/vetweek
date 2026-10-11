import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vetweek/models.dart';

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
          '-Command',
          command,
        ],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      ).timeout(timeout);

      return PowerShellResult(
        exitCode: result.exitCode,
        stdout: result.stdout.toString(),
        stderr: result.stderr.toString(),
      );
    } on TimeoutException catch (e) {
      throw 'Превышено время ожидания: $e';
    }
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

class _RegRead {
  final bool missing;
  final bool isNull;
  final String value;

  const _RegRead({
    required this.missing,
    required this.isNull,
    this.value = '',
  });

  factory _RegRead.missing() {
    return const _RegRead(
      missing: true,
      isNull: false,
    );
  }

  factory _RegRead.nullValue() {
    return const _RegRead(
      missing: false,
      isNull: true,
    );
  }

  factory _RegRead.found(String value) {
    return _RegRead(
      missing: false,
      isNull: false,
      value: value,
    );
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

  ThemeMode get themeMode => _themeMode;

  int get seedColorValue => _seedColorValue;

  Color get seedColor => Color(_seedColorValue);

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

class SystemService extends ChangeNotifier {
  final PowerShellService shell;
  final LogService log;

  bool _isLoading = false;
  bool _isAdmin = false;
  String _os = 'Определяется...';
  String _error = '';
  DateTime? _checkedAt;

  SystemService({
    required this.shell,
    required this.log,
  });

  bool get isLoading => _isLoading;

  bool get isAdmin => _isAdmin;

  String get os => _os;

  String get error => _error;

  DateTime? get checkedAt => _checkedAt;

  Future<void> refresh() async {
    if (_isLoading) {
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      _isAdmin = await _checkAdmin();
      _os = await _readOsName();
      _error = '';
      _checkedAt = DateTime.now();

      log.success(
        'Проверка системы завершена',
        _isAdmin
            ? 'Права администратора обнаружены'
            : 'Права администратора не обнаружены',
      );
    } catch (e) {
      _error = e.toString();
      _os = Platform.operatingSystemVersion;
      log.error('Ошибка проверки системы', _error);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> _checkAdmin() async {
    if (!Platform.isWindows) {
      return false;
    }

    final command =
        r"[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)";

    final result = await shell.run(
      command,
      timeout: const Duration(seconds: 15),
    );

    if (!result.success) {
      throw result.errorOrOutput;
    }

    return result.stdout.trim().toLowerCase().contains('true');
  }

  Future<String> _readOsName() async {
    if (!Platform.isWindows) {
      return Platform.operatingSystemVersion;
    }

    final command =
        r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; $name=''; $disp=''; $build=''; $ubr=''; try { $reg=Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop; $name=[string]$reg.ProductName; $disp=[string]$reg.DisplayVersion; $build=[string]$reg.CurrentBuildNumber; $ubr=[string]$reg.UBR } catch {}; if(-not $name){ try { $os=Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop; $name=[string]$os.Caption; if(-not $build){ $build=[string]$os.BuildNumber } } catch {} }; Write-Output ($name + '|' + $disp + '|' + $build + '|' + $ubr)";

    final result = await shell.run(
      command,
      timeout: const Duration(seconds: 25),
    );

    final output = result.stdout.trim();

    if (result.success && output.isNotEmpty) {
      final parts = output.split('|');

      var name = parts.isNotEmpty ? parts[0].trim() : '';
      var display = parts.length > 1 ? parts[1].trim() : '';
      var build = parts.length > 2 ? parts[2].trim() : '';
      var ubr = parts.length > 3 ? parts[3].trim() : '';

      if (name.toLowerCase().startsWith('microsoft ')) {
        name = name.substring(10);
      }

      final buildNumber = int.tryParse(build) ?? 0;

      if (buildNumber >= 22000 &&
          name.toLowerCase().contains('windows 10')) {
        name = name.replaceFirst(
          RegExp('Windows 10', caseSensitive: false),
          'Windows 11',
        );
      }

      if (name.isEmpty) {
        name = Platform.operatingSystemVersion;
      }

      final buffer = StringBuffer(name);

      if (display.isNotEmpty) {
        buffer.write(' ($display)');
      }

      if (build.isNotEmpty) {
        buffer.write(' · сборка $build');

        if (ubr.isNotEmpty && ubr != '0') {
          buffer.write('.$ubr');
        }
      }

      return buffer.toString();
    }

    return Platform.operatingSystemVersion;
  }

  Future<void> elevateAndRestart() async {
    if (!Platform.isWindows) {
      return;
    }

    final exe = Platform.resolvedExecutable.replaceAll("'", "''");

    final command =
        "Start-Process -FilePath '$exe' -Verb RunAs";

    log.warning('Запрошено повышение прав, перезапуск от администратора');

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

    exit(0);
  }
}

class RegistryService {
  final PowerShellService shell;

  RegistryService({
    required this.shell,
  });

  String _valueSelector(RegistryOp op) {
    if (op.isDefault) {
      return r'$null';
    }

    return psQuote(op.valueName ?? '');
  }

  String _kind(RegValueType type) {
    switch (type) {
      case RegValueType.dword:
        return 'DWord';
      case RegValueType.string:
        return 'String';
    }
  }

  String readManyCommand(List<RegistryOp> ops) {
    if (ops.isEmpty) {
      return r"Write-Output '[]'";
    }

    final buffer = StringBuffer();

    buffer.write(
      r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; $res=New-Object System.Collections.Generic.List[object]; ",
    );

    for (var i = 0; i < ops.length; i++) {
      final op = ops[i];
      final hive = hiveDotNet(op.hive);
      final key = psQuote(op.key);
      final selector = _valueSelector(op);

      buffer.write('\$k=[Microsoft.Win32.Registry]::');
      buffer.write(hive);
      buffer.write('.OpenSubKey(');
      buffer.write(key);
      buffer.write(
        r"); if($k){ $v=$k.GetValue(",
      );
      buffer.write(selector);
      buffer.write(
        r",$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames); $k.Close(); if($null -eq $v){ $s='NULL'; $val='' } else { $s='VAL'; $val=[string]$v } } else { $s='MISSING'; $val='' }; $res.Add([pscustomobject]@{i=",
      );
      buffer.write(i.toString());
      buffer.write(r";s=$s;v=$val}); ");
    }

    buffer.write(r"($res | ConvertTo-Json -Compress -Depth 3)");

    return buffer.toString();
  }

  Future<List<_RegRead>> readMany(List<RegistryOp> ops) async {
    if (ops.isEmpty) {
      return [];
    }

    final result = await shell.run(
      readManyCommand(ops),
      timeout: const Duration(seconds: 45),
    );

    if (!result.success) {
      throw result.errorOrOutput;
    }

    final output = result.stdout.trim();

    if (output.isEmpty) {
      return List<_RegRead>.generate(ops.length, (_) => _RegRead.missing());
    }

    final decoded = jsonDecode(output);
    final list = decoded is List ? decoded : [decoded];

    final reads = List<_RegRead>.generate(
      ops.length,
      (_) => _RegRead.missing(),
    );

    for (final item in list) {
      if (item is Map<String, dynamic>) {
        final index = int.tryParse(item['i'].toString()) ?? -1;
        final state = (item['s'] ?? '').toString().toUpperCase();
        final value = (item['v'] ?? '').toString();

        if (index >= 0 && index < reads.length) {
          if (state == 'MISSING') {
            reads[index] = _RegRead.missing();
          } else if (state == 'NULL') {
            reads[index] = _RegRead.nullValue();
          } else {
            reads[index] = _RegRead.found(value);
          }
        }
      }
    }

    return reads;
  }

  String writeCommand(RegistryOp op, Object? value) {
    final hive = hiveDotNet(op.hive);
    final key = psQuote(op.key);
    final selector = _valueSelector(op);
    final kind = _kind(op.type);

    if (op.type == RegValueType.dword) {
      int numeric = 0;

      if (value is int) {
        numeric = value;
      } else if (value is num) {
        numeric = value.toInt();
      } else {
        numeric = int.tryParse(value.toString()) ?? 0;
      }

      return "\$ErrorActionPreference='Stop'; \$k=[Microsoft.Win32.Registry]::$hive.CreateSubKey($key); \$k.SetValue($selector,[int]$numeric,[Microsoft.Win32.RegistryValueKind]::$kind); \$k.Close()";
    }

    final str = psQuote(value?.toString() ?? '');

    return "\$ErrorActionPreference='Stop'; \$k=[Microsoft.Win32.Registry]::$hive.CreateSubKey($key); \$k.SetValue($selector,$str,[Microsoft.Win32.RegistryValueKind]::$kind); \$k.Close()";
  }

  Future<void> write(RegistryOp op, Object? value) async {
    final result = await shell.run(
      writeCommand(op, value),
      timeout: const Duration(seconds: 25),
    );

    if (!result.success) {
      throw result.errorOrOutput;
    }
  }

  String deleteValueCommand(RegistryOp op) {
    final hive = hiveDotNet(op.hive);
    final key = psQuote(op.key);
    final name = psQuote(op.valueName ?? '');

    return "\$ErrorActionPreference='Stop'; \$k=[Microsoft.Win32.Registry]::$hive.OpenSubKey($key,\$true); if(\$k){ \$k.DeleteValue($name,\$true); \$k.Close() }";
  }

  Future<void> deleteValue(RegistryOp op) async {
    final result = await shell.run(
      deleteValueCommand(op),
      timeout: const Duration(seconds: 25),
    );

    if (!result.success) {
      throw result.errorOrOutput;
    }
  }

  String deleteKeyCommand(RegistryOp op) {
    final hive = hiveDotNet(op.hive);
    final key = psQuote(op.key);

    return "\$ErrorActionPreference='Stop'; [Microsoft.Win32.Registry]::$hive.DeleteSubKeyTree($key,\$true)";
  }

  Future<void> deleteKey(RegistryOp op) async {
    final result = await shell.run(
      deleteKeyCommand(op),
      timeout: const Duration(seconds: 25),
    );

    if (!result.success) {
      throw result.errorOrOutput;
    }
  }
}

class TweakEngine extends ChangeNotifier {
  final PowerShellService shell;
  final RegistryService registry;
  final LogService log;

  final Map<String, TweakStatus> _statuses = {};
  final Map<String, String> _errors = {};
  final Map<String, List<Object?>> _backups = {};
  final Set<String> _runningIds = {};

  DateTime? _lastFullRefresh;

  TweakEngine({
    required this.shell,
    required this.registry,
    required this.log,
  });

  TweakStatus statusOf(String id) => _statuses[id] ?? TweakStatus.unknown;

  String errorFor(String id) => _errors[id] ?? '';

  bool isBusy(String id) => _runningIds.contains(id);

  bool get anyBusy => _runningIds.isNotEmpty;

  void setStatus(String id, TweakStatus status) {
    _statuses[id] = status;
    notifyListeners();
  }

  void _setError(String id, String message) {
    _errors[id] = message;
    notifyListeners();
  }

  void _clearError(String id) {
    if (_errors.remove(id) != null) {
      notifyListeners();
    }
  }

  Future<void> refresh(Tweak tweak) async {
    try {
      if (tweak is RegistryTweakWrapper) {
        await _refreshRegistry(tweak.tweak);
      } else if (tweak is CommandTweakWrapper) {
        await _refreshCommand(tweak.tweak);
      }

      _clearError(tweak.id);
    } catch (e) {
      _setError(tweak.id, e.toString());
      setStatus(tweak.id, TweakStatus.error);
      log.error('Ошибка чтения статуса твика', '${tweak.title}: $e');
    }
  }

  Future<void> refreshAll(
    List<Tweak> tweaks, {
    bool force = false,
  }) async {
    if (!force &&
        _lastFullRefresh != null &&
        DateTime.now().difference(_lastFullRefresh!) <
            const Duration(seconds: 20)) {
      return;
    }

    for (final tweak in tweaks) {
      await refresh(tweak);
    }

    _lastFullRefresh = DateTime.now();
    notifyListeners();
  }

  Future<void> _refreshRegistry(RegistryTweak tweak) async {
    final reads = await registry.readMany(tweak.ops);
    final backup = _backups[tweak.id];

    var applied = 0;
    var reverted = 0;

    for (var i = 0; i < tweak.ops.length; i++) {
      final op = tweak.ops[i];
      final read = reads[i];

      if (_isApplied(op, read)) {
        applied++;
      }

      if (_isReverted(
        op,
        read,
        backup != null && i < backup.length ? backup[i] : null,
        backup != null,
      )) {
        reverted++;
      }
    }

    if (applied == tweak.ops.length) {
      setStatus(tweak.id, TweakStatus.applied);
    } else if (reverted == tweak.ops.length) {
      setStatus(tweak.id, TweakStatus.notApplied);
    } else {
      setStatus(tweak.id, TweakStatus.partial);
    }
  }

  Future<void> _refreshCommand(CommandTweak tweak) async {
    final result = await shell.run(
      tweak.statusCommand,
      timeout: const Duration(seconds: 30),
    );

    if (!result.success) {
      throw result.errorOrOutput;
    }

    final out = result.stdout.trim();

    if (out.contains(tweak.appliedToken)) {
      setStatus(tweak.id, TweakStatus.applied);
    } else if (tweak.notAppliedToken != null &&
        out.contains(tweak.notAppliedToken!)) {
      setStatus(tweak.id, TweakStatus.notApplied);
    } else if (tweak.notAppliedToken == null) {
      setStatus(tweak.id, TweakStatus.notApplied);
    } else {
      setStatus(tweak.id, TweakStatus.unknown);
    }
  }

  bool _isAbsent(_RegRead read) {
    return read.missing || read.isNull;
  }

  bool _matchesValue(
    RegistryOp op,
    _RegRead read,
    Object? expected,
  ) {
    if (_isAbsent(read)) {
      return expected == null;
    }

    if (expected == null) {
      return false;
    }

    if (op.type == RegValueType.dword) {
      final parsed = int.tryParse(read.value);
      return parsed != null && parsed == expected;
    }

    return read.value == expected.toString();
  }

  bool _matchesBackup(
    RegistryOp op,
    _RegRead read,
    Object? backupValue,
  ) {
    if (backupValue == '__MISSING__') {
      return read.missing;
    }

    if (backupValue == '__NULL__') {
      return read.isNull;
    }

    if (_isAbsent(read) || backupValue == null) {
      return false;
    }

    if (op.type == RegValueType.dword) {
      final parsed = int.tryParse(read.value);
      return parsed != null && parsed == backupValue;
    }

    return read.value == backupValue.toString();
  }

  bool _isApplied(RegistryOp op, _RegRead read) {
    switch (op.applyAction) {
      case RegAction.setValue:
        return _matchesValue(op, read, op.applyValue);
      case RegAction.deleteValue:
        return _isAbsent(read);
      case RegAction.deleteKey:
        return read.missing;
    }
  }

  bool _isReverted(
    RegistryOp op,
    _RegRead read,
    Object? backupValue,
    bool hasBackup,
  ) {
    if (hasBackup) {
      return _matchesBackup(op, read, backupValue);
    }

    return _isRevertedByDefinition(op, read);
  }

  bool _isRevertedByDefinition(RegistryOp op, _RegRead read) {
    switch (op.revertAction) {
      case RegAction.setValue:
        if (op.missingCountsAsReverted && _isAbsent(read)) {
          return true;
        }

        if (op.revertValue == null) {
          return !_isAbsent(read);
        }

        return _matchesValue(op, read, op.revertValue);
      case RegAction.deleteValue:
        return _isAbsent(read);
      case RegAction.deleteKey:
        return read.missing;
    }
  }

  Object? _serializableFromRead(RegistryOp op, _RegRead read) {
    if (read.missing) {
      return '__MISSING__';
    }

    if (read.isNull) {
      return '__NULL__';
    }

    if (op.type == RegValueType.dword) {
      return int.tryParse(read.value) ?? read.value;
    }

    return read.value;
  }

  Future<void> apply(Tweak tweak) async {
    if (_runningIds.contains(tweak.id)) {
      return;
    }

    _runningIds.add(tweak.id);
    _clearError(tweak.id);
    notifyListeners();

    try {
      if (tweak is RegistryTweakWrapper) {
        await _applyRegistry(tweak.tweak);
      } else if (tweak is CommandTweakWrapper) {
        await _applyCommand(tweak.tweak);
      }

      log.success('Твик применен', tweak.title);
      await refresh(tweak);
    } catch (e) {
      _setError(tweak.id, e.toString());
      setStatus(tweak.id, TweakStatus.error);
      log.error('Не удалось применить твик', '${tweak.title}: $e');
      rethrow;
    } finally {
      _runningIds.remove(tweak.id);
      notifyListeners();
    }
  }

  Future<void> revert(Tweak tweak) async {
    if (_runningIds.contains(tweak.id)) {
      return;
    }

    _runningIds.add(tweak.id);
    _clearError(tweak.id);
    notifyListeners();

    try {
      if (tweak is RegistryTweakWrapper) {
        await _revertRegistry(tweak.tweak);
      } else if (tweak is CommandTweakWrapper) {
        await _revertCommand(tweak.tweak);
      }

      log.success('Твик откачен', tweak.title);
      await refresh(tweak);
    } catch (e) {
      _setError(tweak.id, e.toString());
      setStatus(tweak.id, TweakStatus.error);
      log.error('Не удалось откатить твик', '${tweak.title}: $e');
      rethrow;
    } finally {
      _runningIds.remove(tweak.id);
      notifyListeners();
    }
  }

  Future<void> _backupRegistry(RegistryTweak tweak) async {
    if (_backups.containsKey(tweak.id)) {
      return;
    }

    final reads = await registry.readMany(tweak.ops);

    final originals = <Object?>[];

    for (var i = 0; i < tweak.ops.length; i++) {
      originals.add(_serializableFromRead(tweak.ops[i], reads[i]));
    }

    _backups[tweak.id] = originals;
    await _saveBackups();
  }

  Future<void> _applyRegistry(RegistryTweak tweak) async {
    await _backupRegistry(tweak);

    for (final op in tweak.ops) {
      switch (op.applyAction) {
        case RegAction.setValue:
          await registry.write(op, op.applyValue);
          break;
        case RegAction.deleteValue:
          await registry.deleteValue(op);
          break;
        case RegAction.deleteKey:
          await registry.deleteKey(op);
          break;
      }
    }

    if (tweak.applyShell != null) {
      final result = await shell.run(
        tweak.applyShell!,
        timeout: const Duration(seconds: 45),
      );

      if (!result.success) {
        throw result.errorOrOutput;
      }
    }
  }

  Future<void> _revertRegistry(RegistryTweak tweak) async {
    final backup = _backups[tweak.id];

    for (var i = 0; i < tweak.ops.length; i++) {
      final op = tweak.ops[i];
      final Object? original =
          backup != null && i < backup.length ? backup[i] : op.revertValue;

      switch (op.revertAction) {
        case RegAction.setValue:
          if (original == '__MISSING__' || original == '__NULL__') {
            if (op.isDefault) {
              await registry.deleteKey(op);
            } else {
              await registry.deleteValue(op);
            }
          } else {
            await registry.write(op, original);
          }
          break;
        case RegAction.deleteValue:
          await registry.deleteValue(op);
          break;
        case RegAction.deleteKey:
          await registry.deleteKey(op);
          break;
      }
    }

    if (tweak.revertShell != null) {
      final result = await shell.run(
        tweak.revertShell!,
        timeout: const Duration(seconds: 45),
      );

      if (!result.success) {
        throw result.errorOrOutput;
      }
    }
  }

  Future<void> _applyCommand(CommandTweak tweak) async {
    final result = await shell.run(
      tweak.applyCommand,
      timeout: const Duration(seconds: 60),
    );

    if (!result.success) {
      throw result.errorOrOutput;
    }
  }

  Future<void> _revertCommand(CommandTweak tweak) async {
    if (tweak.revertCommand == null) {
      throw 'Твик не поддерживает откат';
    }

    final result = await shell.run(
      tweak.revertCommand!,
      timeout: const Duration(seconds: 60),
    );

    if (!result.success) {
      throw result.errorOrOutput;
    }
  }

  Future<File> _backupFile() async {
    final directory = await AppPaths.ensureVeTweekDirectory();

    return File(
      '${directory.path}${Platform.pathSeparator}tweaks_backup.json',
    );
  }

  Future<void> _saveBackups() async {
    try {
      final file = await _backupFile();

      final serializable = <String, dynamic>{};

      _backups.forEach((key, values) {
        serializable[key] = values
            .map((v) {
              if (v == '__MISSING__') {
                return '__MISSING__';
              }

              if (v == '__NULL__') {
                return '__NULL__';
              }

              return v;
            })
            .toList();
      });

      await file.writeAsString(jsonEncode(serializable), flush: true);
    } catch (_) {
      return;
    }
  }

  Future<void> loadBackups() async {
    try {
      final file = await _backupFile();

      if (!await file.exists()) {
        return;
      }

      final data = jsonDecode(await file.readAsString())
          as Map<String, dynamic>;

      data.forEach((key, values) {
        if (values is List) {
          _backups[key] = values
              .map((v) {
                if (v == null) {
                  return '__NULL__';
                }

                return v as Object?;
              })
              .toList();
        }
      });
    } catch (_) {
      return;
    }
  }
}

class AppxService extends ChangeNotifier {
  final PowerShellService shell;
  final LogService log;

  static const List<String> junkNames = [
    'Microsoft.BingNews',
    'Microsoft.GetHelp',
    'Microsoft.Getstarted',
    'Microsoft.Microsoft3DViewer',
    'Microsoft.MixedReality.Portal',
    'Microsoft.WindowsFeedbackHub',
    'Microsoft.WindowsMaps',
    'Microsoft.ZuneMusic',
    'Microsoft.ZuneVideo',
    'Microsoft.XboxApp',
    'Microsoft.XboxGamingOverlay',
    'Microsoft.Xbox.TCUI',
    'Microsoft.GamingApp',
    'Microsoft.People',
    'Microsoft.YourPhone',
    'Microsoft.CommsPhone',
    'Microsoft.Messaging',
    'Microsoft.3DBuilder',
    'Microsoft.PowerBI',
    'Microsoft.MicrosoftOfficeHub',
    'Microsoft.Advertising.Xaml',
    'Microsoft.WindowsSoundRecorder',
    'Microsoft.SkypeApp',
    'Microsoft.MicrosoftSolitaireCollection',
  ];

  final List<AppxPackage> _packages = [];
  String _query = '';
  bool _loading = false;
  bool _busy = false;
  String _error = '';

  AppxService({
    required this.shell,
    required this.log,
  });

  List<AppxPackage> get packages => List.unmodifiable(_packages);

  String get query => _query;

  bool get loading => _loading;

  bool get busy => _busy;

  String get error => _error;

  List<AppxPackage> get visiblePackages {
    if (_query.trim().isEmpty) {
      return List.unmodifiable(_packages);
    }

    final lower = _query.trim().toLowerCase();

    return _packages
        .where(
          (package) =>
              package.name.toLowerCase().contains(lower) ||
              package.packageFullName.toLowerCase().contains(lower),
        )
        .toList();
  }

  int get selectedCount => _packages.where((package) => package.selected).length;

  void setQuery(String value) {
    _query = value;
    notifyListeners();
  }

  void toggle(AppxPackage package) {
    package.selected = !package.selected;
    notifyListeners();
  }

  void selectAllVisible() {
    for (final package in visiblePackages) {
      package.selected = true;
    }

    notifyListeners();
  }

  void selectJunk() {
    final lowerJunk = junkNames.map((e) => e.toLowerCase()).toSet();

    for (final package in _packages) {
      package.selected = lowerJunk.contains(package.name.toLowerCase());
    }

    notifyListeners();
  }

  void clearSelection() {
    for (final package in _packages) {
      package.selected = false;
    }

    notifyListeners();
  }

  Future<void> load() async {
    if (_loading) {
      return;
    }

    _loading = true;
    _error = '';
    notifyListeners();

    log.info('Загрузка списка приложений Windows');

    try {
      if (!Platform.isWindows) {
        throw 'Раздел доступен только в Windows';
      }

      final command =
          r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; Get-AppxPackage | Select-Object Name, PackageFullName, Publisher, Version, InstallLocation | ConvertTo-Json -Depth 3";

      final result = await shell.run(command);

      if (!result.success) {
        throw result.errorOrOutput;
      }

      final output = result.stdout.toString().trim();

      if (output.isEmpty) {
        _packages.clear();
      } else {
        final decoded = jsonDecode(output);
        final list = decoded is List ? decoded : [decoded];
        final newPackages = <AppxPackage>[];

        for (final item in list) {
          if (item is Map<String, dynamic>) {
            newPackages.add(
              AppxPackage(
                name: (item['Name'] ?? '').toString(),
                packageFullName: (item['PackageFullName'] ?? '').toString(),
                publisher: (item['Publisher'] ?? '').toString(),
                version: (item['Version'] ?? '').toString(),
                installLocation: (item['InstallLocation'] ?? '').toString(),
              ),
            );
          }
        }

        newPackages.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );

        _packages.clear();
        _packages.addAll(newPackages);
      }

      log.success(
        'Список приложений загружен',
        'Всего элементов: ${_packages.length}',
      );
    } catch (e) {
      _error = e.toString();
      log.error('Не удалось загрузить список приложений', _error);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<String> removeSelected() async {
    final selected = _packages.where((package) => package.selected).toList();

    if (selected.isEmpty) {
      return 'Нет выбранных приложений';
    }

    if (_busy) {
      return 'Удаление уже выполняется';
    }

    _busy = true;
    notifyListeners();

    var success = 0;
    var failed = 0;

    for (final package in selected) {
      try {
        await _removePackage(package);
        _packages.remove(package);
        success++;

        log.success('Приложение удалено', package.packageFullName);
      } catch (e) {
        failed++;
        package.selected = true;

        log.error(
          'Не удалось удалить приложение',
          '${package.packageFullName}: $e',
        );
      }

      notifyListeners();
    }

    _busy = false;
    notifyListeners();

    return 'Удалено: $success, ошибок: $failed';
  }

  Future<void> _removePackage(AppxPackage package) async {
    if (!Platform.isWindows) {
      throw 'Раздел доступен только в Windows';
    }

    final escaped = package.name.replaceAll("'", "''");

    final command =
        r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; try { Get-AppxPackage -Name '" +
            escaped +
            r"' | Remove-AppxPackage; Write-Output 'OK' } catch { [Console]::Error.WriteLine($_.Exception.Message); exit 1 }";

    final result = await shell.run(command);

    if (!result.success) {
      throw result.errorOrOutput;
    }
  }

  Future<String> exportBackup() async {
    final directory = await AppPaths.ensureVeTweekDirectory();

    final file = File(
      '${directory.path}${Platform.pathSeparator}vetweek_appx_${DateTime.now().millisecondsSinceEpoch}.json',
    );

    final data = _packages
        .map(
          (package) => {
            'name': package.name,
            'packageFullName': package.packageFullName,
            'publisher': package.publisher,
            'version': package.version,
            'installLocation': package.installLocation,
          },
        )
        .toList();

    await file.writeAsString(jsonEncode(data), flush: true);

    log.success('Резервная копия списка приложений сохранена', file.path);

    return file.path;
  }
}

class DefenderService extends ChangeNotifier {
  final PowerShellService shell;
  final LogService log;

  DefenderStatus status = DefenderStatus.unknown;
  bool realtimeDisabled = false;
  String error = '';
  bool busy = false;

  DefenderService({
    required this.shell,
    required this.log,
  });

  Future<void> refresh({required bool isAdmin}) async {
    if (busy) {
      return;
    }

    if (!isAdmin) {
      status = DefenderStatus.unavailable;
      error = 'Требуются права администратора для чтения статуса';
      notifyListeners();
      return;
    }

    busy = true;
    status = DefenderStatus.checking;
    error = '';
    notifyListeners();

    try {
      final command =
          r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; if (Get-Command Get-MpPreference -ErrorAction SilentlyContinue) { (Get-MpPreference).DisableRealtimeMonitoring } else { 'UNAVAILABLE' }";

      final result = await shell.run(
        command,
        timeout: const Duration(seconds: 30),
      );

      if (!result.success) {
        throw result.errorOrOutput;
      }

      final output = result.stdout.trim();

      if (output.toUpperCase().contains('UNAVAILABLE')) {
        status = DefenderStatus.unavailable;
        realtimeDisabled = false;
      } else {
        realtimeDisabled = output.toLowerCase().contains('true');
        status = realtimeDisabled
            ? DefenderStatus.disabled
            : DefenderStatus.enabled;
      }

      log.info('Статус Defender обновлен', output);
    } catch (e) {
      status = DefenderStatus.error;
      error = e.toString();
      log.error('Ошибка Defender', error);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> setRealtimeDisabled(bool value) async {
    if (busy) {
      return;
    }

    busy = true;
    notifyListeners();

    try {
      final command = value
          ? r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; Set-MpPreference -DisableRealtimeMonitoring $true"
          : r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; Set-MpPreference -DisableRealtimeMonitoring $false";

      final result = await shell.run(
        command,
        timeout: const Duration(seconds: 30),
      );

      if (!result.success) {
        throw result.errorOrOutput;
      }

      if (value) {
        log.warning('Реальная защита отключена');
      } else {
        log.success('Реальная защита включена');
      }

      busy = false;
      notifyListeners();
    } catch (e) {
      error = e.toString();
      status = DefenderStatus.error;
      log.error('Не удалось изменить Defender', error);

      busy = false;
      notifyListeners();

      rethrow;
    }
  }
}

class AdvertisingService extends ChangeNotifier {
  final PowerShellService shell;
  final LogService log;

  static const String registryPath =
      'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\ContentDeliveryManager';

  static const List<String> registryNames = [
    'ContentDeliveryAllowed',
    'RotatingLockScreenOverlayEnabled',
    'SilentInstalledAppsEnabled',
    'SoftLandingEnabled',
    'SubscribedContent-310093Enabled',
    'SubscribedContent-338388Enabled',
    'SubscribedContent-338389Enabled',
    'SystemPaneSuggestionsEnabled',
  ];

  AdvertisingStatus status = AdvertisingStatus.unknown;
  bool adsDisabled = false;
  bool busy = false;
  String error = '';

  AdvertisingService({
    required this.shell,
    required this.log,
  });

  Future<void> refresh() async {
    if (busy) {
      return;
    }

    busy = true;
    status = AdvertisingStatus.checking;
    error = '';
    notifyListeners();

    try {
      var anyFound = false;
      var allZero = true;

      for (final name in registryNames) {
        final value = await _getValue(name);

        if (value != null) {
          anyFound = true;

          if (value != 0) {
            allZero = false;
          }
        }
      }

      adsDisabled = anyFound && allZero;

      status = adsDisabled
          ? AdvertisingStatus.disabled
          : AdvertisingStatus.enabled;

      log.info(
        'Статус рекламных параметров обновлен',
        adsDisabled ? 'Отключено' : 'Включено',
      );
    } catch (e) {
      status = AdvertisingStatus.error;
      error = e.toString();
      log.error('Ошибка проверки рекламных параметров', error);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> disableAds() async {
    if (busy) {
      return;
    }

    busy = true;
    notifyListeners();

    try {
      await _ensureBackup();

      for (final name in registryNames) {
        await _setValue(name, 0);
      }

      log.success('Рекламные параметры отключены');

      busy = false;
      notifyListeners();

      await refresh();
    } catch (e) {
      error = e.toString();
      status = AdvertisingStatus.error;
      log.error('Не удалось отключить рекламные параметры', error);

      busy = false;
      notifyListeners();

      rethrow;
    }
  }

  Future<void> enableAds() async {
    if (busy) {
      return;
    }

    busy = true;
    notifyListeners();

    try {
      final restored = await _restoreBackup();

      if (!restored) {
        for (final name in registryNames) {
          await _setValue(name, 1);
        }

        log.warning('Резервная копия не найдена, значения установлены в 1');
      } else {
        log.success('Рекламные параметры восстановлены из резервной копии');
      }

      busy = false;
      notifyListeners();

      await refresh();
    } catch (e) {
      error = e.toString();
      status = AdvertisingStatus.error;
      log.error('Не удалось включить рекламные параметры', error);

      busy = false;
      notifyListeners();

      rethrow;
    }
  }

  Future<int?> _getValue(String name) async {
    final command = _getCommand(name);

    final result = await shell.run(
      command,
      timeout: const Duration(seconds: 20),
    );

    if (!result.success) {
      throw result.errorOrOutput;
    }

    final output = result.stdout.trim();

    if (output.isEmpty || output.toUpperCase() == 'NULL') {
      return null;
    }

    return int.tryParse(output);
  }

  String _getCommand(String name) {
    return r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; $path='" +
        registryPath +
        r"'; if (Test-Path $path) { $value=(Get-ItemProperty -Path $path -Name '" +
        name +
        r"' -ErrorAction SilentlyContinue).'" +
        name +
        r"'; if ($null -eq $value) { 'NULL' } else { $value } } else { 'NULL' }";
  }

  Future<void> _setValue(String name, int value) async {
    final command = _setCommand(name, value);

    final result = await shell.run(
      command,
      timeout: const Duration(seconds: 20),
    );

    if (!result.success) {
      throw result.errorOrOutput;
    }
  }

  String _setCommand(String name, int value) {
    return r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; $path='" +
        registryPath +
        r"'; if (!(Test-Path $path)) { New-Item -Path $path -Force | Out-Null }; New-ItemProperty -Path $path -Name '" +
        name +
        r"' -Value " +
        value.toString() +
        r" -PropertyType DWord -Force | Out-Null";
  }

  Future<void> _removeValue(String name) async {
    final command = _removeCommand(name);

    final result = await shell.run(
      command,
      timeout: const Duration(seconds: 20),
    );

    if (!result.success) {
      throw result.errorOrOutput;
    }
  }

  String _removeCommand(String name) {
    return r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; $path='" +
        registryPath +
        r"'; if (Test-Path $path) { Remove-ItemProperty -Path $path -Name '" +
        name +
        r"' -ErrorAction SilentlyContinue }";
  }

  Future<File> _backupFile() async {
    final directory = await AppPaths.ensureVeTweekDirectory();

    return File(
      '${directory.path}${Platform.pathSeparator}advertising_backup.json',
    );
  }

  Future<void> _ensureBackup() async {
    final file = await _backupFile();

    if (await file.exists()) {
      return;
    }

    final map = <String, dynamic>{};

    for (final name in registryNames) {
      map[name] = await _getValue(name);
    }

    await file.writeAsString(jsonEncode(map), flush: true);

    log.info('Создана резервная копия рекламных параметров', file.path);
  }

  Future<bool> _restoreBackup() async {
    final file = await _backupFile();

    if (!await file.exists()) {
      return false;
    }

    final content = await file.readAsString();
    final decoded = jsonDecode(content) as Map<String, dynamic>;

    for (final entry in decoded.entries) {
      final value = entry.value;

      if (value == null) {
        await _removeValue(entry.key);
      } else if (value is int) {
        await _setValue(entry.key, value);
      } else if (value is num) {
        await _setValue(entry.key, value.toInt());
      }
    }

    return true;
  }
}

class WidgetsService extends ChangeNotifier {
  final PowerShellService shell;
  final LogService log;

  bool busy = false;
  bool packagesLoaded = false;
  List<String> packageNames = [];
  String error = '';

  WidgetsService({
    required this.shell,
    required this.log,
  });

  bool get removed => packagesLoaded && packageNames.isEmpty;

  Future<void> refresh() async {
    if (busy) {
      return;
    }

    busy = true;
    error = '';
    notifyListeners();

    try {
      final command =
          r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; $packages = Get-AppxPackage | Where-Object { $_.Name -like '*WebExperience*' -or $_.Name -like '*Weather*' -or $_.Name -like '*Widgets*' }; if ($packages) { $packages | Select-Object -ExpandProperty Name | ConvertTo-Json } else { '[]' }";

      final result = await shell.run(
        command,
        timeout: const Duration(minutes: 1),
      );

      if (!result.success) {
        throw result.errorOrOutput;
      }

      final output = result.stdout.trim();

      if (output.isEmpty || output == '[]') {
        packageNames = [];
      } else {
        final decoded = jsonDecode(output);

        if (decoded is List) {
          packageNames = decoded.map((e) => e.toString()).toList();
        } else if (decoded is String) {
          packageNames = [decoded];
        } else {
          packageNames = [];
        }
      }

      packagesLoaded = true;

      log.info(
        'Поиск пакетов виджетов и погоды завершен',
        'Найдено: ${packageNames.length}',
      );
    } catch (e) {
      error = e.toString();
      log.error('Ошибка поиска пакетов виджетов', error);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> removePackages() async {
    if (busy || packageNames.isEmpty) {
      return;
    }

    busy = true;
    notifyListeners();

    try {
      await _backup();

      final command =
          r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; $packages = Get-AppxPackage | Where-Object { $_.Name -like '*WebExperience*' -or $_.Name -like '*Weather*' -or $_.Name -like '*Widgets*' }; foreach ($package in $packages) { Remove-AppxPackage -Package $package.PackageFullName }; Write-Output 'OK'";

      final result = await shell.run(
        command,
        timeout: const Duration(minutes: 5),
      );

      if (!result.success) {
        throw result.errorOrOutput;
      }

      log.warning(
        'Пакеты виджетов и погоды удалены',
        packageNames.join(', '),
      );

      busy = false;
      notifyListeners();

      await refresh();
    } catch (e) {
      error = e.toString();
      log.error('Не удалось удалить пакеты виджетов', error);

      busy = false;
      notifyListeners();

      rethrow;
    }
  }

  Future<void> _backup() async {
    final directory = await AppPaths.ensureVeTweekDirectory();

    final file = File(
      '${directory.path}${Platform.pathSeparator}widgets_backup_${DateTime.now().millisecondsSinceEpoch}.json',
    );

    await file.writeAsString(jsonEncode(packageNames), flush: true);

    log.info('Резервная копия списка пакетов виджетов сохранена', file.path);
  }
}

class TweakCatalog {
  static List<Tweak> build() {
    final tweaks = <Tweak>[];

    tweaks.add(
      RegistryTweakWrapper(
        RegistryTweak(
          id: 'privacy.telemetry',
          title: 'Отключить телеметрию',
          description:
              'Блокировка отправки диагностических данных и отчетов об использовании в Microsoft.',
          category: TweakCategory.privacy,
          requiresAdmin: true,
          reversible: true,
          ops: [
            RegistryOp(
              hive: Hive.hklm,
              key: r'SOFTWARE\Policies\Microsoft\Windows\DataCollection',
              valueName: 'AllowTelemetry',
              type: RegValueType.dword,
              applyValue: 0,
              applyAction: RegAction.setValue,
              revertAction: RegAction.deleteValue,
            ),
          ],
        ),
      ),
    );

    tweaks.add(
      RegistryTweakWrapper(
        RegistryTweak(
          id: 'privacy.feedback',
          title: 'Отключить уведомления об отзывах',
          description:
              'Скрывает предложения оставить отзыв и связанные уведомления системы.',
          category: TweakCategory.privacy,
          requiresAdmin: true,
          reversible: true,
          ops: [
            RegistryOp(
              hive: Hive.hklm,
              key: r'SOFTWARE\Policies\Microsoft\Windows\DataCollection',
              valueName: 'DoNotShowFeedbackNotifications',
              type: RegValueType.dword,
              applyValue: 1,
              applyAction: RegAction.setValue,
              revertAction: RegAction.deleteValue,
            ),
          ],
        ),
      ),
    );

    tweaks.add(
      RegistryTweakWrapper(
        RegistryTweak(
          id: 'privacy.activity',
          title: 'Отключить историю активности',
          description:
              'Запрет сбора истории открытых файлов и приложений и её синхронизации между устройствами.',
          category: TweakCategory.privacy,
          requiresAdmin: true,
          reversible: true,
          ops: [
            RegistryOp(
              hive: Hive.hklm,
              key: r'SOFTWARE\Policies\Microsoft\Windows\System',
              valueName: 'EnableActivityFeed',
              type: RegValueType.dword,
              applyValue: 0,
              applyAction: RegAction.setValue,
              revertAction: RegAction.deleteValue,
            ),
            RegistryOp(
              hive: Hive.hklm,
              key: r'SOFTWARE\Policies\Microsoft\Windows\System',
              valueName: 'PublishUserActivities',
              type: RegValueType.dword,
              applyValue: 0,
              applyAction: RegAction.setValue,
              revertAction: RegAction.deleteValue,
            ),
            RegistryOp(
              hive: Hive.hklm,
              key: r'SOFTWARE\Policies\Microsoft\Windows\System',
              valueName: 'UploadUserActivities',
              type: RegValueType.dword,
              applyValue: 0,
              applyAction: RegAction.setValue,
              revertAction: RegAction.deleteValue,
            ),
          ],
        ),
      ),
    );

    tweaks.add(
      RegistryTweakWrapper(
        RegistryTweak(
          id: 'privacy.websearch',
          title: 'Отключить веб‑поиск в меню Пуск',
          description:
              'Убирает подсказки Bing из поиска, оставляя только локальный поиск по файлам.',
          category: TweakCategory.privacy,
          requiresAdmin: false,
          reversible: true,
          ops: [
            RegistryOp(
              hive: Hive.hkcu,
              key: r'Software\Policies\Microsoft\Windows\Explorer',
              valueName: 'DisableSearchBoxSuggestions',
              type: RegValueType.dword,
              applyValue: 1,
              applyAction: RegAction.setValue,
              revertAction: RegAction.deleteValue,
            ),
            RegistryOp(
              hive: Hive.hkcu,
              key: r'Software\Microsoft\Windows\CurrentVersion\Search',
              valueName: 'BingSearchEnabled',
              type: RegValueType.dword,
              applyValue: 0,
              applyAction: RegAction.setValue,
              revertAction: RegAction.deleteValue,
            ),
          ],
        ),
      ),
    );

    tweaks.add(
      RegistryTweakWrapper(
        RegistryTweak(
          id: 'privacy.adid',
          title: 'Отключить рекламный идентификатор',
          description:
              'Запрещает приложениям использовать идентификатор рекламы пользователя.',
          category: TweakCategory.privacy,
          requiresAdmin: false,
          reversible: true,
          ops: [
            RegistryOp(
              hive: Hive.hkcu,
              key: r'Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo',
              valueName: 'Enabled',
              type: RegValueType.dword,
              applyValue: 0,
              applyAction: RegAction.setValue,
              revertAction: RegAction.deleteValue,
            ),
          ],
        ),
      ),
    );

    tweaks.add(
      RegistryTweakWrapper(
        RegistryTweak(
          id: 'explorer.classicmenu',
          title: 'Классическое контекстное меню',
          description:
              'Возвращает старое полное меню правой кнопки мыши без «Показать дополнительные параметры».',
          category: TweakCategory.explorer,
          requiresAdmin: false,
          reversible: true,
          ops: [
            RegistryOp(
              hive: Hive.hkcu,
              key:
                  r'Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32',
              isDefault: true,
              type: RegValueType.string,
              applyValue: '',
              applyAction: RegAction.setValue,
              revertAction: RegAction.deleteKey,
            ),
          ],
        ),
      ),
    );

    tweaks.add(
      RegistryTweakWrapper(
        RegistryTweak(
          id: 'explorer.gallery',
          title: 'Скрыть Галерею в Проводнике',
          description:
              'Удаляет раздел Галереи из навигации Проводника Windows 11 и позволяет вернуть его обратно.',
          category: TweakCategory.explorer,
          requiresAdmin: true,
          reversible: true,
          ops: [
            RegistryOp(
              hive: Hive.hklm,
              key:
                  r'SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace_46351065\{e88865b5-3e64-4361-bc3b-55034d442721}',
              isDefault: true,
              type: RegValueType.string,
              applyValue: null,
              applyAction: RegAction.deleteKey,
              revertAction: RegAction.setValue,
              revertValue: '',
            ),
          ],
        ),
      ),
    );

    tweaks.add(
      RegistryTweakWrapper(
        RegistryTweak(
          id: 'explorer.home',
          title: 'Скрыть Главную в Проводнике',
          description:
              'Переключает открытие Проводника на «Этот компьютер» вместо раздела «Главная».',
          category: TweakCategory.explorer,
          requiresAdmin: false,
          reversible: true,
          ops: [
            RegistryOp(
              hive: Hive.hkcu,
              key:
                  r'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced',
              valueName: 'LaunchTo',
              type: RegValueType.dword,
              applyValue: 1,
              applyAction: RegAction.setValue,
              revertAction: RegAction.setValue,
              revertValue: 2,
              missingCountsAsReverted: true,
            ),
          ],
        ),
      ),
    );

    tweaks.add(
      CommandTweakWrapper(
        CommandTweak(
          id: 'explorer.godmode',
          title: 'Создать ярлык God Mode',
          description:
              'Создаёт на рабочем столе папку со всеми настройками Windows в одном месте.',
          category: TweakCategory.explorer,
          requiresAdmin: false,
          reversible: true,
          applyCommand:
              r"$ErrorActionPreference='Stop'; $p=Join-Path ([Environment]::GetFolderPath('Desktop')) 'God Mode.{ED7BA470-8E54-465E-825C-99712043E01C}'; if(!(Test-Path $p)){New-Item -ItemType Directory -Path $p | Out-Null}; Write-Output 'OK'",
          revertCommand:
              r"$ErrorActionPreference='Stop'; $p=Join-Path ([Environment]::GetFolderPath('Desktop')) 'God Mode.{ED7BA470-8E54-465E-825C-99712043E01C}'; if(Test-Path $p){Remove-Item -Path $p -Recurse -Force}; Write-Output 'OK'",
          statusCommand:
              r"$ErrorActionPreference='Stop'; $p=Join-Path ([Environment]::GetFolderPath('Desktop')) 'God Mode.{ED7BA470-8E54-465E-825C-99712043E01C}'; (Test-Path $p)",
          appliedToken: 'True',
          notAppliedToken: 'False',
        ),
      ),
    );

    tweaks.add(
      RegistryTweakWrapper(
        RegistryTweak(
          id: 'system.onedrive',
          title: 'Отключить OneDrive',
          description:
              'Отключает синхронизацию и автозапуск OneDrive, сохраняя возможность возврата.',
          category: TweakCategory.system,
          requiresAdmin: false,
          reversible: true,
          ops: [
            RegistryOp(
              hive: Hive.hkcu,
              key: r'Software\Policies\Microsoft\Windows\OneDrive',
              valueName: 'DisableFileSyncNGSC',
              type: RegValueType.dword,
              applyValue: 1,
              applyAction: RegAction.setValue,
              revertAction: RegAction.deleteValue,
            ),
            RegistryOp(
              hive: Hive.hkcu,
              key: r'Software\Microsoft\Windows\CurrentVersion\Run',
              valueName: 'OneDrive',
              type: RegValueType.string,
              applyValue: null,
              applyAction: RegAction.deleteValue,
              revertAction: RegAction.setValue,
            ),
          ],
          applyShell:
              r"$ErrorActionPreference='SilentlyContinue'; Stop-Process -Name 'OneDrive' -Force -ErrorAction SilentlyContinue; Write-Output 'OK'",
        ),
      ),
    );

    tweaks.add(
      CommandTweakWrapper(
        CommandTweak(
          id: 'system.hibernate',
          title: 'Отключить гибернацию',
          description:
              'Освобождает от 4 до 16 ГБ на системном диске, убирая файл hiberfil.sys.',
          category: TweakCategory.system,
          requiresAdmin: true,
          reversible: true,
          applyCommand:
              r"$ErrorActionPreference='Stop'; powercfg /h off; Write-Output 'OK'",
          revertCommand:
              r"$ErrorActionPreference='Stop'; powercfg /h on; Write-Output 'OK'",
          statusCommand: r"(Test-Path 'C:\hiberfil.sys')",
          appliedToken: 'False',
          notAppliedToken: 'True',
        ),
      ),
    );

    tweaks.add(
      CommandTweakWrapper(
        CommandTweak(
          id: 'system.ultimate',
          title: 'Схема максимальной производительности',
          description:
              'Активирует скрытую схему Ultimate Performance для стационарных ПК.',
          category: TweakCategory.system,
          requiresAdmin: true,
          reversible: true,
          applyCommand:
              r"$ErrorActionPreference='Stop'; $out = powercfg /duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61; if($out -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})'){ powercfg /setactive $matches[1] }; Write-Output 'OK'",
          revertCommand:
              r"$ErrorActionPreference='Stop'; powercfg /setactive 381b4222-f694-41f0-9685-ff5bb260df2e; Write-Output 'OK'",
          statusCommand:
              r"$ErrorActionPreference='Stop'; $active = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes' -Name 'ActivePowerScheme' -ErrorAction SilentlyContinue).ActivePowerScheme; if ($active -eq 'e9a42b02-d5df-448d-aa00-03f14749eb61') { 'APPLIED' } else { $out = powercfg /getactivescheme; if ($out -match 'e9a42b02-d5df-448d-aa00-03f14749eb61') { 'APPLIED' } else { 'NOT' } }",
          appliedToken: 'APPLIED',
          notAppliedToken: 'NOT',
        ),
      ),
    );

    tweaks.add(
      RegistryTweakWrapper(
        RegistryTweak(
          id: 'performance.gamebar',
          title: 'Отключить Xbox Game Bar и DVR',
          description:
              'Отключает фоновую запись экрана и игровой оверлей, что может поднять FPS и снизить задержку.',
          category: TweakCategory.performance,
          requiresAdmin: true,
          reversible: true,
          ops: [
            RegistryOp(
              hive: Hive.hkcu,
              key: r'System\GameConfigStore',
              valueName: 'GameDVR_Enabled',
              type: RegValueType.dword,
              applyValue: 0,
              applyAction: RegAction.setValue,
              revertAction: RegAction.deleteValue,
            ),
            RegistryOp(
              hive: Hive.hkcu,
              key: r'Software\Microsoft\Windows\CurrentVersion\GameDVR',
              valueName: 'AppCaptureEnabled',
              type: RegValueType.dword,
              applyValue: 0,
              applyAction: RegAction.setValue,
              revertAction: RegAction.deleteValue,
            ),
            RegistryOp(
              hive: Hive.hklm,
              key: r'SOFTWARE\Policies\Microsoft\Windows\GameDVR',
              valueName: 'AllowGameDVR',
              type: RegValueType.dword,
              applyValue: 0,
              applyAction: RegAction.setValue,
              revertAction: RegAction.deleteValue,
            ),
          ],
        ),
      ),
    );

    final serviceNames = [
      'DiagTrack',
      'SysMain',
      'RemoteRegistry',
      'WbioSrvc',
      'Fax',
    ];

    for (final svc in serviceNames) {
      tweaks.add(
        RegistryTweakWrapper(
          RegistryTweak(
            id: 'performance.service.$svc',
            title: 'Отключить службу $svc',
            description:
                'Останавливает и отключает автозапуск службы $svc, сохраняя исходный тип запуска для отката.',
            category: TweakCategory.performance,
            requiresAdmin: true,
            reversible: true,
            ops: [
              RegistryOp(
                hive: Hive.hklm,
                key: r'SYSTEM\CurrentControlSet\Services\' + svc,
                valueName: 'Start',
                type: RegValueType.dword,
                applyValue: 4,
                applyAction: RegAction.setValue,
                revertAction: RegAction.setValue,
              ),
            ],
            applyShell:
                r"$ErrorActionPreference='SilentlyContinue'; Stop-Service -Name '" +
                    svc +
                    r"' -Force -ErrorAction SilentlyContinue; Write-Output 'OK'",
          ),
        ),
      );
    }

    return tweaks;
  }
}

class AppServices {
  final PowerShellService powershell = PowerShellService();
  final SettingsService settings = SettingsService();
  final LogService log = LogService();

  late final RegistryService registry;
  late final SystemService system;
  late final AppxService appx;
  late final DefenderService defender;
  late final AdvertisingService advertising;
  late final WidgetsService widgets;
  late final TweakEngine engine;
  late final List<Tweak> tweaks;

  AppServices() {
    registry = RegistryService(shell: powershell);
    system = SystemService(shell: powershell, log: log);
    appx = AppxService(shell: powershell, log: log);
    defender = DefenderService(shell: powershell, log: log);
    advertising = AdvertisingService(shell: powershell, log: log);
    widgets = WidgetsService(shell: powershell, log: log);
    engine = TweakEngine(shell: powershell, registry: registry, log: log);
    tweaks = TweakCatalog.build();
  }

  Future<void> init() async {
    await settings.load();
    await engine.loadBackups();
    await system.refresh();
    log.info('Приложение запущено');
  }
}