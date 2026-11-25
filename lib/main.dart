import 'dart:async';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart' show ValueNotifier, kReleaseMode;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'app_settings.dart';
import 'devoirs.dart';
import 'devoirs_notifications.dart';
import 'devoirs_page.dart';
import 'notes.dart';
import 'edt.dart';
import 'settings_page.dart';
import 'update.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await DevoirNotifications.instance.initialize();
  final settings = await AppSettingsStore.load();
  runApp(PrepaHubApp(initialSettings: settings));
}

class PrepaHubApp extends StatefulWidget {
  final AppSettings initialSettings;

  const PrepaHubApp({super.key, this.initialSettings = AppSettings.defaults});

  @override
  State<PrepaHubApp> createState() => _PrepaHubAppState();
}

class _PrepaHubAppState extends State<PrepaHubApp> {
  static const _seed = Color(0xFF3F51B5);
  late AppSettings _settings;

  @override
  void initState() {
    super.initState();
    _settings = widget.initialSettings;
  }

  Future<void> _updateSettings(AppSettings next) async {
    setState(() => _settings = next);
    await AppSettingsStore.save(next);
  }

  ThemeData _theme(ColorScheme scheme, {bool amoled = false}) {
    final colors = amoled
        ? scheme.copyWith(
            surface: Colors.black,
            surfaceContainerLowest: Colors.black,
            surfaceContainerLow: const Color(0xFF080808),
            surfaceContainer: const Color(0xFF0F0F0F),
            surfaceContainerHigh: const Color(0xFF171717),
            surfaceContainerHighest: const Color(0xFF202020),
            surfaceTint: Colors.transparent,
          )
        : scheme;
    return ThemeData(
      colorScheme: colors,
      useMaterial3: true,
      scaffoldBackgroundColor: amoled ? Colors.black : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        final dynamicColorAvailable =
            lightDynamic != null || darkDynamic != null;
        final light = _settings.dynamicColor
            ? lightDynamic?.harmonized() ??
                  ColorScheme.fromSeed(seedColor: _seed)
            : ColorScheme.fromSeed(seedColor: _seed);
        final dark = _settings.dynamicColor
            ? darkDynamic?.harmonized() ??
                  ColorScheme.fromSeed(
                    seedColor: _seed,
                    brightness: Brightness.dark,
                  )
            : ColorScheme.fromSeed(
                seedColor: _seed,
                brightness: Brightness.dark,
              );
        return MaterialApp(
          title: 'PrépaHub',
          debugShowCheckedModeBanner: false,
          theme: _theme(light),
          darkTheme: _theme(dark, amoled: _settings.amoledBlack),
          themeMode: _settings.themeMode,
          home: RootPage(
            settings: _settings,
            onSettingsChanged: _updateSettings,
            dynamicColorAvailable: dynamicColorAvailable,
          ),
        );
      },
    );
  }
}

class RootPage extends StatefulWidget {
  final AppSettings settings;
  final Future<void> Function(AppSettings) onSettingsChanged;
  final bool dynamicColorAvailable;

  const RootPage({
    super.key,
    required this.settings,
    required this.onSettingsChanged,
    required this.dynamicColorAvailable,
  });

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
            label: 'Planning',
          ),
          NavigationDestination(icon: Icon(Icons.checklist), label: 'Devoirs'),
          NavigationDestination(
            selectedIcon: Icon(Icons.settings),
            icon: Icon(Icons.settings_outlined),
            label: 'Réglages',
          ),
        ],
      ),
      body: <Widget>[
        /// Notes page
        NotesPage(),

        /// Timetable and khôlles
        EDTPage(onTimetableChanged: _syncDevoirNotifications),

        /// Homework
        DevoirsPage(draftRequest: _devoirDraftRequest),

        /// Settings
        SettingsPage(
          settings: widget.settings,
          onSettingsChanged: widget.onSettingsChanged,
          dynamicColorAvailable: widget.dynamicColorAvailable,
        ),
      ][currentPageIndex],
    );
  }
}
