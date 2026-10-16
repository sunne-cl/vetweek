import 'package:flutter/material.dart';
import 'package:vetweek/models.dart';
import 'package:vetweek/services/base.dart';
import 'package:vetweek/widgets.dart';
import 'package:vetweek/pages/shell.dart';

class ExperimentsPage extends StatefulWidget {
  final AppServices services;

  const ExperimentsPage({
    super.key,
    required this.services,
  });

  @override
  State<ExperimentsPage> createState() => _ExperimentsPageState();
}

class _ExperimentsPageState extends State<ExperimentsPage> {
  final TextEditingController _gpuNameController = TextEditingController();
  final TextEditingController _cpuNameController = TextEditingController();
  final TextEditingController _namingController = TextEditingController();
  final TextEditingController _timerController = TextEditingController();

  String _gpuPnp = '';
  bool _prefilled = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!widget.services.experiments.checked) {
        widget.services.experiments.refresh();
      }
    });
  }

  @override
  void dispose() {
    _gpuNameController.dispose();
    _cpuNameController.dispose();
    _namingController.dispose();
    _timerController.dispose();
    super.dispose();
  }

  Future<bool> _admin(String title) async {
    return ensureAdminGeneric(context, widget.services, title);
  }

  Future<void> _confirmAndRun({
    required String title,
    required String message,
    required Future<void> Function() action,
    required String success,
    bool danger = true,
    bool admin = false,
  }) async {
    if (admin && !await _admin(title)) {
      return;
    }

    final confirmed = await confirmDialog(
      context,
      title: title,
      message: message,
      confirmLabel: 'Выполнить',
      danger: danger,
    );

    if (!confirmed) {
      return;
    }

    try {
      await action();
      showSnack(context, success);
    } catch (e) {
      showSnack(context, e.toString());
    }
  }

  Future<void> _openDrivesDialog() async {
    final exp = widget.services.experiments;
    final selected = <int>{};

    for (var i = 0; i < 26; i++) {
      if (exp.noDrivesMask & (1 << i) != 0) {
        selected.add(i);
      }
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);

        return StatefulBuilder(
          builder: (context, setDialogState) {
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
                        'Скрыть буквы дисков',
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Выбранные буквы исчезнут из раздела «Этот ПК». Данные не удаляются.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Flexible(
                        child: SingleChildScrollView(
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: List.generate(26, (i) {
                              final letter =
                                  String.fromCharCode('A'.codeUnitAt(0) + i);
                              final active = selected.contains(i);

                              return MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: GestureDetector(
                                  onTap: () {
                                    setDialogState(() {
                                      if (active) {
                                        selected.remove(i);
                                      } else {
                                        selected.add(i);
                                      }
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: active
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.surfaceVariant,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      letter,
                                      style:
                                          theme.textTheme.bodyMedium?.copyWith(
                                        color: active
                                            ? theme.colorScheme.onPrimary
                                            : theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () {
                              Navigator.of(dialogContext).pop();
                            },
                            child: const Text('Отмена'),
                          ),
                          const SizedBox(width: 12),
                          FilledButton(
                            onPressed: () async {
                              var mask = 0;

                              for (final i in selected) {
                                mask |= 1 << i;
                              }

                              Navigator.of(dialogContext).pop();

                              try {
                                await widget.services.experiments
                                    .setNoDrives(mask);
                                showSnack(context, 'Маска дисков применена');
                              } catch (e) {
                                showSnack(context, e.toString());
                              }
                            },
                            child: const Text('Применить'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _switchTile({
    required String title,
    required bool value,
    required Future<void> Function(bool) onChanged,
    bool enabled = true,
  }) {
    return SwitchListTile(
      title: Text(title),
      value: value,
      onChanged: !enabled || widget.services.experiments.busy
          ? null
          : (v) async {
              try {
                await onChanged(v);
              } catch (e) {
                if (mounted) {
                  showSnack(context, e.toString());
                }
              }
            },
    );
  }

  @override
  Widget build(BuildContext context) {
    final services = widget.services;
    final exp = services.experiments;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (!_prefilled && exp.checked) {
      _prefilled = true;
      _cpuNameController.text = exp.cpuName;
      _namingController.text = exp.namingTemplate;

      if (exp.gpus.isNotEmpty) {
        _gpuPnp = exp.gpus.first.pnpDeviceId;
        _gpuNameController.text = exp.gpus.first.displayName;
      }
    }

    return AnimatedBuilder(
      animation: exp,
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const PageHeader(
              title: 'Эксперименты',
              subtitle:
                  'Тестовые и потенциально рискованные функции. Применяйте осознанно',
            ),
            if (exp.busy) const LinearProgressIndicator(),
            if (exp.error.isNotEmpty) ...[
              SectionCard(child: InfoRow(label: 'Ошибка', value: exp.error)),
              const SizedBox(height: 16),
            ],
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Проводник и интерфейс',
                    style: theme.textTheme.titleLarge,
                  ),
                  _switchTile(
                    title: 'Скрыть часто используемые папки в быстром доступе',
                    value: !exp.showFrequent,
                    onChanged: (v) => exp.setShowFrequent(!v),
                  ),
                  _switchTile(
                    title: 'Отключить историю недавних документов',
                    value: !exp.showRecent,
                    onChanged: (v) => exp.setShowRecent(!v),
                  ),
                  _switchTile(
                    title: 'Использовать галочки для выбора элементов',
                    value: exp.autoCheck,
                    onChanged: exp.setAutoCheck,
                  ),
                  _switchTile(
                    title: 'Показывать подтверждение при удалении файлов',
                    value: exp.confirmDelete,
                    onChanged: exp.setConfirmDelete,
                  ),
                  _switchTile(
                    title: 'Кнопка «Завершить задачу» в меню панели задач',
                    value: exp.endTask,
                    onChanged: exp.setEndTask,
                  ),
                  _switchTile(
                    title: 'Выключить прозрачность',
                    value: exp.transparencyOff,
                    onChanged: exp.setTransparencyOff,
                  ),
                  _switchTile(
                    title: 'Выключить размытие на экране блокировки',
                    value: exp.lockBlurOff,
                    onChanged: (v) async {
                      if (v && !await _admin('Размытие экрана блокировки')) {
                        return;
                      }

                      await exp.setLockBlurOff(v);
                    },
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        onPressed: exp.busy
                            ? null
                            : () {
                                _openDrivesDialog();
                              },
                        icon: const Icon(Icons.visibility_off_outlined),
                        label: const Text('Скрыть буквы дисков'),
                      ),
                      OutlinedButton.icon(
                        onPressed: exp.busy
                            ? null
                            : () async {
                                await exp.setNoDrives(0);
                                showSnack(context, 'Все буквы показаны');
                              },
                        icon: const Icon(Icons.visibility_outlined),
                        label: const Text('Показать все буквы'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Цвет выделения',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton(
                        onPressed: exp.busy
                            ? null
                            : () async {
                                await exp.setHilightColor('0 120 215');
                                showSnack(context, 'Синий цвет выделения');
                              },
                        child: const Text('Синий'),
                      ),
                      FilledButton(
                        onPressed: exp.busy
                            ? null
                            : () async {
                                await exp.setHilightColor('188 0 45');
                                showSnack(context, 'Красный цвет выделения');
                              },
                        child: const Text('Красный'),
                      ),
                      FilledButton(
                        onPressed: exp.busy
                            ? null
                            : () async {
                                await exp.setHilightColor('56 106 32');
                                showSnack(context, 'Зеленый цвет выделения');
                              },
                        child: const Text('Зеленый'),
                      ),
                      OutlinedButton(
                        onPressed: exp.busy
                            ? null
                            : () async {
                                await exp.setHilightColor('');
                                showSnack(context, 'Цвет выделения сброшен');
                              },
                        child: const Text('Сбросить'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _namingController,
                    decoration: const InputDecoration(
                      labelText: 'Название новых папок и файлов по умолчанию',
                      hintText: 'Например: Новая папка',
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: exp.busy
                        ? null
                        : () async {
                            await exp.setNamingTemplate(
                              _namingController.text.trim(),
                            );
                            showSnack(context, 'Шаблон имени применен');
                          },
                    icon: const Icon(Icons.check),
                    label: const Text('Применить шаблон имени'),
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
                    'Переименование железа',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  WarningBanner(
                    text:
                        'Имя процессора хранится в энергозависимом разделе HARDWARE и сбрасывается при каждой перезагрузке. Переименование видеокарты пишет в защищенный раздел Enum и требует прав администратора.',
                  ),
                  const SizedBox(height: 16),
                  if (exp.gpus.isEmpty)
                    Text(
                      'Видеокарты не найдены',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    )
                  else ...[
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
                        value: exp.gpus.any((g) => g.pnpDeviceId == _gpuPnp)
                            ? _gpuPnp
                            : exp.gpus.first.pnpDeviceId,
                        underline: const SizedBox.shrink(),
                        dropdownColor: scheme.surface,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurface,
                        ),
                        items: exp.gpus
                            .map(
                              (g) => DropdownMenuItem<String>(
                                value: g.pnpDeviceId,
                                child: SizedBox(
                                  width: 320,
                                  child: Text(
                                    g.displayName,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: exp.busy
                            ? null
                            : (value) {
                                setState(() {
                                  _gpuPnp = value ?? '';

                                  for (final g in exp.gpus) {
                                    if (g.pnpDeviceId == _gpuPnp) {
                                      _gpuNameController.text = g.displayName;
                                    }
                                  }
                                });
                              },
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _gpuNameController,
                      decoration: const InputDecoration(
                        labelText: 'Новое имя видеокарты',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton.icon(
                          onPressed: exp.busy || _gpuPnp.isEmpty
                              ? null
                              : () async {
                                  if (!await _admin('Переименование видеокарты')) {
                                    return;
                                  }

                                  try {
                                    await exp.renameGpu(
                                      _gpuPnp,
                                      _gpuNameController.text.trim(),
                                    );
                                    showSnack(context, 'Видеокарта переименована');
                                  } catch (e) {
                                    showSnack(context, e.toString());
                                  }
                                },
                          icon: const Icon(Icons.check),
                          label: const Text('Переименовать видеокарту'),
                        ),
                        OutlinedButton.icon(
                          onPressed: exp.busy || _gpuPnp.isEmpty
                              ? null
                              : () async {
                                  if (!await _admin('Переименование видеокарты')) {
                                    return;
                                  }

                                  try {
                                    await exp.revertGpu(_gpuPnp);
                                    showSnack(context, 'Имя видеокарты восстановлено');
                                  } catch (e) {
                                    showSnack(context, e.toString());
                                  }
                                },
                          icon: const Icon(Icons.undo),
                          label: const Text('Восстановить имя'),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 20),
                  TextField(
                    controller: _cpuNameController,
                    decoration: const InputDecoration(
                      labelText: 'Новое имя процессора',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        onPressed: exp.busy
                            ? null
                            : () async {
                                if (!await _admin('Переименование процессора')) {
                                  return;
                                }

                                try {
                                  await exp.renameCpu(
                                    _cpuNameController.text.trim(),
                                  );
                                  showSnack(
                                    context,
                                    'Процессор переименован до перезагрузки',
                                  );
                                } catch (e) {
                                  showSnack(context, e.toString());
                                }
                              },
                        icon: const Icon(Icons.check),
                        label: const Text('Переименовать процессор'),
                      ),
                      OutlinedButton.icon(
                        onPressed: exp.busy
                            ? null
                            : () async {
                                if (!await _admin('Переименование процессора')) {
                                  return;
                                }

                                try {
                                  await exp.revertCpu();
                                  showSnack(context, 'Имя процессора восстановлено');
                                } catch (e) {
                                  showSnack(context, e.toString());
                                }
                              },
                        icon: const Icon(Icons.undo),
                        label: const Text('Восстановить имя'),
                      ),
                    ],
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
                    'Системные эксперименты',
                    style: theme.textTheme.titleLarge,
                  ),
                  _switchTile(
                    title: 'Отключить залипание клавиш',
                    value: exp.stickyKeysOff,
                    onChanged: exp.setStickyKeysOff,
                  ),
                  _switchTile(
                    title: 'Отключить изоляцию ядра / целостность памяти',
                    value: exp.hvciOff,
                    onChanged: (v) async {
                      if (v && !await _admin('Изоляция ядра')) {
                        return;
                      }

                      await exp.setHvciOff(v);
                    },
                  ),
                  _switchTile(
                    title: 'Отключить контроль учётных записей (UAC)',
                    value: exp.uacOff,
                    onChanged: (v) async {
                      if (v && !await _admin('UAC')) {
                        return;
                      }

                      await exp.setUacOff(v);
                    },
                  ),
                  _switchTile(
                    title: 'Суперподробные сведения о системе при загрузке',
                    value: exp.verboseStatus,
                    onChanged: (v) async {
                      if (v && !await _admin('Подробные сведения')) {
                        return;
                      }

                      await exp.setVerboseStatus(v);
                    },
                  ),
                  _switchTile(
                    title: 'Поменять левую и правую кнопки мыши',
                    value: exp.swapMouse,
                    onChanged: exp.setSwapMouse,
                  ),
                  _switchTile(
                    title: 'Синий экран по Ctrl + двойной Scroll Lock',
                    value: exp.crashOnCtrlScroll,
                    onChanged: (v) async {
                      if (v && !await _admin('BSOD по клавишам')) {
                        return;
                      }

                      await exp.setCrashOnCtrlScroll(v);
                    },
                  ),
                  _switchTile(
                    title: 'Выключить логотип Windows в загрузчике',
                    value: exp.quietBoot,
                    onChanged: (v) async {
                      if (!await _admin('Загрузчик')) {
                        return;
                      }

                      await exp.setQuietBoot(v);
                    },
                  ),
                  _switchTile(
                    title: 'Выключить анимацию в загрузчике',
                    value: exp.bootuxDisabled,
                    onChanged: (v) async {
                      if (!await _admin('Загрузчик')) {
                        return;
                      }

                      await exp.setBootuxDisabled(v);
                    },
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        onPressed: exp.busy
                            ? null
                            : () {
                                _confirmAndRun(
                                  title: 'Таймаут chkdsk',
                                  message:
                                      'Таймаут проверки диска при загрузке будет установлен на 60 секунд. Исходное значение сохраняется для отката.',
                                  action: exp.setChkdskTimeout,
                                  success: 'Таймаут chkdsk установлен на 60 секунд',
                                  admin: true,
                                );
                              },
                        icon: const Icon(Icons.timer_outlined),
                        label: const Text('chkdsk 60 секунд'),
                      ),
                      OutlinedButton.icon(
                        onPressed: exp.busy
                            ? null
                            : () async {
                                try {
                                  await exp.revertChkdskTimeout();
                                  showSnack(context, 'Таймаут chkdsk восстановлен');
                                } catch (e) {
                                  showSnack(context, e.toString());
                                }
                              },
                        icon: const Icon(Icons.undo),
                        label: const Text('Откатить таймаут'),
                      ),
                    ],
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
                    'Восстановление и очистка',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  InfoRow(
                    label: 'Папка TEMP',
                    value: formatBytes(exp.tempBytes),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: exp.busy
                        ? null
                        : () async {
                            await exp.cleanTemp();
                            showSnack(context, 'TEMP очищен');
                          },
                    icon: const Icon(Icons.cleaning_services_outlined),
                    label: const Text('Очистить TEMP'),
                  ),
                  const SizedBox(height: 16),
                  InfoRow(
                    label: 'Кэш pip',
                    value: formatBytes(exp.pipBytes),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: exp.busy
                        ? null
                        : () async {
                            await exp.cleanPip();
                            showSnack(context, 'Кэш pip очищен');
                          },
                    icon: const Icon(Icons.cleaning_services_outlined),
                    label: const Text('Очистить кэш pip'),
                  ),
                  const SizedBox(height: 16),
                  InfoRow(
                    label: 'Кэш миниатюр',
                    value: formatBytes(exp.thumbBytes),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: exp.busy
                        ? null
                        : () async {
                            await exp.cleanThumbs();
                            showSnack(context, 'Кэш миниатюр очищен');
                          },
                    icon: const Icon(Icons.cleaning_services_outlined),
                    label: const Text('Очистить кэш миниатюр'),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        onPressed: exp.busy
                            ? null
                            : () {
                                _confirmAndRun(
                                  title: 'Восстановление SFC',
                                  message:
                                      'Запустить sfc /scannow. Проверка может занять несколько минут.',
                                  action: exp.runSfc,
                                  success: 'SFC завершен',
                                  admin: true,
                                  danger: false,
                                );
                              },
                        icon: const Icon(Icons.build_outlined),
                        label: const Text('Восстановить SFC'),
                      ),
                      FilledButton.icon(
                        onPressed: exp.busy
                            ? null
                            : () {
                                _confirmAndRun(
                                  title: 'Восстановление DISM',
                                  message:
                                      'Запустить DISM /Online /Cleanup-Image /RestoreHealth. Операция может занять длительное время.',
                                  action: exp.runDism,
                                  success: 'DISM завершен',
                                  admin: true,
                                  danger: false,
                                );
                              },
                        icon: const Icon(Icons.build_outlined),
                        label: const Text('Восстановить DISM'),
                      ),
                    ],
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
                    'Таймер выключения',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _timerController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Минут до выключения',
                      hintText: '30',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        onPressed: exp.busy
                            ? null
                            : () async {
                                final minutes =
                                    int.tryParse(_timerController.text.trim());

                                if (minutes == null || minutes <= 0) {
                                  showSnack(context, 'Введите корректное число минут');
                                  return;
                                }

                                try {
                                  await exp.shutdownTimer(minutes);
                                  showSnack(context, 'Выключение через $minutes мин');
                                } catch (e) {
                                  showSnack(context, e.toString());
                                }
                              },
                        icon: const Icon(Icons.power_settings_new),
                        label: const Text('Поставить таймер'),
                      ),
                      OutlinedButton.icon(
                        onPressed: exp.busy
                            ? null
                            : () async {
                                try {
                                  await exp.cancelShutdown();
                                  showSnack(context, 'Таймер выключения отменен');
                                } catch (e) {
                                  showSnack(context, e.toString());
                                }
                              },
                        icon: const Icon(Icons.cancel_outlined),
                        label: const Text('Отменить таймер'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: exp.busy
                  ? null
                  : () async {
                      await exp.refresh();
                      showSnack(context, 'Эксперименты обновлены');
                    },
              icon: const Icon(Icons.refresh),
              label: const Text('Обновить состояние'),
            ),
          ],
        );
      },
    );
  }
}