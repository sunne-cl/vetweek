import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:vetweek/models.dart';
import 'package:vetweek/services/base.dart';
import 'package:vetweek/services/system.dart';

class GpuItem {
  final String name;
  final String pnpDeviceId;
  final String friendlyName;

  GpuItem({
    required this.name,
    required this.pnpDeviceId,
    required this.friendlyName,
  });

  String get displayName => friendlyName.isNotEmpty ? friendlyName : name;
}

class ExperimentsService extends ChangeNotifier {
  final PowerShellService shell;
  final LogService log;
  final RegistryService registry;
  final StateService state;
  final SystemService system;

  bool busy = false;
  String error = '';
  bool checked = false;

  bool showFrequent = true;
  bool showRecent = true;
  bool autoCheck = false;
  bool confirmDelete = true;
  bool stickyKeysOff = false;
  bool hvciOff = false;
  bool uacOff = false;
  bool verboseStatus = false;
  bool endTask = false;
  bool quietBoot = false;
  bool bootuxDisabled = false;
  bool swapMouse = false;
  bool crashOnCtrlScroll = false;
  bool lockBlurOff = false;
  bool transparencyOff = false;
  int noDrivesMask = 0;
  String namingTemplate = '';
  String hilightColor = '';

  List<GpuItem> gpus = [];
  String cpuName = '';
  int tempBytes = 0;
  int pipBytes = 0;
  int thumbBytes = 0;

  ExperimentsService({
    required this.shell,
    required this.log,
    required this.registry,
    required this.state,
    required this.system,
  });

  RegistryOp _op(
    Hive hive,
    String key,
    String valueName,
    RegValueType type,
  ) {
    return RegistryOp(
      hive: hive,
      key: key,
      valueName: valueName,
      type: type,
      applyValue: null,
      applyAction: RegAction.setValue,
      revertAction: RegAction.deleteValue,
    );
  }

  Future<void> refresh() async {
    if (busy) {
      return;
    }

    busy = true;
    error = '';
    notifyListeners();

    try {
      const advanced = r'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced';

      final reads = await registry.readMany([
        _op(Hive.hkcu, advanced, 'ShowFrequent', RegValueType.dword),
        _op(Hive.hkcu, advanced, 'ShowRecent', RegValueType.dword),
        _op(Hive.hkcu, advanced, 'AutoCheckSelect', RegValueType.dword),
        _op(
          Hive.hkcu,
          r'Software\Microsoft\Windows\CurrentVersion\Policies\Explorer',
          'ConfirmFileDelete',
          RegValueType.dword,
        ),
        _op(
          Hive.hkcu,
          r'Control Panel\Accessibility\StickyKeys',
          'Flags',
          RegValueType.string,
        ),
        _op(
          Hive.hklm,
          r'SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity',
          'Enabled',
          RegValueType.dword,
        ),
        _op(
          Hive.hklm,
          r'SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System',
          'EnableLUA',
          RegValueType.dword,
        ),
        _op(
          Hive.hklm,
          r'SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System',
          'VerboseStatus',
          RegValueType.dword,
        ),
        _op(Hive.hkcu, advanced, 'TaskbarEndTask', RegValueType.dword),
        _op(
          Hive.hkcu,
          r'Control Panel\Mouse',
          'SwapMouseButtons',
          RegValueType.string,
        ),
        _op(
          Hive.hklm,
          r'SYSTEM\CurrentControlSet\Services\kbdhid\Parameters',
          'CrashOnCtrlScroll',
          RegValueType.dword,
        ),
        _op(
          Hive.hklm,
          r'SOFTWARE\Policies\Microsoft\Windows\System',
          'DisableAcrylicBlurOnLockScreen',
          RegValueType.dword,
        ),
        _op(
          Hive.hkcu,
          r'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize',
          'EnableTransparency',
          RegValueType.dword,
        ),
        _op(
          Hive.hkcu,
          r'Software\Microsoft\Windows\CurrentVersion\Policies\Explorer',
          'NoDrives',
          RegValueType.dword,
        ),
        _op(
          Hive.hkcu,
          r'Software\Microsoft\Windows\CurrentVersion\Explorer\NamingTemplates',
          'RenameNameTemplate',
          RegValueType.string,
        ),
        _op(Hive.hkcu, r'Control Panel\Colors', 'Hilight', RegValueType.string),
      ]);

      showFrequent = !_isZero(reads[0]);
      showRecent = !_isZero(reads[1]);
      autoCheck = _isOne(reads[2]);
      confirmDelete = reads[3].missing || reads[3].isNull ? true : _isOne(reads[3]);
      stickyKeysOff = reads[4].value == '506';
      hvciOff = reads[5].value == '0';
      uacOff = reads[6].value == '0';
      verboseStatus = _isOne(reads[7]);
      endTask = _isOne(reads[8]);
      swapMouse = reads[9].value == '1';
      crashOnCtrlScroll = _isOne(reads[10]);
      lockBlurOff = _isOne(reads[11]);
      transparencyOff = reads[12].value == '0';
      noDrivesMask = int.tryParse(reads[13].value) ?? 0;
      namingTemplate =
          reads[14].missing || reads[14].isNull ? '' : reads[14].value;
      hilightColor = reads[15].missing || reads[15].isNull ? '' : reads[15].value;

      final bcd = await shell.run(
        r"$ErrorActionPreference='SilentlyContinue'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; (bcdedit /enum '{current}') -join ' '",
        timeout: const Duration(seconds: 20),
      );

      if (bcd.success) {
        final text = bcd.stdout;
        quietBoot = RegExp(r'quietboot\s+Yes', caseSensitive: false).hasMatch(text);
        bootuxDisabled =
            RegExp(r'bootux\s+Disabled', caseSensitive: false).hasMatch(text);
      }

      final gpuResult = await shell.run(
        r"$ErrorActionPreference='SilentlyContinue'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; $list=New-Object System.Collections.Generic.List[object]; foreach ($v in (Get-CimInstance Win32_VideoController)) { $friendly=''; $prop=Get-ItemProperty -Path ('HKLM:\SYSTEM\CurrentControlSet\Enum\' + $v.PNPDeviceID) -Name 'FriendlyName' -ErrorAction SilentlyContinue; if ($prop) { $friendly=[string]$prop.FriendlyName }; $list.Add(@{ name=$v.Name; pnp=$v.PNPDeviceID; friendly=$friendly }) }; $list | ConvertTo-Json -Compress",
        timeout: const Duration(seconds: 30),
      );

      if (gpuResult.success) {
        gpus = _parseGpus(gpuResult.stdout.trim());
      }

      final cpuResult = await shell.run(
        r"$ErrorActionPreference='SilentlyContinue'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; (Get-ItemProperty 'HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0').ProcessorNameString",
        timeout: const Duration(seconds: 20),
      );

      if (cpuResult.success) {
        cpuName = cpuResult.stdout.trim();

        if (cpuName.isNotEmpty && state.getDevBackup('cpu.name') == null) {
          state.setDevBackup('cpu.name', cpuName);
          await state.save();
        }
      }

      tempBytes = await _dirSize(r'$env:TEMP');
      pipBytes = await _dirSize(r'$env:LOCALAPPDATA\pip\cache');
      thumbBytes = await _dirSize(
        r'$env:LOCALAPPDATA\Microsoft\Windows\Explorer',
        'thumbcache_*.db',
      );

      checked = true;
    } catch (e) {
      error = e.toString();
      log.error('Ошибка чтения экспериментов', error);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  bool _isZero(RegRead read) {
    if (read.missing || read.isNull) {
      return false;
    }

    return int.tryParse(read.value) == 0;
  }

  bool _isOne(RegRead read) {
    if (read.missing || read.isNull) {
      return false;
    }

    return int.tryParse(read.value) == 1;
  }

  List<GpuItem> _parseGpus(String output) {
    if (output.isEmpty || output == '[]') {
      return [];
    }

    try {
      final decoded = jsonDecode(output);
      final list = decoded is List ? decoded : [decoded];
      final result = <GpuItem>[];

      for (final item in list) {
        if (item is Map<String, dynamic>) {
          result.add(
            GpuItem(
              name: (item['name'] ?? '').toString(),
              pnpDeviceId: (item['pnp'] ?? '').toString(),
              friendlyName: (item['friendly'] ?? '').toString(),
            ),
          );
        }
      }

      return result;
    } catch (_) {
      return [];
    }
  }

  Future<int> _dirSize(String path, [String filter = '*']) async {
    final command =
        "\$ErrorActionPreference='SilentlyContinue'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; (Get-ChildItem -Path \"$path\" -Filter '$filter' -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum";

    final result = await shell.run(
      command,
      timeout: const Duration(seconds: 60),
    );

    if (!result.success) {
      return 0;
    }

    return int.tryParse(result.stdout.trim()) ?? 0;
  }

  Future<void> _write(
    Hive hive,
    String key,
    String valueName,
    RegValueType type,
    Object? value,
  ) async {
    final op = _op(hive, key, valueName, type);
    await registry.write(op, value);
  }

  Future<void> _delete(Hive hive, String key, String valueName) async {
    final op = _op(hive, key, valueName, RegValueType.dword);
    await registry.deleteValue(op);
  }

  Future<void> _run(String command, String message) async {
    if (busy) {
      return;
    }

    busy = true;
    error = '';
    notifyListeners();

    try {
      final result = await shell.run(
        command,
        timeout: const Duration(minutes: 20),
      );

      if (!result.success) {
        throw result.errorOrOutput;
      }

      log.success(message);
    } catch (e) {
      error = e.toString();
      log.error(message, error);
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> setShowFrequent(bool value) async {
    await _write(
      Hive.hkcu,
      r'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced',
      'ShowFrequent',
      RegValueType.dword,
      value ? 1 : 0,
    );
    log.success('Часто используемые папки: ${value ? 'показаны' : 'скрыты'}');
    await refresh();
  }

  Future<void> setShowRecent(bool value) async {
    await _write(
      Hive.hkcu,
      r'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced',
      'ShowRecent',
      RegValueType.dword,
      value ? 1 : 0,
    );
    log.success('История недавних документов: ${value ? 'включена' : 'отключена'}');
    await refresh();
  }

  Future<void> setAutoCheck(bool value) async {
    await _write(
      Hive.hkcu,
      r'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced',
      'AutoCheckSelect',
      RegValueType.dword,
      value ? 1 : 0,
    );
    log.success('Галочки выбора элементов: ${value ? 'включены' : 'отключены'}');
    await refresh();
  }

  Future<void> setConfirmDelete(bool value) async {
    if (value) {
      await _delete(
        Hive.hkcu,
        r'Software\Microsoft\Windows\CurrentVersion\Policies\Explorer',
        'ConfirmFileDelete',
      );
    } else {
      await _write(
        Hive.hkcu,
        r'Software\Microsoft\Windows\CurrentVersion\Policies\Explorer',
        'ConfirmFileDelete',
        RegValueType.dword,
        0,
      );
    }

    log.success('Подтверждение удаления: ${value ? 'включено' : 'отключено'}');
    await refresh();
  }

  Future<void> setStickyKeysOff(bool value) async {
    await _write(
      Hive.hkcu,
      r'Control Panel\Accessibility\StickyKeys',
      'Flags',
      RegValueType.string,
      value ? '506' : '510',
    );
    log.success('Залипание клавиш: ${value ? 'отключено' : 'включено'}');
    await refresh();
  }

  Future<void> setHvciOff(bool value) async {
    if (value && state.getDevBackup('hvci') == null) {
      state.setDevBackup('hvci', hvciOff ? '0' : '1');
      await state.save();
    }

    await _write(
      Hive.hklm,
      r'SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity',
      'Enabled',
      RegValueType.dword,
      value ? 0 : 1,
    );
    log.warning('Изоляция ядра: ${value ? 'отключена' : 'включена'}');
    await refresh();
  }

  Future<void> setUacOff(bool value) async {
    if (value && state.getDevBackup('uac') == null) {
      state.setDevBackup('uac', uacOff ? '0' : '1');
      await state.save();
    }

    await _write(
      Hive.hklm,
      r'SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System',
      'EnableLUA',
      RegValueType.dword,
      value ? 0 : 1,
    );
    log.warning('UAC: ${value ? 'отключен' : 'включен'}. Требуется перезагрузка');
    await refresh();
  }

  Future<void> setVerboseStatus(bool value) async {
    if (value) {
      await _write(
        Hive.hklm,
        r'SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System',
        'VerboseStatus',
        RegValueType.dword,
        1,
      );
    } else {
      await _delete(
        Hive.hklm,
        r'SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System',
        'VerboseStatus',
      );
    }

    log.success('Подробные сведения о системе: ${value ? 'включены' : 'отключены'}');
    await refresh();
  }

  Future<void> setEndTask(bool value) async {
    await _write(
      Hive.hkcu,
      r'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced',
      'TaskbarEndTask',
      RegValueType.dword,
      value ? 1 : 0,
    );
    log.success('Кнопка «Завершить задачу»: ${value ? 'включена' : 'отключена'}');
    await refresh();
  }

  Future<void> setLockBlurOff(bool value) async {
    if (value) {
      await _write(
        Hive.hklm,
        r'SOFTWARE\Policies\Microsoft\Windows\System',
        'DisableAcrylicBlurOnLockScreen',
        RegValueType.dword,
        1,
      );
    } else {
      await _delete(
        Hive.hklm,
        r'SOFTWARE\Policies\Microsoft\Windows\System',
        'DisableAcrylicBlurOnLockScreen',
      );
    }

    log.success('Размытие на экране блокировки: ${value ? 'отключено' : 'включено'}');
    await refresh();
  }

  Future<void> setTransparencyOff(bool value) async {
    await _write(
      Hive.hkcu,
      r'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize',
      'EnableTransparency',
      RegValueType.dword,
      value ? 0 : 1,
    );
    log.success('Прозрачность: ${value ? 'отключена' : 'включена'}');
    await refresh();
  }

  Future<void> setQuietBoot(bool value) async {
    await _run(
      r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; bcdedit /set '{current}' quietboot " +
          (value ? 'yes' : 'no') +
          r"; Write-Output 'OK'",
      'Логотип Windows в загрузчике: ${value ? 'отключен' : 'включен'}',
    );
    await refresh();
  }

  Future<void> setBootuxDisabled(bool value) async {
    await _run(
      r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; bcdedit /set '{current}' bootux " +
          (value ? 'disabled' : 'standard') +
          r"; Write-Output 'OK'",
      'Анимация загрузчика: ${value ? 'отключена' : 'включена'}',
    );
    await refresh();
  }

  Future<void> setSwapMouse(bool value) async {
    await _write(
      Hive.hkcu,
      r'Control Panel\Mouse',
      'SwapMouseButtons',
      RegValueType.string,
      value ? '1' : '0',
    );
    log.warning('Кнопки мыши: ${value ? 'поменяны' : 'восстановлены'}. Требуется перезагрузка');
    await refresh();
  }

  Future<void> setCrashOnCtrlScroll(bool value) async {
    if (value) {
      await _write(
        Hive.hklm,
        r'SYSTEM\CurrentControlSet\Services\kbdhid\Parameters',
        'CrashOnCtrlScroll',
        RegValueType.dword,
        1,
      );
    } else {
      await _delete(
        Hive.hklm,
        r'SYSTEM\CurrentControlSet\Services\kbdhid\Parameters',
        'CrashOnCtrlScroll',
      );
    }

    log.warning('BSOD по Ctrl+Scroll: ${value ? 'включен' : 'отключен'}. Требуется перезагрузка');
    await refresh();
  }

  Future<void> setNoDrives(int mask) async {
    if (mask == 0) {
      await _delete(
        Hive.hkcu,
        r'Software\Microsoft\Windows\CurrentVersion\Policies\Explorer',
        'NoDrives',
      );
    } else {
      await _write(
        Hive.hkcu,
        r'Software\Microsoft\Windows\CurrentVersion\Policies\Explorer',
        'NoDrives',
        RegValueType.dword,
        mask,
      );
    }

    log.success('Маска скрытия дисков применена: $mask');
    await refresh();
  }

  Future<void> setNamingTemplate(String value) async {
    if (value.isEmpty) {
      await _delete(
        Hive.hkcu,
        r'Software\Microsoft\Windows\CurrentVersion\Explorer\NamingTemplates',
        'RenameNameTemplate',
      );
    } else {
      await _write(
        Hive.hkcu,
        r'Software\Microsoft\Windows\CurrentVersion\Explorer\NamingTemplates',
        'RenameNameTemplate',
        RegValueType.string,
        value,
      );
    }

    log.success('Шаблон имени новых элементов обновлен');
    await refresh();
  }

  Future<void> setHilightColor(String rgb) async {
    if (rgb.isEmpty) {
      await _delete(Hive.hkcu, r'Control Panel\Colors', 'Hilight');
      await _delete(Hive.hkcu, r'Control Panel\Colors', 'HilightText');
    } else {
      await _write(
        Hive.hkcu,
        r'Control Panel\Colors',
        'Hilight',
        RegValueType.string,
        rgb,
      );
      await _write(
        Hive.hkcu,
        r'Control Panel\Colors',
        'HilightText',
        RegValueType.string,
        '255 255 255',
      );
    }

    log.success('Цвет выделения обновлен. Требуется выход из системы');
    await refresh();
  }

  Future<void> renameGpu(String pnpDeviceId, String newName) async {
    await _run(
      r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; Set-ItemProperty -Path ('HKLM:\SYSTEM\CurrentControlSet\Enum\' + '" +
          pnpDeviceId.replaceAll("'", "''") +
          "') -Name 'FriendlyName' -Value '" +
          newName.replaceAll("'", "''") +
          "' -Type String; Write-Output 'OK'",
      'Видеокарта переименована',
    );
    await refresh();
  }

  Future<void> revertGpu(String pnpDeviceId) async {
    await _run(
      r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; Remove-ItemProperty -Path ('HKLM:\SYSTEM\CurrentControlSet\Enum\' + '" +
          pnpDeviceId.replaceAll("'", "''") +
          "') -Name 'FriendlyName' -ErrorAction SilentlyContinue; Write-Output 'OK'",
      'Имя видеокарты восстановлено',
    );
    await refresh();
  }

  Future<void> renameCpu(String newName) async {
    await _run(
      r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; Set-ItemProperty -Path 'HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0' -Name 'ProcessorNameString' -Value '" +
          newName.replaceAll("'", "''") +
          "' -Type String; Write-Output 'OK'",
      'Процессор переименован до перезагрузки',
    );
    await refresh();
  }

  Future<void> revertCpu() async {
    final backup = state.getDevBackup('cpu.name');

    if (backup == null) {
      throw 'Резервная копия имени процессора не найдена';
    }

    await renameCpu(backup.toString());
  }

  Future<void> cleanTemp() async {
    await _run(
      r"$ErrorActionPreference='SilentlyContinue'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; Remove-Item -Path $env:TEMP\* -Recurse -Force -ErrorAction SilentlyContinue; Write-Output 'OK'",
      'Папка TEMP очищена',
    );
    await refresh();
  }

  Future<void> cleanPip() async {
    await _run(
      r"$ErrorActionPreference='SilentlyContinue'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; Remove-Item -Path $env:LOCALAPPDATA\pip\cache\* -Recurse -Force -ErrorAction SilentlyContinue; Write-Output 'OK'",
      'Кэш pip очищен',
    );
    await refresh();
  }

  Future<void> cleanThumbs() async {
    await _run(
      r"$ErrorActionPreference='SilentlyContinue'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; Remove-Item -Path $env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_*.db -Force -ErrorAction SilentlyContinue; Write-Output 'OK'",
      'Кэш миниатюр очищен. Часть файлов могла быть занята Проводником',
    );
    await refresh();
  }

  Future<void> runSfc() async {
    await _run(
      r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; sfc /scannow; Write-Output 'OK'",
      'SFC завершен',
    );
  }

  Future<void> runDism() async {
    await _run(
      r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; DISM /Online /Cleanup-Image /RestoreHealth; Write-Output 'OK'",
      'DISM завершен',
    );
  }

  Future<void> setChkdskTimeout() async {
    if (busy) {
      return;
    }

    busy = true;
    error = '';
    notifyListeners();

    try {
      if (state.getDevBackup('chkntfs.t') == null) {
        final current = await shell.run(
          r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; chkntfs /t",
          timeout: const Duration(seconds: 20),
        );

        final match = RegExp(r'\d+').firstMatch(current.stdout);

        if (match != null) {
          state.setDevBackup('chkntfs.t', match.group(0));
          await state.save();
        }
      }

      final result = await shell.run(
        r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; chkntfs /t:60; Write-Output 'OK'",
        timeout: const Duration(seconds: 20),
      );

      if (!result.success) {
        throw result.errorOrOutput;
      }

      log.success('Таймаут chkdsk установлен на 60 секунд');
    } catch (e) {
      error = e.toString();
      log.error('Не удалось установить таймаут chkdsk', error);
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> revertChkdskTimeout() async {
    final backup = state.getDevBackup('chkntfs.t');

    if (backup == null) {
      throw 'Резервное значение таймаута не найдено';
    }

    await _run(
      r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; chkntfs /t:" +
          backup.toString() +
          r"; Write-Output 'OK'",
      'Таймаут chkdsk восстановлен',
    );
  }

  Future<void> shutdownTimer(int minutes) async {
    final seconds = minutes * 60;

    await _run(
      r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; shutdown /s /t " +
          seconds.toString() +
          r"; Write-Output 'OK'",
      'Таймер выключения установлен на $minutes мин',
    );
  }

  Future<void> cancelShutdown() async {
    await _run(
      r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; shutdown /a; Write-Output 'OK'",
      'Таймер выключения отменен',
    );
  }
}