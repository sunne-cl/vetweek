enum LogLevel {
  info,
  success,
  warning,
  error,
}

class LogEntry {
  final DateTime time;
  final LogLevel level;
  final String message;
  final String details;

  LogEntry({
    required this.time,
    required this.level,
    required this.message,
    required this.details,
  });
}

class AppxPackage {
  final String name;
  final String packageFullName;
  final String publisher;
  final String version;
  final String installLocation;
  bool selected;

  AppxPackage({
    required this.name,
    required this.packageFullName,
    required this.publisher,
    required this.version,
    required this.installLocation,
    this.selected = false,
  });
}

class PowerShellResult {
  final int exitCode;
  final String stdout;
  final String stderr;

  PowerShellResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  bool get success => exitCode == 0;

  String get errorOrOutput {
    if (stderr.trim().isNotEmpty) {
      return stderr.trim();
    }

    return stdout.trim();
  }
}

enum DefenderStatus {
  unknown,
  checking,
  enabled,
  disabled,
  unavailable,
  error,
}

enum AdvertisingStatus {
  unknown,
  checking,
  disabled,
  enabled,
  error,
}

enum TweakCategory {
  privacy,
  explorer,
  system,
  performance,
}

enum TweakStatus {
  unknown,
  applied,
  notApplied,
  partial,
  needsAdmin,
  error,
}

enum Hive {
  hkcu,
  hklm,
  hkcr,
}

enum RegValueType {
  dword,
  string,
  expandString,
}

enum RegAction {
  setValue,
  deleteValue,
  deleteKey,
}

class RegistryOp {
  final Hive hive;
  final String key;
  final String? valueName;
  final bool isDefault;
  final RegValueType type;
  final Object? applyValue;
  final RegAction applyAction;
  final RegAction revertAction;
  final Object? revertValue;
  final bool missingCountsAsReverted;

  const RegistryOp({
    required this.hive,
    required this.key,
    this.valueName,
    this.isDefault = false,
    required this.type,
    this.applyValue,
    required this.applyAction,
    required this.revertAction,
    this.revertValue,
    this.missingCountsAsReverted = false,
  });
}

class RegistryTweak {
  final String id;
  final String title;
  final String description;
  final TweakCategory category;
  final bool requiresAdmin;
  final bool reversible;
  final String warning;
  final List<RegistryOp> ops;
  final String? applyShell;
  final String? revertShell;

  RegistryTweak({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.requiresAdmin,
    required this.reversible,
    this.warning = '',
    required this.ops,
    this.applyShell,
    this.revertShell,
  });
}

class CommandTweak {
  final String id;
  final String title;
  final String description;
  final TweakCategory category;
  final bool requiresAdmin;
  final bool reversible;
  final String warning;
  final String applyCommand;
  final String? revertCommand;
  final String statusCommand;
  final String appliedToken;
  final String? notAppliedToken;

  CommandTweak({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.requiresAdmin,
    required this.reversible,
    this.warning = '',
    required this.applyCommand,
    this.revertCommand,
    required this.statusCommand,
    required this.appliedToken,
    this.notAppliedToken,
  });
}

abstract class Tweak {
  String get id;
  String get title;
  String get description;
  TweakCategory get category;
  bool get requiresAdmin;
  bool get reversible;
  String get warning;
}

class RegistryTweakWrapper implements Tweak {
  final RegistryTweak tweak;

  RegistryTweakWrapper(this.tweak);

  @override
  String get id => tweak.id;
  @override
  String get title => tweak.title;
  @override
  String get description => tweak.description;
  @override
  TweakCategory get category => tweak.category;
  @override
  bool get requiresAdmin => tweak.requiresAdmin;
  @override
  bool get reversible => tweak.reversible;
  @override
  String get warning => tweak.warning;
}

class CommandTweakWrapper implements Tweak {
  final CommandTweak tweak;

  CommandTweakWrapper(this.tweak);

  @override
  String get id => tweak.id;
  @override
  String get title => tweak.title;
  @override
  String get description => tweak.description;
  @override
  TweakCategory get category => tweak.category;
  @override
  bool get requiresAdmin => tweak.requiresAdmin;
  @override
  bool get reversible => tweak.reversible;
  @override
  String get warning => tweak.warning;
}

class CpuInfo {
  final String name;
  final int cores;
  final int logicalProcessors;
  final int maxMhz;

  CpuInfo({
    required this.name,
    required this.cores,
    required this.logicalProcessors,
    required this.maxMhz,
  });
}

class GpuInfo {
  final String name;
  final String driverVersion;
  final int memoryMb;

  GpuInfo({
    required this.name,
    required this.driverVersion,
    required this.memoryMb,
  });
}

class RamModule {
  final int capacityGb;
  final int speedMhz;
  final String manufacturer;

  RamModule({
    required this.capacityGb,
    required this.speedMhz,
    required this.manufacturer,
  });
}

class DiskDriveInfo {
  final String model;
  final String interfaceType;
  final String mediaType;
  final int sizeGb;

  DiskDriveInfo({
    required this.model,
    required this.interfaceType,
    required this.mediaType,
    required this.sizeGb,
  });

  String get kind {
    final lowerMedia = mediaType.toLowerCase();
    final lowerIface = interfaceType.toLowerCase();

    if (lowerIface.contains('nvme') || lowerMedia.contains('nvme')) {
      return 'NVMe';
    }

    if (lowerMedia.contains('ssd') ||
        lowerMedia.contains('fixed ssd') ||
        lowerIface.contains('scsi') && lowerMedia.contains('ssd')) {
      return 'SSD';
    }

    if (lowerMedia.contains('hdd') || lowerMedia.contains('fixed hdd')) {
      return 'HDD';
    }

    return 'Не определено';
  }
}

class PcSpecs {
  final CpuInfo cpu;
  final List<GpuInfo> gpus;
  final List<RamModule> ramModules;
  final List<DiskDriveInfo> drives;

  PcSpecs({
    required this.cpu,
    required this.gpus,
    required this.ramModules,
    required this.drives,
  });

  int get totalRamGb =>
      ramModules.fold(0, (sum, m) => sum + m.capacityGb);

  String get ramSummary {
    if (ramModules.isEmpty) {
      return 'Не определено';
    }

    final speeds = ramModules
        .map((m) => m.speedMhz)
        .where((s) => s > 0)
        .toSet()
        .toList();

    final speedText = speeds.isEmpty ? '' : ' @ ${speeds.join('/')} МГц';

    return '$totalRamGb ГБ (${ramModules.length} мод.)$speedText';
  }
}

class DiskUsage {
  final String drive;
  final int totalBytes;
  final int freeBytes;

  DiskUsage({
    required this.drive,
    required this.totalBytes,
    required this.freeBytes,
  });

  int get usedBytes => totalBytes - freeBytes;

  double get usedRatio {
    if (totalBytes <= 0) {
      return 0;
    }

    return usedBytes / totalBytes;
  }
}

class BrowserInfo {
  final String id;
  final String displayName;
  final List<String> cachePaths;
  bool selected;

  BrowserInfo({
    required this.id,
    required this.displayName,
    required this.cachePaths,
    this.selected = true,
  });
}

class CleanupSelection {
  bool tempUser;
  bool tempSystem;
  bool updateLogs;
  bool recycleBin;
  bool allBrowsers;

  CleanupSelection({
    this.tempUser = true,
    this.tempSystem = true,
    this.updateLogs = true,
    this.recycleBin = true,
    this.allBrowsers = true,
  });
}

class StartupEntry {
  final String hive;
  final String key;
  final String valueName;
  final String valueData;
  final String scope;
  final bool critical;

  StartupEntry({
    required this.hive,
    required this.key,
    required this.valueName,
    required this.valueData,
    required this.scope,
    this.critical = false,
  });

  String get uniqueId => '$hive|$key|$valueName';
}

class DnsPreset {
  final String id;
  final String displayName;
  final String primary;
  final String secondary;

  DnsPreset({
    required this.id,
    required this.displayName,
    required this.primary,
    required this.secondary,
  });
}

class NetworkAdapterInfo {
  final String alias;
  final String description;
  final String status;
  final List<String> dnsServers;
  final List<String> gateways;

  NetworkAdapterInfo({
    required this.alias,
    required this.description,
    required this.status,
    required this.dnsServers,
    required this.gateways,
  });
}

class PathEntry {
  final String value;
  final bool exists;

  PathEntry({
    required this.value,
    required this.exists,
  });
}

class WindowsComponentState {
  final String featureName;
  final String displayName;
  final String state;
  final bool requiresAdmin;
  final bool rebootRequired;
  final String warning;

  WindowsComponentState({
    required this.featureName,
    required this.displayName,
    required this.state,
    required this.requiresAdmin,
    required this.rebootRequired,
    this.warning = '',
  });

  bool get enabled => state.toUpperCase().contains('ENABLED');
}