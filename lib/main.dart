import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'notes.dart';
import 'colloscope.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const PrepaHubApp());
}

class PrepaHubApp extends StatelessWidget {
  const PrepaHubApp({super.key});

  static const _seed = Color(0xFF3F51B5);

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        final light = lightDynamic?.harmonized() ??
            ColorScheme.fromSeed(seedColor: _seed);
        final dark = darkDynamic?.harmonized() ??
            ColorScheme.fromSeed(
                seedColor: _seed, brightness: Brightness.dark);
        return MaterialApp(
          title: 'PrepaHub',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(colorScheme: light, useMaterial3: true),
          darkTheme: ThemeData(colorScheme: dark, useMaterial3: true),
          themeMode: ThemeMode.system,
          home: const RootPage(),
        );
      },
    );
  }
}

class RootPage extends StatefulWidget {
  const RootPage({super.key});

  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  int currentPageIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: NavigationBar(
        onDestinationSelected: (int index) {
          setState(() {
            currentPageIndex = index;
          });
        },
        selectedIndex: currentPageIndex,
        destinations: const <Widget>[
          NavigationDestination(
            selectedIcon: Icon(Icons.pie_chart),
            icon: Icon(Icons.pie_chart_outline),
            label: 'Notes',
          ),
          NavigationDestination(
//            icon: Badge(label: Text('2'), child: Icon(Icons.calendar_month)),
            icon: Icon(Icons.calendar_month),
            label: 'Colloscope',
          ),
          NavigationDestination(
            icon: Icon(Icons.abc),
            label: '',
          ),
        ],
      ),
      body: <Widget>[
        /// Notes page
        NotesPage(),
        
        /// Colloscope
        ColloscopePage(),
        
        /// Idk
        const Center(child: Text('Rien pour le moment')),
        ][currentPageIndex],
    );
  }
}
