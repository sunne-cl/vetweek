import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:vetweek/models.dart';
import 'package:vetweek/services/apps.dart';
import 'package:vetweek/services/base.dart';
import 'package:vetweek/services/system.dart';
import 'package:vetweek/services/tweaks.dart';
import 'package:vetweek/widgets.dart';
import 'package:vetweek/pages/shell.dart';

class FastSettingsPage extends StatefulWidget {
  final AppServices services;

  const FastSettingsPage({
    super.key,
    required this.services,
  });

  @override
  State<FastSettingsPage> createState() => _FastSettingsPageState();
}

class _FastSettingsPageState extends State<FastSettingsPage> {
  late final Listenable _listenable;

  static const List<String> _fastIds = [
    'fast.hidden',
    'fast.extensions',
    'explorer.home',
    'fast.desktopicon',
    'fast.shortcutname',
    'fast.dedupdrives',
    'fast.taskbaral',
    'fast.darkmode',
  ];

  @override
  void initState() {
    super.initState();

    _listenable = Listenable.merge([
      widget.services.engine,
      widget.services.system,
    ]);
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

    final canApply = !busy && !needsAdmin && status != TweakStatus.applied;
    final canRevert = tweak.reversible &&
        !busy &&
        !needsAdmin &&
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

    return AnimatedBuilder(
      animation: _listenable,
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const PageHeader(
              title: 'Быстрая настройка',
              subtitle: 'Проводник, рабочий стол и кастомизация в один клик',
            ),
            for (final id in _fastIds)
              for (final tweak in services.tweaks.where((t) => t.id == id)) ...[
                _buildTweakCard(tweak),
                const SizedBox(height: 12),
              ],
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

  String _wuVersion = '25H2';
  int _perfValue = 100;

  @override
  void initState() {
    super.initState();

    _listenable = Listenable.merge([
      widget.services.system,
      widget.services.defender,
      widget.services.advertising,
      widget.services.widgets,
      widget.services.windowsUpdate,
      widget.services.engine,
      widget.services.cleanup,
    ]);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.services.cleanup.detectBrowsers();

      if (!widget.services.windowsUpdate.checked) {
        if (widget.services.system.isAdmin) {
          widget.services.windowsUpdate.refresh();
        }
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
        disable ? 'Реальная защита отключена' : 'Реальная защита включена',
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

  Future<void> _wuPause(BuildContext context) async {
    final services = widget.services;

    if (!await ensureRestorePoint(context, services)) {
      return;
    }

    if (!await ensureAdminGeneric(context, services, 'Windows Update')) {
      return;
    }

    final confirmed = await confirmDialog(
      context,
      title: 'Приостановка службы Windows Update',
      message:
          'Служба wuauserv будет отключена и остановлена. Система перестанет получать обновления безопасности. Продолжить?',
      confirmLabel: 'Приостановить',
      danger: true,
    );

    if (!confirmed) {
      return;
    }

    try {
      await services.windowsUpdate.pause();
      showSnack(context, 'Служба Windows Update приостановлена');
    } catch (e) {
      showSnack(context, e.toString());
    }
  }

  Future<void> _wuResume(BuildContext context) async {
    final services = widget.services;

    if (!await ensureAdminGeneric(context, services, 'Windows Update')) {
      return;
    }

    try {
      await services.windowsUpdate.resume();
      showSnack(context, 'Служба Windows Update возобновлена');
    } catch (e) {
      showSnack(context, e.toString());
    }
  }

  Future<void> _wuClear(BuildContext context) async {
    final services = widget.services;

    if (!await ensureAdminGeneric(context, services, 'Кэш Windows Update')) {
      return;
    }

    final confirmed = await confirmDialog(
      context,
      title: 'Очистка кэша Windows Update',
      message:
          'Будут удалены загруженные файлы обновлений из SoftwareDistribution. Это безопасно и освобождает место. Продолжить?',
      confirmLabel: 'Очистить',
    );

    if (!confirmed) {
      return;
    }

    try {
      final freed = await services.windowsUpdate.clearCache();
      showSnack(context, 'Кэш очищен. Освобождено: ${formatBytes(freed)}');
    } catch (e) {
      showSnack(context, e.toString());
    }
  }

  Future<void> _wuBlock(BuildContext context) async {
    final services = widget.services;

    if (!await ensureRestorePoint(context, services)) {
      return;
    }

    if (!await ensureAdminGeneric(context, services, 'Блокировка версии')) {
      return;
    }

    final confirmed = await confirmDialog(
      context,
      title: 'Блокировка обновлений на версии',
      message:
          'Windows будет оставаться на выбранной версии через TargetReleaseVersion. Более новые функциональные обновления устанавливаться не будут. Продолжить?',
      confirmLabel: 'Заблокировать',
      danger: true,
    );

    if (!confirmed) {
      return;
    }

    try {
      await services.windowsUpdate.blockVersion(_wuVersion);
      showSnack(context, 'Обновления заблокированы на $_wuVersion');
    } catch (e) {
      showSnack(context, e.toString());
    }
  }

  Future<void> _wuUnblock(BuildContext context) async {
    final services = widget.services;

    if (!await ensureAdminGeneric(context, services, 'Блокировка версии')) {
      return;
    }

    try {
      await services.windowsUpdate.unblockVersion();
      showSnack(context, 'Блокировка версии снята');
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
      message: 'Будут удалены выбранные временные файлы, кэши и Корзина. Продолжить?',
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

  Future<void> _disableReservedStorage(BuildContext context) async {
    final services = widget.services;

    if (!await ensureRestorePoint(context, services)) {
      return;
    }

    if (!await ensureAdminGeneric(
      context,
      services,
      'Резервируемое хранилище',
    )) {
      return;
    }

    final confirmed = await confirmDialog(
      context,
      title: 'Отключение резервируемого хранилища',
      message:
          'ТЕСТОВАЯ ФУНКЦИЯ. VeTweek выполнит DISM-команду отключения резервируемого хранилища Windows. Это может освободить несколько гигабайт, но является системной операцией. Может потребоваться перезагрузка. Продолжить?',
      confirmLabel: 'Отключить',
      danger: true,
    );

    if (!confirmed) {
      return;
    }

    try {
      await services.system.disableReservedStorage();

      showSnack(
        context,
        services.system.reservedError.isNotEmpty
            ? services.system.reservedError
            : 'Резервируемое хранилище отключено',
      );
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

  Widget _buildWindowsUpdateCard() {
    final services = widget.services;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final wu = services.windowsUpdate;
    final isAdmin = services.system.isAdmin;

    String serviceLabel;
    Color serviceColor;

    if (!isAdmin) {
      serviceLabel = 'Нужен админ';
      serviceColor = scheme.tertiary;
    } else if (!wu.checked) {
      serviceLabel = 'Не проверено';
      serviceColor = scheme.onSurfaceVariant;
    } else if (wu.serviceDisabled) {
      serviceLabel = 'Приостановлена';
      serviceColor = scheme.error;
    } else {
      serviceLabel = 'Работает';
      serviceColor = scheme.primary;
    }

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Обновления Windows',
                  style: theme.textTheme.titleLarge,
                ),
              ),
              StatusChip(
                label: serviceLabel,
                color: serviceColor,
              ),
            ],
          ),
          const SizedBox(height: 12),
          InfoRow(
            label: 'Кэш обновлений',
            value: wu.checked ? formatBytes(wu.cacheBytes) : 'Не проверено',
          ),
          const SizedBox(height: 12),
          InfoRow(
            label: 'Блокировка версии',
            value: wu.targetBlocked && wu.targetVersion.isNotEmpty
                ? 'Заблокировано на ${wu.targetVersion}'
                : 'Не заблокировано',
          ),
          if (wu.error.isNotEmpty) ...[
            const SizedBox(height: 12),
            InfoRow(label: 'Ошибка', value: wu.error),
          ],
          if (wu.busy) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 16),
          Text(
            'Приостановить службу Windows Update',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: wu.busy || wu.serviceDisabled || !isAdmin
                    ? null
                    : () {
                        _wuPause(context);
                      },
                icon: const Icon(Icons.pause),
                label: const Text('Приостановить'),
              ),
              OutlinedButton.icon(
                onPressed: wu.busy || !wu.serviceDisabled || !isAdmin
                    ? null
                    : () {
                        _wuResume(context);
                      },
                icon: const Icon(Icons.play_arrow),
                label: const Text('Возобновить'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'Очистить кэш Windows Update',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: wu.busy || !isAdmin ? null : () {
              _wuClear(context);
            },
            icon: const Icon(Icons.cleaning_services_outlined),
            label: const Text('Очистить'),
          ),
          const SizedBox(height: 20),
          Text(
            'Заблокировать обновления на определённой версии Windows',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: DropdownButton<String>(
                  value: _wuVersion,
                  underline: const SizedBox.shrink(),
                  dropdownColor: scheme.surface,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurface,
                  ),
                  items: WindowsUpdateService.versionPresets
                      .map(
                        (version) => DropdownMenuItem<String>(
                          value: version,
                          child: Text(version),
                        ),
                      )
                      .toList(),
                  onChanged: wu.busy
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() {
                              _wuVersion = value;
                            });
                          }
                        },
                ),
              ),
              FilledButton.icon(
                onPressed: wu.busy || wu.targetBlocked || !isAdmin
                    ? null
                    : () {
                        _wuBlock(context);
                      },
                icon: const Icon(Icons.lock_outline),
                label: const Text('Заблокировать'),
              ),
              OutlinedButton.icon(
                onPressed: wu.busy || !wu.targetBlocked || !isAdmin
                    ? null
                    : () {
                        _wuUnblock(context);
                      },
                icon: const Icon(Icons.lock_open),
                label: const Text('Разблокировать'),
              ),
              TextButton.icon(
                onPressed: wu.busy || !isAdmin
                    ? null
                    : () async {
                        await wu.refresh();
                      },
                icon: const Icon(Icons.refresh),
                label: const Text('Обновить'),
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

  Widget _buildReservedStorageCard() {
    final services = widget.services;
    final theme = Theme.of(context);

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Резервируемое хранилище',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Text(
            'Windows резервирует место на диске под обновления и системные задачи. Отключение может освободить несколько гигабайт.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          WarningBanner(
            text:
                'ТЕСТОВАЯ ФУНКЦИЯ. Операция выполняется через DISM и может потребовать перезагрузки. Не отключай резервируемое хранилище, если не понимаешь, зачем это нужно.',
          ),
          if (services.system.reservedError.isNotEmpty) ...[
            const SizedBox(height: 12),
            InfoRow(
              label: 'Ошибка',
              value: services.system.reservedError,
            ),
          ],
          if (services.system.reservedMessage.isNotEmpty) ...[
            const SizedBox(height: 12),
            InfoRow(
              label: 'Вывод',
              value: services.system.reservedMessage,
            ),
          ],
          if (services.system.reservedBusy) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
              elevation: 0,
              shadowColor: Colors.transparent,
            ),
            onPressed: services.system.reservedBusy
                ? null
                : () {
                    _disableReservedStorage(context);
                  },
            icon: const Icon(Icons.storage_outlined),
            label: const Text('Отключить резервируемое хранилище'),
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

    final blockedByAdmin = needsAdmin;
    final canApply = !busy && !blockedByAdmin && status != TweakStatus.applied;
    final canRevert = tweak.reversible &&
        !busy &&
        !blockedByAdmin &&
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
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
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Производительность процессора',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Минимальная производительность процессора: $_perfValue%',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  Slider(
                    value: _perfValue.toDouble(),
                    min: 10,
                    max: 100,
                    divisions: 90,
                    label: '$_perfValue%',
                    onChanged: (value) {
                      setState(() {
                        _perfValue = value.round();
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () async {
                      try {
                        await services.powershell.run(
                          r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN " +
                              _perfValue.toString() +
                              r"; powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN " +
                              _perfValue.toString() +
                              r"; powercfg /setactive SCHEME_CURRENT; Write-Output 'OK'",
                          timeout: const Duration(seconds: 30),
                        );
                        showSnack(
                          context,
                          'Минимальная производительность: $_perfValue%',
                        );
                      } catch (e) {
                        showSnack(context, e.toString());
                      }
                    },
                    icon: const Icon(Icons.speed),
                    label: const Text('Применить'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
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

                          await services.defender.refresh(
                            isAdmin: services.system.isAdmin,
                          );
                          await services.advertising.refresh();
                          await services.widgets.refresh();

                          if (services.system.isAdmin) {
                            await services.windowsUpdate.refresh();
                          }

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
                OutlinedButton.icon(
                  onPressed: services.system.isLoading
                      ? null
                      : () async {
                          try {
                            await services.system.restartExplorer();
                            showSnack(context, 'Проводник перезапущен');
                          } catch (e) {
                            showSnack(context, e.toString());
                          }
                        },
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Перезапустить Проводник'),
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
            _buildWindowsUpdateCard(),
            const SizedBox(height: 16),
            _buildCleanupCard(),
            const SizedBox(height: 16),
            _buildReservedStorageCard(),
            const SizedBox(height: 16),
            for (final category in categories) ...[
              Builder(
                builder: (context) {
                  final query = services.search.query.trim().toLowerCase();

                  final items = services.tweaks
                      .where((t) => t.category == category)
                      .where((t) {
                        if (query.isEmpty) {
                          return true;
                        }

                        return t.title.toLowerCase().contains(query) ||
                            t.description.toLowerCase().contains(query);
                      })
                      .toList();

                  if (items.isEmpty) {
                    return const SizedBox.shrink();
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          categoryLabel(category),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      for (final tweak in items) ...[
                        _buildTweakCard(tweak),
                        const SizedBox(height: 12),
                      ],
                      const SizedBox(height: 8),
                    ],
                  );
                },
              ),
            ],
          ],
        );
      },
    );
  }
}