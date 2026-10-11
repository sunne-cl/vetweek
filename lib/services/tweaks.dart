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
          id: 'explorer.home',
          title: 'Скрыть Главную в Проводнике',
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
          id: 'system.windowsupdate',
          title: 'Отключить обновления Windows',
          description:
              'Полностью отключает службу обновлений Windows (wuauserv). Без паузы на 30 дней.',
          category: TweakCategory.system,
          requiresAdmin: true,
          reversible: true,
          warning:
              'ОПАСНО. Отключение обновлений оставляет систему без патчей безопасности. Включайте обратно сразу после необходимости. Возможны сбои Microsoft Store и компонентов, зависящих от wuauserv.',
          applyCommand:
              r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; Set-Service -Name wuauserv -StartupType Disabled -ErrorAction Stop; Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue; Write-Output 'OK'",
          revertCommand:
              r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; Set-Service -Name wuauserv -StartupType Manual -ErrorAction Stop; Write-Output 'OK'",
          statusCommand:
              r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; $s=(Get-Service -Name wuauserv -ErrorAction SilentlyContinue).StartType; if($s -eq 'Disabled'){'APPLIED'}elseif($s){'NOT'}else{'UNKNOWN'}",
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
          id: 'performance.ui.instantresponse',
          title: 'Мгновенный отклик интерфейса',
          description:
              'Убирает задержку контекстных меню и ускоряет завершение зависших приложений.',
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