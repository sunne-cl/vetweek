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