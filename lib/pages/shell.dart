import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:vetweek/models.dart';
import 'package:vetweek/services/apps.dart';
import 'package:vetweek/services/base.dart';
import 'package:vetweek/services/network.dart';
import 'package:vetweek/services/system.dart';
import 'package:vetweek/services/tweaks.dart';
import 'package:vetweek/widgets.dart';
import 'package:vetweek/pages/core_pages.dart';
import 'package:vetweek/pages/dev_pages.dart';

void showSnack(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      duration: const Duration(milliseconds: 1800),
    ),
  );
}

Future<bool> confirmDialog(
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

Future<void> showWelcomeDialog(BuildContext context) async {
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return Dialog(
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: SizedBox(
          width: 520,
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Image.asset(
                      'logo.png',
                      width: 40,
                      height: 40,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return Icon(
                          Icons.tune,
                          size: 32,
                          color: scheme.primary,
                        );
                      },
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Добро пожаловать в VeTweek',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Версия 0.4.0',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  'VeTweek — инструмент для настройки и оптимизации Windows: приватность, телеметрия, очистка системы, производительность, сеть и инструменты разработчика.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                _WelcomePoint(
                  icon: Icons.restore,
                  text:
                      'Перед применением твиков рекомендуется создать точку восстановления Windows. Программа сама предложит её создать перед первым твиком.',
                ),
                const SizedBox(height: 10),
                _WelcomePoint(
                  icon: Icons.admin_panel_settings_outlined,
                  text:
                      'Для системных твиков требуются права администратора. Программа попросит перезапуск от администратора при необходимости.',
                ),
                const SizedBox(height: 10),
                _WelcomePoint(
                  icon: Icons.warning_amber_rounded,
                  text:
                      'Приложение создано с помощью искусственного интеллекта. Все действия выполняются под вашу полную ответственность. Создатели не несут ответственности за последствия.',
                ),
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                    },
                    child: const Text('Понять и продолжить'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _WelcomePoint extends StatelessWidget {
  final IconData icon;
  final String text;

  const _WelcomePoint({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 18,
          color: scheme.primary,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

Future<bool> ensureAdminGeneric(
  BuildContext context,
  AppServices services,
  String title,
) async {
  if (services.system.isAdmin) {
    return true;
  }

  final confirmed = await confirmDialog(
    context,
    title: 'Требуются права администратора',
    message:
        'Для действия «$title» нужны права администратора. VeTweek перезапустится от администратора.',
    confirmLabel: 'Перезапустить от администратора',
  );

  if (confirmed) {
    await services.system.elevateAndRestart();
  }

  return false;
}

Future<bool> ensureAdminTweak(
  BuildContext context,
  AppServices services,
  Tweak tweak,
) async {
  if (!tweak.requiresAdmin) {
    return true;
  }

  return ensureAdminGeneric(context, services, tweak.title);
}

Future<bool> ensureRestorePoint(
  BuildContext context,
  AppServices services, {
  bool force = false,
}) async {
  if (!force && services.state.restorePointSuggested) {
    return true;
  }

  final theme = Theme.of(context);

  final result = await showDialog<String>(
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
              Text(
                'Точка восстановления',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text(
                'Перед применением твиков рекомендуется создать точку восстановления Windows. Если выбрать «Без точки», дальнейшие действия выполняются на вашу ответственность.',
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
                      Navigator.of(dialogContext).pop('cancel');
                    },
                    child: const Text('Отмена'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: () {
                      Navigator.of(dialogContext).pop('skip');
                    },
                    child: const Text('Без точки'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () {
                      Navigator.of(dialogContext).pop('create');
                    },
                    child: const Text('Создать'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );

  if (result == 'cancel') {
    return false;
  }

  if (result == 'skip') {
    services.state.markRestorePointSuggested();
    await services.state.save();
    services.log.warning('Точка восстановления пропущена пользователем');
    return true;
  }

  if (!services.system.isAdmin) {
    final admin = await ensureAdminGeneric(
      context,
      services,
      'Создание точки восстановления',
    );

    if (!admin) {
      return false;
    }
  }

  try {
    await services.restorePoint.create();
    services.state.markRestorePointSuggested();
    await services.state.save();
    return true;
  } catch (e) {
    showSnack(context, e.toString());
    return false;
  }
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

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }

      if (widget.services.state.firstLaunchCompleted) {
        return;
      }

      await showWelcomeDialog(context);

      widget.services.state.markFirstLaunchCompleted();
      await widget.services.state.save();
    });
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
    } else {
      setState(() {});
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

  int _safeIndex(int value, int length) {
    if (value < 0 || value >= length) {
      return 0;
    }

    return value;
  }

  Widget _buildPage(int index) {
    switch (index) {
      case 0:
        return DashboardPage(
          services: widget.services,
          onOpenCleanup: () {
            setState(() {
              _index = 1;
            });
          },
        );
      case 1:
        return TweaksPage(services: widget.services);
      case 2:
        return AppsPage(services: widget.services);
      case 3:
        return NetworkPage(services: widget.services);
      case 4:
        return LogsPage(services: widget.services);
      case 5:
        return SettingsPage(services: widget.services);
      default:
        return DevPage(services: widget.services);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final devEnabled = widget.services.settings.devModeEnabled;

    final destinations = <NavigationRailDestination>[
      const NavigationRailDestination(
        icon: Icon(Icons.dashboard_outlined),
        selectedIcon: Icon(Icons.dashboard),
        label: Text('Главная'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.tune_outlined),
        selectedIcon: Icon(Icons.tune),
        label: Text('Твики'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.apps_outlined),
        selectedIcon: Icon(Icons.apps),
        label: Text('Приложения'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.lan_outlined),
        selectedIcon: Icon(Icons.lan),
        label: Text('Сеть'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.list_alt_outlined),
        selectedIcon: Icon(Icons.list_alt),
        label: Text('Журнал'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.settings_outlined),
        selectedIcon: Icon(Icons.settings),
        label: Text('Настройки'),
      ),
      if (devEnabled)
        const NavigationRailDestination(
          icon: Icon(Icons.developer_board_outlined),
          selectedIcon: Icon(Icons.developer_board),
          label: Text('Dev'),
        ),
    ];

    final safeIndex = _safeIndex(_index, destinations.length);

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
                    isAdmin: widget.services.system.isAdmin,
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
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: SizedBox(
                        width: 96,
                        child: NavigationRail(
                          selectedIndex: safeIndex,
                          onDestinationSelected: (value) {
                            setState(() {
                              _index = value;
                            });
                          },
                          labelType: NavigationRailLabelType.all,
                          destinations: destinations,
                        ),
                      ),
                    ),
                    Expanded(
                      child: _buildPage(safeIndex),
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