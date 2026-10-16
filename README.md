# VeTweek

A desktop utility for Windows 10 / 11 written in Flutter. It bundles privacy
tweaks, system cleanup, network tools, app management and a set of experimental
features behind one interface. Every change goes through the registry,
PowerShell or bcdedit, and most of them are reversible.

Current version: **0.6.0**

Repository: https://github.com/sunne-cl/vetweek

---

## Requirements

- Windows 10 21H2 or newer. Windows 11 recommended.
- Administrator rights for system-level tweaks, Defender, services, bcdedit and
  HKLM writes. The app elevates itself on demand.

Ready-to-run builds are published on the Releases page. Download the archive
for the latest release, unpack it and run `vetweek.exe`. The whole folder is
required, not only the executable: it needs `flutter_windows.dll` and the
`data` directory next to it.

---

## What it does

### Home

- Operating system build, admin state, Defender / advertising / widgets status.
- Hardware summary: CPU, GPUs, RAM modules, drives.
- System drive usage bar.
- One-click restore point creation.
- "About Windows" panel (admin only): activation state, edition, build, install
  date, language, region, timezone, virtualization, VBS, real-time protection.

### Fast

Single-click toggles for the most common Explorer settings:

- Show hidden files.
- Show file extensions.
- Open Explorer to This PC.
- This PC icon on desktop.
- Remove the "- Shortcut" suffix from new links.
- Remove duplicated drives in the navigation pane.
- Left-aligned taskbar (Windows 11).
- System dark theme.

### Tweaks

- CPU minimum performance slider (10% - 100%) applied through powercfg.
- Refresh all statuses, revert all applied tweaks, restart Explorer.
- Defender real-time protection on/off.
- Advertising and recommendation parameters on/off.
- Widgets / weather package removal.
- Windows Update block: pause the wuauserv service, clear the
  SoftwareDistribution cache, pin updates to a specific release via
  TargetReleaseVersion.
- Cleanup: user and system temp, old update logs, Recycle Bin, browser caches.
- Reserved storage removal through DISM (experimental).
- Full catalog grouped by category:
  - Privacy: telemetry, feedback notifications, activity history, web search in
    Start, advertising ID, silent app provisioning, handwriting input,
    cross-device clipboard.
  - Explorer: classic context menu, Gallery namespace, separate folder
    processes, "This PC" folders, seconds in the clock, God Mode folder,
    transparent shortcut-arrow icon.
  - System: OneDrive, clipboard history, hibernation, Ultimate Performance
    scheme, legacy boot menu, boot menu on every start, TTL 65, pagefile
    control, SmartScreen, Copilot, toast notifications, delivery optimization.
  - Performance: Game Bar / DVR, Nexus overlay, HAGS, sticky keys, mouse
    acceleration, keyboard repeat rate, menu delay, hung-app timeouts, QoS
    limit, fullscreen optimizations, power throttling, hidden power-plan
    settings, DWM flip model, disabling of DiagTrack / SysMain / RemoteRegistry
    / WbioSrvc / Fax.

### Experiments

Tested but potentially risky features, separated from the main catalog:

- Hide frequent folders and recent documents in Quick access.
- Checkboxes instead of hover selection, delete confirmation, "End task" in the
  taskbar menu.
- Disable transparency and lock-screen blur.
- Hide drive letters in This PC via a NoDrives bitmask.
- Custom selection color.
- Default naming template for new files and folders.
- Rename GPU through the FriendlyName value of its Enum key.
- Rename CPU through ProcessorNameString. Note: the HARDWARE hive is volatile,
  so this name resets on every reboot.
- Disable sticky keys, HVCI / memory integrity, UAC, verbose startup status.
- Swap left and right mouse buttons.
- Trigger a bugcheck with Ctrl + double Scroll Lock (CrashOnCtrlScroll).
- Hide the Windows logo and the boot animation via bcdedit.
- Set the chkdsk auto-check timeout to 60 seconds with rollback.
- Run SFC and DISM RestoreHealth.
- Clean TEMP, pip cache and thumbnail cache.
- Scheduled shutdown timer with cancel.

### Apps

- Installed UWP packages listed with their human-readable display names
  (resolved through Get-StartApps, not raw package ids).
- Select visible, select known junk, clear selection, bulk removal.
- JSON backup of the package list.
- winget upgrade --all.
- Startup manager: Run / RunOnce / Winlogon entries with registry backups and
  restore.

### Network

- Network adapters with current DNS and gateway.
- DNS presets: malw.link (179.254.166.171 / 164.5.224.81), Cloudflare, Google,
  plus manual primary / secondary / gateway fields.
- Hosts file unlock: downloads the hosts list from
  https://raw.githubusercontent.com/ImMALWARE/dns.malw.link/refs/heads/master/hosts,
  keeps a backup of the original file under %APPDATA%\VeTweek\hosts_backup and
  can roll back.
- Flush DNS cache, full network reset (Winsock, TCP/IP, release/renew).

### Logs

- In-app journal of every action with severity levels, export to file, clear.

### Settings

- Light / dark / system theme, OLED black variant, accent color presets.
- Dev tab toggle.
- Save and load configuration snapshots.
- Link to the GitHub repository.

---

## First-run unwanted program scan

On the first launch, after the welcome dialog, VeTweek scans installed packages
against a fixed list of unwanted software and offers to remove the matches. The
list is intentionally narrow and covers only known junk categories:

| Pattern | Group |
| --- | --- |
| `Qihoo360TechnologyCo.*`, `360TotalSecurity.*` | third-party AV |
| `BothTalentInternationalLimited.*`, `IObit.*`, `AdvancedSystemCare.*`, `DriverBooster.*`, `SmartDefrag.*` | "optimizer" suites |
| `CCleaner.*`, `Piriform.*`, `GlaryUtilities.*`, `Auslogics.*` | cleaners |
| `Mail.Ru.*`, `Yandex.YandexMusic_*` | regional clients |
| `Disney.*`, `CandyCrushSaga_*` | preinstalled games |

Exact package ids from the same publishers are matched as well. The dialog
shows every detected package with a checkbox, supports select-all / clear, and
removes only what the user confirms. Nothing is deleted without an explicit
action, and the scan runs once.

---

## Project layout

    lib/
      main.dart            entry point, window setup
      models.dart          data classes and enums
      theme.dart           Material 3 theme
      widgets.dart         shared UI components
      services/
        base.dart          app services container, logging, settings, state
        system.dart        OS info, hardware, registry helper, PowerShell runner
        tweaks.dart        tweak catalog, Defender, advertising, widgets, update, cleanup
        apps.dart          UWP packages, startup, winget, dev components
        network.dart       adapters, DNS, hosts
        experiments.dart   experimental registry and bcdedit operations
      pages/
        shell.dart         navigation, dialogs, first-run scan
        core_pages.dart    dashboard
        core_pages1.dart   fast settings, tweaks
        core_pages2.dart   apps, logs, settings
        experiments_page.dart
        dev_pages.dart     network, dev

---

## Safety

- A restore point is offered before the first tweak is applied.
- Registry tweaks store their previous values and expose a revert action.
- Removal of UWP packages and hosts modification are irreversible without
  manual recovery; the hosts backup is the exception.
- Some bcdedit-based statuses are parsed from English tokens and may report
  incorrectly on localized systems even though the change itself is applied.
- CPU renaming is volatile by design.

---

## Disclaimer

VeTweek was built with AI assistance. It modifies system components, the
registry, the boot configuration and installed applications. Use it only if you
understand what each option does and accept the consequences. The authors are
not responsible for data loss, broken systems or any other damage caused by
this software.

---

## Building from source

Only needed if you want to compile the app yourself instead of using a Release
build from the Releases page. Requires the Flutter SDK with Windows desktop
support and the Visual Studio 2022 "Desktop development with C++" workload.

    flutter pub get
    flutter build windows --release

The executable and its runtime land in:

    build\windows\x64\runner\Release\
