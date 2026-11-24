import 'dart:async';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart' show ValueNotifier, kReleaseMode;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'devoirs.dart';
import 'devoirs_notifications.dart';
import 'devoirs_page.dart';
import 'notes.dart';
import 'edt.dart';
import 'update.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await DevoirNotifications.instance.initialize();
  runApp(const PrepaHubApp());
}

class PrepaHubApp extends StatelessWidget {
  const PrepaHubApp({super.key});

  static const _seed = Color(0xFF3F51B5);

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        final light =
            lightDynamic?.harmonized() ??
            ColorScheme.fromSeed(seedColor: _seed);
        final dark =
            darkDynamic?.harmonized() ??
            ColorScheme.fromSeed(seedColor: _seed, brightness: Brightness.dark);
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
  Timer? _updateTimer;
  final ValueNotifier<DevoirDraft?> _devoirDraftRequest =
      ValueNotifier<DevoirDraft?>(null);

  @override
  void initState() {
    super.initState();

    final initialTap = devoirNotificationTap.value;
    if (initialTap != null) {
      devoirNotificationTap.value = null;
      currentPageIndex = 2;
      if (initialTap.matiere != null) {
        _devoirDraftRequest.value = DevoirDraft(matiere: initialTap.matiere);
      }
    }
    devoirNotificationTap.addListener(_handleDevoirNotification);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(DevoirNotifications.instance.sync());
    });

    if (kReleaseMode) {
      _updateTimer = Timer(const Duration(seconds: 4), _checkUpdate);
    }
  }

  @override
  void dispose() {
    devoirNotificationTap.removeListener(_handleDevoirNotification);
    _devoirDraftRequest.dispose();
    _updateTimer?.cancel();
    super.dispose();
  }

  void _handleDevoirNotification() {
    final tap = devoirNotificationTap.value;
    if (tap == null) return;
    devoirNotificationTap.value = null;
    if (!mounted) return;
    setState(() => currentPageIndex = 2);
    if (tap.matiere != null) {
      _devoirDraftRequest.value = DevoirDraft(matiere: tap.matiere);
    }
  }

  void _syncDevoirNotifications() {
    unawaited(DevoirNotifications.instance.sync());
  }

  Future<void> _checkUpdate() async {
    final u = await checkForUpdate();
    if (u == null || !mounted) return;
    showUpdateSnack(context, u);
  }

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
            selectedIcon: Icon(Icons.calendar_month),
            icon: Icon(Icons.calendar_month_outlined),
            label: 'Emploi du temps',
          ),
          NavigationDestination(icon: Icon(Icons.checklist), label: 'Devoirs'),
        ],
      ),
      body: <Widget>[
        /// Notes page
        NotesPage(),

        /// Timetable and khôlles
        EDTPage(onTimetableChanged: _syncDevoirNotifications),

        /// Homework
        DevoirsPage(draftRequest: _devoirDraftRequest),
      ][currentPageIndex],
    );
  }
}
