import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:vetweek/models.dart';
import 'package:vetweek/services/base.dart';
import 'package:vetweek/services/system.dart';

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
          r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; if (Get-Command Get-MpPreference -ErrorAction SilentlyContinue) { $v=(Get-MpPreference).DisableRealtimeMonitoring; if ($v) { 'TRUE' } else { 'FALSE' } } else { 'UNAVAILABLE' }";

      final result = await shell.run(
        command,
        timeout: const Duration(seconds: 30),
      );

      if (!result.success) {
        throw result.errorOrOutput;
      }

      final output = result.stdout.trim().toUpperCase();

      if (output.contains('UNAVAILABLE')) {
        status = DefenderStatus.unavailable;
        realtimeDisabled = false;
        error = 'Defender недоступен или не обнаружен';
      } else if (output.contains('TRUE')) {
        realtimeDisabled = true;
        status = DefenderStatus.disabled;
        error = '';
      } else if (output.contains('FALSE')) {
        realtimeDisabled = false;
        status = DefenderStatus.enabled;
        error = '';
      } else {
        status = DefenderStatus.error;
        error = 'Неизвестный ответ Defender: $output';
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
    error = '';
    notifyListeners();

    try {
      final command = value
          ? r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; Set-MpPreference -DisableRealtimeMonitoring $true; Write-Output 'OK'"
          : r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; Set-MpPreference -DisableRealtimeMonitoring $false; Write-Output 'OK'";

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
    } catch (e) {
      error = e.toString();
      status = DefenderStatus.error;
      log.error('Не удалось изменить Defender', error);
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}

class AdvertisingService extends ChangeNotifier {
  final PowerShellService shell;
  final LogService log;
  final RegistryService registry;

  static final List<RegistryOp> adsOps = <RegistryOp>[
    RegistryOp(
      hive: Hive.hkcu,
      key: r'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager',
      valueName: 'ContentDeliveryAllowed',
      type: RegValueType.dword,
      applyValue: 0,
      applyAction: RegAction.setValue,
      revertAction: RegAction.deleteValue,
    ),
    RegistryOp(
      hive: Hive.hkcu,
      key: r'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager',
      valueName: 'RotatingLockScreenOverlayEnabled',
      type: RegValueType.dword,
      applyValue: 0,
      applyAction: RegAction.setValue,
      revertAction: RegAction.deleteValue,
    ),
    RegistryOp(
      hive: Hive.hkcu,
      key: r'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager',
      valueName: 'SilentInstalledAppsEnabled',
      type: RegValueType.dword,
      applyValue: 0,
      applyAction: RegAction.setValue,
      revertAction: RegAction.deleteValue,
    ),
    RegistryOp(
      hive: Hive.hkcu,
      key: r'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager',
      valueName: 'SoftLandingEnabled',
      type: RegValueType.dword,
      applyValue: 0,
      applyAction: RegAction.setValue,
      revertAction: RegAction.deleteValue,
    ),
    RegistryOp(
      hive: Hive.hkcu,
      key: r'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager',
      valueName: 'SystemPaneSuggestionsEnabled',
      type: RegValueType.dword,
      applyValue: 0,
      applyAction: RegAction.setValue,
      revertAction: RegAction.deleteValue,
    ),
    RegistryOp(
      hive: Hive.hkcu,
      key: r'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager',
      valueName: 'SubscribedContent-310093Enabled',
      type: RegValueType.dword,
      applyValue: 0,
      applyAction: RegAction.setValue,
      revertAction: RegAction.deleteValue,
    ),
    RegistryOp(
      hive: Hive.hkcu,
      key: r'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager',
      valueName: 'SubscribedContent-338388Enabled',
      type: RegValueType.dword,
      applyValue: 0,
      applyAction: RegAction.setValue,
      revertAction: RegAction.deleteValue,
    ),
    RegistryOp(
      hive: Hive.hkcu,
      key: r'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager',
      valueName: 'SubscribedContent-338389Enabled',
      type: RegValueType.dword,
      applyValue: 0,
      applyAction: RegAction.setValue,
      revertAction: RegAction.deleteValue,
    ),
  ];

  AdvertisingStatus status = AdvertisingStatus.unknown;
  bool adsDisabled = false;
  bool busy = false;
  String error = '';

  AdvertisingService({
    required this.shell,
    required this.log,
    required this.registry,
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
      final reads = await registry.readMany(adsOps);

      var anyFound = false;
      var allZero = true;

      for (final read in reads) {
        if (!read.missing && !read.isNull) {
          anyFound = true;

          final parsed = int.tryParse(read.value);

          if (parsed == null || parsed != 0) {
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
    error = '';
    notifyListeners();

    try {
      for (final op in adsOps) {
        await registry.write(op, op.applyValue);
      }

      log.success('Рекламные параметры отключены');
      await refresh();
    } catch (e) {
      error = e.toString();
      status = AdvertisingStatus.error;
      log.error('Не удалось отключить рекламные параметры', error);
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> enableAds() async {
    if (busy) {
      return;
    }

    busy = true;
    error = '';
    notifyListeners();

    try {
      for (final op in adsOps) {
        await registry.deleteValue(op);
      }

      log.success('Рекламные параметры восстановлены до значений по умолчанию');
      await refresh();
    } catch (e) {
      error = e.toString();
      status = AdvertisingStatus.error;
      log.error('Не удалось включить рекламные параметры', error);
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
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
          r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; $packages = Get-AppxPackage | Where-Object { $_.Name -like '*WebExperience*' -or $_.Name -like '*Weather*' -or $_.Name -like '*Widgets*' -or $_.Name -like '*BingWeather*' }; if ($packages) { $packages | Select-Object -ExpandProperty Name | ConvertTo-Json -Compress } else { '[]' }";

      final result = await shell.run(
        command,
        timeout: const Duration(minutes: 1),
      );

      if (!result.success) {
        throw result.errorOrOutput;
      }

      packageNames = _parseNames(result.stdout.trim());
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

  List<String> _parseNames(String output) {
    if (output.isEmpty || output == '[]') {
      return [];
    }

    try {
      final decoded = jsonDecode(output);

      if (decoded is List) {
        return decoded.map((e) => e.toString()).toList();
      }

      if (decoded is String) {
        return [decoded];
      }
    } catch (_) {
      return output
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }

    return [];
  }

  Future<void> removePackages() async {
    if (busy || packageNames.isEmpty) {
      return;
    }

    busy = true;
    error = '';
    notifyListeners();

    try {
      final command =
          r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; $packages = Get-AppxPackage | Where-Object { $_.Name -like '*WebExperience*' -or $_.Name -like '*Weather*' -or $_.Name -like '*Widgets*' -or $_.Name -like '*BingWeather*' }; foreach ($package in $packages) { Remove-AppxPackage -Package $package.PackageFullName }; Write-Output 'OK'";

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

      await refresh();
    } catch (e) {
      error = e.toString();
      log.error('Не удалось удалить пакеты виджетов', error);
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}

class WindowsUpdateService extends ChangeNotifier {
  final PowerShellService shell;
  final LogService log;
  final RegistryService registry;
  final SystemService system;

  static const List<String> versionPresets = [
    '21H2',
    '22H2',
    '23H2',
    '24H2',
    '25H2',
  ];

  static const String _wuKey =
      r'SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate';

  bool busy = false;
  String error = '';
  bool checked = false;
  bool serviceDisabled = false;
  int cacheBytes = 0;
  bool targetBlocked = false;
  String targetVersion = '';

  WindowsUpdateService({
    required this.shell,
    required this.log,
    required this.registry,
    required this.system,
  });

  RegistryOp _trvOp() {
    return RegistryOp(
      hive: Hive.hklm,
      key: _wuKey,
      valueName: 'TargetReleaseVersion',
      type: RegValueType.dword,
      applyValue: 1,
      applyAction: RegAction.setValue,
      revertAction: RegAction.deleteValue,
    );
  }

  RegistryOp _trvInfoOp() {
    return RegistryOp(
      hive: Hive.hklm,
      key: _wuKey,
      valueName: 'TargetReleaseVersionInfo',
      type: RegValueType.string,
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
      final serviceCommand =
          r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; $s=(Get-Service -Name wuauserv -ErrorAction SilentlyContinue).StartType; if($s){[string]$s}else{'UNKNOWN'}";

      final serviceResult = await shell.run(
        serviceCommand,
        timeout: const Duration(seconds: 25),
      );

      if (serviceResult.success) {
        serviceDisabled =
            serviceResult.stdout.trim() == 'Disabled';
      }

      final cacheCommand =
          r"$ErrorActionPreference='SilentlyContinue'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; (Get-ChildItem -Path 'C:\Windows\SoftwareDistribution\Download' -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum";

      final cacheResult = await shell.run(
        cacheCommand,
        timeout: const Duration(seconds: 40),
      );

      if (cacheResult.success) {
        cacheBytes = int.tryParse(cacheResult.stdout.trim()) ?? 0;
      }

      final reads = await registry.readMany([_trvOp(), _trvInfoOp()]);

      targetBlocked = reads[0].value == '1';
      targetVersion = reads[1].missing || reads[1].isNull ? '' : reads[1].value;

      checked = true;
    } catch (e) {
      error = e.toString();
      log.error('Ошибка чтения состояния Windows Update', error);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> pause() async {
    await _run(
      r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; Set-Service -Name wuauserv -StartupType Disabled -ErrorAction Stop; Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue; Write-Output 'OK'",
      'Служба Windows Update приостановлена',
    );
  }

  Future<void> resume() async {
    await _run(
      r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; Set-Service -Name wuauserv -StartupType Manual -ErrorAction Stop; Start-Service -Name wuauserv -ErrorAction SilentlyContinue; Write-Output 'OK'",
      'Служба Windows Update возобновлена',
    );
  }

  Future<int> clearCache() async {
    if (busy) {
      return 0;
    }

    busy = true;
    error = '';
    notifyListeners();

    try {
      final before = cacheBytes;

      final command =
          r"$ErrorActionPreference='SilentlyContinue'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue; Stop-Service -Name bits -Force -ErrorAction SilentlyContinue; Remove-Item -Path 'C:\Windows\SoftwareDistribution\Download\*' -Recurse -Force -ErrorAction SilentlyContinue; Start-Service -Name wuauserv -ErrorAction SilentlyContinue; Start-Service -Name bits -ErrorAction SilentlyContinue; Write-Output 'OK'";

      final result = await shell.run(
        command,
        timeout: const Duration(minutes: 5),
      );

      if (!result.success) {
        throw result.errorOrOutput;
      }

      await refresh();

      final freed = before - cacheBytes;

      log.success(
        'Кэш Windows Update очищен',
        'Освобождено примерно: ${freed > 0 ? freed : 0} байт',
      );

      return freed > 0 ? freed : 0;
    } catch (e) {
      error = e.toString();
      log.error('Не удалось очистить кэш Windows Update', error);
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> blockVersion(String version) async {
    if (busy) {
      return;
    }

    busy = true;
    error = '';
    notifyListeners();

    try {
      await registry.write(_trvOp(), 1);
      await registry.write(_trvInfoOp(), version);

      log.success(
        'Обновления заблокированы на версии',
        version,
      );

      await refresh();
    } catch (e) {
      error = e.toString();
      log.error('Не удалось заблокировать версию обновлений', error);
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> unblockVersion() async {
    if (busy) {
      return;
    }

    busy = true;
    error = '';
    notifyListeners();

    try {
      await registry.deleteValue(_trvOp());
      await registry.deleteValue(_trvInfoOp());

      log.success('Блокировка версии обновлений снята');

      await refresh();
    } catch (e) {
      error = e.toString();
      log.error('Не удалось снять блокировку версии обновлений', error);
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> _run(String command, String successMessage) async {
    if (busy) {
      return;
    }

    busy = true;
    error = '';
    notifyListeners();

    try {
      final result = await shell.run(
        command,
        timeout: const Duration(seconds: 60),
      );

      if (!result.success) {
        throw result.errorOrOutput;
      }

      log.success(successMessage);

      await refresh();
    } catch (e) {
      error = e.toString();
      log.error(successMessage, error);
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
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
          title: 'Отключить веб-поиск в меню Пуск',
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
          id: 'privacy.autoprovisioning',
          title: 'Запретить автоустановку рекламных приложений',
          description:
              'Мешает Windows автоматически ставить рекомендованные приложения после обновлений.',
          category: TweakCategory.privacy,
          requiresAdmin: false,
          reversible: true,
          ops: [
            RegistryOp(
              hive: Hive.hkcu,
              key:
                  r'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager',
              valueName: 'SilentInstalledAppsEnabled',
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
          id: 'privacy.input.tipc',
          title: 'Отключить сбор данных рукописного ввода',
          description:
              'Выключает отправку данных о вводе через TIPC.',
          category: TweakCategory.privacy,
          requiresAdmin: false,
          reversible: true,
          ops: [
            RegistryOp(
              hive: Hive.hkcu,
              key: r'Software\Microsoft\Input\TIPC',
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
          id: 'privacy.clipboard.sync',
          title: 'Отключить синхронизацию буфера обмена между устройствами',
          description:
              'Запрещает Windows передавать содержимое буфера обмена на другие устройства через облако.',
          category: TweakCategory.privacy,
          requiresAdmin: true,
          reversible: true,
          ops: [
            RegistryOp(
              hive: Hive.hklm,
              key: r'SOFTWARE\Policies\Microsoft\Windows\System',
              valueName: 'AllowCrossDeviceClipboard',
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
          warning:
              'После применения может потребоваться перезапуск Проводника или выход из системы.',
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
          warning:
              'Удаляет системный раздел навигации. После применения перезапустите Проводник.',
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
          id: 'explorer.gallery.show',
          title: 'Включить Галерейный вид в Проводнике',
          description:
              'Восстанавливает системный раздел Галереи с продвинутым отображением изображений в навигации Проводника.',
          category: TweakCategory.explorer,
          requiresAdmin: true,
          reversible: true,
          warning:
              'Доступно только на сборках Windows 11 с поддержкой Галереи. После применения перезапустите Проводник.',
          ops: [
            RegistryOp(
              hive: Hive.hklm,
              key:
                  r'SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace_46351065\{e88865b5-3e64-4361-bc3b-55034d442721}',
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
          id: 'explorer.home',
          title: 'Открывать Проводник в «Этот компьютер»',
          description:
              'Переключает открытие Проводника на «Этот компьютер» вместо раздела «Главная».',
          category: TweakCategory.explorer,
          requiresAdmin: false,
          reversible: true,
          warning:
              'После применения перезапустите Проводник, чтобы изменение вступило в силу.',
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
      RegistryTweakWrapper(
        RegistryTweak(
          id: 'fast.hidden',
          title: 'Показывать скрытые файлы и папки',
          description:
              'Включает отображение скрытых файлов и папок в Проводнике.',
          category: TweakCategory.explorer,
          requiresAdmin: false,
          reversible: true,
          ops: [
            RegistryOp(
              hive: Hive.hkcu,
              key:
                  r'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced',
              valueName: 'Hidden',
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
      RegistryTweakWrapper(
        RegistryTweak(
          id: 'fast.extensions',
          title: 'Показывать расширения файлов',
          description:
              'Показывает расширения файлов. Защищает от масок вида документ.exe.txt.',
          category: TweakCategory.explorer,
          requiresAdmin: false,
          reversible: true,
          ops: [
            RegistryOp(
              hive: Hive.hkcu,
              key:
                  r'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced',
              valueName: 'HideFileExt',
              type: RegValueType.dword,
              applyValue: 0,
              applyAction: RegAction.setValue,
              revertAction: RegAction.setValue,
              revertValue: 1,
              missingCountsAsReverted: true,
            ),
          ],
        ),
      ),
    );

    tweaks.add(
      RegistryTweakWrapper(
        RegistryTweak(
          id: 'fast.desktopicon',
          title: 'Показывать иконку «Этот компьютер» на рабочем столе',
          description:
              'Добавляет системную иконку «Этот компьютер» на рабочий стол.',
          category: TweakCategory.explorer,
          requiresAdmin: false,
          reversible: true,
          ops: [
            RegistryOp(
              hive: Hive.hkcu,
              key:
                  r'Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel',
              valueName: '{20D04FE0-3AEA-1069-A2D8-08002B30309D}',
              type: RegValueType.dword,
              applyValue: 0,
              applyAction: RegAction.setValue,
              revertAction: RegAction.setValue,
              revertValue: 1,
              missingCountsAsReverted: true,
            ),
          ],
        ),
      ),
    );

    tweaks.add(
      CommandTweakWrapper(
        CommandTweak(
          id: 'fast.shortcutname',
          title: 'Убрать приписку «- ярлык» у новых ярлыков',
          description:
              'Новые ярлыки создаются без добавления слова «- ярлык» в имя.',
          category: TweakCategory.explorer,
          requiresAdmin: false,
          reversible: true,
          warning:
              'Действует только на ярлыки, созданные после применения твика.',
          applyCommand:
              r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer' -Name 'link' -Value ([byte[]](0x00,0x00,0x00,0x00)) -Type Binary; Write-Output 'OK'",
          revertCommand:
              r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer' -Name 'link' -Value ([byte[]](0x1e,0x00,0x00,0x00)) -Type Binary; Write-Output 'OK'",
          statusCommand:
              r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; $v=(Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer' -Name 'link' -ErrorAction SilentlyContinue).link; if($v -ne $null -and $v.Length -ge 4 -and $v[0] -eq 0 -and $v[1] -eq 0 -and $v[2] -eq 0 -and $v[3] -eq 0){'APPLIED'}else{'NOT'}",
          appliedToken: 'APPLIED',
          notAppliedToken: 'NOT',
        ),
      ),
    );

    tweaks.add(
      RegistryTweakWrapper(
        RegistryTweak(
          id: 'fast.dedupdrives',
          title: 'Убрать дублирование дисков в боковой панели',
          description:
              'Удаляет системный раздел DelegateFolders, из-за которого флешки и внешние диски дублируются в навигации Проводника.',
          category: TweakCategory.explorer,
          requiresAdmin: true,
          reversible: true,
          warning:
              'После применения перезапустите Проводник. Откат восстанавливает раздел.',
          ops: [
            RegistryOp(
              hive: Hive.hklm,
              key:
                  r'SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\DelegateFolders\{F5FB2C77-0E2F-4A16-A381-3E560C68BC83}',
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
          id: 'fast.taskbaral',
          title: 'Панель задач слева (Windows 11)',
          description:
              'Перемещает кнопки панели задач влево, как в классической раскладке Windows.',
          category: TweakCategory.explorer,
          requiresAdmin: false,
          reversible: true,
          warning: 'Работает только в Windows 11.',
          ops: [
            RegistryOp(
              hive: Hive.hkcu,
              key:
                  r'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced',
              valueName: 'TaskbarAl',
              type: RegValueType.dword,
              applyValue: 0,
              applyAction: RegAction.setValue,
              revertAction: RegAction.setValue,
              revertValue: 1,
              missingCountsAsReverted: true,
            ),
          ],
        ),
      ),
    );

    tweaks.add(
      RegistryTweakWrapper(
        RegistryTweak(
          id: 'fast.darkmode',
          title: 'Системная темная тема Windows',
          description:
              'Переключает приложения и систему на темный режим оформления Windows.',
          category: TweakCategory.explorer,
          requiresAdmin: false,
          reversible: true,
          ops: [
            RegistryOp(
              hive: Hive.hkcu,
              key: r'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize',
              valueName: 'AppsUseLightTheme',
              type: RegValueType.dword,
              applyValue: 0,
              applyAction: RegAction.setValue,
              revertAction: RegAction.setValue,
              revertValue: 1,
              missingCountsAsReverted: true,
            ),
            RegistryOp(
              hive: Hive.hkcu,
              key: r'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize',
              valueName: 'SystemUsesLightTheme',
              type: RegValueType.dword,
              applyValue: 0,
              applyAction: RegAction.setValue,
              revertAction: RegAction.setValue,
              revertValue: 1,
              missingCountsAsReverted: true,
            ),
          ],
        ),
      ),
    );

    tweaks.add(
      RegistryTweakWrapper(
        RegistryTweak(
          id: 'explorer.separateprocess',
          title: 'Запускать папки Проводника в отдельном процессе',
          description:
              'Включает SeparateProcess. Зависание одного окна папки не роняет весь Проводник, рабочий стол и панель задач.',
          category: TweakCategory.explorer,
          requiresAdmin: false,
          reversible: true,
          warning:
              'Вступает в силу после перезапуска Проводника или выхода из системы. Незначительно увеличивает потребление памяти.',
          ops: [
            RegistryOp(
              hive: Hive.hkcu,
              key:
                  r'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced',
              valueName: 'SeparateProcess',
              type: RegValueType.dword,
              applyValue: 1,
              applyAction: RegAction.setValue,
              revertAction: RegAction.setValue,
              revertValue: 0,
              missingCountsAsReverted: true,
            ),
          ],
        ),
      ),
    );

    tweaks.add(
      RegistryTweakWrapper(
        RegistryTweak(
          id: 'explorer.mycomputer.folders',
          title: 'Убрать мусорные папки из «Этот компьютер»',
          description:
              'Удаляет из «Этот компьютер» системные ярлыки «3D-объекты», «Музыка» и «Видео». Сами папки на диске не удаляются.',
          category: TweakCategory.explorer,
          requiresAdmin: true,
          reversible: true,
          warning:
              'Удаляет системные ключи навигации. После применения перезапустите Проводник. На отдельных сборках CLSID папок могут отличаться, тогда папки останутся видимыми.',
          ops: [
            RegistryOp(
              hive: Hive.hklm,
              key:
                  r'SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace\{0DB7E03F-FC29-4DC6-9020-FF41B59E513D}',
              isDefault: true,
              type: RegValueType.string,
              applyValue: null,
              applyAction: RegAction.deleteKey,
              revertAction: RegAction.setValue,
            ),
            RegistryOp(
              hive: Hive.hklm,
              key:
                  r'SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace\{3dfdf296-dbec-4fb4-81d1-6a3438bcf4de}',
              isDefault: true,
              type: RegValueType.string,
              applyValue: null,
              applyAction: RegAction.deleteKey,
              revertAction: RegAction.setValue,
            ),
            RegistryOp(
              hive: Hive.hklm,
              key:
                  r'SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace\{f86fa3ab-70d2-4fc7-9c99-fcbf05467f3a}',
              isDefault: true,
              type: RegValueType.string,
              applyValue: null,
              applyAction: RegAction.deleteKey,
              revertAction: RegAction.setValue,
            ),
          ],
        ),
      ),
    );

    tweaks.add(
      RegistryTweakWrapper(
        RegistryTweak(
          id: 'explorer.seconds',
          title: 'Показывать секунды в системных часах',
          description:
              'Включает отображение секунд в часах на панели задач через ShowSecondsInSystemClock.',
          category: TweakCategory.explorer,
          requiresAdmin: false,
          reversible: true,
          warning:
              'Работает на Windows 10 и Windows 11 24H2 и новее. На промежуточных сборках Windows 11 параметр может игнорироваться. Требуется перезапуск Проводника.',
          ops: [
            RegistryOp(
              hive: Hive.hkcu,
              key:
                  r'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced',
              valueName: 'ShowSecondsInSystemClock',
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
              r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; $p=Join-Path ([Environment]::GetFolderPath('Desktop')) 'God Mode.{ED7BA470-8E54-465E-825C-99712043E01C}'; if(!(Test-Path $p)){New-Item -ItemType Directory -Path $p | Out-Null}; Write-Output 'OK'",
          revertCommand:
              r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; $p=Join-Path ([Environment]::GetFolderPath('Desktop')) 'God Mode.{ED7BA470-8E54-465E-825C-99712043E01C}'; if(Test-Path $p){Remove-Item -Path $p -Recurse -Force}; Write-Output 'OK'",
          statusCommand:
              r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; $p=Join-Path ([Environment]::GetFolderPath('Desktop')) 'God Mode.{ED7BA470-8E54-465E-825C-99712043E01C}'; if(Test-Path $p){'APPLIED'}else{'NOT'}",
          appliedToken: 'APPLIED',
          notAppliedToken: 'NOT',
        ),
      ),
    );

    tweaks.add(
      CommandTweakWrapper(
        CommandTweak(
          id: 'explorer.arrow',
          title: 'Убрать стрелки с ярлыков',
          description:
              'Создает прозрачный empty.ico и назначает его для системных стрелок ярлыков.',
          category: TweakCategory.explorer,
          requiresAdmin: true,
          reversible: true,
          warning:
              'После применения нажми «Перезапустить Проводник» или перезагрузи ПК. Для отката удали параметр 29 из Shell Icons.',
          applyCommand:
              r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; $p=Join-Path (Join-Path $env:APPDATA 'VeTweek') 'empty.ico'; $k=[Microsoft.Win32.Registry]::LocalMachine.CreateSubKey('SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Icons'); $k.SetValue('29', ($p + ',0'), [Microsoft.Win32.RegistryValueKind]::String); $k.Close(); Write-Output 'OK'",
          revertCommand:
              r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; $k=[Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Icons',$true); if($k){ $k.DeleteValue('29',$false); $k.Close() }; Write-Output 'OK'",
          statusCommand:
              r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; $p=Join-Path (Join-Path $env:APPDATA 'VeTweek') 'empty.ico'; $k=[Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Icons'); if($k){ $v=[string]$k.GetValue('29',$null); $k.Close(); if($v -eq ($p + ',0') -and (Test-Path $p)){ 'APPLIED' } else { 'NOT' } } else { 'NOT' }",
          appliedToken: 'APPLIED',
          notAppliedToken: 'NOT',
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
          warning:
              'OneDrive будет остановлен. Локальные файлы останутся на месте.',
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
              r"$ErrorActionPreference='SilentlyContinue'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; Stop-Process -Name 'OneDrive' -Force -ErrorAction SilentlyContinue; Write-Output 'OK'",
        ),
      ),
    );

    tweaks.add(
      RegistryTweakWrapper(
        RegistryTweak(
          id: 'system.clipboard.history',
          title: 'Включить историю буфера обмена',
          description:
              'Включает историю буфера обмена (Win+V). Windows хранит до 25 элементов, размер истории через реестр не увеличивается.',
          category: TweakCategory.system,
          requiresAdmin: false,
          reversible: true,
          warning:
              'Скопированные данные сохраняются локально в истории буфера обмена до очистки или перезагрузки.',
          ops: [
            RegistryOp(
              hive: Hive.hkcu,
              key: r'Software\Microsoft\Clipboard',
              valueName: 'EnableClipboardHistory',
              type: RegValueType.dword,
              applyValue: 1,
              applyAction: RegAction.setValue,
              revertAction: RegAction.setValue,
              revertValue: 0,
              missingCountsAsReverted: true,
            ),
          ],
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
          warning:
              'После отключения гибернации режим «Спящий» с сохранением на диск станет недоступен.',
          applyCommand:
              r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; powercfg /h off; Write-Output 'OK'",
          revertCommand:
              r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; powercfg /h on; Write-Output 'OK'",
          statusCommand:
              r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; if(Test-Path 'C:\hiberfil.sys'){'NOT'}else{'APPLIED'}",
          appliedToken: 'APPLIED',
          notAppliedToken: 'NOT',
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
          warning:
              'Схема доступна не на всех сборках Windows. Увеличивает энергопотребление и нагрев.',
          applyCommand:
              r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; $out = powercfg /duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61; if($out -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})'){ powercfg /setactive $matches[1]; Write-Output 'OK' } else { Write-Error 'Схема не поддерживается на этой сборке'; exit 1 }",
          revertCommand:
              r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; powercfg /setactive 381b4222-f694-41f0-9685-ff5bb260df2e; Write-Output 'OK'",
          statusCommand:
              r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; $out = powercfg /getactivescheme; if ($out -match 'e9a42b02-d5df-448d-aa00-03f14749eb61') { 'APPLIED' } else { 'NOT' }",
          appliedToken: 'APPLIED',
          notAppliedToken: 'NOT',
        ),
      ),
    );

    tweaks.add(
      CommandTweakWrapper(
        CommandTweak(
          id: 'system.bootmenu.legacy',
          title: 'Старый загрузчик системы (legacy)',
          description:
              'Включает классическое текстовое меню загрузки в стиле Windows 7 через bcdedit.',
          category: TweakCategory.system,
          requiresAdmin: true,
          reversible: true,
          warning:
              'Изменяет конфигурацию загрузки. Ошибка загрузчика может потребовать восстановления. Действует после перезагрузки.',
          applyCommand:
              r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; bcdedit /set '{current}' bootmenupolicy legacy; Write-Output 'OK'",
          revertCommand:
              r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; bcdedit /set '{current}' bootmenupolicy standard; Write-Output 'OK'",
          statusCommand:
              r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; $o=(bcdedit /enum '{current}') -join ' '; if($o -like '*legacy*'){'APPLIED'}else{'NOT'}",
          appliedToken: 'APPLIED',
          notAppliedToken: 'NOT',
        ),
      ),
    );

    tweaks.add(
      CommandTweakWrapper(
        CommandTweak(
          id: 'system.bootmenu.display',
          title: 'Меню загрузки при каждом старте',
          description:
              'Показывает меню выбора загрузки перед каждым стартом системы через bcdedit.',
          category: TweakCategory.system,
          requiresAdmin: true,
          reversible: true,
          warning:
              'Изменяет конфигурацию загрузчика. При каждой загрузке будет появляться меню выбора.',
          applyCommand:
              r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; bcdedit /set '{bootmgr}' displaybootmenu yes; Write-Output 'OK'",
          revertCommand:
              r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; bcdedit /set '{bootmgr}' displaybootmenu no; Write-Output 'OK'",
          statusCommand:
              r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; $o=(bcdedit /enum '{bootmgr}') -join ' '; if($o -like '*yes*'){'APPLIED'}else{'NOT'}",
          appliedToken: 'APPLIED',
          notAppliedToken: 'NOT',
        ),
      ),
    );

    tweaks.add(
      RegistryTweakWrapper(
        RegistryTweak(
          id: 'system.ttl65',
          title: 'Обход ограничения раздачи интернета (TTL 65)',
          description:
              'Устанавливает DefaultTTL 65 в параметрах Tcpip. Помогает против детекции раздачи трафика мобильными операторами.',
          category: TweakCategory.system,
          requiresAdmin: true,
          reversible: true,
          warning:
              'Может нарушать условия договора оператора связи. Используйте на свой риск.',
          ops: [
            RegistryOp(
              hive: Hive.hklm,
              key: r'SYSTEM\CurrentControlSet\Services\Tcpip\Parameters',
              valueName: 'DefaultTTL',
              type: RegValueType.dword,
              applyValue: 65,
              applyAction: RegAction.setValue,
              revertAction: RegAction.deleteValue,
            ),
          ],
        ),
      ),
    );

    tweaks.add(
      CommandTweakWrapper(
        CommandTweak(
          id: 'system.pagefile.disable',
          title: 'Отключить файл подкачки',
          description:
              'Полностью отключает файл подкачки через управление параметрами Win32_ComputerSystem и Win32_PageFileSetting.',
          category: TweakCategory.system,
          requiresAdmin: true,
          reversible: true,
          warning:
              'ОПАСНО. Только для ПК с большим объемом ОЗУ. Без файла подкачки системы с малой памятью могут падать с нехваткой памяти. Требуется перезагрузка.',
          applyCommand:
              r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; $cs=Get-CimInstance Win32_ComputerSystem; $cs | Set-CimInstance -Property @{AutomaticManagedPagefile=$false}; Get-CimInstance Win32_PageFileSetting -ErrorAction SilentlyContinue | Remove-CimInstance -ErrorAction SilentlyContinue; Write-Output 'OK'",
          revertCommand:
              r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; $cs=Get-CimInstance Win32_ComputerSystem; $cs | Set-CimInstance -Property @{AutomaticManagedPagefile=$true}; Write-Output 'OK'",
          statusCommand:
              r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; $cs=Get-CimInstance Win32_ComputerSystem; if($cs.AutomaticManagedPagefile -eq $false){'APPLIED'}else{'NOT'}",
          appliedToken: 'APPLIED',
          notAppliedToken: 'NOT',
        ),
      ),
    );

    tweaks.add(
      RegistryTweakWrapper(
        RegistryTweak(
          id: 'system.smartscreen',
          title: 'Отключить SmartScreen',
          description:
              'Отключает проверку приложений и файлов через Windows SmartScreen.',
          category: TweakCategory.system,
          requiresAdmin: true,
          reversible: true,
          warning:
              'ТЕСТОВАЯ ФУНКЦИЯ. ОПАСНО. SmartScreen перестанет блокировать непроверенные приложения и файлы из интернета. Это заметно снижает защиту системы. Используй только если полностью понимаешь риск и у тебя есть альтернативная защита.',
          ops: [
            RegistryOp(
              hive: Hive.hklm,
              key: r'SOFTWARE\Policies\Microsoft\Windows\System',
              valueName: 'EnableSmartScreen',
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
          id: 'system.copilot',
          title: 'Отключить Windows Copilot',
          description:
              'Выключает ИИ-помощник Copilot через политику Windows.',
          category: TweakCategory.system,
          requiresAdmin: false,
          reversible: true,
          warning:
              'Работает не во всех редакциях и сборках Windows 11.',
          ops: [
            RegistryOp(
              hive: Hive.hkcu,
              key: r'Software\Policies\Microsoft\Windows\WindowsCopilot',
              valueName: 'TurnOffWindowsCopilot',
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
          id: 'system.notifications.toasts',
          title: 'Разрешить всплывающие уведомления',
          description:
              'Включает глобальные toast-уведомления, если они были отключены системными ограничениями.',
          category: TweakCategory.system,
          requiresAdmin: false,
          reversible: true,
          warning:
              'Это не полноценное отключение Focus Assist, а управление всплывающими уведомлениями через указанный параметр реестра.',
          ops: [
            RegistryOp(
              hive: Hive.hkcu,
              key:
                  r'Software\Microsoft\Windows\CurrentVersion\Notifications\Settings',
              valueName: 'NOC_GLOBAL_SETTING_TOASTS_ENABLED',
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
          id: 'system.deliveryoptimization',
          title: 'Отключить раздачу обновлений WUDO',
          description:
              'Запрещает использовать твой интернет-канал для раздачи обновлений другим пользователям.',
          category: TweakCategory.system,
          requiresAdmin: true,
          reversible: true,
          ops: [
            RegistryOp(
              hive: Hive.hklm,
              key:
                  r'SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config',
              valueName: 'DODownloadMode',
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

    tweaks.add(
      RegistryTweakWrapper(
        RegistryTweak(
          id: 'performance.gamebar.fse',
          title: 'Отключить Game Bar Nexus и стартовую панель',
          description:
              'Глобальный рубильник для игрового поведения Windows. Отключает UseNexusForGameBarEnabled и ShowStartPanel.',
          category: TweakCategory.performance,
          requiresAdmin: false,
          reversible: true,
          warning:
              'Может повлиять на поведение Game Bar и оптимизаций оконных игр. После применения перезапусти игры или выйди из системы.',
          ops: [
            RegistryOp(
              hive: Hive.hkcu,
              key: r'Software\Microsoft\GameBar',
              valueName: 'UseNexusForGameBarEnabled',
              type: RegValueType.dword,
              applyValue: 0,
              applyAction: RegAction.setValue,
              revertAction: RegAction.deleteValue,
            ),
            RegistryOp(
              hive: Hive.hkcu,
              key: r'Software\Microsoft\GameBar',
              valueName: 'ShowStartPanel',
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
          id: 'performance.hags',
          title: 'Hardware-Accelerated GPU Scheduling',
          description:
              'Включает планирование GPU с аппаратным ускорением через реестр.',
          category: TweakCategory.performance,
          requiresAdmin: true,
          reversible: true,
          warning:
              'ТРЕБУЕТ ПЕРЕЗАГРУЗКУ. Работает только при поддержке видеокарты и драйвера. Если значение не применилось или драйвер не поддерживает HAGS — оставьте как есть.',
          ops: [
            RegistryOp(
              hive: Hive.hklm,
              key: r'SYSTEM\CurrentControlSet\Control\GraphicsDrivers',
              valueName: 'HwSchMode',
              type: RegValueType.dword,
              applyValue: 2,
              applyAction: RegAction.setValue,
              revertAction: RegAction.setValue,
              revertValue: 1,
              missingCountsAsReverted: true,
            ),
          ],
        ),
      ),
    );

    tweaks.add(
      RegistryTweakWrapper(
        RegistryTweak(
          id: 'performance.stickykeys',
          title: 'Отключить залипание клавиш',
          description:
              'Полное отключение залипания клавиш и блокировка случайного включения пятикратным нажатием Shift.',
          category: TweakCategory.performance,
          requiresAdmin: false,
          reversible: true,
          ops: [
            RegistryOp(
              hive: Hive.hkcu,
              key: r'Control Panel\Accessibility\StickyKeys',
              valueName: 'Flags',
              type: RegValueType.string,
              applyValue: '506',
              applyAction: RegAction.setValue,
              revertAction: RegAction.setValue,
              revertValue: '510',
              missingCountsAsReverted: true,
            ),
          ],
        ),
      ),
    );

    tweaks.add(
      RegistryTweakWrapper(
        RegistryTweak(
          id: 'performance.mouse.acceleration',
          title: 'Отключить акселерацию мыши',
          description:
              'Убирает программное ускорение курсора. Прицел движется пропорционально движению мыши.',
          category: TweakCategory.performance,
          requiresAdmin: false,
          reversible: true,
          warning:
              'После применения может потребоваться выход из системы или перезапуск Проводника.',
          ops: [
            RegistryOp(
              hive: Hive.hkcu,
              key: r'Control Panel\Mouse',
              valueName: 'MouseSpeed',
              type: RegValueType.string,
              applyValue: '0',
              applyAction: RegAction.setValue,
              revertAction: RegAction.deleteValue,
            ),
            RegistryOp(
              hive: Hive.hkcu,
              key: r'Control Panel\Mouse',
              valueName: 'MouseThreshold1',
              type: RegValueType.string,
              applyValue: '0',
              applyAction: RegAction.setValue,
              revertAction: RegAction.deleteValue,
            ),
            RegistryOp(
              hive: Hive.hkcu,
              key: r'Control Panel\Mouse',
              valueName: 'MouseThreshold2',
              type: RegValueType.string,
              applyValue: '0',
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
          id: 'performance.keyboard',
          title: 'Снизить задержку повтора клавиатуры',
          description:
              'Устанавливает KeyboardDelay в 0 и KeyboardSpeed в 31. Символы при зажатии клавиши повторяются с минимальной задержкой.',
          category: TweakCategory.performance,
          requiresAdmin: false,
          reversible: true,
          warning:
              'Вступает в силу после выхода из системы. Слишком быстрый повтор может мешать при наборе текста.',
          ops: [
            RegistryOp(
              hive: Hive.hkcu,
              key: r'Control Panel\Keyboard',
              valueName: 'KeyboardDelay',
              type: RegValueType.string,
              applyValue: '0',
              applyAction: RegAction.setValue,
              revertAction: RegAction.setValue,
              revertValue: '1',
            ),
            RegistryOp(
              hive: Hive.hkcu,
              key: r'Control Panel\Keyboard',
              valueName: 'KeyboardSpeed',
              type: RegValueType.string,
              applyValue: '31',
              applyAction: RegAction.setValue,
              revertAction: RegAction.setValue,
              revertValue: '31',
            ),
          ],
        ),
      ),
    );

    tweaks.add(
      RegistryTweakWrapper(
        RegistryTweak(
          id: 'performance.ui.instantresponse',
          title: 'Мгновенный отклик интерфейса и быстрое выключение',
          description:
              'Убирает задержку контекстных меню и ускоряет завершение зависших приложений при выключении ПК.',
          category: TweakCategory.performance,
          requiresAdmin: false,
          reversible: true,
          warning:
              'Windows будет быстрее убивать зависшие процессы. Используй осторожно, если часто работаешь с тяжелыми приложениями.',
          ops: [
            RegistryOp(
              hive: Hive.hkcu,
              key: r'Control Panel\Desktop',
              valueName: 'MenuShowDelay',
              type: RegValueType.string,
              applyValue: '0',
              applyAction: RegAction.setValue,
              revertAction: RegAction.deleteValue,
            ),
            RegistryOp(
              hive: Hive.hkcu,
              key: r'Control Panel\Desktop',
              valueName: 'HungAppTimeout',
              type: RegValueType.string,
              applyValue: '2000',
              applyAction: RegAction.setValue,
              revertAction: RegAction.deleteValue,
            ),
            RegistryOp(
              hive: Hive.hkcu,
              key: r'Control Panel\Desktop',
              valueName: 'WaitToKillAppTimeout',
              type: RegValueType.string,
              applyValue: '2000',
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
          id: 'performance.qos.limit',
          title: 'Снять лимит QoS 20%',
          description:
              'Отключает резервирование полосы пропускания Windows для системных задач.',
          category: TweakCategory.performance,
          requiresAdmin: true,
          reversible: true,
          warning:
              'Влияет на сетевой приоритет системы. Обычно безопасно, но меняет поведение QoS Packet Scheduler.',
          ops: [
            RegistryOp(
              hive: Hive.hklm,
              key: r'SOFTWARE\Policies\Microsoft\Windows\Psched',
              valueName: 'NonBestEffortLimit',
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
          id: 'performance.fullscreen.optimizations',
          title: 'Отключить оптимизацию во весь экран',
          description:
              'Глобальный твик для игр. Может снизить инпут-лаг в полноэкранных приложениях.',
          category: TweakCategory.performance,
          requiresAdmin: false,
          reversible: true,
          warning:
              'Глобальное поведение может отличаться в зависимости от игры, драйвера и версии Windows.',
          ops: [
            RegistryOp(
              hive: Hive.hkcu,
              key: r'System\GameConfigStore',
              valueName: 'GameDVR_FSEBehavior',
              type: RegValueType.dword,
              applyValue: 2,
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
          id: 'performance.powerthrottling',
          title: 'Отключить Power Throttling',
          description:
              'Мешает Windows принудительно занижать приоритет фоновых приложений, что иногда помогает в играх и стриминге.',
          category: TweakCategory.performance,
          requiresAdmin: true,
          reversible: true,
          warning:
              'Может увеличить фоновое энергопотребление. Не рекомендуется для ноутбуков от батареи.',
          ops: [
            RegistryOp(
              hive: Hive.hklm,
              key: r'SYSTEM\CurrentControlSet\Control\Power\PowerThrottling',
              valueName: 'PowerThrottlingOff',
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
          id: 'performance.cpu.parking.visible',
          title: 'Показать настройку парковки ядер',
          description:
              'Раскрывает скрытый параметр электропитания для управления парковкой ядер процессора.',
          category: TweakCategory.performance,
          requiresAdmin: true,
          reversible: true,
          warning:
              'Твик только показывает скрытую настройку в панели электропитания. Само значение парковки нужно выставлять вручную после применения.',
          ops: [
            RegistryOp(
              hive: Hive.hklm,
              key:
                  r'SYSTEM\CurrentControlSet\Control\Power\PowerSettings\54533251-82be-4824-96c1-47b60b740d00\0cc5b647-c1df-4637-891a-dec35c318583',
              valueName: 'Attributes',
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
          id: 'performance.cpu.boost.visible',
          title: 'Показать настройку агрессивности буста',
          description:
              'Раскрывает скрытый параметр электропитания для управления режимом буста процессора.',
          category: TweakCategory.performance,
          requiresAdmin: true,
          reversible: true,
          warning:
              'Твик только показывает скрытую настройку в панели электропитания. Значение буста нужно настраивать вручную после применения.',
          ops: [
            RegistryOp(
              hive: Hive.hklm,
              key:
                  r'SYSTEM\CurrentControlSet\Control\Power\PowerSettings\54533251-82be-4824-96c1-47b60b740d00\be337238-0d82-4146-a960-4f3749d470c7',
              valueName: 'Attributes',
              type: RegValueType.dword,
              applyValue: 2,
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
          id: 'performance.dwm.flipmodel',
          title: 'Оптимизация flip-модели для оконных приложений',
          description:
              'Применяет DirectXUserGlobalKey для оконных приложений и может снизить задержку DWM.',
          category: TweakCategory.performance,
          requiresAdmin: false,
          reversible: true,
          warning:
              'ТЕСТОВАЯ ФУНКЦИЯ. Может повлиять на совместимость старых DirectX-приложений, вызвать артефакты или изменить поведение окон. При проблемах сразу откати твик.',
          ops: [
            RegistryOp(
              hive: Hive.hkcu,
              key: r'Software\Microsoft\DirectX\UserGpuPreferences',
              valueName: 'DirectXUserGlobalKey',
              type: RegValueType.dword,
              applyValue: 1,
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
            warning:
                'Отключение службы может затронуть зависящие от неё компоненты Windows.',
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
                r"$ErrorActionPreference='SilentlyContinue'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; Stop-Service -Name '" +
                    svc +
                    r"' -Force -ErrorAction SilentlyContinue; Write-Output 'OK'",
          ),
        ),
      );
    }

    return tweaks;
  }
}