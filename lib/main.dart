import 'package:flutter/material.dart';
import 'package:material_ui/material_ui.dart' as material_ui;
import 'package:window_manager/window_manager.dart';
import 'package:vetweek/pages.dart';
import 'package:vetweek/services.dart';
import 'package:vetweek/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await windowManager.ensureInitialized();

  const options = WindowOptions(
    size: Size(1320, 840),
    minimumSize: Size(1120, 720),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    title: 'VeTweek',
  );

  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.setAsFrameless();
    await windowManager.setResizable(true);
    await windowManager.show();
    await windowManager.focus();
  });

  final services = AppServices();
  await services.init();

  runApp(VeTweekApp(services: services));
}

class VeTweekApp extends StatelessWidget {
  final AppServices services;

  const VeTweekApp({
    super.key,
    required this.services,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        services.settings,
        services.log,
        services.system,
        services.appx,
        services.defender,
        services.advertising,
        services.widgets,
      ]),
      builder: (context, child) {
        return MaterialApp(
          title: 'VeTweek',
          debugShowCheckedModeBanner: false,
          themeMode: services.settings.themeMode,
          theme: AppTheme.build(
            brightness: Brightness.light,
            seedColor: services.settings.seedColor,
          ),
          darkTheme: AppTheme.build(
            brightness: Brightness.dark,
            seedColor: services.settings.seedColor,
          ),
          home: AppShell(services: services),
        );
      },
    );
  }
}
