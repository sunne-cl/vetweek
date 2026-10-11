import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:vetweek/models.dart';
import 'package:vetweek/services/base.dart';
import 'package:vetweek/services/system.dart';

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
    'Microsoft.549981C3F5F10',
    'Microsoft.BingWeather',
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

class StartupService extends ChangeNotifier {
  final PowerShellService shell;
  final LogService log;
  final RegistryService registry;
  final StateService state;

  List<StartupEntry> entries = [];
  List<StartupEntry> extendedEntries = [];
  bool busy = false;
  String error = '';

  StartupService({
    required this.shell,
    required this.log,
    required this.registry,
    required this.state,
  });

  bool get hasBackups => state.startupBackups.isNotEmpty;

  Future<void> loadNormal() async {
    await _load(false);
  }

  Future<void> loadExtended() async {
    await _load(true);
  }

  Future<void> _load(bool extended) async {
    if (busy) {
      return;
    }

    busy = true;
    error = '';
    notifyListeners();

    try {
      final paths = <String>[
        r'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
        r'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
      ];

      if (extended) {
        paths.addAll([
          r'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce',
          r'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
          r'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon',
        ]);
      }

      final buffer = StringBuffer();
      buffer.write(
        r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; $res=New-Object System.Collections.Generic.List[object]; $paths=@(",
      );

      for (var i = 0; i < paths.length; i++) {
        buffer.write(psQuote(paths[i]));
        if (i < paths.length - 1) {
          buffer.write(',');
        }
      }

      buffer.write(
        r"); foreach($p in $paths){ if(Test-Path $p){ $item=Get-ItemProperty -Path $p; foreach($prop in $item.PSObject.Properties){ if($prop.Name -notin @('PSPath','PSParentPath','PSChildName','PSDrive','PSProvider')){ if($p -like '*Winlogon*' -and $prop.Name -notin @('Userinit','Shell')){ continue }; $hive=if($p -like 'HKCU:*'){'HKCU'}else{'HKLM'}; $scope=if($p -like '*RunOnce*'){'RunOnce'}elseif($p -like '*Winlogon*'){'Winlogon'}else{'Run'}; $critical=($p -like '*Winlogon*'); $res.Add([pscustomobject]@{hive=$hive;key=$p;name=$prop.Name;data=[string]$prop.Value;scope=$scope;critical=$critical}) } } } }; ($res | ConvertTo-Json -Compress -Depth 3)",
      );

      final result = await shell.run(
        buffer.toString(),
        timeout: const Duration(seconds: 35),
      );

      if (!result.success) {
        throw result.errorOrOutput;
      }

      final output = result.stdout.trim();
      final parsed = <StartupEntry>[];

      if (output.isNotEmpty && output != '[]') {
        final decoded = jsonDecode(output);
        final list = decoded is List ? decoded : [decoded];

        for (final item in list) {
          if (item is Map<String, dynamic>) {
            parsed.add(
              StartupEntry(
                hive: (item['hive'] ?? '').toString(),
                key: (item['key'] ?? '').toString(),
                valueName: (item['name'] ?? '').toString(),
                valueData: (item['data'] ?? '').toString(),
                scope: (item['scope'] ?? '').toString(),
                critical: item['critical'] == true,
              ),
            );
          }
        }
      }

      if (extended) {
        extendedEntries = parsed;
      } else {
        entries = parsed;
      }

      log.info(
        extended ? 'Расширенная автозагрузка загружена' : 'Автозагрузка загружена',
        'Элементов: ${parsed.length}',
      );
    } catch (e) {
      error = e.toString();
      log.error('Ошибка загрузки автозагрузки', error);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  RegistryOp _opFor(StartupEntry entry) {
    final hive = entry.hive == 'HKLM' ? Hive.hklm : Hive.hkcu;
    var key = entry.key;

    if (key.startsWith(r'HKCU:\')) {
      key = key.substring(6);
    } else if (key.startsWith(r'HKLM:\')) {
      key = key.substring(6);
    }

    return RegistryOp(
      hive: hive,
      key: key,
      valueName: entry.valueName,
      type: RegValueType.string,
      applyValue: null,
      applyAction: RegAction.deleteValue,
      revertAction: RegAction.setValue,
      revertValue: entry.valueData,
    );
  }

  Future<void> delete(StartupEntry entry) async {
    state.setStartupBackup(entry.uniqueId, entry.valueData);
    await state.save();

    await registry.deleteValue(_opFor(entry));

    entries.removeWhere((e) => e.uniqueId == entry.uniqueId);
    extendedEntries.removeWhere((e) => e.uniqueId == entry.uniqueId);

    log.warning('Запись автозагрузки удалена', '${entry.valueName}: ${entry.valueData}');
    notifyListeners();
  }

  Future<String> restoreAll() async {
    final backups = Map<String, Object?>.from(state.startupBackups);

    if (backups.isEmpty) {
      return 'Нет резервных копий автозагрузки';
    }

    var restored = 0;
    var failed = 0;

    for (final item in backups.entries) {
      final parts = item.key.split('|');

      if (parts.length < 3) {
        failed++;
        continue;
      }

      final hive = parts[0] == 'HKLM' ? Hive.hklm : Hive.hkcu;
      final key = parts.sublist(1, parts.length - 1).join('|');
      final name = parts.last;
      final data = item.value?.toString() ?? '';

      final op = RegistryOp(
        hive: hive,
        key: key,
        valueName: name,
        type: RegValueType.string,
        applyValue: data,
        applyAction: RegAction.setValue,
        revertAction: RegAction.deleteValue,
      );

      try {
        await registry.write(op, data);
        state.removeStartupBackup(item.key);
        restored++;
      } catch (_) {
        failed++;
      }
    }

    await state.save();
    await loadNormal();
    await loadExtended();

    return 'Восстановлено: $restored, ошибок: $failed';
  }
}

class WingetService extends ChangeNotifier {
  final PowerShellService shell;
  final LogService log;
  final SystemService system;

  bool busy = false;
  String error = '';
  String lastMessage = '';

  WingetService({
    required this.shell,
    required this.log,
    required this.system,
  });

  Future<void> upgradeAll() async {
    if (busy) {
      return;
    }

    busy = true;
    error = '';
    lastMessage = '';
    notifyListeners();

    try {
      if (system.isAdmin) {
        final result = await shell.run(
          r"winget upgrade --all --accept-source-agreements --accept-package-agreements",
          timeout: const Duration(minutes: 15),
        );

        if (!result.success) {
          throw result.errorOrOutput;
        }

        lastMessage = result.stdout.trim();
        log.success('winget upgrade --all выполнен', lastMessage);
      } else {
        final command =
            "Start-Process -FilePath 'powershell.exe' -ArgumentList '-NoProfile','-WindowStyle','Hidden','-Command','winget upgrade --all --accept-source-agreements --accept-package-agreements' -Verb RunAs";

        await shell.runDetachedElevated(command);

        lastMessage = 'Запрошено повышение для winget upgrade --all';
        log.warning(lastMessage);
      }
    } catch (e) {
      error = e.toString();
      log.error('Ошибка winget upgrade --all', error);
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}

class _ComponentDef {
  final String id;
  final String displayName;
  final String featureName;
  final String warning;

  const _ComponentDef({
    required this.id,
    required this.displayName,
    required this.featureName,
    required this.warning,
  });
}

class DevService extends ChangeNotifier {
  final PowerShellService shell;
  final LogService log;
  final RegistryService registry;
  final StateService state;
  final SystemService system;
  final StartupService startup;

  static const List<_ComponentDef> _componentDefs = [
    _ComponentDef(
      id: 'wsl',
      displayName: 'Windows Subsystem for Linux',
      featureName: 'Microsoft-Windows-Subsystem-Linux',
      warning: 'Требует перезагрузки. Может потребоваться включение виртуализации в BIOS/UEFI.',
    ),
    _ComponentDef(
      id: 'vmp',
      displayName: 'Virtual Machine Platform',
      featureName: 'VirtualMachinePlatform',
      warning: 'Требует перезагрузки. Нужен для WSL2 и некоторых гипервизоров.',
    ),
    _ComponentDef(
      id: 'hyperv',
      displayName: 'Hyper-V',
      featureName: 'Microsoft-Hyper-V-All',
      warning: 'Доступен не во всех редакциях Windows. Требует перезагрузки и может конфликтовать с другими гипервизорами.',
    ),
  ];

  List<WindowsComponentState> components = [];
  List<PathEntry> userPath = [];
  List<PathEntry> systemPath = [];
  bool devModeEnabled = false;
  bool loaded = false;
  bool busy = false;
  String error = '';

  DevService({
    required this.shell,
    required this.log,
    required this.registry,
    required this.state,
    required this.system,
    required this.startup,
  });

  Future<void> refreshAll() async {
    await refreshComponents();
    await refreshPaths();
    await refreshDevMode();
    loaded = true;
    notifyListeners();
  }

  Future<void> refreshComponents() async {
    if (busy) {
      return;
    }

    busy = true;
    error = '';
    notifyListeners();

    try {
      if (!system.isAdmin) {
        components = _componentDefs
            .map(
              (def) => WindowsComponentState(
                featureName: def.featureName,
                displayName: def.displayName,
                state: 'Требуются права администратора',
                requiresAdmin: true,
                rebootRequired: true,
                warning: def.warning,
              ),
            )
            .toList();
        return;
      }

      final buffer = StringBuffer();
      buffer.write(
        r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; $res=New-Object System.Collections.Generic.List[object]; $features=@(",
      );

      for (var i = 0; i < _componentDefs.length; i++) {
        buffer.write(psQuote(_componentDefs[i].featureName));
        if (i < _componentDefs.length - 1) {
          buffer.write(',');
        }
      }

      buffer.write(
        r"); foreach($f in $features){ try { $state=(Get-WindowsOptionalFeature -Online -FeatureName $f -ErrorAction Stop).State } catch { $state='UNKNOWN' }; $res.Add([pscustomobject]@{feature=$f;state=$state}) }; ($res | ConvertTo-Json -Compress -Depth 3)",
      );

      final result = await shell.run(
        buffer.toString(),
        timeout: const Duration(seconds: 45),
      );

      if (!result.success) {
        throw result.errorOrOutput;
      }

      final output = result.stdout.trim();
      final states = <String, String>{};

      if (output.isNotEmpty && output != '[]') {
        final decoded = jsonDecode(output);
        final list = decoded is List ? decoded : [decoded];

        for (final item in list) {
          if (item is Map<String, dynamic>) {
            states[(item['feature'] ?? '').toString()] =
                (item['state'] ?? '').toString();
          }
        }
      }

      components = _componentDefs
          .map(
            (def) => WindowsComponentState(
              featureName: def.featureName,
              displayName: def.displayName,
              state: states[def.featureName] ?? 'UNKNOWN',
              requiresAdmin: true,
              rebootRequired: true,
              warning: def.warning,
            ),
          )
          .toList();
    } catch (e) {
      error = e.toString();
      log.error('Ошибка чтения компонентов Windows', error);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> enableComponent(String featureName) async {
    await _setComponent(featureName, true);
  }

  Future<void> disableComponent(String featureName) async {
    await _setComponent(featureName, false);
  }

  Future<void> _setComponent(String featureName, bool enable) async {
    if (busy) {
      return;
    }

    busy = true;
    error = '';
    notifyListeners();

    try {
      final def = _componentDefs.firstWhere((d) => d.featureName == featureName);
      final current = components.firstWhere(
        (c) => c.featureName == featureName,
        orElse: () => WindowsComponentState(
          featureName: featureName,
          displayName: def.displayName,
          state: 'UNKNOWN',
          requiresAdmin: true,
          rebootRequired: true,
          warning: def.warning,
        ),
      );

      _backupDev('component.${def.id}', current.state);

      final action = enable ? 'Enable' : 'Disable';
      final command =
          "\$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; $action-WindowsOptionalFeature -Online -FeatureName ${psQuote(featureName)} -All -NoRestart; Write-Output 'OK'";

      final result = await shell.run(
        command,
        timeout: const Duration(minutes: 10),
      );

      if (!result.success) {
        throw result.errorOrOutput;
      }

      log.success(
        enable ? 'Компонент включен' : 'Компонент отключен',
        '$featureName. Требуется перезагрузка.',
      );

      await refreshComponents();
    } catch (e) {
      error = e.toString();
      log.error('Ошибка изменения компонента Windows', error);
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> refreshPaths() async {
    try {
      final command =
          r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; $u=[Environment]::GetEnvironmentVariable('Path','User'); $m=[Environment]::GetEnvironmentVariable('Path','Machine'); [pscustomobject]@{user=$u;machine=$m} | ConvertTo-Json -Compress";

      final result = await shell.run(
        command,
        timeout: const Duration(seconds: 25),
      );

      if (!result.success) {
        throw result.errorOrOutput;
      }

      final data = jsonDecode(result.stdout.trim()) as Map<String, dynamic>;
      final user = (data['user'] ?? '').toString();
      final machine = (data['machine'] ?? '').toString();

      userPath = _parsePath(user);
      systemPath = _parsePath(machine);

      notifyListeners();
    } catch (e) {
      error = e.toString();
      notifyListeners();
    }
  }

  List<PathEntry> _parsePath(String value) {
    if (value.trim().isEmpty) {
      return [];
    }

    return value
        .split(';')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .map(
          (e) => PathEntry(
            value: e,
            exists: FileSystemEntity.typeSync(e) != FileSystemEntityType.notFound,
          ),
        )
        .toList();
  }

  Future<void> addPath(String target, String path) async {
    final clean = path.trim();

    if (clean.isEmpty) {
      return;
    }

    final list = target == 'Machine' ? List<String>.from(systemPath.map((e) => e.value)) : List<String>.from(userPath.map((e) => e.value));

    if (list.any((e) => e.toLowerCase() == clean.toLowerCase())) {
      return;
    }

    list.add(clean);
    await setPath(target, list.join(';'));
  }

  Future<void> removePath(String target, int index) async {
    final list = target == 'Machine'
        ? List<String>.from(systemPath.map((e) => e.value))
        : List<String>.from(userPath.map((e) => e.value));

    if (index < 0 || index >= list.length) {
      return;
    }

    list.removeAt(index);
    await setPath(target, list.join(';'));
  }

  Future<void> movePath(String target, int index, int delta) async {
    final list = target == 'Machine'
        ? List<String>.from(systemPath.map((e) => e.value))
        : List<String>.from(userPath.map((e) => e.value));

    final newIndex = index + delta;

    if (index < 0 || index >= list.length) {
      return;
    }

    if (newIndex < 0 || newIndex >= list.length) {
      return;
    }

    final value = list.removeAt(index);
    list.insert(newIndex, value);

    await setPath(target, list.join(';'));
  }

  Future<void> setPath(String target, String value) async {
    if (busy) {
      return;
    }

    if (target == 'Machine' && !system.isAdmin) {
      throw 'Для системного PATH нужны права администратора';
    }

    busy = true;
    error = '';
    notifyListeners();

    try {
      _backupDev('path.$target', target == 'Machine' ? systemPath.map((e) => e.value).join(';') : userPath.map((e) => e.value).join(';'));

      final command =
          "\$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; [Environment]::SetEnvironmentVariable('Path', ${psQuote(value)}, ${psQuote(target == 'Machine' ? 'Machine' : 'User')}); Write-Output 'OK'";

      final result = await shell.run(
        command,
        timeout: const Duration(seconds: 30),
      );

      if (!result.success) {
        throw result.errorOrOutput;
      }

      log.success('Переменная PATH обновлена', target);
      await refreshPaths();
      await state.save();
    } catch (e) {
      error = e.toString();
      log.error('Ошибка обновления PATH', error);
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> refreshDevMode() async {
    try {
      final op = RegistryOp(
        hive: Hive.hklm,
        key: r'SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock',
        valueName: 'AllowDevelopmentWithoutDevLicense',
        type: RegValueType.dword,
        applyValue: 1,
        applyAction: RegAction.setValue,
        revertAction: RegAction.setValue,
        revertValue: 0,
      );

      final reads = await registry.readMany([op]);
      devModeEnabled = reads.first.value == '1';
      notifyListeners();
    } catch (e) {
      error = e.toString();
      notifyListeners();
    }
  }

  Future<void> setDevMode(bool enable) async {
    if (busy) {
      return;
    }

    if (!system.isAdmin) {
      throw 'Для Developer Mode нужны права администратора';
    }

    busy = true;
    error = '';
    notifyListeners();

    try {
      final op = RegistryOp(
        hive: Hive.hklm,
        key: r'SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock',
        valueName: 'AllowDevelopmentWithoutDevLicense',
        type: RegValueType.dword,
        applyValue: enable ? 1 : 0,
        applyAction: RegAction.setValue,
        revertAction: RegAction.setValue,
        revertValue: enable ? 0 : 1,
      );

      final reads = await registry.readMany([op]);
      _backupDev('devmode', reads.first.value.isEmpty ? '__MISSING__' : reads.first.value);

      await registry.write(op, enable ? 1 : 0);

      log.success(
        enable ? 'Developer Mode включен' : 'Developer Mode отключен',
        'Может потребоваться перезагрузка или подтверждение в Параметрах.',
      );

      await refreshDevMode();
      await state.save();
    } catch (e) {
      error = e.toString();
      log.error('Ошибка Developer Mode', error);
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> openDevSettings() async {
    await shell.run(
      r"Start-Process 'ms-settings:developers'",
      timeout: const Duration(seconds: 15),
    );
  }

  void _backupDev(String key, Object? value) {
    if (state.getDevBackup(key) == null) {
      state.setDevBackup(key, value);
    }
  }

  Future<String> rollback() async {
    if (busy) {
      return 'Откат уже выполняется';
    }

    busy = true;
    error = '';
    notifyListeners();

    var ok = 0;
    var failed = 0;

    try {
      final pathUser = state.getDevBackup('path.User');
      if (pathUser != null) {
        await setPath('User', pathUser.toString());
        ok++;
      }

      final pathMachine = state.getDevBackup('path.Machine');
      if (pathMachine != null && system.isAdmin) {
        await setPath('Machine', pathMachine.toString());
        ok++;
      }

      final devMode = state.getDevBackup('devmode');
      if (devMode != null && system.isAdmin) {
        final op = RegistryOp(
          hive: Hive.hklm,
          key: r'SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock',
          valueName: 'AllowDevelopmentWithoutDevLicense',
          type: RegValueType.dword,
          applyValue: devMode == '__MISSING__' ? 0 : devMode,
          applyAction: RegAction.setValue,
          revertAction: RegAction.deleteValue,
        );

        if (devMode == '__MISSING__') {
          await registry.deleteValue(op);
        } else {
          await registry.write(op, devMode);
        }

        ok++;
      }

      for (final def in _componentDefs) {
        final backup = state.getDevBackup('component.${def.id}');

        if (backup == null) {
          continue;
        }

        final current = components.firstWhere(
          (c) => c.featureName == def.featureName,
          orElse: () => WindowsComponentState(
            featureName: def.featureName,
            displayName: def.displayName,
            state: 'UNKNOWN',
            requiresAdmin: true,
            rebootRequired: true,
            warning: def.warning,
          ),
        );

        if (backup.toString().toUpperCase().contains('DISABLED') &&
            current.enabled) {
          await disableComponent(def.featureName);
          ok++;
        } else if (backup.toString().toUpperCase().contains('ENABLED') &&
            !current.enabled) {
          await enableComponent(def.featureName);
          ok++;
        }
      }

      final startupResult = await startup.restoreAll();
      log.info('Откат автозагрузки', startupResult);

      await state.save();
      await refreshAll();

      return 'Откат Dev завершен. Успешно: $ok, ошибок: $failed';
    } catch (e) {
      error = e.toString();
      log.error('Ошибка отката Dev', error);
      return 'Ошибка отката Dev: $error';
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}