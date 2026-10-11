import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:vetweek/models.dart';
import 'package:vetweek/services.dart';

class TopBar extends StatelessWidget {
  final AppServices services;
  final TextEditingController searchController;
  final bool maximized;
  final VoidCallback onMinimize;
  final VoidCallback onToggleMaximize;
  final VoidCallback onClose;

  const TopBar({
    super.key,
    required this.services,
    required this.searchController,
    required this.maximized,
    required this.onMinimize,
    required this.onToggleMaximize,
    required this.onClose,
  });

  Future<void> _startDrag(DragStartDetails details) async {
    await windowManager.startDragging();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      height: 64,
      color: scheme.surface,
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: _startDrag,
            child: Container(
              width: 200,
              padding: const EdgeInsets.only(left: 20),
              alignment: Alignment.centerLeft,
              child: Image.asset(
                'logo.png',
                height: 28,
                width: 28,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                errorBuilder: (context, error, stackTrace) {
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: searchController,
                decoration: InputDecoration(
                  hintText: 'Поиск приложений',
                  prefixIcon: const Icon(Icons.search, size: 20),
                ),
              ),
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: _startDrag,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Container(
                margin: const EdgeInsets.only(right: 16),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: services.system.isAdmin
                      ? scheme.primaryContainer
                      : scheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  services.system.isAdmin ? 'Администратор' : 'Пользователь',
                  style: TextStyle(
                    fontSize: 12,
                    color: services.system.isAdmin
                        ? scheme.onPrimaryContainer
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
          WindowButton(
            icon: Icons.minimize,
            onTap: onMinimize,
          ),
          WindowButton(
            icon: maximized ? Icons.filter_none : Icons.crop_square,
            onTap: onToggleMaximize,
          ),
          WindowButton(
            icon: Icons.close,
            onTap: onClose,
            danger: true,
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class WindowButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool danger;

  const WindowButton({
    required this.icon,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: SizedBox(
        width: 46,
        height: 64,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            hoverColor: Colors.transparent,
            child: Center(
              child: Icon(
                icon,
                size: 20,
                color: danger ? scheme.error : scheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PageHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const PageHeader({
    super.key,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class SectionCard extends StatelessWidget {
  final Widget child;

  const SectionCard({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}

class InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const InfoRow({
    super.key,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 220,
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}

class StatusChip extends StatelessWidget {
  final String label;
  final Color color;

  const StatusChip({
    super.key,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

String tweakStatusLabel(TweakStatus status) {
  switch (status) {
    case TweakStatus.unknown:
      return 'Не проверено';
    case TweakStatus.applied:
      return 'Применено';
    case TweakStatus.notApplied:
      return 'Не применено';
    case TweakStatus.partial:
      return 'Частично';
    case TweakStatus.needsAdmin:
      return 'Нужен админ';
    case TweakStatus.error:
      return 'Ошибка';
  }
}

Color tweakStatusColor(BuildContext context, TweakStatus status) {
  final scheme = Theme.of(context).colorScheme;

  switch (status) {
    case TweakStatus.applied:
      return scheme.primary;
    case TweakStatus.notApplied:
      return scheme.onSurfaceVariant;
    case TweakStatus.partial:
      return scheme.tertiary;
    case TweakStatus.needsAdmin:
      return scheme.tertiary;
    case TweakStatus.error:
      return scheme.error;
    case TweakStatus.unknown:
      return scheme.onSurfaceVariant;
  }
}

String categoryLabel(TweakCategory category) {
  switch (category) {
    case TweakCategory.privacy:
      return 'Конфиденциальность и телеметрия';
    case TweakCategory.explorer:
      return 'Проводник и контекстное меню';
    case TweakCategory.system:
      return 'Система и очистка';
    case TweakCategory.performance:
      return 'Производительность и игры';
  }
}