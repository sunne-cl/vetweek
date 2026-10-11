# VeTweek

VeTweek is a Windows desktop application for managing common system tweaks, privacy settings, built-in Windows components, telemetry, advertising identifiers, widgets, apps, and performance-related options.

The application is intended for users who understand what system changes they are applying and who accept the risks associated with modifying Windows settings.

Important: VeTweek was created with the assistance of artificial intelligence. All actions performed by the user inside this program are carried out entirely at the user's own risk. The creators do not bear responsibility for any damage, data loss, system instability, reduced security, broken features, failed updates, or any other consequences that may result from using VeTweek.

---

## Download

The ready-to-use Windows build is available in the Releases section of this GitHub repository.

To download and run VeTweek:

1. Open the repository page on GitHub.
2. Go to the Releases section.
3. Download the latest Windows release archive.
4. Extract the archive completely.
5. Run vetweek.exe from the extracted folder.

Do not copy only vetweek.exe without the supporting files. The executable requires nearby runtime files and the data folder from the release archive.

---

## Before Applying Tweaks

Before making system changes, it is strongly recommended to create a Windows restore point.

A restore point allows you to return the system to an earlier state if a tweak causes unexpected behavior.

### Create a Restore Point Manually

1. Press Win and R together.
2. Enter sysdm.cpl.
3. Open the System Protection tab.
4. Select the system drive, usually C.
5. Click Create.
6. Enter a descriptive name, for example Before VeTweek tweaks.
7. Wait until the restore point is created.

### Create a Restore Point Using PowerShell

Run PowerShell as Administrator and execute this command:

Checkpoint-Computer -Description "Before VeTweek tweaks" -RestorePointType MODIFY_SETTINGS

If restore point creation is disabled, enable System Protection for the system drive first.

---

## Features

VeTweek includes functions for managing common Windows tweaks and system components.

### Privacy and Telemetry

- Disable or enable telemetry-related settings.
- Disable feedback notifications.
- Disable activity history collection.
- Disable web search suggestions in Start Menu search.
- Disable advertising ID.

These options are intended to reduce data collection and recommendation features built into Windows.

### Windows Defender

- Check the current real-time protection state.
- Disable real-time protection.
- Enable real-time protection.

Disabling Windows Defender reduces system protection. Use this function only if you understand the consequences and have an alternative security solution or a specific temporary reason.

### Advertising and Suggestions

- Disable content delivery suggestions.
- Disable recommended apps.
- Disable lock screen suggestions.
- Disable system pane suggestions.
- Restore previous values when supported.

### Widgets and Weather

- Detect installed widget, weather, and related packages.
- Remove detected widget and weather packages.
- Keep backup information about detected packages when supported.

Removing system packages may affect related Windows features.

### Explorer and Context Menu

- Return the classic Windows context menu.
- Hide Gallery in File Explorer.
- Hide Home in File Explorer and open This PC instead.
- Create a God Mode shortcut on the Desktop.
- Remove the God Mode shortcut when supported.

### System Cleanup and Debloat

- View installed UWP packages.
- Search installed packages.
- Select packages manually.
- Select common junk packages.
- Remove selected packages.
- Export a backup list of installed packages.

Removing built-in Windows packages can break associated features. Only remove packages you understand and no longer need.

### OneDrive

- Disable OneDrive synchronization.
- Disable OneDrive automatic startup.
- Restore previous settings when supported.

### Power and Performance

- Disable hibernation to free disk space used by hiberfil.sys.
- Enable hibernation again when supported.
- Activate the Ultimate Performance power scheme when available.
- Restore the balanced power scheme when supported.

### Gaming and Background Recording

- Disable Xbox Game Bar.
- Disable Game DVR.
- Disable background recording features.
- Restore previous settings when supported.

### Services

VeTweek can disable selected Windows services that are commonly targeted by optimization tools.

Examples may include:

- Diagnostic tracking service.
- SysMain service.
- Remote Registry service.
- Biometric service.
- Fax service.

Disabling services can affect Windows functionality. Only disable services if you know what they do and do not need them.

---

## Interface

VeTweek uses a Material Design 3 interface with support for light, dark, and system themes.

Main sections:

- Dashboard: system status and quick actions.
- Tweaks: privacy, Defender, advertising, widgets, Explorer, system, and performance tweaks.
- Apps: installed Windows packages, search, selection, removal, and backup list export.
- Logs: action history, warnings, and errors.
- Settings: theme mode and accent color.

The interface is designed to show the current state of supported tweaks and allow the user to apply or revert them when the underlying system mechanism supports it.

---

## System Requirements

- Windows 10 or Windows 11.
- Administrator rights for system-level tweaks.
- Enough free disk space for the application and temporary logs.
- PowerShell availability for system operations.

Some functions may behave differently depending on the Windows edition, build, language, installed updates, group policy settings, or third-party software.

---

## Administrator Rights

Several tweaks require elevated permissions because they modify system-wide registry keys, services, power settings, or protected Windows components.

If VeTweek detects that administrator rights are missing for an action that requires them, it will ask to restart with elevated permissions instead of silently failing.

Running the application as Administrator is recommended when applying system-level changes.

---

## Safety Recommendations

Before using VeTweek:

- Create a Windows restore point.
- Save important work.
- Close active applications.
- Understand what each tweak does.
- Do not apply all tweaks at once if you are unsure.
- Check system behavior after changes.
- Keep backups of important data.

After applying tweaks:

- Restart the computer if required.
- Restart File Explorer if Explorer-related changes do not appear immediately.
- Verify that essential Windows features still work.
- Revert unnecessary tweaks if something behaves incorrectly.

---

## Risk Disclaimer

VeTweek modifies Windows settings and system components. Some changes may be difficult to reverse without a restore point, system reset, or manual repair.

The creators are not responsible for:

- Operating system damage.
- Data loss.
- Application breakage.
- Service failure.
- Reduced security.
- Windows Update problems.
- Microsoft Store problems.
- Defender or antivirus issues.
- Driver or system component issues.
- Loss of productivity.
- Any direct or indirect damage caused by using this software.

All actions in VeTweek are performed by the user voluntarily and under the user's full responsibility.

By using VeTweek, you confirm that you understand the risks and accept full responsibility for any changes made to your system.

---

## AI-Generated Notice

This project was created with the help of artificial intelligence.

AI assistance may introduce inaccuracies, incomplete logic, or behavior that depends on the specific Windows version and configuration. Users should verify results and avoid applying changes blindly.

The presence of AI-generated code does not reduce user responsibility when modifying the operating system.

---

## Not Affiliated With Microsoft

VeTweek is an independent project and is not affiliated with, endorsed by, or connected to Microsoft.

Windows, Microsoft, Defender, OneDrive, Xbox, and other names may be trademarks of their respective owners.

---

## Building From Source

If you want to build VeTweek yourself, you need:

- Flutter SDK.
- Windows desktop development support.
- Visual Studio Build Tools or Visual Studio with the Desktop development with C++ workload.
- Git.
- Developer Mode enabled on Windows for plugin symlink support.

Install dependencies:

flutter pub get

Run in debug mode:

flutter run -d windows

Build the release executable:

flutter build windows --release

The release output is located in:

build\windows\x64\runner\Release

Copy the entire Release folder when distributing the application.

---

## Support and Issues

If you find a bug or want to suggest an improvement, open an issue in the GitHub repository.

When reporting an issue, include:

- Windows version.
- VeTweek version.
- Exact action performed.
- Screenshot if relevant.
- Log output from the Logs section.
- Whether the application was run as Administrator.

---

## [License](License)
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
