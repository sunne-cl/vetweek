import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vetweek/models.dart';
import 'package:vetweek/services/apps.dart';
import 'package:vetweek/services/base.dart';
import 'package:vetweek/widgets.dart';
import 'package:vetweek/pages/shell.dart';

class NetworkPage extends StatefulWidget {
  final AppServices services;

  const NetworkPage({
    super.key,
    required this.services,
  });

  @override
  State<NetworkPage> createState() => _NetworkPageState();
}

class _NetworkPageState extends State<NetworkPage> {
  late final Listenable _listenable;

  final TextEditingController _primaryController = TextEditingController();
  final TextEditingController _secondaryController = TextEditingController();
  final TextEditingController _gatewayController = TextEditingController();

  String _prefilledAlias = '';
  bool _hostsBusy = false;
  bool _hostsHasBackup = false;

  @override
  void initState() {
    super.initState();

    _listenable = Listenable.merge([
      widget.services.network,
      widget.services.system,
      widget.services.log,
    ]);

    widget.services.network.addListener(_onNetworkChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.services.network.adapters.isEmpty) {
        widget.services.network.refreshAdapters();
      }
      _checkHostsBackup();
    });
  }

  @override
  void dispose() {
    widget.services.network.removeListener(_onNetworkChanged);
    _primaryController.dispose();
    _secondaryController.dispose();
    _gatewayController.dispose();
    super.dispose();
  }

  void _onNetworkChanged() {
    final network = widget.services.network;
    final alias = network.selectedAlias;

    if (alias.isEmpty || alias == _prefilledAlias) {
      return;
    }

    _prefilledAlias = alias;

    NetworkAdapterInfo? adapter;

    for (final item in network.adapters) {
      if (item.alias == alias) {
        adapter = item;
      }
    }

    if (adapter == null) {
      return;
    }

    _primaryController.text =
        adapter.dnsServers.isNotEmpty ? adapter.dnsServers[0] : '';
    _secondaryController.text =
        adapter.dnsServers.length > 1 ? adapter.dnsServers[1] : '';
    _gatewayController.text =
        adapter.gateways.isNotEmpty ? adapter.gateways[0] : '';
  }

  Future<void> _checkHostsBackup() async {
    final result = await widget.services.powershell.run(
      r"$ErrorActionPreference='SilentlyContinue'; if (Test-Path (Join-Path $env:APPDATA 'VeTweek\hosts_backup')) { 'HAS_BACKUP' } else { 'NO_BACKUP' }",
      timeout: const Duration(seconds: 15),
    );

    if (mounted) {
      setState(() {
        _hostsHasBackup = result.stdout.trim() == 'HAS_BACKUP';
      });
    }
  }

  Future<void> _applyDns(String primary, String secondary) async {
    final services = widget.services;

    if (!await ensureAdminGeneric(context, services, 'DNS')) {
      return;
    }

    final confirmed = await confirmDialog(
      context,
      title: 'Смена DNS',
      message:
          'VeTweek изменит DNS для выбранного адаптера. При неверных адресах интернет может перестать работать. Продолжить?',
      confirmLabel: 'Применить',
    );

    if (!confirmed) {
      return;
    }

    try {
      await services.network.applyDns(primary, secondary);
      await services.network.refreshAdapters();
      showSnack(context, 'DNS применен');
    } catch (e) {
      showSnack(context, e.toString());
    }
  }

  Future<void> _resetDns() async {
    final services = widget.services;

    if (!await ensureAdminGeneric(context, services, 'Сброс DNS')) {
      return;
    }

    try {
      await services.network.resetDns();
      await services.network.refreshAdapters();
      showSnack(context, 'DNS сброшен на автоматический');
    } catch (e) {
      showSnack(context, e.toString());
    }
  }

  Future<void> _applyGateway() async {
    final services = widget.services;
    final gateway = _gatewayController.text.trim();

    if (gateway.isEmpty) {
      showSnack(context, 'Введите адрес шлюза');
      return;
    }

    if (!await ensureAdminGeneric(context, services, 'Шлюз')) {
      return;
    }

    final confirmed = await confirmDialog(
      context,
      title: 'Изменение шлюза',
      message:
          'Неверный шлюз может полностью отключить интернет до ручной настройки. Продолжить?',
      confirmLabel: 'Применить',
      danger: true,
    );

    if (!confirmed) {
      return;
    }

    try {
      await services.network.applyGateway(gateway);
      await services.network.refreshAdapters();
      showSnack(context, 'Шлюз применен');
    } catch (e) {
      showSnack(context, e.toString());
    }
  }

  Future<void> _flushDns() async {
    final services = widget.services;

    if (!await ensureAdminGeneric(context, services, 'Очистка DNS')) {
      return;
    }

    try {
      await services.network.flushDns();
      showSnack(context, 'Кэш DNS очищен');
    } catch (e) {
      showSnack(context, e.toString());
    }
  }

  Future<void> _resetNetwork() async {
    final services = widget.services;

    if (!await ensureAdminGeneric(context, services, 'Сброс сети')) {
      return;
    }

    final confirmed = await confirmDialog(
      context,
      title: 'Сброс сети',
      message:
          'Будут сброшены Winsock, TCP/IP, выдан и получен IP, очищен DNS. Требуется перезагрузка. Продолжить?',
      confirmLabel: 'Сбросить',
      danger: true,
    );

    if (!confirmed) {
      return;
    }

    try {
      await services.network.resetNetwork();
      await services.network.refreshAdapters();
      showSnack(context, 'Сброс сети выполнен. Требуется перезагрузка.');
    } catch (e) {
      showSnack(context, e.toString());
    }
  }

  Future<void> _applyHosts() async {
    final services = widget.services;

    if (_hostsBusy) {
      return;
    }

    if (!await ensureAdminGeneric(context, services, 'Hosts файл')) {
      return;
    }

    final confirmed = await confirmDialog(
      context,
      title: 'Применение hosts для разблокировки',
      message:
          'Будет скачан hosts файл с dns.malw.link и применён к системе. Оригинальный hosts будет сохранён в %APPDATA%\\VeTweek\\hosts_backup для возможного отката. Продолжить?',
      confirmLabel: 'Применить',
      danger: true,
    );

    if (!confirmed) {
      return;
    }

    setState(() {
      _hostsBusy = true;
    });

    try {
      final url =
          'https://raw.githubusercontent.com/ImMALWARE/dns.malw.link/refs/heads/master/hosts';

      final command =
          "\$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; \$backupPath=Join-Path \$env:APPDATA 'VeTweek\\hosts_backup'; \$hostsPath='C:\\Windows\\System32\\drivers\\etc\\hosts'; \$dir=Split-Path \$backupPath -Parent; if(!(Test-Path \$dir)){New-Item -ItemType Directory -Path \$dir -Force | Out-Null}; Copy-Item -Path \$hostsPath -Destination \$backupPath -Force; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '$url' -OutFile \$hostsPath -UseBasicParsing -ErrorAction Stop; Write-Output 'OK'";

      final result = await services.powershell.run(
        command,
        timeout: const Duration(minutes: 2),
      );

      if (!result.success) {
        throw result.errorOrOutput;
      }

      services.log.success(
        'Hosts файл применён',
        'Источник: dns.malw.link',
      );

      await _checkHostsBackup();

      if (mounted) {
        showSnack(
          context,
          'Hosts применён. Может потребоваться очистка DNS-кэша или перезагрузка.',
        );
      }
    } catch (e) {
      services.log.error('Ошибка применения hosts', e.toString());
      if (mounted) {
        showSnack(context, 'Ошибка: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _hostsBusy = false;
        });
      }
    }
  }

  Future<void> _removeHosts() async {
    final services = widget.services;

    if (_hostsBusy || !_hostsHasBackup) {
      return;
    }

    if (!await ensureAdminGeneric(context, services, 'Hosts файл')) {
      return;
    }

    final confirmed = await confirmDialog(
      context,
      title: 'Откат hosts файла',
      message:
          'Будет восстановлен оригинальный hosts из резервной копии. Все разблокировки через dns.malw.link перестанут работать. Продолжить?',
      confirmLabel: 'Откатить',
      danger: true,
    );

    if (!confirmed) {
      return;
    }

    setState(() {
      _hostsBusy = true;
    });

    try {
      final command =
          r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; $backupPath=Join-Path $env:APPDATA 'VeTweek\hosts_backup'; $hostsPath='C:\Windows\System32\drivers\etc\hosts'; if (!(Test-Path $backupPath)) { Write-Error 'Резервная копия не найдена'; exit 1 }; Copy-Item -Path $backupPath -Destination $hostsPath -Force; Write-Output 'OK'";

      final result = await services.powershell.run(
        command,
        timeout: const Duration(minutes: 1),
      );

      if (!result.success) {
        throw result.errorOrOutput;
      }

      services.log.success('Hosts файл откачен к резервной копии');

      await _checkHostsBackup();

      if (mounted) {
        showSnack(context, 'Hosts откачен. Может потребоваться перезагрузка.');
      }
    } catch (e) {
      services.log.error('Ошибка отката hosts', e.toString());
      if (mounted) {
        showSnack(context, 'Ошибка: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _hostsBusy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = widget.services;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final network = services.network;

    return AnimatedBuilder(
      animation: _listenable,
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const PageHeader(
              title: 'Сеть',
              subtitle: 'DNS, hosts, шлюз, очистка кэша и сброс сети',
            ),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Сетевые адаптеры',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  if (network.busy) const LinearProgressIndicator(),
                  if (network.error.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    InfoRow(label: 'Ошибка', value: network.error),
                  ],
                  const SizedBox(height: 16),
                  if (network.adapters.isEmpty)
                    Text(
                      'Адаптеры не найдены',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    )
                  else
                    for (final adapter in network.adapters)
                      RadioListTile<String>(
                        value: adapter.alias,
                        groupValue: network.selectedAlias,
                        onChanged: (value) {
                          if (value != null) {
                            network.setSelectedAlias(value);
                          }
                        },
                        title: Text(adapter.alias),
                        subtitle: Text(
                          '${adapter.description} · ${adapter.status}\nDNS: ${adapter.dnsServers.isEmpty ? 'нет' : adapter.dnsServers.join(', ')}\nШлюз: ${adapter.gateways.isEmpty ? 'нет' : adapter.gateways.join(', ')}',
                        ),
                        isThreeLine: true,
                      ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: network.busy
                        ? null
                        : () async {
                            await network.refreshAdapters();
                          },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Обновить адаптеры'),
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
                    'DNS пресеты',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        onPressed: network.busy
                            ? null
                            : () {
                                _applyDns('179.254.166.171', '164.5.224.81');
                              },
                        icon: const Icon(Icons.shield_outlined),
                        label: const Text('malw.link'),
                      ),
                      FilledButton.icon(
                        onPressed: network.busy
                            ? null
                            : () {
                                _applyDns('1.1.1.1', '1.0.0.1');
                              },
                        icon: const Icon(Icons.dns_outlined),
                        label: const Text('Cloudflare'),
                      ),
                      FilledButton.icon(
                        onPressed: network.busy
                            ? null
                            : () {
                                _applyDns('8.8.8.8', '8.8.4.4');
                              },
                        icon: const Icon(Icons.dns_outlined),
                        label: const Text('Google'),
                      ),
                      OutlinedButton.icon(
                        onPressed: network.busy ? null : _resetDns,
                        icon: const Icon(Icons.restore),
                        label: const Text('Сбросить DNS'),
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
                    'Hosts файл (разблокировка)',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Применяет hosts файл с dns.malw.link для разблокировки заблокированных сервисов в России. Оригинал сохраняется автоматически.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  InfoRow(
                    label: 'Резервная копия',
                    value: _hostsHasBackup ? 'Существует' : 'Нет',
                  ),
                  if (_hostsBusy) ...[
                    const SizedBox(height: 16),
                    const LinearProgressIndicator(),
                  ],
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        onPressed: _hostsBusy ? null : _applyHosts,
                        icon: const Icon(Icons.download),
                        label: const Text('Применить hosts'),
                      ),
                      OutlinedButton.icon(
                        onPressed:
                            _hostsBusy || !_hostsHasBackup ? null : _removeHosts,
                        icon: const Icon(Icons.undo),
                        label: const Text('Откатить hosts'),
                      ),
                      TextButton.icon(
                        onPressed:
                            _hostsBusy ? null : _checkHostsBackup,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Обновить'),
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
                    'Ручная настройка',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Поля автоматически заполняются текущими значениями выбранного адаптера.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _primaryController,
                    decoration: const InputDecoration(
                      labelText: 'Основной DNS',
                      hintText: '1.1.1.1',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _secondaryController,
                    decoration: const InputDecoration(
                      labelText: 'Вторичный DNS',
                      hintText: '1.0.0.1',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _gatewayController,
                    decoration: const InputDecoration(
                      labelText: 'Шлюз',
                      hintText: '192.168.1.1',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        onPressed: network.busy
                            ? null
                            : () {
                                _applyDns(
                                  _primaryController.text.trim(),
                                  _secondaryController.text.trim(),
                                );
                              },
                        icon: const Icon(Icons.check),
                        label: const Text('Применить DNS'),
                      ),
                      FilledButton.icon(
                        onPressed: network.busy ? null : _applyGateway,
                        icon: const Icon(Icons.router_outlined),
                        label: const Text('Применить шлюз'),
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
                    'Обслуживание сети',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  if (network.lastMessage.isNotEmpty)
                    InfoRow(
                        label: 'Последний вывод', value: network.lastMessage),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        onPressed: network.busy ? null : _flushDns,
                        icon: const Icon(Icons.cleaning_services_outlined),
                        label: const Text('Очистить кэш DNS'),
                      ),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: scheme.error,
                          foregroundColor: scheme.onError,
                          elevation: 0,
                          shadowColor: Colors.transparent,
                        ),
                        onPressed: network.busy ? null : _resetNetwork,
                        icon: const Icon(Icons.network_check),
                        label: const Text('Сбросить сеть'),
                      ),
                    ],
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

class DevPage extends StatefulWidget {
  final AppServices services;

  const DevPage({
    super.key,
    required this.services,
  });

  @override
  State<DevPage> createState() => _DevPageState();
}

class _DevPageState extends State<DevPage> {
  late final Listenable _listenable;

  final TextEditingController _legalCaptionController =
      TextEditingController();
  final TextEditingController _legalTextController = TextEditingController();

  bool _legalPrefilled = false;

  @override
  void initState() {
    super.initState();

    _listenable = Listenable.merge([
      widget.services.dev,
      widget.services.startup,
      widget.services.system,
      widget.services.log,
    ]);

    widget.services.dev.addListener(_onDevChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!widget.services.dev.loaded) {
        widget.services.dev.refreshAll();
      }

      if (widget.services.startup.extendedEntries.isEmpty) {
        widget.services.startup.loadExtended();
      }
    });
  }

  @override
  void dispose() {
    widget.services.dev.removeListener(_onDevChanged);
    _legalCaptionController.dispose();
    _legalTextController.dispose();
    super.dispose();
  }

  void _onDevChanged() {
    final dev = widget.services.dev;

    if (_legalPrefilled || !dev.legalChecked) {
      return;
    }

    _legalPrefilled = true;
    _legalCaptionController.text = dev.legalCaption;
    _legalTextController.text = dev.legalText;
  }

  String _policyStatusLabel({
    required bool checked,
    required String error,
    required bool enabled,
  }) {
    if (error == 'Нужны права администратора') {
      return 'Нужен админ';
    }

    if (error.isNotEmpty) {
      return 'Ошибка';
    }

    if (!checked) {
      return 'Не проверено';
    }

    return enabled ? 'Включен' : 'Отключен';
  }

  Color _policyStatusColor({
    required bool checked,
    required String error,
    required bool enabled,
  }) {
    final scheme = Theme.of(context).colorScheme;

    if (error == 'Нужны права администратора') {
      return scheme.tertiary;
    }

    if (error.isNotEmpty) {
      return scheme.error;
    }

    if (!checked) {
      return scheme.onSurfaceVariant;
    }

    return enabled ? scheme.primary : scheme.error;
  }

  Future<void> _toggleComponent(
    BuildContext context,
    WindowsComponentState component,
    bool enable,
  ) async {
    final services = widget.services;

    if (!await ensureAdminGeneric(context, services, component.displayName)) {
      return;
    }

    final confirmed = await confirmDialog(
      context,
      title: enable ? 'Включение компонента' : 'Отключение компонента',
      message: component.warning.isEmpty
          ? 'Компонент: ${component.displayName}. Требуется перезагрузка.'
          : component.warning,
      confirmLabel: enable ? 'Включить' : 'Отключить',
      danger: !enable,
    );

    if (!confirmed) {
      return;
    }

    try {
      if (enable) {
        await services.dev.enableComponent(component.featureName);
      } else {
        await services.dev.disableComponent(component.featureName);
      }

      showSnack(
        context,
        enable
            ? '${component.displayName} включен. Требуется перезагрузка.'
            : '${component.displayName} отключен. Требуется перезагрузка.',
      );
    } catch (e) {
      showSnack(context, e.toString());
    }
  }

  Future<void> _setDevMode(BuildContext context, bool enable) async {
    final services = widget.services;

    if (!await ensureAdminGeneric(context, services, 'Developer Mode')) {
      return;
    }

    final confirmed = await confirmDialog(
      context,
      title: enable ? 'Включение Developer Mode' : 'Отключение Developer Mode',
      message:
          'Developer Mode позволяет устанавливать неподписанные приложения и может снизить защиту системы. Продолжить?',
      confirmLabel: enable ? 'Включить' : 'Отключить',
      danger: enable,
    );

    if (!confirmed) {
      return;
    }

    try {
      await services.dev.setDevMode(enable);
      showSnack(
        context,
        enable ? 'Developer Mode включен' : 'Developer Mode отключен',
      );
    } catch (e) {
      showSnack(context, e.toString());
    }
  }

  Future<void> _openDevSettings() async {
    final services = widget.services;

    try {
      await services.dev.openDevSettings();
    } catch (e) {
      showSnack(context, e.toString());
    }
  }

  Future<void> _changeTaskManager(
    BuildContext context,
    bool enable,
    bool machine,
  ) async {
    final services = widget.services;

    if (machine && !services.system.isAdmin) {
      await ensureAdminGeneric(
        context,
        services,
        'Диспетчер задач (вся система)',
      );
      return;
    }

    if (!enable) {
      final confirmed = await confirmDialog(
        context,
        title: 'Отключение Диспетчера задач',
        message:
            'Диспетчер задач будет отключен для ${machine ? 'всей системы' : 'текущего пользователя'}. Это может помешать завершению процессов и диагностике. Продолжить?',
        confirmLabel: 'Отключить',
        danger: true,
      );

      if (!confirmed) {
        return;
      }
    }

    try {
      await services.dev.setTaskManager(enable: enable, machine: machine);
      showSnack(
        context,
        enable ? 'Диспетчер задач включен' : 'Диспетчер задач отключен',
      );
    } catch (e) {
      showSnack(context, e.toString());
    }
  }

  Future<void> _changeRegistryEditor(
    BuildContext context,
    bool enable,
    bool machine,
  ) async {
    final services = widget.services;

    if (machine && !services.system.isAdmin) {
      await ensureAdminGeneric(
        context,
        services,
        'Редактор реестра (вся система)',
      );
      return;
    }

    if (!enable) {
      final confirmed = await confirmDialog(
        context,
        title: 'Отключение Редактора реестра',
        message:
            'Редактор реестра будет отключен для ${machine ? 'всей системы' : 'текущего пользователя'}. Это может помешать ручной правке реестра. Продолжить?',
        confirmLabel: 'Отключить',
        danger: true,
      );

      if (!confirmed) {
        return;
      }
    }

    try {
      await services.dev.setRegistryEditor(enable: enable, machine: machine);
      showSnack(
        context,
        enable ? 'Редактор реестра включен' : 'Редактор реестра отключен',
      );
    } catch (e) {
      showSnack(context, e.toString());
    }
  }

  Future<void> _applyLegal(BuildContext context) async {
    final services = widget.services;

    if (!await ensureAdminGeneric(
      context,
      services,
      'Текст экрана блокировки',
    )) {
      return;
    }

    try {
      await services.dev.setLegalNotice(
        _legalCaptionController.text.trim(),
        _legalTextController.text.trim(),
      );
      showSnack(context, 'Текст экрана блокировки применен');
    } catch (e) {
      showSnack(context, e.toString());
    }
  }

  Future<void> _clearLegal(BuildContext context) async {
    final services = widget.services;

    if (!await ensureAdminGeneric(
      context,
      services,
      'Текст экрана блокировки',
    )) {
      return;
    }

    final confirmed = await confirmDialog(
      context,
      title: 'Удаление текста экрана блокировки',
      message:
          'Собственный текст и заголовок будут удалены с экрана блокировки. Продолжить?',
      confirmLabel: 'Удалить',
      danger: true,
    );

    if (!confirmed) {
      return;
    }

    try {
      await services.dev.clearLegalNotice();
      _legalCaptionController.clear();
      _legalTextController.clear();
      showSnack(context, 'Текст экрана блокировки удален');
    } catch (e) {
      showSnack(context, e.toString());
    }
  }

  Future<void> _addPath(BuildContext context, String target) async {
    final services = widget.services;
    final controller = TextEditingController();

    if (target == 'Machine' &&
        !await ensureAdminGeneric(context, services, 'System PATH')) {
      controller.dispose();
      return;
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);

        return AlertDialog(
          backgroundColor: theme.colorScheme.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Добавить путь в PATH',
            style: theme.textTheme.titleLarge,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                target == 'Machine'
                    ? 'Системный PATH'
                    : 'Пользовательский PATH',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Путь',
                  hintText: r'C:\Tools\bin',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Добавить'),
            ),
          ],
        );
      },
    );

    final value = controller.text.trim();
    controller.dispose();

    if (result == true && value.isNotEmpty) {
      try {
        await services.dev.addPath(target, value);
        await services.dev.refreshPaths();
        showSnack(context, 'Путь добавлен');
      } catch (e) {
        showSnack(context, e.toString());
      }
    }
  }

  Future<void> _removePath(
    BuildContext context,
    String target,
    int index,
  ) async {
    final services = widget.services;
    final list = target == 'Machine'
        ? services.dev.systemPath
        : services.dev.userPath;

    if (index < 0 || index >= list.length) {
      return;
    }

    if (target == 'Machine' &&
        !await ensureAdminGeneric(context, services, 'System PATH')) {
      return;
    }

    final confirmed = await confirmDialog(
      context,
      title: 'Удаление пути из PATH',
      message: 'Удалить путь: ${list[index].value}?',
      confirmLabel: 'Удалить',
      danger: true,
    );

    if (!confirmed) {
      return;
    }

    try {
      await services.dev.removePath(target, index);
      await services.dev.refreshPaths();
      showSnack(context, 'Путь удален');
    } catch (e) {
      showSnack(context, e.toString());
    }
  }

  Future<void> _movePath(
    BuildContext context,
    String target,
    int index,
    int delta,
  ) async {
    final services = widget.services;

    if (target == 'Machine' &&
        !await ensureAdminGeneric(context, services, 'System PATH')) {
      return;
    }

    try {
      await services.dev.movePath(target, index, delta);
      await services.dev.refreshPaths();
    } catch (e) {
      showSnack(context, e.toString());
    }
  }

  Future<void> _deleteExtendedStartup(
    BuildContext context,
    StartupEntry entry,
  ) async {
    final services = widget.services;

    if (!await ensureRestorePoint(context, services)) {
      return;
    }

    final confirmed = await confirmDialog(
      context,
      title: 'Удаление расширенной записи автозагрузки',
      message:
          'Это критичная точка автозагрузки. Неправильное удаление может сделать систему незагружаемой или сломать вход в Windows. Резервная копия будет сохранена. Продолжить только если вы понимаете риск.',
      confirmLabel: 'Удалить',
      danger: true,
    );

    if (!confirmed) {
      return;
    }

    try {
      await services.startup.delete(entry);
      await services.startup.loadExtended();
      showSnack(context, 'Расширенная запись удалена');
    } catch (e) {
      showSnack(context, e.toString());
    }
  }

  Future<void> _rollbackDev(BuildContext context) async {
    final services = widget.services;

    final confirmed = await confirmDialog(
      context,
      title: 'Откат Dev изменений',
      message:
          'VeTweek вернет только те Dev-изменения, по которым сохранил резервные копии: PATH, Developer Mode, компоненты, системные инструменты, текст экрана блокировки и автозагрузку. Продолжить?',
      confirmLabel: 'Откатить',
      danger: true,
    );

    if (!confirmed) {
      return;
    }

    try {
      final result = await services.dev.rollback();
      showSnack(context, result);
    } catch (e) {
      showSnack(context, e.toString());
    }
  }

  Widget _buildPathSection(String target, List<PathEntry> entries) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final services = widget.services;
    final isSystem = target == 'Machine';
    final blocked = isSystem && !services.system.isAdmin;

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  isSystem ? 'System PATH' : 'User PATH',
                  style: theme.textTheme.titleLarge,
                ),
              ),
              if (blocked)
                StatusChip(
                  label: 'Нужен админ',
                  color: scheme.tertiary,
                ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: services.dev.busy || blocked
                    ? null
                    : () {
                        _addPath(context, target);
                      },
                icon: const Icon(Icons.add),
                label: const Text('Добавить путь'),
              ),
              TextButton.icon(
                onPressed: services.dev.busy
                    ? null
                    : () async {
                        await services.dev.refreshPaths();
                      },
                icon: const Icon(Icons.refresh),
                label: const Text('Обновить'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (entries.isEmpty)
            Text(
              'Путей нет',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            )
          else
            for (var i = 0; i < entries.length; i++)
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
                      child: SelectableText(
                        entries[i].value,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    const SizedBox(width: 12),
                    StatusChip(
                      label: entries[i].exists ? 'Существует' : 'Отсутствует',
                      color: entries[i].exists
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                    ),
                    IconButton(
                      onPressed: services.dev.busy || blocked || i == 0
                          ? null
                          : () {
                              _movePath(context, target, i, -1);
                            },
                      icon: const Icon(Icons.arrow_upward),
                    ),
                    IconButton(
                      onPressed: services.dev.busy ||
                              blocked ||
                              i == entries.length - 1
                          ? null
                          : () {
                              _movePath(context, target, i, 1);
                            },
                      icon: const Icon(Icons.arrow_downward),
                    ),
                    IconButton(
                      onPressed: services.dev.busy || blocked
                          ? null
                          : () {
                              _removePath(context, target, i);
                            },
                      icon: const Icon(Icons.delete_outline),
                      color: scheme.error,
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildPolicyCard({
    required String title,
    required String scope,
    required bool checked,
    required bool enabled,
    required String error,
    required bool machine,
    required Future<void> Function(bool) onChange,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final services = widget.services;
    final busy = services.dev.busy || services.dev.policyBusy;
    final needsAdminAction = machine && !services.system.isAdmin;
    final canChangeBase = !busy && (checked || needsAdminAction);
    final label = _policyStatusLabel(
      checked: checked,
      error: error,
      enabled: enabled,
    );
    final color = _policyStatusColor(
      checked: checked,
      error: error,
      enabled: enabled,
    );

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      scope,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              StatusChip(
                label: label,
                color: color,
              ),
            ],
          ),
          if (error.isNotEmpty && error != 'Нужны права администратора') ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: SelectableText(
                error,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onErrorContainer,
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: canChangeBase && !enabled
                    ? () async {
                        await onChange(true);
                      }
                    : null,
                icon: const Icon(Icons.check, size: 16),
                label: const Text('Включить'),
              ),
              OutlinedButton.icon(
                onPressed: canChangeBase && enabled
                    ? () async {
                        await onChange(false);
                      }
                    : null,
                icon: const Icon(Icons.close, size: 16),
                label: const Text('Отключить'),
              ),
              TextButton.icon(
                onPressed: busy
                    ? null
                    : () async {
                        await services.dev.refreshPolicies();
                      },
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Обновить'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegalCard() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final services = widget.services;
    final dev = services.dev;
    final busy = dev.busy;

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Текст на экране блокировки',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Text(
            'Выводит собственный заголовок и текст над полем ввода пароля при включении ПК через LegalNoticeCaption и LegalNoticeText.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (!services.system.isAdmin) ...[
            const SizedBox(height: 12),
            StatusChip(
              label: 'Нужен админ',
              color: scheme.tertiary,
            ),
          ],
          if (dev.legalError.isNotEmpty &&
              dev.legalError != 'Нужны права администратора') ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: SelectableText(
                dev.legalError,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onErrorContainer,
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _legalCaptionController,
            decoration: const InputDecoration(
              labelText: 'Заголовок',
              hintText: 'Например: Контакт при утере',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _legalTextController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Текст',
              hintText: 'Имя, телефон, мотивирующая цитата',
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: busy
                    ? null
                    : () {
                        _applyLegal(context);
                      },
                icon: const Icon(Icons.check),
                label: const Text('Применить текст'),
              ),
              OutlinedButton.icon(
                onPressed: busy
                    ? null
                    : () {
                        _clearLegal(context);
                      },
                icon: const Icon(Icons.delete_outline),
                label: const Text('Убрать текст'),
              ),
              TextButton.icon(
                onPressed: busy
                    ? null
                    : () async {
                        await dev.refreshLegalNotice();
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

  @override
  Widget build(BuildContext context) {
    final services = widget.services;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dev = services.dev;

    return AnimatedBuilder(
      animation: _listenable,
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const PageHeader(
              title: 'Dev',
              subtitle:
                  'Системные инструменты, компоненты Windows, Developer Mode, PATH и расширенная автозагрузка',
            ),
            Text(
              'Системные инструменты',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            _buildPolicyCard(
              title: 'Диспетчер задач',
              scope: 'Текущий пользователь',
              checked: dev.taskMgrUserChecked,
              enabled: dev.taskMgrUserEnabled,
              error: dev.taskMgrUserError,
              machine: false,
              onChange: (enable) =>
                  _changeTaskManager(context, enable, false),
            ),
            const SizedBox(height: 16),
            _buildPolicyCard(
              title: 'Диспетчер задач',
              scope: 'Вся система',
              checked: dev.taskMgrMachineChecked,
              enabled: dev.taskMgrMachineEnabled,
              error: dev.taskMgrMachineError,
              machine: true,
              onChange: (enable) =>
                  _changeTaskManager(context, enable, true),
            ),
            const SizedBox(height: 16),
            _buildPolicyCard(
              title: 'Редактор реестра',
              scope: 'Текущий пользователь',
              checked: dev.regEditUserChecked,
              enabled: dev.regEditUserEnabled,
              error: dev.regEditUserError,
              machine: false,
              onChange: (enable) =>
                  _changeRegistryEditor(context, enable, false),
            ),
            const SizedBox(height: 16),
            _buildPolicyCard(
              title: 'Редактор реестра',
              scope: 'Вся система',
              checked: dev.regEditMachineChecked,
              enabled: dev.regEditMachineEnabled,
              error: dev.regEditMachineError,
              machine: true,
              onChange: (enable) =>
                  _changeRegistryEditor(context, enable, true),
            ),
            const SizedBox(height: 16),
            _buildLegalCard(),
            const SizedBox(height: 16),
            if (dev.busy || dev.policyBusy) const LinearProgressIndicator(),
            if (dev.error.isNotEmpty) ...[
              const SizedBox(height: 16),
              SectionCard(
                child: InfoRow(label: 'Ошибка', value: dev.error),
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: dev.busy || dev.policyBusy
                      ? null
                      : () async {
                          await dev.refreshAll();
                          showSnack(context, 'Dev данные обновлены');
                        },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Обновить Dev'),
                ),
                OutlinedButton.icon(
                  onPressed: dev.busy || dev.policyBusy
                      ? null
                      : () {
                          _rollbackDev(context);
                        },
                  icon: const Icon(Icons.undo),
                  label: const Text('Откатить Dev'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Компоненты Windows',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  if (dev.components.isEmpty)
                    Text(
                      'Компоненты не загружены',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    )
                  else
                    for (final component in dev.components) ...[
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              component.displayName,
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                          StatusChip(
                            label: component.state,
                            color: component.enabled
                                ? scheme.primary
                                : scheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                      if (component.warning.isNotEmpty)
                        WarningBanner(text: component.warning),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          FilledButton.icon(
                            onPressed: dev.busy || component.enabled
                                ? null
                                : () {
                                    _toggleComponent(context, component, true);
                                  },
                            icon: const Icon(Icons.check),
                            label: const Text('Включить'),
                          ),
                          OutlinedButton.icon(
                            onPressed: dev.busy || !component.enabled
                                ? null
                                : () {
                                    _toggleComponent(context, component, false);
                                  },
                            icon: const Icon(Icons.close),
                            label: const Text('Отключить'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
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
                    'Developer Mode',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  InfoRow(
                    label: 'Статус',
                    value: dev.devModeEnabled ? 'Включен' : 'Отключен',
                  ),
                  const SizedBox(height: 16),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: SwitchListTile(
                      title: const Text('Developer Mode'),
                      value: dev.devModeEnabled,
                      onChanged: dev.busy
                          ? null
                          : (value) {
                              _setDevMode(context, value);
                            },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        onPressed: dev.busy
                            ? null
                            : () async {
                                await dev.refreshDevMode();
                              },
                        icon: const Icon(Icons.refresh),
                        label: const Text('Обновить статус'),
                      ),
                      OutlinedButton.icon(
                        onPressed: dev.busy ? null : _openDevSettings,
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('Открыть параметры разработчика'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _buildPathSection('User', dev.userPath),
            const SizedBox(height: 16),
            _buildPathSection('Machine', dev.systemPath),
            const SizedBox(height: 16),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Расширенная автозагрузка',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  WarningBanner(
                    text:
                        'Userinit, Shell и RunOnce могут быть критичны для входа в систему. Удаляйте только если точно знаете, что делаете.',
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
                                await services.startup.loadExtended();
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
                        label: const Text('Восстановить'),
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
                  if (services.startup.extendedEntries.isEmpty)
                    Text(
                      'Расширенные записи не найдены',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    )
                  else
                    for (final entry in services.startup.extendedEntries)
                      Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: scheme.surface,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    entry.valueName,
                                    style: theme.textTheme.titleMedium,
                                  ),
                                ),
                                if (entry.critical)
                                  StatusChip(
                                    label: 'Критично',
                                    color: scheme.error,
                                  ),
                                IconButton(
                                  onPressed: services.startup.busy
                                      ? null
                                      : () {
                                          _deleteExtendedStartup(
                                            context,
                                            entry,
                                          );
                                        },
                                  icon: const Icon(Icons.delete_outline),
                                  color: scheme.error,
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            SelectableText(
                              entry.valueData,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${entry.hive} · ${entry.scope} · ${entry.key}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
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