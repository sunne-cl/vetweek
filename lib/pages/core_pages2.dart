import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vetweek/models.dart';
import 'package:vetweek/services/apps.dart';
import 'package:vetweek/services/base.dart';
import 'package:vetweek/widgets.dart';
import 'package:vetweek/pages/shell.dart';

class AppsPage extends StatefulWidget {
  final AppServices services;

  const AppsPage({
    super.key,
    required this.services,
  });

  @override
  State<AppsPage> createState() => _AppsPageState();
}

class _AppsPageState extends State<AppsPage> {
  late final Listenable _listenable;

  @override
  void initState() {
    super.initState();

    _listenable = Listenable.merge([
      widget.services.appx,
      widget.services.startup,
      widget.services.winget,
      widget.services.log,
    ]);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.services.appx.packages.isEmpty) {
        widget.services.appx.load();
      }

      if (widget.services.startup.entries.isEmpty) {
        widget.services.startup.loadNormal();
      }
    });
  }

  Future<void> _removeSelected(BuildContext context) async {
    final services = widget.services;
    final count = services.appx.selectedCount;

    if (count == 0) {
      return;
    }

    if (!await ensureRestorePoint(context, services)) {
      return;
    }

    final confirmed = await confirmDialog(
      context,
      title: 'Удаление приложений',
      message:
          'Выбрано приложений: $count. Действие может быть необратимым для некоторых пакетов.',
      confirmLabel: 'Удалить',
      danger: true,
    );

    if (!confirmed) {
      return;
    }

    final result = await services.appx.removeSelected();
    showSnack(context, result);
  }

  Future<void> _export(BuildContext context) async {
    final services = widget.services;

    try {
      final path = await services.appx.exportBackup();
      showSnack(context, 'Резервная копия сохранена: $path');
    } catch (e) {
      showSnack(context, e.toString());
    }
  }

  Future<void> _deleteStartup(BuildContext context, StartupEntry entry) async {
    final services = widget.services;

    if (!await ensureRestorePoint(context, services)) {
      return;
    }

    final confirmed = await confirmDialog(
      context,
      title: 'Удаление записи автозагрузки',
      message:
          'Запись будет удалена из реестра. Резервная копия сохранена, но восстановление не гарантировано для всех программ. Продолжить?',
      confirmLabel: 'Удалить',
      danger: true,
    );

    if (!confirmed) {
      return;
    }

    try {
      await services.startup.delete(entry);
      showSnack(context, 'Запись автозагрузки удалена');
    } catch (e) {
      showSnack(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = widget.services;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final packages = services.appx.visiblePackages;

    return AnimatedBuilder(
      animation: _listenable,
      builder: (context, _) {
        return Column(
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: PageHeader(
                title: 'Приложения',
                subtitle: 'UWP-пакеты, автозагрузка и winget',
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                children: [
                  SectionCard(
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton.icon(
                          onPressed: services.appx.loading
                              ? null
                              : () async {
                                  await services.appx.load();
                                },
                          icon: const Icon(Icons.refresh),
                          label: const Text('Обновить UWP'),
                        ),
                        TextButton(
                          onPressed: services.appx.loading
                              ? null
                              : () {
                                  services.appx.selectAllVisible();
                                },
                          child: const Text('Выбрать видимые'),
                        ),
                        TextButton(
                          onPressed: services.appx.loading
                              ? null
                              : () {
                                  services.appx.selectJunk();
                                },
                          child: const Text('Выбрать мусор'),
                        ),
                        TextButton(
                          onPressed: services.appx.selectedCount == 0
                              ? null
                              : () {
                                  services.appx.clearSelection();
                                },
                          child: const Text('Снять выбор'),
                        ),
                        FilledButton.icon(
                          onPressed: services.appx.selectedCount == 0 ||
                                  services.appx.busy
                              ? null
                              : () {
                                  _removeSelected(context);
                                },
                          icon: const Icon(Icons.delete_outline),
                          label: Text(
                            'Удалить выбранные (${services.appx.selectedCount})',
                          ),
                        ),
                        TextButton(
                          onPressed: services.appx.packages.isEmpty
                              ? null
                              : () {
                                  _export(context);
                                },
                          child: const Text('Резервная копия списка'),
                        ),
                        FilledButton.icon(
                          onPressed: services.winget.busy
                              ? null
                              : () async {
                                  await services.winget.upgradeAll();
                                  showSnack(
                                    context,
                                    services.winget.error.isNotEmpty
                                        ? services.winget.error
                                        : services.winget.lastMessage.isEmpty
                                            ? 'winget upgrade --all запущен'
                                            : services.winget.lastMessage,
                                  );
                                },
                          icon: const Icon(Icons.system_update_alt),
                          label: const Text('Обновить все программы'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (services.appx.loading ||
                      services.appx.busy ||
                      services.winget.busy)
                    const LinearProgressIndicator(),
                  if (services.appx.error.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    SectionCard(
                      child: Text(
                        services.appx.error,
                        style: TextStyle(color: scheme.error),
                      ),
                    ),
                  ],
                  if (services.winget.error.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    SectionCard(
                      child: Text(
                        services.winget.error,
                        style: TextStyle(color: scheme.error),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (packages.isEmpty)
                    SectionCard(
                      child: Text(
                        services.appx.packages.isEmpty
                            ? 'Список приложений не загружен'
                            : 'Ничего не найдено',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    )
                  else
                    for (final package in packages)
                      Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        decoration: BoxDecoration(
                          color: scheme.surfaceVariant,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: CheckboxListTile(
                          value: package.selected,
                          onChanged: (_) {
                            services.appx.toggle(package);
                          },
                          title: Text(package.name),
                          subtitle: Text(package.packageFullName),
                          controlAffinity: ListTileControlAffinity.leading,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 16),
                          activeColor: scheme.primary,
                          checkColor: scheme.onPrimary,
                        ),
                      ),
                  const SizedBox(height: 24),
                  SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Автозагрузка',
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            FilledButton.icon(
                              onPressed: services.startup.busy
                                  ? null
                                  : () async {
                                      await services.startup.loadNormal();
                                    },
                              icon: const Icon(Icons.refresh),
                              label: const Text('Обновить'),
                            ),
                            OutlinedButton.icon(
                              onPressed: services.startup.hasBackups
                                  ? () async {
                                      final result =
                                          await services.startup.restoreAll();
                                      showSnack(context, result);
                                    }
                                  : null,
                              icon: const Icon(Icons.restore),
                              label: const Text('Восстановить удаленные'),
                            ),
                          ],
                        ),
                        if (services.startup.error.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          InfoRow(
                            label: 'Ошибка',
                            value: services.startup.error,
                          ),
                        ],
                        if (services.startup.busy) ...[
                          const SizedBox(height: 16),
                          const LinearProgressIndicator(),
                        ],
                        const SizedBox(height: 16),
                        if (services.startup.entries.isEmpty)
                          Text(
                            'Записи автозагрузки не найдены',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          )
                        else
                          for (final entry in services.startup.entries)
                            Container(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: scheme.surface,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          entry.valueName,
                                          style: theme.textTheme.titleMedium,
                                        ),
                                        const SizedBox(height: 4),
                                        SelectableText(
                                          entry.valueData,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color: scheme.onSurfaceVariant,
                                              ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${entry.hive} · ${entry.scope}',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color: scheme.onSurfaceVariant,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: services.startup.busy
                                        ? null
                                        : () {
                                            _deleteStartup(context, entry);
                                          },
                                    icon: const Icon(Icons.delete_outline),
                                    color: scheme.error,
                                  ),
                                ],
                              ),
                            ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class LogsPage extends StatefulWidget {
  final AppServices services;

  const LogsPage({
    super.key,
    required this.services,
  });

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  late final Listenable _listenable;

  @override
  void initState() {
    super.initState();

    _listenable = Listenable.merge([
      widget.services.log,
    ]);
  }

  Color _levelColor(BuildContext context, LogLevel level) {
    final scheme = Theme.of(context).colorScheme;

    switch (level) {
      case LogLevel.success:
        return scheme.primary;
      case LogLevel.warning:
        return scheme.tertiary;
      case LogLevel.error:
        return scheme.error;
      case LogLevel.info:
        return scheme.onSurfaceVariant;
    }
  }

  String _levelText(LogLevel level) {
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

  @override
  Widget build(BuildContext context) {
    final services = widget.services;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final entries = services.log.entries;

    return AnimatedBuilder(
      animation: _listenable,
      builder: (context, _) {
        return Column(
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: PageHeader(
                title: 'Журнал',
                subtitle: 'История действий и ошибок',
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SectionCard(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: () async {
                        try {
                          final path = await services.log.export();
                          showSnack(context, 'Журнал сохранен: $path');
                        } catch (e) {
                          showSnack(context, e.toString());
                        }
                      },
                      icon: const Icon(Icons.upload_file),
                      label: const Text('Экспорт'),
                    ),
                    TextButton(
                      onPressed: services.log.entries.isEmpty
                          ? null
                          : () {
                              services.log.clear();
                            },
                      child: const Text('Очистить'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (entries.isEmpty)
              Expanded(
                child: Center(
                  child: Text(
                    'Журнал пуст',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    final levelColor = _levelColor(context, entry.level);

                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: scheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                entry.time.toLocal().toString(),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(width: 12),
                              StatusChip(
                                label: _levelText(entry.level),
                                color: levelColor,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SelectableText(
                            entry.message,
                            style: theme.textTheme.bodyLarge,
                          ),
                          if (entry.details.isNotEmpty)
                            const SizedBox(height: 4),
                          if (entry.details.isNotEmpty)
                            SelectableText(
                              entry.details,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

class SettingsPage extends StatefulWidget {
  final AppServices services;

  const SettingsPage({
    super.key,
    required this.services,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final Listenable _listenable;

  bool _configBusy = false;

  @override
  void initState() {
    super.initState();

    _listenable = Listenable.merge([
      widget.services.settings,
    ]);
  }

  Future<void> _saveConfig() async {
    if (_configBusy) {
      return;
    }

    setState(() {
      _configBusy = true;
    });

    try {
      final result = await widget.services.powershell.run(
        r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; $dir=Join-Path $env:APPDATA 'VeTweek\configs'; if(!(Test-Path $dir)){New-Item -ItemType Directory -Path $dir -Force | Out-Null}; $settingsPath=Join-Path $env:APPDATA 'VeTweek\settings.json'; $statePath=Join-Path $env:APPDATA 'VeTweek\state.json'; $s=$null; $t=$null; if(Test-Path $settingsPath){$s=Get-Content $settingsPath -Raw}; if(Test-Path $statePath){$t=Get-Content $statePath -Raw}; $obj=@{ settings=$s; state=$t; saved=[DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss') }; $name='config_' + [DateTime]::Now.ToString('yyyyMMdd_HHmmss') + '.json'; ($obj | ConvertTo-Json -Compress) | Set-Content (Join-Path $dir $name) -Encoding UTF8; Write-Output $name",
        timeout: const Duration(seconds: 30),
      );

      if (!result.success) {
        throw result.errorOrOutput;
      }

      if (mounted) {
        showSnack(
          context,
          'Конфиг сохранен: ${result.stdout.trim()}',
        );
      }
    } catch (e) {
      if (mounted) {
        showSnack(context, e.toString());
      }
    } finally {
      if (mounted) {
        setState(() {
          _configBusy = false;
        });
      }
    }
  }

  Future<void> _loadConfig() async {
    if (_configBusy) {
      return;
    }

    setState(() {
      _configBusy = true;
    });

    try {
      final result = await widget.services.powershell.run(
        r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; $dir=Join-Path $env:APPDATA 'VeTweek\configs'; if(!(Test-Path $dir)){ '[]' } else { (Get-ChildItem $dir -Filter *.json | Sort-Object Name -Descending | Select-Object -ExpandProperty Name) | ConvertTo-Json -Compress }",
        timeout: const Duration(seconds: 30),
      );

      if (!result.success) {
        throw result.errorOrOutput;
      }

      final names = <String>[];
      final decoded = jsonDecode(result.stdout.trim());

      if (decoded is List) {
        for (final item in decoded) {
          names.add(item.toString());
        }
      } else if (decoded is String) {
        names.add(decoded);
      }

      if (names.isEmpty) {
        if (mounted) {
          showSnack(context, 'Сохраненных конфигов нет');
        }
        return;
      }

      if (!mounted) {
        return;
      }

      final chosen = await showDialog<String>(
        context: context,
        builder: (dialogContext) {
          final theme = Theme.of(dialogContext);

          return Dialog(
            backgroundColor: theme.colorScheme.surface,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: SizedBox(
              width: 420,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Выберите конфиг',
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            for (final name in names)
                              ListTile(
                                title: Text(name),
                                onTap: () {
                                  Navigator.of(dialogContext).pop(name);
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );

      if (chosen == null) {
        return;
      }

      final apply = await widget.services.powershell.run(
        r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; $path=Join-Path $env:APPDATA ('VeTweek\configs\' + '" +
            chosen.replaceAll("'", "''") +
            r"'); $obj=Get-Content $path -Raw | ConvertFrom-Json; if ($obj.settings) { Set-Content (Join-Path $env:APPDATA 'VeTweek\settings.json') -Value $obj.settings -Encoding UTF8 }; if ($obj.state) { Set-Content (Join-Path $env:APPDATA 'VeTweek\state.json') -Value $obj.state -Encoding UTF8 }; Write-Output 'OK'",
        timeout: const Duration(seconds: 30),
      );

      if (!apply.success) {
        throw apply.errorOrOutput;
      }

      if (mounted) {
        showSnack(context, 'Конфиг загружен. Перезапустите приложение');
      }
    } catch (e) {
      if (mounted) {
        showSnack(context, e.toString());
      }
    } finally {
      if (mounted) {
        setState(() {
          _configBusy = false;
        });
      }
    }
  }

  Future<void> _openGithub() async {
    try {
      await widget.services.powershell.run(
        r"$ErrorActionPreference='Stop'; Start-Process 'https://github.com/sunne-cl/vetweek'",
        timeout: const Duration(seconds: 15),
      );
    } catch (e) {
      if (mounted) {
        showSnack(context, e.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = widget.services;
    final theme = Theme.of(context);

    const seedColorValues = [
      0xFF0B57D0,
      0xFF00696E,
      0xFF7D5260,
      0xFF386A20,
      0xFF8A4FFF,
      0xFFB3261E,
    ];

    return AnimatedBuilder(
      animation: _listenable,
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const PageHeader(
              title: 'Настройки',
              subtitle: 'Оформление, конфиги и параметры приложения',
            ),
            SectionCard(
              child: Column(
                children: [
                  RadioListTile<ThemeMode>(
                    title: const Text('Системная тема'),
                    value: ThemeMode.system,
                    groupValue: services.settings.themeMode,
                    onChanged: (value) {
                      if (value != null) {
                        services.settings.setThemeMode(value);
                      }
                    },
                  ),
                  RadioListTile<ThemeMode>(
                    title: const Text('Светлая тема'),
                    value: ThemeMode.light,
                    groupValue: services.settings.themeMode,
                    onChanged: (value) {
                      if (value != null) {
                        services.settings.setThemeMode(value);
                      }
                    },
                  ),
                  RadioListTile<ThemeMode>(
                    title: const Text('Темная тема'),
                    value: ThemeMode.dark,
                    groupValue: services.settings.themeMode,
                    onChanged: (value) {
                      if (value != null) {
                        services.settings.setThemeMode(value);
                      }
                    },
                  ),
                  SwitchListTile(
                    title: const Text('OLED тема'),
                    subtitle: const Text('Полностью черный фон в темной теме'),
                    value: services.settings.oled,
                    onChanged: services.settings.setOled,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Акцентный цвет',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: seedColorValues.map((value) {
                      final color = Color(value);
                      final selected =
                          services.settings.seedColorValue == value;

                      return MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () {
                            services.settings.setSeedColorValue(value);
                          },
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: selected
                                ? Icon(
                                    Icons.check,
                                    color: ThemeData
                                                .estimateBrightnessForColor(
                                                  color,
                                                ) ==
                                            Brightness.dark
                                        ? Colors.white
                                        : Colors.black,
                                  )
                                : null,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SectionCard(
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('Dev режим'),
                    subtitle: const Text('Показать вкладку Dev'),
                    value: services.settings.devModeEnabled,
                    onChanged: (value) {
                      services.settings.setDevModeEnabled(value);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Конфигурация',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Сохранение и загрузка копий настроек и состояния приложения. Файлы хранятся в папке VeTweek\\configs.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (_configBusy) ...[
                    const SizedBox(height: 16),
                    const LinearProgressIndicator(),
                  ],
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        onPressed: _configBusy ? null : _saveConfig,
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('Сохранить конфиг'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _configBusy ? null : _loadConfig,
                        icon: const Icon(Icons.folder_open_outlined),
                        label: const Text('Загрузить конфиг'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SectionCard(
              child: Column(
                children: [
                  const InfoRow(
                    label: 'Приложение',
                    value: 'VeTweek',
                  ),
                  const SizedBox(height: 12),
                  const InfoRow(
                    label: 'Версия',
                    value: '0.6.0',
                  ),
                  const SizedBox(height: 12),
                  InfoRow(
                    label: 'Каталог данных',
                    value: AppPaths.baseDirectory(),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      onPressed: _openGithub,
                      icon: const Icon(Icons.code),
                      label: const Text('Github'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}