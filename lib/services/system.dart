import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:vetweek/models.dart';
import 'package:vetweek/services/base.dart';

class SystemService extends ChangeNotifier {
  final PowerShellService shell;
  final LogService log;

  bool _isLoading = false;
  bool _isAdmin = false;
  String _os = 'Определяется...';
  String _error = '';
  DateTime? _checkedAt;
  PcSpecs? _specs;
  DiskUsage? _diskC;

  bool reservedBusy = false;
  String reservedError = '';
  String reservedMessage = '';

  SystemService({
    required this.shell,
    required this.log,
  });

  bool get isLoading => _isLoading;

  bool get isAdmin => _isAdmin;

  String get os => _os;

  String get error => _error;

  DateTime? get checkedAt => _checkedAt;

  PcSpecs? get specs => _specs;

  DiskUsage? get diskC => _diskC;

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

  Future<void> refreshHardware() async {
    try {
      _specs = await _readSpecs();
      _diskC = await _readDiskC();
      notifyListeners();
    } catch (e) {
      log.error('Ошибка чтения характеристик ПК', e.toString());
    }
  }

  Future<void> restartExplorer() async {
    final result = await shell.run(
      r"$ErrorActionPreference='SilentlyContinue'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue; Start-Sleep -Milliseconds 700; Start-Process explorer; Write-Output 'OK'",
      timeout: const Duration(seconds: 30),
    );

    if (!result.success) {
      throw result.errorOrOutput;
    }

    log.info('Проводник перезапущен');
  }

  Future<void> disableReservedStorage() async {
    if (reservedBusy) {
      return;
    }

    reservedBusy = true;
    reservedError = '';
    reservedMessage = '';
    notifyListeners();

    try {
      final result = await shell.run(
        r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; DISM.exe /Online /Set-ReservedStorageState /State:Disabled; Write-Output 'OK'",
        timeout: const Duration(minutes: 5),
      );

      if (!result.success) {
        throw result.errorOrOutput;
      }

      reservedMessage = result.stdout.trim();

      log.success(
        'Резервируемое хранилище отключено',
        reservedMessage,
      );
    } catch (e) {
      reservedError = e.toString();
      log.error('Не удалось отключить резервируемое хранилище', reservedError);
      rethrow;
    } finally {
      reservedBusy = false;
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

  Future<PcSpecs> _readSpecs() async {
    final command =
        r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; $cpu=Get-CimInstance Win32_Processor | Select-Object -First 1; $gpus=@(Get-CimInstance Win32_VideoController); $ram=@(Get-CimInstance Win32_PhysicalMemory); $disks=@(Get-CimInstance Win32_DiskDrive); $obj=[pscustomobject]@{ cpu=[pscustomobject]@{name=$cpu.Name;cores=[int]$cpu.NumberOfCores;logical=[int]$cpu.NumberOfLogicalProcessors;mhz=[int]$cpu.MaxClockSpeed}; gpus=@($gpus|ForEach-Object{[pscustomobject]@{name=$_.Name;driver=[string]$_.DriverVersion;mem=[int64]($_.AdapterRAM/1MB)}}); ram=@($ram|ForEach-Object{[pscustomobject]@{gb=[int64]($_.Capacity/1GB);speed=[int]$_.Speed;man=[string]$_.Manufacturer}}); disks=@($disks|ForEach-Object{[pscustomobject]@{model=$_.Model;iface=[string]$_.InterfaceType;media=[string]$_.MediaType;gb=[int64]($_.Size/1GB)}}) }; $obj | ConvertTo-Json -Depth 5";

    final result = await shell.run(
      command,
      timeout: const Duration(seconds: 40),
    );

    if (!result.success) {
      throw result.errorOrOutput;
    }

    final output = result.stdout.trim();

    if (output.isEmpty) {
      return PcSpecs(
        cpu: CpuInfo(
          name: 'Не определено',
          cores: 0,
          logicalProcessors: 0,
          maxMhz: 0,
        ),
        gpus: [],
        ramModules: [],
        drives: [],
      );
    }

    final data = jsonDecode(output) as Map<String, dynamic>;

    final cpuMap = (data['cpu'] as Map?)?.cast<String, dynamic>() ?? {};
    final cpu = CpuInfo(
      name: (cpuMap['name'] ?? 'Не определено').toString(),
      cores: _toInt(cpuMap['cores']),
      logicalProcessors: _toInt(cpuMap['logical']),
      maxMhz: _toInt(cpuMap['mhz']),
    );

    final gpus = <GpuInfo>[];
    final gpuList = data['gpus'];

    if (gpuList is List) {
      for (final item in gpuList) {
        if (item is Map) {
          final m = item.cast<String, dynamic>();
          gpus.add(
            GpuInfo(
              name: (m['name'] ?? '').toString(),
              driverVersion: (m['driver'] ?? '').toString(),
              memoryMb: _toInt(m['mem']),
            ),
          );
        }
      }
    }

    final ram = <RamModule>[];
    final ramList = data['ram'];

    if (ramList is List) {
      for (final item in ramList) {
        if (item is Map) {
          final m = item.cast<String, dynamic>();
          ram.add(
            RamModule(
              capacityGb: _toInt(m['gb']),
              speedMhz: _toInt(m['speed']),
              manufacturer: (m['man'] ?? '').toString(),
            ),
          );
        }
      }
    }

    final drives = <DiskDriveInfo>[];
    final diskList = data['disks'];

    if (diskList is List) {
      for (final item in diskList) {
        if (item is Map) {
          final m = item.cast<String, dynamic>();
          drives.add(
            DiskDriveInfo(
              model: (m['model'] ?? '').toString(),
              interfaceType: (m['iface'] ?? '').toString(),
              mediaType: (m['media'] ?? '').toString(),
              sizeGb: _toInt(m['gb']),
            ),
          );
        }
      }
    }

    return PcSpecs(cpu: cpu, gpus: gpus, ramModules: ram, drives: drives);
  }

  Future<DiskUsage> _readDiskC() async {
    final command =
        r"$ErrorActionPreference='Stop'; $d=Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DeviceID -eq 'C:' }; Write-Output ([string]$d.Size + '|' + [string]$d.FreeSpace)";

    final result = await shell.run(
      command,
      timeout: const Duration(seconds: 20),
    );

    final output = result.stdout.trim();

    if (result.success && output.isNotEmpty) {
      final parts = output.split('|');
      final total = parts.isNotEmpty ? int.tryParse(parts[0].trim()) ?? 0 : 0;
      final free = parts.length > 1 ? int.tryParse(parts[1].trim()) ?? 0 : 0;

      return DiskUsage(drive: 'C:', totalBytes: total, freeBytes: free);
    }

    return DiskUsage(drive: 'C:', totalBytes: 0, freeBytes: 0);
  }

  int _toInt(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value.toString()) ?? 0;
  }

  Future<void> elevateAndRestart() async {
    if (!Platform.isWindows) {
      return;
    }

    final exe = Platform.resolvedExecutable.replaceAll("'", "''");

    final command = "Start-Process -FilePath '$exe' -Verb RunAs";

    log.warning('Запрошено повышение прав, перезапуск от администратора');

    await shell.runDetachedElevated(command);

    exit(0);
  }
}

class RestorePointService extends ChangeNotifier {
  final PowerShellService shell;
  final LogService log;

  bool busy = false;
  String error = '';

  RestorePointService({
    required this.shell,
    required this.log,
  });

  Future<void> create() async {
    if (busy) {
      return;
    }

    busy = true;
    error = '';
    notifyListeners();

    try {
      final command =
          r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; try { Enable-ComputerRestore -Drive 'C:\' -ErrorAction SilentlyContinue; Checkpoint-Computer -Description 'VeTweek manual' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop; Write-Output 'OK' } catch { [Console]::Error.WriteLine($_.Exception.Message); exit 1 }";

      final result = await shell.run(
        command,
        timeout: const Duration(seconds: 90),
      );

      if (!result.success) {
        throw result.errorOrOutput;
      }

      log.success('Точка восстановления создана');
    } catch (e) {
      error = e.toString();
      log.error('Не удалось создать точку восстановления', error);
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}

class CleanupService extends ChangeNotifier {
  final PowerShellService shell;
  final LogService log;

  bool busy = false;
  String error = '';
  List<BrowserInfo> browsers = [];
  CleanupSelection selection = CleanupSelection();

  CleanupService({
    required this.shell,
    required this.log,
  });

  Future<void> detectBrowsers() async {
    try {
      final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';
      final appData = Platform.environment['APPDATA'] ?? '';

      final candidates = <BrowserInfo>[
        BrowserInfo(
          id: 'chrome',
          displayName: 'Google Chrome',
          cachePaths: [
            '$localAppData\\Google\\Chrome\\User Data\\*\\Cache',
            '$localAppData\\Google\\Chrome\\User Data\\*\\Code Cache',
            '$localAppData\\Google\\Chrome\\User Data\\*\\GPUCache',
          ],
        ),
        BrowserInfo(
          id: 'edge',
          displayName: 'Microsoft Edge',
          cachePaths: [
            '$localAppData\\Microsoft\\Edge\\User Data\\*\\Cache',
            '$localAppData\\Microsoft\\Edge\\User Data\\*\\Code Cache',
            '$localAppData\\Microsoft\\Edge\\User Data\\*\\GPUCache',
          ],
        ),
        BrowserInfo(
          id: 'firefox',
          displayName: 'Mozilla Firefox',
          cachePaths: [
            '$localAppData\\Mozilla\\Firefox\\Profiles\\*\\cache2',
          ],
        ),
        BrowserInfo(
          id: 'opera',
          displayName: 'Opera',
          cachePaths: [
            '$appData\\Opera Software\\Opera Stable\\Cache',
            '$appData\\Opera Software\\Opera Stable\\Code Cache',
          ],
        ),
        BrowserInfo(
          id: 'brave',
          displayName: 'Brave',
          cachePaths: [
            '$localAppData\\BraveSoftware\\Brave-Browser\\User Data\\*\\Cache',
            '$localAppData\\BraveSoftware\\Brave-Browser\\User Data\\*\\Code Cache',
          ],
        ),
      ];

      final found = <BrowserInfo>[];

      for (final browser in candidates) {
        bool exists = false;

        for (final path in browser.cachePaths) {
          final parent = _parentFromPattern(path);

          if (parent.isNotEmpty && await Directory(parent).exists()) {
            exists = true;
            break;
          }
        }

        if (exists) {
          found.add(browser);
        }
      }

      browsers = found;
      notifyListeners();
    } catch (e) {
      error = e.toString();
      notifyListeners();
    }
  }

  String _parentFromPattern(String path) {
    final wildcard = path.indexOf('\\*\\');

    if (wildcard != -1) {
      return path.substring(0, wildcard);
    }

    if (path.endsWith('\\*')) {
      return path.substring(0, path.length - 2);
    }

    return path;
  }

  void setSelection(CleanupSelection value) {
    selection = value;
    notifyListeners();
  }

  void toggleBrowser(String id, bool value) {
    for (final browser in browsers) {
      if (browser.id == id) {
        browser.selected = value;
      }
    }

    notifyListeners();
  }

  void selectAllBrowsers(bool value) {
    selection.allBrowsers = value;

    for (final browser in browsers) {
      browser.selected = value;
    }

    notifyListeners();
  }

  Future<String> runCleanup() async {
    if (busy) {
      return 'Очистка уже выполняется';
    }

    busy = true;
    error = '';
    notifyListeners();

    final buffer = StringBuffer();
    var freed = 0;

    try {
      if (selection.tempUser) {
        freed += await _clearPath(
          Platform.environment['TEMP'] ?? '',
          buffer,
          'Временные файлы пользователя',
        );
      }

      if (selection.tempSystem) {
        freed += await _clearPath(
          r'C:\Windows\Temp',
          buffer,
          'Временные файлы системы',
        );
      }

      if (selection.updateLogs) {
        freed += await _clearPath(
          r'C:\Windows\SoftwareDistribution\Download',
          buffer,
          'Загрузки обновлений',
        );
      }

      if (selection.recycleBin) {
        freed += await _clearRecycleBin(buffer);
      }

      if (selection.allBrowsers) {
        for (final browser in browsers) {
          if (browser.selected) {
            for (final path in browser.cachePaths) {
              freed += await _clearGlob(path, buffer, browser.displayName);
            }
          }
        }
      }

      log.success(
        'Очистка завершена',
        'Освобождено примерно: ${formatBytesStatic(freed)}',
      );
    } catch (e) {
      error = e.toString();
      log.error('Ошибка очистки', error);
    } finally {
      busy = false;
      notifyListeners();
    }

    if (error.isNotEmpty) {
      return 'Ошибки: $error';
    }

    return 'Очищено. Освобождено примерно ${formatBytesStatic(freed)}.';
  }

  Future<int> _clearPath(String path, StringBuffer buffer, String label) async {
    if (path.isEmpty || !await Directory(path).exists()) {
      buffer.writeln('$label: путь не найден');
      return 0;
    }

    final before = await _dirSize(path);
    final result = await shell.run(
      "\$ErrorActionPreference='SilentlyContinue'; Remove-Item -Path ${psQuote('$path\\*')} -Recurse -Force -ErrorAction SilentlyContinue; Write-Output 'OK'",
      timeout: const Duration(minutes: 3),
    );

    final after = await _dirSize(path);
    final freed = before > after ? before - after : 0;

    buffer.writeln('$label: ${result.success ? 'очищено' : 'ошибка'}');

    return freed;
  }

  Future<int> _clearGlob(
    String pattern,
    StringBuffer buffer,
    String label,
  ) async {
    final result = await shell.run(
      "\$ErrorActionPreference='SilentlyContinue'; Get-ChildItem -Path ${psQuote(pattern)} -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue; Write-Output 'OK'",
      timeout: const Duration(minutes: 3),
    );

    buffer.writeln('$label: ${result.success ? 'кэш очищен' : 'ошибка'}');

    return 0;
  }

  Future<int> _clearRecycleBin(StringBuffer buffer) async {
    final result = await shell.run(
      r"$ErrorActionPreference='SilentlyContinue'; Clear-RecycleBin -Force -ErrorAction SilentlyContinue; Write-Output 'OK'",
      timeout: const Duration(minutes: 3),
    );

    buffer.writeln('Корзина: ${result.success ? 'очищена' : 'ошибка'}');

    return 0;
  }

  Future<int> _dirSize(String path) async {
    try {
      final result = await shell.run(
        "\$ErrorActionPreference='SilentlyContinue'; (Get-ChildItem -Path ${psQuote(path)} -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum",
        timeout: const Duration(seconds: 30),
      );

      return int.tryParse(result.stdout.trim()) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  static String formatBytesStatic(int bytes) {
    if (bytes <= 0) {
      return '0 Б';
    }

    const units = ['Б', 'КБ', 'МБ', 'ГБ', 'ТБ'];
    double size = bytes.toDouble();
    int unitIndex = 0;

    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }

    final text = size >= 100 ? size.toStringAsFixed(0) : size.toStringAsFixed(1);

    return '$text ${units[unitIndex]}';
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
      case RegValueType.expandString:
        return 'ExpandString';
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

  Future<List<RegRead>> readMany(List<RegistryOp> ops) async {
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
      return List<RegRead>.generate(ops.length, (_) => RegRead.missing());
    }

    final decoded = jsonDecode(output);
    final list = decoded is List ? decoded : [decoded];

    final reads = List<RegRead>.generate(
      ops.length,
      (_) => RegRead.missing(),
    );

    for (final item in list) {
      if (item is Map<String, dynamic>) {
        final index = int.tryParse(item['i'].toString()) ?? -1;
        final state = (item['s'] ?? '').toString().toUpperCase();
        final value = (item['v'] ?? '').toString();

        if (index >= 0 && index < reads.length) {
          if (state == 'MISSING') {
            reads[index] = RegRead.missing();
          } else if (state == 'NULL') {
            reads[index] = RegRead.nullValue();
          } else {
            reads[index] = RegRead.found(value);
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

    return "\$ErrorActionPreference='Stop'; \$k=[Microsoft.Win32.Registry]::$hive.OpenSubKey($key,\$true); if(\$k){ \$k.DeleteValue($name,\$false); \$k.Close() }";
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

    return "\$ErrorActionPreference='Stop'; [Microsoft.Win32.Registry]::$hive.DeleteSubKeyTree($key,\$false)";
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

class RegRead {
  final bool missing;
  final bool isNull;
  final String value;

  const RegRead({
    required this.missing,
    required this.isNull,
    this.value = '',
  });

  factory RegRead.missing() {
    return const RegRead(missing: true, isNull: false);
  }

  factory RegRead.nullValue() {
    return const RegRead(missing: false, isNull: true);
  }

  factory RegRead.found(String value) {
    return RegRead(missing: false, isNull: false, value: value);
  }
}

class TweakEngine extends ChangeNotifier {
  final PowerShellService shell;
  final RegistryService registry;
  final LogService log;
  final StateService state;

  final Map<String, TweakStatus> _statuses = {};
  final Map<String, String> _errors = {};
  final Map<String, List<Object?>> _backups = {};
  final Set<String> _runningIds = {};

  DateTime? _lastFullRefresh;

  TweakEngine({
    required this.shell,
    required this.registry,
    required this.log,
    required this.state,
  }) {
    state.tweakStatuses.forEach((id, value) {
      final status = TweakStatus.values.firstWhere(
        (s) => s.name == value,
        orElse: () => TweakStatus.unknown,
      );
      _statuses[id] = status;
    });

    _errors.addAll(state.tweakErrors);

    state.tweakBackups.forEach((id, value) {
      if (value is List) {
        _backups[id] = value.cast<Object?>();
      }
    });

    _lastFullRefresh = state.lastCheckTime;
  }

  TweakStatus statusOf(String id) => _statuses[id] ?? TweakStatus.unknown;

  String errorFor(String id) => _errors[id] ?? '';

  bool isBusy(String id) => _runningIds.contains(id);

  bool get anyBusy => _runningIds.isNotEmpty;

  void _setStatus(String id, TweakStatus status) {
    _statuses[id] = status;
    state.setTweakStatus(id, status);
    notifyListeners();
  }

  void _setError(String id, String message) {
    if (message.isEmpty) {
      _errors.remove(id);
    } else {
      _errors[id] = message;
    }

    state.setTweakError(id, message);
    notifyListeners();
  }

  Future<void> refresh(Tweak tweak) async {
    try {
      if (tweak is RegistryTweakWrapper) {
        await _refreshRegistry(tweak.tweak);
      } else if (tweak is CommandTweakWrapper) {
        await _refreshCommand(tweak.tweak);
      }

      _setError(tweak.id, '');
    } catch (e) {
      _setError(tweak.id, e.toString());
      _setStatus(tweak.id, TweakStatus.error);
      log.error('Ошибка чтения статуса твика', '${tweak.title}: $e');
    }
  }

  Future<void> refreshAll(List<Tweak> tweaks, {bool force = false}) async {
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
    state.markChecked();
    await state.save();
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
      _setStatus(tweak.id, TweakStatus.applied);
    } else if (reverted == tweak.ops.length) {
      _setStatus(tweak.id, TweakStatus.notApplied);
    } else {
      _setStatus(tweak.id, TweakStatus.partial);
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
      _setStatus(tweak.id, TweakStatus.applied);
    } else if (tweak.notAppliedToken != null &&
        out.contains(tweak.notAppliedToken!)) {
      _setStatus(tweak.id, TweakStatus.notApplied);
    } else if (tweak.notAppliedToken == null) {
      _setStatus(tweak.id, TweakStatus.notApplied);
    } else {
      _setStatus(tweak.id, TweakStatus.unknown);
    }
  }

  bool _isAbsent(RegRead read) {
    return read.missing || read.isNull;
  }

  bool _matchesValue(RegistryOp op, RegRead read, Object? expected) {
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

  bool _matchesBackup(RegistryOp op, RegRead read, Object? backupValue) {
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

  bool _isApplied(RegistryOp op, RegRead read) {
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
    RegRead read,
    Object? backupValue,
    bool hasBackup,
  ) {
    if (hasBackup) {
      return _matchesBackup(op, read, backupValue);
    }

    return _isRevertedByDefinition(op, read);
  }

  bool _isRevertedByDefinition(RegistryOp op, RegRead read) {
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

  Object? _serializableFromRead(RegistryOp op, RegRead read) {
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
    _setError(tweak.id, '');
    notifyListeners();

    try {
      if (tweak is RegistryTweakWrapper) {
        await _applyRegistry(tweak.tweak);
      } else if (tweak is CommandTweakWrapper) {
        await _applyCommand(tweak.tweak);
      }

      log.success('Твик применен', tweak.title);
      await refresh(tweak);
      await state.save();
    } catch (e) {
      _setError(tweak.id, e.toString());
      _setStatus(tweak.id, TweakStatus.error);
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
    _setError(tweak.id, '');
    notifyListeners();

    try {
      if (tweak is RegistryTweakWrapper) {
        await _revertRegistry(tweak.tweak);
      } else if (tweak is CommandTweakWrapper) {
        await _revertCommand(tweak.tweak);
      }

      log.success('Твик откачен', tweak.title);
      await refresh(tweak);
      await state.save();
    } catch (e) {
      _setError(tweak.id, e.toString());
      _setStatus(tweak.id, TweakStatus.error);
      log.error('Не удалось откатить твик', '${tweak.title}: $e');
      rethrow;
    } finally {
      _runningIds.remove(tweak.id);
      notifyListeners();
    }
  }

  Future<void> revertAll(List<Tweak> tweaks) async {
    for (final tweak in tweaks) {
      if (!tweak.reversible) {
        continue;
      }

      final status = statusOf(tweak.id);

      if (status != TweakStatus.applied && status != TweakStatus.partial) {
        continue;
      }

      try {
        await revert(tweak);
      } catch (_) {
        continue;
      }
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
    state.setTweakBackup(tweak.id, originals);
    await state.save();
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
            if (op.revertValue != null) {
              await registry.write(op, op.revertValue);
            } else if (op.isDefault) {
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
    if (tweak.id == 'explorer.arrow') {
      await _writeEmptyIcon();
    }

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

  Future<void> _writeEmptyIcon() async {
    final directory = Directory(
      '${AppPaths.baseDirectory()}${Platform.pathSeparator}VeTweek',
    );

    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    final bytes = <int>[
      0x00,
      0x00,
      0x01,
      0x00,
      0x01,
      0x00,
      0x01,
      0x02,
      0x00,
      0x00,
      0x01,
      0x00,
      0x20,
      0x00,
      0x30,
      0x00,
      0x00,
      0x00,
      0x16,
      0x00,
      0x00,
      0x00,
      0x28,
      0x00,
      0x00,
      0x00,
      0x01,
      0x00,
      0x00,
      0x00,
      0x02,
      0x00,
      0x00,
      0x00,
      0x01,
      0x00,
      0x20,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x30,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
    ];

    final file = File(
      '${directory.path}${Platform.pathSeparator}empty.ico',
    );

    await file.writeAsBytes(bytes, flush: true);
  }
}