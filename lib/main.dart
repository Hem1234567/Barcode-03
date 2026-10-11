import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'screens/home_screen.dart';
import 'screens/history_screen.dart';
import 'screens/printer_screen.dart';
import 'screens/templates_screen.dart';
import 'services/printer_service.dart';
import 'services/store.dart';
import 'theme.dart';

final tabController = CupertinoTabController();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Store.init();
  runApp(const BarcodeApp());
  PrinterService.instance.autoReconnect(); // fire & forget, fully offline
}

class BarcodeApp extends StatelessWidget {
  const BarcodeApp({super.key});

  @override
  Widget build(BuildContext context) {
    final brightness = MediaQuery.platformBrightnessOf(context);
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: const Color(0x00000000),
      statusBarIconBrightness:
          brightness == Brightness.dark ? Brightness.light : Brightness.dark,
      systemNavigationBarColor:
          brightness == Brightness.dark ? CupertinoColors.black : CupertinoColors.white,
      systemNavigationBarIconBrightness:
          brightness == Brightness.dark ? Brightness.light : Brightness.dark,
    ));
    return CupertinoApp(
      title: 'Barcode Studio',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(brightness),
      home: CupertinoTabScaffold(
        controller: tabController,
        tabBar: CupertinoTabBar(
          onTap: (_) => HapticFeedback.selectionClick(),
          items: const [
            BottomNavigationBarItem(
                icon: Icon(CupertinoIcons.tag), label: 'Labels'),
            BottomNavigationBarItem(
                icon: Icon(CupertinoIcons.barcode), label: 'Quick'),
            BottomNavigationBarItem(
                icon: Icon(CupertinoIcons.clock), label: 'History'),
            BottomNavigationBarItem(
                icon: Icon(CupertinoIcons.bluetooth), label: 'Printer'),
          ],
        ),
        tabBuilder: (context, i) => CupertinoTabView(
          builder: (_) => switch (i) {
            0 => const TemplatesScreen(),
            1 => const HomeScreen(),
            2 => const HistoryScreen(),
            _ => const PrinterScreen(),
          },
        ),
      ),
    );
  }
}
