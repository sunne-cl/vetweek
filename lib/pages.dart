import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:vetweek/models.dart';
import 'package:vetweek/services.dart';
import 'package:vetweek/widgets.dart';

Future<bool> ensureAdmin(
  BuildContext context,
  AppServices services,
  Tweak tweak,
) async {
  if (!tweak.requiresAdmin) {
    return true;
  }

  if (services.system.isAdmin) {
    return true;
  }

  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final theme = Theme.of(dialogContext);

      return Dialog(
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Требуются права администратора',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text(
                'Для твика «${tweak.title}» нужны права администратора. VeTweek перезапустится от администратора, после чего действие можно применить повторно.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(dialogContext).pop(false);
                    },
                    child: const Text('Отмена'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () {
                      Navigator.of(dialogContext).pop(true);
                    },
                    child: const Text('Перезапустить от администратора'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );

  if (result == true) {
    await services.system.elevateAndRestart();
  }

  return false;
}

Future<bool> ensureAdminGeneric(
  BuildContext context,
  AppServices services,
  String title,
) async {
  if (services.system.isAdmin) {
    return true;
  }

  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final theme = Theme.of(dialogContext);

      return Dialog(
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Требуются права администратора',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text(
                'Для действия «$title» нужны права администратора. VeTweek перезапустится от администратора.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(dialogContext).pop(false);
                    },
                    child: const Text('Отмена'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () {
                      Navigator.of(dialogContext).pop(true);
                    },
                    child: const Text('Перезапустить от администратора'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );

  if (result == true) {
    await services.system.elevateAndRestart();
  }

  return false;
}

class AppShell extends StatefulWidget {
  final AppServices services;

  const AppShell({
    super.key,
    required this.services,
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WindowListener {
  int _index = 0;
  bool _maximized = false;
  Rect _normalBounds = const Rect.fromLTWH(0, 0, 1320, 840);

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();

    windowManager.addListener(this);

    windowManager.isMaximized().then((value) {
      if (mounted) {
        setState(() {
          _maximized = value;
        });
      }
    });

    windowManager.getBounds().then((value) {
      _normalBounds = value;
    });

    _searchController.addListener(_onSearch);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearch() {
    final query = _searchController.text;

    widget.services.appx.setQuery(query);

    if (query.trim().isNotEmpty && _index != 2) {
      setState(() {
        _index = 2;
      });
    }
  }

  @override
  void onWindowMaximized() {
    if (mounted) {
      setState(() {
        _maximized = true;
      });
    }
  }

  @override
  void onWindowUnmaximized() {
    if (mounted) {
      setState(() {
        _maximized = false;
      });
    }
  }

  Future<void> _minimize() async {
    await windowManager.minimize();
  }

  Future<void> _toggleMaximize() async {
    final isMax = await windowManager.isMaximized();

    if (isMax) {
      await windowManager.unmaximize();
      await windowManager.setBounds(_normalBounds);
      setState(() {
        _maximized = false;
      });
    } else {
      _normalBounds = await windowManager.getBounds();
      await windowManager.maximize();
      setState(() {
        _maximized = true;
      });
    }
  }

  Future<void> _close() async {
    await windowManager.close();
  }

  Widget _buildPage() {
    switch (_index) {
      case 0:
        return DashboardPage(services: widget.services);
      case 1:
        return TweaksPage(services: widget.services);
      case 2:
        return AppsPage(services: widget.services);
      case 3:
        return LogsPage(services: widget.services);
      default:
        return SettingsPage(services: widget.services);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        color: scheme.surface,
        child: Scaffold(
          backgroundColor: scheme.surface,
          body: Column(
            children: [
              AnimatedBuilder(
                animation: widget.services.system,
                builder: (context, _) {
                  return TopBar(
                    services: widget.services,
                    searchController: _searchController,
                    maximized: _maximized,
                    onMinimize: _minimize,
                    onToggleMaximize: _toggleMaximize,
                    onClose: _close,
                  );
                },
              ),
              Expanded(
                child: Row(
                  children: [
                    NavigationRail(
                      selectedIndex: _index,
                      onDestinationSelected: (value) {
                        setState(() {
                          _index = value;
                        });
                      },
                      labelType: NavigationRailLabelType.all,
                      destinations: const [
                        NavigationRailDestination(
                          icon: Icon(Icons.dashboard_outlined),
                          selectedIcon: Icon(Icons.dashboard),
                          label: Text('Главная'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.tune_outlined),
                          selectedIcon: Icon(Icons.tune),
                          label: Text('Твики'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.apps_outlined),
                          selectedIcon: Icon(Icons.apps),
                          label: Text('Приложения'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.list_alt_outlined),
                          selectedIcon: Icon(Icons.list_alt),
                          label: Text('Журнал'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.settings_outlined),
                          selectedIcon: Icon(Icons.settings),
                          label: Text('Настройки'),
                        ),
                      ],
                    ),
                    Expanded(
                      child: _buildPage(),
                    ),
                  ],
                ),
              ),
              Container(
                width: double.infinity,
                color: scheme.surface,
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
                child: Text(
                  'Создано с помощью vexikoff + Qwen',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DashboardPage extends StatefulWidget {
  final AppServices services;

  const DashboardPage({
    super.key,
    required this.services,
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
      widget.services.settings,
      widget.services.log,
      widget.services.system,
      widget.services.appx,
      widget.services.defender,
      widget.services.advertising,
      widget.services.widgets,
      widget.services.engine,
    ]);
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

  Future<void> _refreshAll() async {
    final messenger = ScaffoldMessenger.of(context);
    final services = widget.services;

    await services.system.refresh();
    await services.defender.refresh(isAdmin: services.system.isAdmin);
    await services.advertising.refresh();
    await services.widgets.refresh();
    await services.engine.refreshAll(services.tweaks, force: true);

    messenger.showSnackBar(
      SnackBar(
        content: const Text('Обновление статусов завершено'),
        duration: const Duration(milliseconds: 1600),
      ),
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
              title: 'Главная',
              subtitle: 'Состояние системы и быстрые действия',
            ),
            SectionCard(
              child: Column(
                children: [
                  const InfoRow(
                    label: 'Приложение',
                    value: 'VeTweek',
                  ),
                  const SizedBox(height: 12),
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
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: services.system.isLoading ||
                          services.defender.busy ||
                          services.advertising.busy ||
                          services.widgets.busy ||
                          services.engine.anyBusy
                      ? null
                      : _refreshAll,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Обновить статусы'),
                ),
                FilledButton.icon(
                  onPressed: services.appx.loading
                      ? null
                      : () async {
                          final messenger = ScaffoldMessenger.of(context);
                          await services.appx.load();

                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                services.appx.error.isEmpty
                                    ? 'Список приложений загружен'
                                    : services.appx.error,
                              ),
                              duration: const Duration(milliseconds: 1600),
                            ),
                          );
                        },
                  icon: const Icon(Icons.apps),
                  label: const Text('Загрузить приложения'),
                ),
                FilledButton.icon(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);

                    try {
                      final path = await services.log.export();

                      messenger.showSnackBar(
                        SnackBar(
                          content: Text('Журнал сохранен: $path'),
                          duration: const Duration(milliseconds: 1600),
                        ),
                      );
                    } catch (e) {
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(e.toString()),
                          duration: const Duration(milliseconds: 1600),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Экспорт журнала'),
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
  bool _initialRefreshing = false;

  @override
  void initState() {
    super.initState();

    _listenable = Listenable.merge([
      widget.services.system,
      widget.services.defender,
      widget.services.advertising,
      widget.services.widgets,
      widget.services.engine,
    ]);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshInitial();
    });
  }

  Future<void> _refreshInitial() async {
    if (_initialRefreshing) {
      return;
    }

    _initialRefreshing = true;

    if (mounted) {
      setState(() {});
    }

    try {
      await widget.services.system.refresh();
      await widget.services.defender.refresh(
        isAdmin: widget.services.system.isAdmin,
      );
      await widget.services.advertising.refresh();
      await widget.services.widgets.refresh();
      await widget.services.engine.refreshAll(
        widget.services.tweaks,
        force: false,
      );
    } catch (_) {
      return;
    } finally {
      _initialRefreshing = false;

      if (mounted) {
        setState(() {});
      }
    }
  }

  void _snack(BuildContext context, String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(milliseconds: 1600),
      ),
    );
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

  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
    bool danger = false,
  }) async {
    final theme = Theme.of(context);

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: theme.colorScheme.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleLarge),
                const SizedBox(height: 12),
                Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () {
                        Navigator.of(dialogContext).pop(false);
                      },
                      child: const Text('Отмена'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      style: danger
                          ? FilledButton.styleFrom(
                              backgroundColor: theme.colorScheme.error,
                              foregroundColor: theme.colorScheme.onError,
                              elevation: 0,
                              shadowColor: Colors.transparent,
                            )
                          : null,
                      onPressed: () {
                        Navigator.of(dialogContext).pop(true);
                      },
                      child: Text(confirmLabel),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    return result == true;
  }

  Future<void> _disableDefender(BuildContext context) async {
    final services = widget.services;

    if (!await ensureAdminGeneric(context, services, 'Defender')) {
      return;
    }

    final confirmed = await _confirm(
      context,
      title: 'Отключение реальной защиты',
      message:
          'VeTweek отключит реальную защиту. Это снизит безопасность системы. Продолжить?',
      confirmLabel: 'Отключить',
      danger: true,
    );

    if (!confirmed) {
      return;
    }

    try {
      await services.defender.setRealtimeDisabled(true);
      await services.defender.refresh(isAdmin: true);
      _snack(context, 'Реальная защита отключена');
    } catch (e) {
      _snack(context, e.toString());
    }
  }

  Future<void> _enableDefender(BuildContext context) async {
    final services = widget.services;

    if (!await ensureAdminGeneric(context, services, 'Defender')) {
      return;
    }

    try {
      await services.defender.setRealtimeDisabled(false);
      await services.defender.refresh(isAdmin: true);
      _snack(context, 'Реальная защита включена');
    } catch (e) {
      _snack(context, e.toString());
    }
  }

  Future<void> _disableAds(BuildContext context) async {
    try {
      await widget.services.advertising.disableAds();
      _snack(context, 'Рекламные параметры отключены');
    } catch (e) {
      _snack(context, e.toString());
    }
  }

  Future<void> _enableAds(BuildContext context) async {
    try {
      await widget.services.advertising.enableAds();
      _snack(context, 'Рекламные параметры включены');
    } catch (e) {
      _snack(context, e.toString());
    }
  }

  Future<void> _removeWidgets(BuildContext context) async {
    final confirmed = await _confirm(
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
      await widget.services.widgets.removePackages();
      _snack(context, 'Пакеты виджетов и погоды удалены');
    } catch (e) {
      _snack(context, e.toString());
    }
  }

  Future<void> _applyTweak(BuildContext context, Tweak tweak) async {
    final services = widget.services;

    final ok = await ensureAdmin(context, services, tweak);

    if (!ok) {
      return;
    }

    try {
      await services.engine.apply(tweak);
      _snack(context, 'Применено: ${tweak.title}');
    } catch (e) {
      _snack(context, e.toString());
    }
  }

  Future<void> _revertTweak(BuildContext context, Tweak tweak) async {
    final services = widget.services;

    final ok = await ensureAdmin(context, services, tweak);

    if (!ok) {
      return;
    }

    try {
      await services.engine.revert(tweak);
      _snack(context, 'Откачено: ${tweak.title}');
    } catch (e) {
      _snack(context, e.toString());
    }
  }

  Future<void> _refreshAllTweaks(BuildContext context) async {
    final services = widget.services;

    try {
      await services.engine.refreshAll(services.tweaks, force: true);
      _snack(context, 'Статусы твиков обновлены');
    } catch (e) {
      _snack(context, e.toString());
    }
  }

  Widget _buildCustomDefender(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final services = widget.services;

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Defender', style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          InfoRow(
            label: 'Статус',
            value: _defenderText(services.defender.status),
          ),
          if (services.defender.error.isNotEmpty) ...[
            const SizedBox(height: 12),
            InfoRow(label: 'Ошибка', value: services.defender.error),
          ],
          if (services.defender.busy || _initialRefreshing) ...[
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
                onPressed: _initialRefreshing ||
                        services.defender.busy ||
                        services.defender.status == DefenderStatus.disabled
                    ? null
                    : () {
                        _disableDefender(context);
                      },
                icon: const Icon(Icons.shield_outlined),
                label: const Text('Отключить реальную защиту'),
              ),
              FilledButton.icon(
                onPressed: _initialRefreshing ||
                        services.defender.busy ||
                        services.defender.status == DefenderStatus.enabled
                    ? null
                    : () {
                        _enableDefender(context);
                      },
                icon: const Icon(Icons.shield),
                label: const Text('Включить реальную защиту'),
              ),
              TextButton.icon(
                onPressed: _initialRefreshing || services.defender.busy
                    ? null
                    : () async {
                        await services.defender.refresh(
                          isAdmin: services.system.isAdmin,
                        );
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

  Widget _buildCustomAdvertising(BuildContext context) {
    final theme = Theme.of(context);
    final services = widget.services;

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Реклама и рекомендации', style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          InfoRow(
            label: 'Статус',
            value: _advertisingText(services.advertising.status),
          ),
          if (services.advertising.error.isNotEmpty) ...[
            const SizedBox(height: 12),
            InfoRow(label: 'Ошибка', value: services.advertising.error),
          ],
          if (services.advertising.busy || _initialRefreshing) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: _initialRefreshing ||
                        services.advertising.busy ||
                        services.advertising.status ==
                            AdvertisingStatus.disabled
                    ? null
                    : () {
                        _disableAds(context);
                      },
                icon: const Icon(Icons.block),
                label: const Text('Отключить рекламные параметры'),
              ),
              TextButton.icon(
                onPressed: _initialRefreshing ||
                        services.advertising.busy ||
                        services.advertising.status ==
                            AdvertisingStatus.enabled
                    ? null
                    : () {
                        _enableAds(context);
                      },
                icon: const Icon(Icons.restore),
                label: const Text('Включить рекламные параметры'),
              ),
              TextButton.icon(
                onPressed: _initialRefreshing || services.advertising.busy
                    ? null
                    : () async {
                        await services.advertising.refresh();
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

  Widget _buildCustomWidgets(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final services = widget.services;

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Виджеты и погода', style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          InfoRow(
            label: 'Найдено пакетов',
            value: services.widgets.packagesLoaded
                ? services.widgets.packageNames.length.toString()
                : 'Не проверено',
          ),
          if (services.widgets.error.isNotEmpty) ...[
            const SizedBox(height: 12),
            InfoRow(label: 'Ошибка', value: services.widgets.error),
          ],
          if (services.widgets.busy || _initialRefreshing) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],
          if (services.widgets.packageNames.isNotEmpty) ...[
            const SizedBox(height: 16),
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
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: _initialRefreshing || services.widgets.busy
                    ? null
                    : () async {
                        await services.widgets.refresh();
                      },
                icon: const Icon(Icons.search),
                label: const Text('Проверить пакеты'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError,
                  elevation: 0,
                  shadowColor: Colors.transparent,
                ),
                onPressed: _initialRefreshing ||
                        services.widgets.busy ||
                        services.widgets.packageNames.isEmpty
                    ? null
                    : () {
                        _removeWidgets(context);
                      },
                icon: const Icon(Icons.delete_outline),
                label: const Text('Удалить найденные пакеты'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTweakCard(BuildContext context, Tweak tweak) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final services = widget.services;

    final status = services.engine.statusOf(tweak.id);
    final busy = services.engine.isBusy(tweak.id);
    final needsAdmin = tweak.requiresAdmin && !services.system.isAdmin;
    final error = services.engine.errorFor(tweak.id);

    String statusLabel;
    Color statusColor;

    if (busy) {
      statusLabel = 'Выполняется';
      statusColor = scheme.tertiary;
    } else if (needsAdmin) {
      statusLabel = 'Нужен админ';
      statusColor = scheme.tertiary;
    } else if (_initialRefreshing && status == TweakStatus.unknown) {
      statusLabel = 'Проверка';
      statusColor = scheme.tertiary;
    } else {
      statusLabel = tweakStatusLabel(status);
      statusColor = tweakStatusColor(context, status);
    }

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  tweak.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              StatusChip(
                label: statusLabel,
                color: statusColor,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            tweak.description,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (error.isNotEmpty) ...[
            const SizedBox(height: 12),
            InfoRow(label: 'Ошибка', value: error),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: _initialRefreshing || busy
                    ? null
                    : () {
                        _applyTweak(context, tweak);
                      },
                icon: const Icon(Icons.check),
                label: const Text('Применить'),
              ),
              if (tweak.reversible)
                OutlinedButton.icon(
                  onPressed: _initialRefreshing || busy
                      ? null
                      : () {
                          _revertTweak(context, tweak);
                        },
                  icon: const Icon(Icons.undo),
                  label: const Text('Откатить'),
                ),
              TextButton.icon(
                onPressed: _initialRefreshing || busy
                    ? null
                    : () async {
                        await services.engine.refresh(tweak);
                      },
                icon: const Icon(Icons.refresh),
                label: const Text('Статус'),
              ),
            ],
          ),
        ],
      ),
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
                  'Управление защитой, рекламой, приватностью и системой',
            ),
            if (_initialRefreshing) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 16),
            ],
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: _initialRefreshing || services.engine.anyBusy
                      ? null
                      : () {
                          _refreshAllTweaks(context);
                        },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Обновить все статусы'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildCustomDefender(context),
            const SizedBox(height: 16),
            _buildCustomAdvertising(context),
            const SizedBox(height: 16),
            _buildCustomWidgets(context),
            const SizedBox(height: 16),
            for (final category in categories) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  categoryLabel(category),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              for (final tweak in services.tweaks
                  .where((t) => t.category == category)) ...[
                _buildTweakCard(context, tweak),
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
      widget.services.log,
    ]);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.services.appx.packages.isEmpty &&
          !widget.services.appx.loading) {
        widget.services.appx.load();
      }
    });
  }

  Future<void> _removeSelected(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final services = widget.services;
    final count = services.appx.selectedCount;

    if (count == 0) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);

        return Dialog(
          backgroundColor: theme.colorScheme.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Удаление приложений',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Text(
                  'Выбрано приложений: $count. Действие может быть необратимым для некоторых пакетов.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () {
                        Navigator.of(dialogContext).pop(false);
                      },
                      child: const Text('Отмена'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: () {
                        Navigator.of(dialogContext).pop(true);
                      },
                      child: const Text('Удалить'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (confirmed == true) {
      final result = await services.appx.removeSelected();

      messenger.showSnackBar(
        SnackBar(
          content: Text(result),
          duration: const Duration(milliseconds: 1600),
        ),
      );
    }
  }

  Future<void> _export(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);

    try {
      final path = await widget.services.appx.exportBackup();

      messenger.showSnackBar(
        SnackBar(
          content: Text('Резервная копия сохранена: $path'),
          duration: const Duration(milliseconds: 1600),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          duration: const Duration(milliseconds: 1600),
        ),
      );
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
                title: 'Приложения Windows',
                subtitle: 'Просмотр и удаление встроенных пакетов',
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
                      onPressed: services.appx.loading
                          ? null
                          : () async {
                              await services.appx.load();
                            },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Обновить'),
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
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (services.appx.loading || services.appx.busy)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: LinearProgressIndicator(),
              ),
            if (services.appx.error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: SectionCard(
                  child: Text(
                    services.appx.error,
                    style: TextStyle(
                      color: scheme.error,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            if (!services.appx.loading && packages.isEmpty)
              Expanded(
                child: Center(
                  child: Text(
                    services.appx.packages.isEmpty
                        ? 'Список приложений не загружен'
                        : 'Ничего не найдено',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  itemCount: packages.length,
                  itemBuilder: (context, index) {
                    final package = packages[index];

                    return Container(
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
                        final messenger = ScaffoldMessenger.of(context);

                        try {
                          final path = await services.log.export();

                          messenger.showSnackBar(
                            SnackBar(
                              content: Text('Журнал сохранен: $path'),
                              duration: const Duration(milliseconds: 1600),
                            ),
                          );
                        } catch (e) {
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(e.toString()),
                              duration: const Duration(milliseconds: 1600),
                            ),
                          );
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
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                    ),
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
                                    color: ThemeData.estimateBrightnessForColor(
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