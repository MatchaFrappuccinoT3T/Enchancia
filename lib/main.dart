import 'package:flutter/material.dart';

import 'project_list_screen.dart';
import 'settings.dart';
import 'store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Store.init();
  final settings = Store.loadGlobalSettings();
  runApp(EnchanciaApp(settings: settings));
}

class EnchanciaApp extends StatelessWidget {
  final AppSettings settings;
  const EnchanciaApp({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final brightness =
            settings.isDark ? Brightness.dark : Brightness.light;
        return MaterialApp(
          title: 'Enchancia',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFFFFC0CB),
              brightness: brightness,
            ),
            useMaterial3: true,
            popupMenuTheme: PopupMenuThemeData(
              color: settings.menuColor,
              surfaceTintColor: Colors.transparent,
              elevation: 3,
              textStyle:
                  TextStyle(color: settings.appBarTextColor, fontSize: 14),
            ),
            dialogTheme: DialogThemeData(
              backgroundColor: settings.menuColor,
              surfaceTintColor: Colors.transparent,
            ),
          ),
          home: ProjectListScreen(globalSettings: settings),
        );
      },
    );
  }
}
