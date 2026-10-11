import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:vetweek/models.dart';
import 'package:vetweek/services/base.dart';
import 'package:vetweek/services/system.dart';

class NetworkService extends ChangeNotifier {
  final PowerShellService shell;
  final LogService log;
  final SystemService system;

  List<NetworkAdapterInfo> adapters = [];
  String selectedAlias = '';
  bool busy = false;
  String error = '';
  String lastMessage = '';

  NetworkService({
    required this.shell,
    required this.log,
    required this.system,
  });

  Future<void> refreshAdapters() async {
    if (busy) {
      return;
    }

    busy = true;
    error = '';
    notifyListeners();

    try {
      final command =
          r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; $adapters=Get-NetAdapter | Select-Object Name, InterfaceDescription, Status; $res=New-Object System.Collections.Generic.List[object]; foreach($a in $adapters){ $dns=@((Get-DnsClientServerAddress -InterfaceAlias $a.Name -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses); $gw=@((Get-NetRoute -InterfaceAlias $a.Name -DestinationPrefix '0.0.0.0/0' -AddressFamily IPv4 -ErrorAction SilentlyContinue).NextHop); $res.Add([pscustomobject]@{alias=$a.Name;desc=$a.InterfaceDescription;status=$a.Status;dns=$dns;gw=$gw}) }; ($res | ConvertTo-Json -Compress -Depth 4)";

      final result = await shell.run(
        command,
        timeout: const Duration(seconds: 35),
      );

      if (!result.success) {
        throw result.errorOrOutput;
      }

      final output = result.stdout.trim();
      final parsed = <NetworkAdapterInfo>[];

      if (output.isNotEmpty && output != '[]') {
        final decoded = jsonDecode(output);
        final list = decoded is List ? decoded : [decoded];

        for (final item in list) {
          if (item is Map<String, dynamic>) {
            parsed.add(
              NetworkAdapterInfo(
                alias: (item['alias'] ?? '').toString(),
                description: (item['desc'] ?? '').toString(),
                status: (item['status'] ?? '').toString(),
                dnsServers: (item['dns'] as List?)?.map((e) => e.toString()).toList() ?? [],
                gateways: (item['gw'] as List?)?.map((e) => e.toString()).toList() ?? [],
              ),
            );
          }
        }
      }

      adapters = parsed;

      if (selectedAlias.isEmpty && adapters.isNotEmpty) {
        selectedAlias = adapters.first.alias;
      }

      log.info('Сетевые адаптеры обновлены', 'Найдено: ${adapters.length}');
    } catch (e) {
      error = e.toString();
      log.error('Ошибка чтения сетевых адаптеров', error);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void setSelectedAlias(String value) {
    selectedAlias = value;
    notifyListeners();
  }

  Future<void> applyDns(String primary, String secondary) async {
    await _runAdminCommand(
      _dnsCommand(primary, secondary),
      'DNS применен',
    );
  }

  Future<void> resetDns() async {
    if (selectedAlias.isEmpty) {
      throw 'Не выбран адаптер';
    }

    await _runAdminCommand(
      "\$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; Set-DnsClientServerAddress -InterfaceAlias ${psQuote(selectedAlias)} -ResetServerAddresses; Write-Output 'OK'",
      'DNS сброшен на автоматический',
    );
  }

  Future<void> applyGateway(String gateway) async {
    if (selectedAlias.isEmpty) {
      throw 'Не выбран адаптер';
    }

    if (gateway.trim().isEmpty) {
      throw 'Введите адрес шлюза';
    }

    await _runAdminCommand(
      "\$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; Remove-NetRoute -InterfaceAlias ${psQuote(selectedAlias)} -DestinationPrefix '0.0.0.0/0' -AddressFamily IPv4 -Confirm:\$false -ErrorAction SilentlyContinue; New-NetRoute -InterfaceAlias ${psQuote(selectedAlias)} -DestinationPrefix '0.0.0.0/0' -NextHop ${psQuote(gateway.trim())} -AddressFamily IPv4 -PolicyStore ActiveStore; Write-Output 'OK'",
      'Шлюз применен',
    );
  }

  Future<void> flushDns() async {
    await _runCommand(
      r"ipconfig /flushdns",
      'Кэш DNS очищен',
    );
  }

  Future<void> resetNetwork() async {
    await _runAdminCommand(
      r"netsh winsock reset; netsh int ip reset; ipconfig /release; ipconfig /renew; ipconfig /flushdns",
      'Сброс сети выполнен. Требуется перезагрузка.',
    );
  }

  String _dnsCommand(String primary, String secondary) {
    final p = primary.trim();
    final s = secondary.trim();

    if (p.isEmpty) {
      return "\$ErrorActionPreference='Stop'; Write-Error 'Введите основной DNS'";
    }

    if (selectedAlias.isEmpty) {
      return "\$ErrorActionPreference='Stop'; Write-Error 'Не выбран адаптер'";
    }

    if (s.isEmpty) {
      return "\$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; Set-DnsClientServerAddress -InterfaceAlias ${psQuote(selectedAlias)} -ServerAddresses @(${psQuote(p)}); Write-Output 'OK'";
    }

    return "\$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; Set-DnsClientServerAddress -InterfaceAlias ${psQuote(selectedAlias)} -ServerAddresses @(${psQuote(p)},${psQuote(s)}); Write-Output 'OK'";
  }

  Future<void> _runCommand(String command, String successMessage) async {
    if (busy) {
      return;
    }

    busy = true;
    error = '';
    lastMessage = '';
    notifyListeners();

    try {
      final result = await shell.run(
        command,
        timeout: const Duration(minutes: 3),
      );

      if (!result.success) {
        throw result.errorOrOutput;
      }

      lastMessage = result.stdout.trim();
      log.success(successMessage, lastMessage);
    } catch (e) {
      error = e.toString();
      log.error(successMessage, error);
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> _runAdminCommand(String command, String successMessage) async {
    if (!system.isAdmin) {
      throw 'Требуются права администратора';
    }

    await _runCommand(command, successMessage);
  }
}