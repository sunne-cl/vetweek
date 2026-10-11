import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vetweek/models.dart';
import 'package:vetweek/services/apps.dart';
import 'package:vetweek/services/base.dart';
import 'package:vetweek/services/system.dart';
import 'package:vetweek/services/tweaks.dart';
import 'package:vetweek/widgets.dart';
import 'package:vetweek/pages/shell.dart';

class DashboardPage extends StatefulWidget {
  final AppServices services;
  final VoidCallback onOpenCleanup;

  const DashboardPage({
    super.key,
    required this.services,
    required this.onOpenCleanup,
  });

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late final Listenable _listenable;

  @override
  void initState() {
    super.initState();

    _listenable = Listenable.merge([
      widget.services.system,
      widget.services.defender,
      widget.services.advertising,
      widget.services.widgets,
      widget.services.engine,
      widget.services.appx,
      widget.services.log,
      widget.services.restorePoint,
      widget.services.cleanup,
    ]);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.services.system.checkedAt == null) {
        widget.services.system.refresh();
      }

      if (widget.services.system.specs == null) {
        widget.services.system.refreshHardware();
      }
    });
  }

  String _defenderText(DefenderStatus status) {
    switch (status) {
      case DefenderStatus.unknown:
        return 'Не проверено';
      case DefenderStatus.checking:
        return 'Проверка';
      case DefenderStatus.enabled:
        return 'Реальная защита включена';
      case DefenderStatus.disabled:
        return 'Реальная защита отключена';
      case DefenderStatus.unavailable:
        return 'Нужны права администратора';
      case DefenderStatus.error:
        return 'Ошибка';
    }
  }

  String _advertisingText(AdvertisingStatus status) {
    switch (status) {
      case AdvertisingStatus.unknown:
        return 'Не проверено';
      case AdvertisingStatus.checking:
        return 'Проверка';
      case AdvertisingStatus.disabled:
        return 'Рекламные параметры отключены';
      case AdvertisingStatus.enabled:
        return 'Рекламные параметры включены';
      case AdvertisingStatus.error:
        return 'Ошибка';
    }
  }

  String _widgetsText() {
    if (!widget.services.widgets.packagesLoaded) {
      return 'Не проверено';
    }

    if (widget.services.widgets.busy) {
      return 'Проверка';
    }

    if (widget.services.widgets.packageNames.isEmpty) {
      return 'Пакеты не найдены';
    }

    return 'Найдено: ${widget.services.widgets.packageNames.length}';
  }

  @override
  Widget build(BuildContext context) {
    final services = widget.services;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final specs = services.system.specs;
    final disk = services.system.diskC;

    return AnimatedBuilder(
      animation: _listenable,
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const PageHeader(
              title: 'Главная',
              subtitle: 'Состояние системы, железо и быстрые действия',
            ),
            SectionCard(
              child: Column(
                children: [
                  InfoRow(
                    label: 'Операционная система',
                    value: services.system.os,
                  ),
                  const SizedBox(height: 12),
                  InfoRow(
                    label: 'Права администратора',
                    value: services.system.isAdmin ? 'Да' : 'Нет',
                  ),
                  const SizedBox(height: 12),
                  InfoRow(
                    label: 'Defender',
                    value: _defenderText(services.defender.status),
                  ),
                  const SizedBox(height: 12),
                  InfoRow(
                    label: 'Реклама',
                    value: _advertisingText(services.advertising.status),
                  ),
                  const SizedBox(height: 12),
                  InfoRow(
                    label: 'Виджеты и погода',
                    value: _widgetsText(),
                  ),
                  const SizedBox(height: 12),
                  InfoRow(
                    label: 'Твиков в каталоге',
                    value: services.tweaks.length.toString(),
                  ),
                  const SizedBox(height: 12),
                  InfoRow(
                    label: 'Приложения в списке',
                    value: services.appx.packages.length.toString(),
                  ),
                  const SizedBox(height: 12),
                  InfoRow(
                    label: 'Записи журнала',
                    value: services.log.entries.length.toString(),
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
                    'Спецификации ПК',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  if (specs == null)
                    Text(
                      'Характеристики не загружены',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    )
                  else ...[
                    InfoRow(
                      label: 'Процессор',
                      value:
                          '${specs.cpu.name} · ${specs.cpu.cores} ядер / ${specs.cpu.logicalProcessors} потоков · ${specs.cpu.maxMhz} МГц',
                    ),
                    const SizedBox(height: 12),
                    InfoRow(
                      label: 'Видеокарты',
                      value: specs.gpus.isEmpty
                          ? 'Не определено'
                          : specs.gpus
                              .map(
                                (e) =>
                                    '${e.name} · ${e.driverVersion} · ${e.memoryMb} МБ',
                              )
                              .join('\n'),
                    ),
                    const SizedBox(height: 12),
                    InfoRow(
                      label: 'Оперативная память',
                      value: specs.ramSummary,
                    ),
                    const SizedBox(height: 12),
                    InfoRow(
                      label: 'Накопители',
                      value: specs.drives.isEmpty
                          ? 'Не определено'
                          : specs.drives
                              .map(
                                (e) =>
                                    '${e.model} · ${e.kind} · ${e.sizeGb} ГБ',
                              )
                              .join('\n'),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Диск C',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  if (disk == null || disk.totalBytes == 0)
                    Text(
                      'Данные о диске недоступны',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    )
                  else ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: disk.usedRatio.clamp(0.0, 1.0),
                        minHeight: 10,
                      ),
                    ),
                    const SizedBox(height: 12),
                    InfoRow(
                      label: 'Занято',
                      value:
                          '${formatBytes(disk.usedBytes)} из ${formatBytes(disk.totalBytes)}',
                    ),
                    const SizedBox(height: 12),
                    InfoRow(
                      label: 'Свободно',
                      value: formatBytes(disk.freeBytes),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: services.system.isLoading ||
                          services.restorePoint.busy
                      ? null
                      : () async {
                          await services.system.refresh();
                          await services.system.refreshHardware();
                          showSnack(context, 'Система обновлена');
                        },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Обновить систему'),
                ),
                FilledButton.icon(
                  onPressed: services.restorePoint.busy
                      ? null
                      : () async {
                          final ok = await ensureRestorePoint(
                            context,
                            services,
                            force: true,
                          );

                          if (ok) {
                            showSnack(context, 'Точка восстановления готова');
                          }
                        },
                  icon: const Icon(Icons.settings_backup_restore),
                  label: const Text('Создать точку восстановления'),
                ),
                FilledButton.icon(
                  onPressed: widget.onOpenCleanup,
                  icon: const Icon(Icons.cleaning_services_outlined),
                  label: const Text('Перейти к очистке'),
                ),
                if (!services.system.isAdmin)
                  FilledButton.icon(
                    onPressed: () async {
                      await ensureAdminGeneric(
                        context,
                        services,
                        'Полный доступ',
                      );
                    },
                    icon: const Icon(Icons.admin_panel_settings_outlined),
                    label: const Text('Запустить от админа'),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class TweaksPage extends StatefulWidget {
  final AppServices services;

  const TweaksPage({
    super.key,
    required this.services,
  });

  @override
  State<TweaksPage> createState() => _TweaksPageState();
}

class _TweaksPageState extends State<TweaksPage> {
  late final Listenable _listenable;

  @override
  void initState() {
    super.initState();

    _listenable = Listenable.merge([
      widget.services.system,
      widget.services.defender,
      widget.services.advertising,
      widget.services.widgets,
      widget.services.engine,
      widget.services.cleanup,
    ]);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.services.cleanup.detectBrowsers();
    });
  }

  String _defenderText(DefenderStatus status) {
    switch (status) {
      case DefenderStatus.unknown:
        return 'Не проверено';
      case DefenderStatus.checking:
        return 'Проверка';
      case DefenderStatus.enabled:
        return 'Включено';
      case DefenderStatus.disabled:
        return 'Отключено';
      case DefenderStatus.unavailable:
        return 'Нужен админ';
      case DefenderStatus.error:
        return 'Ошибка';
    }
  }

  Color _defenderColor(DefenderStatus status) {
    final scheme = Theme.of(context).colorScheme;

    switch (status) {
      case DefenderStatus.enabled:
        return scheme.primary;
      case DefenderStatus.disabled:
        return scheme.error;
      case DefenderStatus.error:
        return scheme.error;
      default:
        return scheme.onSurfaceVariant;
    }
  }

  String _advertisingText(AdvertisingStatus status) {
    switch (status) {
      case AdvertisingStatus.unknown:
        return 'Не проверено';
      case AdvertisingStatus.checking:
        return 'Проверка';
      case AdvertisingStatus.disabled:
        return 'Отключено';
      case AdvertisingStatus.enabled:
        return 'Включено';
      case AdvertisingStatus.error:
        return 'Ошибка';
    }
  }

  Color _advertisingColor(AdvertisingStatus status) {
    final scheme = Theme.of(context).colorScheme;

    switch (status) {
      case AdvertisingStatus.disabled:
        return scheme.primary;
      case AdvertisingStatus.enabled:
        return scheme.error;
      case AdvertisingStatus.error:
        return scheme.error;
      default:
        return scheme.onSurfaceVariant;
    }
  }

  Future<void> _toggleDefender(BuildContext context, bool disable) async {
    final services = widget.services;

    if (!await ensureRestorePoint(context, services)) {
      return;
    }

    if (!await ensureAdminGeneric(context, services, 'Defender')) {
      return;
    }

    final confirmed = await confirmDialog(
      context,
      title: disable ? 'Отключение реальной защиты' : 'Включение реальной защиты',
      message: disable
          ? 'VeTweek отключит реальную защиту. Это снизит безопасность системы. Продолжить?'
          : 'VeTweek включит реальную защиту. Продолжить?',
      confirmLabel: disable ? 'Отключить' : 'Включить',
      danger: disable,
    );

    if (!confirmed) {
      return;
    }

    try {
      await services.defender.setRealtimeDisabled(disable);
      await services.defender.refresh(isAdmin: true);
      showSnack(
        context,
        disable
            ? 'Реальная защита отключена'
            : 'Реальная защита включена',
      );
    } catch (e) {
      showSnack(context, e.toString());
    }
  }

  Future<void> _toggleAdvertising(BuildContext context, bool disable) async {
    final services = widget.services;

    if (!await ensureRestorePoint(context, services)) {
      return;
    }

    try {
      if (disable) {
        await services.advertising.disableAds();
        showSnack(context, 'Рекламные параметры отключены');
      } else {
        await services.advertising.enableAds();
        showSnack(context, 'Рекламные параметры включены');
      }
    } catch (e) {
      showSnack(context, e.toString());
    }
  }

  Future<void> _removeWidgets(BuildContext context) async {
    final services = widget.services;

    if (!await ensureRestorePoint(context, services)) {
      return;
    }

    final confirmed = await confirmDialog(
      context,
      title: 'Удаление пакетов виджетов и погоды',
      message:
          'VeTweek удалит найденные пакеты виджетов, погоды и похожих компонентов. Действие может быть необратимым. Продолжить?',
      confirmLabel: 'Удалить',
      danger: true,
    );

    if (!confirmed) {
      return;
    }

    try {
      await services.widgets.removePackages();
      showSnack(context, 'Пакеты виджетов и погоды удалены');
    } catch (e) {
      showSnack(context, e.toString());
    }
  }

  Future<void> _runTweak(BuildContext context, Tweak tweak, bool apply) async {
    final services = widget.services;

    if (!await ensureRestorePoint(context, services)) {
      return;
    }

    if (!await ensureAdminTweak(context, services, tweak)) {
      return;
    }

    if (tweak.warning.isNotEmpty) {
      final confirmed = await confirmDialog(
        context,
        title: apply ? 'Применение твика' : 'Откат твика',
        message: tweak.warning,
        confirmLabel: apply ? 'Применить' : 'Откатить',
        danger: apply,
      );

      if (!confirmed) {
        return;
      }
    }

    try {
      if (apply) {
        await services.engine.apply(tweak);
        showSnack(context, 'Применено: ${tweak.title}');
      } else {
        await services.engine.revert(tweak);
        showSnack(context, 'Откачено: ${tweak.title}');
      }
    } catch (e) {
      showSnack(context, e.toString());
    }
  }

  Future<void> _runCleanup(BuildContext context) async {
    final services = widget.services;

    final confirmed = await confirmDialog(
      context,
      title: 'Очистка системы',
      message:
          'Будут удалены выбранные временные файлы, кэши и Корзина. Продолжить?',
      confirmLabel: 'Очистить',
      danger: true,
    );

    if (!confirmed) {
      return;
    }

    try {
      final result = await services.cleanup.runCleanup();
      showSnack(context, result);
    } catch (e) {
      showSnack(context, e.toString());
    }
  }

  Widget _buildDefenderCard() {
    final services = widget.services;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = services.defender.status;
    final busy = services.defender.busy;
    final canDisable = status == DefenderStatus.enabled;
    final canEnable = status == DefenderStatus.disabled;

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Defender',
                  style: theme.textTheme.titleLarge,
                ),
              ),
              StatusChip(
                label: _defenderText(status),
                color: _defenderColor(status),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (services.defender.error.isNotEmpty)
            InfoRow(
              label: 'Ошибка',
              value: services.defender.error,
            ),
          if (busy) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError,
                  elevation: 0,
                  shadowColor: Colors.transparent,
                ),
                onPressed: busy || !canDisable
                    ? null
                    : () {
                        _toggleDefender(context, true);
                      },
                icon: const Icon(Icons.shield_outlined),
                label: const Text('Отключить'),
              ),
              OutlinedButton.icon(
                onPressed: busy || !canEnable
                    ? null
                    : () {
                        _toggleDefender(context, false);
                      },
                icon: const Icon(Icons.shield),
                label: const Text('Включить'),
              ),
              TextButton.icon(
                onPressed: busy
                    ? null
                    : () async {
                        await services.defender.refresh(
                          isAdmin: services.system.isAdmin,
                        );
                      },
                icon: const Icon(Icons.refresh),
                label: const Text('Проверить'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAdvertisingCard() {
    final services = widget.services;
    final theme = Theme.of(context);
    final status = services.advertising.status;
    final busy = services.advertising.busy;
    final canDisable = status == AdvertisingStatus.enabled;
    final canEnable = status == AdvertisingStatus.disabled;

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Реклама и рекомендации',
                  style: theme.textTheme.titleLarge,
                ),
              ),
              StatusChip(
                label: _advertisingText(status),
                color: _advertisingColor(status),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (services.advertising.error.isNotEmpty)
            InfoRow(
              label: 'Ошибка',
              value: services.advertising.error,
            ),
          if (busy) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: busy || !canDisable
                    ? null
                    : () {
                        _toggleAdvertising(context, true);
                      },
                icon: const Icon(Icons.block),
                label: const Text('Отключить'),
              ),
              OutlinedButton.icon(
                onPressed: busy || !canEnable
                    ? null
                    : () {
                        _toggleAdvertising(context, false);
                      },
                icon: const Icon(Icons.restore),
                label: const Text('Включить'),
              ),
              TextButton.icon(
                onPressed: busy
                    ? null
                    : () async {
                        await services.advertising.refresh();
                      },
                icon: const Icon(Icons.refresh),
                label: const Text('Проверить'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWidgetsCard() {
    final services = widget.services;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final busy = services.widgets.busy;
    final found = services.widgets.packageNames.length;

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Виджеты и погода',
                  style: theme.textTheme.titleLarge,
                ),
              ),
              StatusChip(
                label: services.widgets.packagesLoaded
                    ? 'Найдено: $found'
                    : 'Не проверено',
                color: found > 0 ? scheme.error : scheme.onSurfaceVariant,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (services.widgets.error.isNotEmpty)
            InfoRow(
              label: 'Ошибка',
              value: services.widgets.error,
            ),
          if (services.widgets.packageNames.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(
                services.widgets.packageNames.join('\n'),
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
          if (busy) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError,
                  elevation: 0,
                  shadowColor: Colors.transparent,
                ),
                onPressed: busy || services.widgets.packageNames.isEmpty
                    ? null
                    : () {
                        _removeWidgets(context);
                      },
                icon: const Icon(Icons.delete_outline),
                label: const Text('Удалить'),
              ),
              TextButton.icon(
                onPressed: busy
                    ? null
                    : () async {
                        await services.widgets.refresh();
                      },
                icon: const Icon(Icons.refresh),
                label: const Text('Проверить'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCleanupCard() {
    final services = widget.services;
    final theme = Theme.of(context);
    final selection = services.cleanup.selection;

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Очистка кэша и мусора',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          CheckboxListTile(
            value: selection.tempUser,
            onChanged: services.cleanup.busy
                ? null
                : (value) {
                    services.cleanup.setSelection(
                      CleanupSelection(
                        tempUser: value ?? false,
                        tempSystem: selection.tempSystem,
                        updateLogs: selection.updateLogs,
                        recycleBin: selection.recycleBin,
                        allBrowsers: selection.allBrowsers,
                      ),
                    );
                  },
            title: const Text('Временные файлы пользователя'),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          CheckboxListTile(
            value: selection.tempSystem,
            onChanged: services.cleanup.busy
                ? null
                : (value) {
                    services.cleanup.setSelection(
                      CleanupSelection(
                        tempUser: selection.tempUser,
                        tempSystem: value ?? false,
                        updateLogs: selection.updateLogs,
                        recycleBin: selection.recycleBin,
                        allBrowsers: selection.allBrowsers,
                      ),
                    );
                  },
            title: const Text('Временные файлы системы'),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          CheckboxListTile(
            value: selection.updateLogs,
            onChanged: services.cleanup.busy
                ? null
                : (value) {
                    services.cleanup.setSelection(
                      CleanupSelection(
                        tempUser: selection.tempUser,
                        tempSystem: selection.tempSystem,
                        updateLogs: value ?? false,
                        recycleBin: selection.recycleBin,
                        allBrowsers: selection.allBrowsers,
                      ),
                    );
                  },
            title: const Text('Старые загрузки обновлений'),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          CheckboxListTile(
            value: selection.recycleBin,
            onChanged: services.cleanup.busy
                ? null
                : (value) {
                    services.cleanup.setSelection(
                      CleanupSelection(
                        tempUser: selection.tempUser,
                        tempSystem: selection.tempSystem,
                        updateLogs: selection.updateLogs,
                        recycleBin: value ?? false,
                        allBrowsers: selection.allBrowsers,
                      ),
                    );
                  },
            title: const Text('Корзина'),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          CheckboxListTile(
            value: selection.allBrowsers,
            onChanged: services.cleanup.busy
                ? null
                : (value) {
                    services.cleanup.selectAllBrowsers(value ?? false);
                  },
            title: const Text('Все найденные браузеры'),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          if (services.cleanup.browsers.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Найденные браузеры',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final browser in services.cleanup.browsers)
              CheckboxListTile(
                value: browser.selected,
                onChanged: services.cleanup.busy
                    ? null
                    : (value) {
                        services.cleanup.toggleBrowser(
                          browser.id,
                          value ?? false,
                        );
                      },
                title: Text(browser.displayName),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
          ],
          if (services.cleanup.busy) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: services.cleanup.busy
                    ? null
                    : () {
                        _runCleanup(context);
                      },
                icon: const Icon(Icons.cleaning_services_outlined),
                label: const Text('Очистить'),
              ),
              TextButton.icon(
                onPressed: services.cleanup.busy
                    ? null
                    : () async {
                        await services.cleanup.detectBrowsers();
                      },
                icon: const Icon(Icons.refresh),
                label: const Text('Обновить браузеры'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTweakCard(Tweak tweak) {
    final services = widget.services;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = services.engine.statusOf(tweak.id);
    final busy = services.engine.isBusy(tweak.id);
    final needsAdmin = tweak.requiresAdmin && !services.system.isAdmin;

    String label;
    Color color;

    if (busy) {
      label = 'Выполняется';
      color = scheme.tertiary;
    } else if (needsAdmin) {
      label = 'Нужен админ';
      color = scheme.tertiary;
    } else {
      label = tweakStatusLabel(status);
      color = tweakStatusColor(context, status);
    }

    final canApply = !busy && status != TweakStatus.applied;
    final canRevert =
        tweak.reversible &&
        !busy &&
        (status == TweakStatus.applied || status == TweakStatus.partial);

    return TweakCard(
      title: tweak.title,
      description: tweak.description,
      statusLabel: label,
      statusColor: color,
      busy: busy,
      canApply: canApply,
      canRevert: canRevert,
      reversible: tweak.reversible,
      error: services.engine.errorFor(tweak.id),
      warning: tweak.warning,
      onApply: () {
        _runTweak(context, tweak, true);
      },
      onRevert: canRevert
          ? () {
              _runTweak(context, tweak, false);
            }
          : null,
      onRefresh: () async {
        await services.engine.refresh(tweak);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final services = widget.services;
    final categories = TweakCategory.values;

    return AnimatedBuilder(
      animation: _listenable,
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const PageHeader(
              title: 'Твики',
              subtitle:
                  'Защита, реклама, приватность, очистка, система и производительность',
            ),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: services.engine.anyBusy
                      ? null
                      : () async {
                          await services.engine.refreshAll(
                            services.tweaks,
                            force: true,
                          );
                          showSnack(context, 'Статусы твиков обновлены');
                        },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Обновить все статусы'),
                ),
                OutlinedButton.icon(
                  onPressed: services.engine.anyBusy
                      ? null
                      : () async {
                          if (!await ensureRestorePoint(context, services)) {
                            return;
                          }

                          final confirmed = await confirmDialog(
                            context,
                            title: 'Откатить все твики',
                            message:
                                'VeTweek вернет только те твики, которые применял сам и по которым сохранил резервные копии. Продолжить?',
                            confirmLabel: 'Откатить',
                            danger: true,
                          );

                          if (!confirmed) {
                            return;
                          }

                          await services.engine.revertAll(services.tweaks);
                          showSnack(context, 'Откат твиков завершен');
                        },
                  icon: const Icon(Icons.undo),
                  label: const Text('Откатить все твики'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildDefenderCard(),
            const SizedBox(height: 16),
            _buildAdvertisingCard(),
            const SizedBox(height: 16),
            _buildWidgetsCard(),
            const SizedBox(height: 16),
            _buildCleanupCard(),
            const SizedBox(height: 16),
            for (final category in categories) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  categoryLabel(category),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              for (final tweak
                  in services.tweaks.where((t) => t.category == category)) ...[
                _buildTweakCard(tweak),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 8),
            ],
          ],
        );
      },
    );
  }
}

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
                                          style:
                                              theme.textTheme.titleMedium,
                                        ),
                                        const SizedBox(height: 4),
                                        SelectableText(
                                          entry.valueData,
                                          style: theme
                                              .textTheme.bodySmall
                                              ?.copyWith(
                                                color:
                                                    scheme.onSurfaceVariant,
                                              ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${entry.hive} · ${entry.scope}',
                                          style: theme
                                              .textTheme.bodySmall
                                              ?.copyWith(
                                                color:
                                                    scheme.onSurfaceVariant,
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

  @override
  void initState() {
    super.initState();

    _listenable = Listenable.merge([
      widget.services.settings,
    ]);
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
              subtitle: 'Оформление и параметры приложения',
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
                children: [
                  const InfoRow(
                    label: 'Приложение',
                    value: 'VeTweek',
                  ),
                  const SizedBox(height: 12),
                  const InfoRow(
                    label: 'Версия',
                    value: '0.1.0',
                  ),
                  const SizedBox(height: 12),
                  InfoRow(
                    label: 'Каталог данных',
                    value: AppPaths.baseDirectory(),
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