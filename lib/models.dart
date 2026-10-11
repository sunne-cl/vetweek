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

  RegistryOp({
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
}