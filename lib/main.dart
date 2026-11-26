import 'dart:async';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart' show ValueNotifier, kReleaseMode;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'app_lock.dart';
import 'app_settings.dart';
import 'devoirs.dart';
import 'devoirs_notifications.dart';
import 'devoirs_page.dart';
import 'notes.dart';
import 'edt.dart';
import 'notes_store.dart';
import 'settings_page.dart';
import 'today_page.dart';
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
          home: AppLockGate(
            enabled: _settings.appLock,
            onDisable: () =>
                _updateSettings(_settings.copyWith(appLock: false)),
            child: RootPage(
              settings: _settings,
              onSettingsChanged: _updateSettings,
              dynamicColorAvailable: dynamicColorAvailable,
            ),
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

class _RootPageState extends State<RootPage> with WidgetsBindingObserver {
  late AppSection _current;
  Timer? _updateTimer;
  Timer? _refreshTimer;
  DateTime? _lastAutoRefresh;
  final ValueNotifier<DevoirDraft?> _devoirDraftRequest =
      ValueNotifier<DevoirDraft?>(null);

  @override
  void initState() {
    super.initState();
    _current = widget.settings.startSection;

    final initialTap = devoirNotificationTap.value;
    if (initialTap != null) {
      devoirNotificationTap.value = null;
      _current = AppSection.devoirs;
      if (initialTap.matiere != null) {
        _devoirDraftRequest.value = DevoirDraft(matiere: initialTap.matiere);
      }
    }
    devoirNotificationTap.addListener(_handleDevoirNotification);
    colleNotificationTap.addListener(_handleColleNotification);
    WidgetsBinding.instance.addObserver(this);
    _configureAutoRefresh();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(DevoirNotifications.instance.sync());
      if (widget.settings.autoRefresh &&
          widget.settings.startSection != AppSection.notes) {
        unawaited(_autoRefresh());
      } else {
        _lastAutoRefresh = DateTime.now();
      }
    });

    if (kReleaseMode) {
      _updateTimer = Timer(const Duration(seconds: 4), _checkUpdate);
    }
  }

  @override
  void dispose() {
    devoirNotificationTap.removeListener(_handleDevoirNotification);
    colleNotificationTap.removeListener(_handleColleNotification);
    WidgetsBinding.instance.removeObserver(this);
    _devoirDraftRequest.dispose();
    _updateTimer?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _handleColleNotification() {
    if (colleNotificationTap.value != true) return;
    colleNotificationTap.value = false;
    if (!mounted) return;
    final target = widget.settings.isAvailable(AppSection.planning)
        ? AppSection.planning
        : AppSection.devoirs;
    if (!widget.settings.isAvailable(target)) return;
    setState(() => _current = target);
  }

  void _configureAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    if (!widget.settings.autoRefresh) return;
    _refreshTimer = Timer.periodic(const Duration(minutes: 30), (_) {
      unawaited(_autoRefresh());
    });
  }

  Future<void> _autoRefresh() async {
    _lastAutoRefresh = DateTime.now();
    await refreshNotesInBackground(notify: widget.settings.notifyNewGrades);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !widget.settings.autoRefresh) {
      return;
    }
    final last = _lastAutoRefresh;
    if (last == null ||
        DateTime.now().difference(last) >= const Duration(minutes: 5)) {
      unawaited(_autoRefresh());
    }
  }

  void _openSection(AppSection section) {
    if (!widget.settings.isAvailable(section)) return;
    setState(() => _current = section);
  }

  void _handleDevoirNotification() {
    final tap = devoirNotificationTap.value;
    if (tap == null) return;
    devoirNotificationTap.value = null;
    if (!mounted) return;
    setState(() => _current = AppSection.devoirs);
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
  void didUpdateWidget(RootPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.settings.isAvailable(_current)) {
      _current = widget.settings.startSection;
    }
    if (oldWidget.settings.autoRefresh != widget.settings.autoRefresh) {
      _configureAutoRefresh();
      if (widget.settings.autoRefresh) unawaited(_autoRefresh());
    }
  }

  Future<void> _openMenu() async {
    final sections = widget.settings.navMenu;
    if (sections.isEmpty) return;
    final picked = await showModalBottomSheet<AppSection>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text('Menu', style: Theme.of(ctx).textTheme.titleLarge),
            ),
            for (final section in sections)
              ListTile(
                leading: Icon(section.icon),
                title: Text(section.label),
                selected: section == _current,
                onTap: () => Navigator.pop(ctx, section),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _current = picked);
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final bar = settings.navBar;
    var selectedIndex = bar.indexOf(_current);
    if (selectedIndex < 0) {
      selectedIndex = settings.navMenu.contains(_current) ? bar.length : 0;
    }

    Widget destinationIcon(Widget icon, {required bool isDefault}) {
      if (!isDefault) return icon;
      return Badge(
        smallSize: 6,
        backgroundColor: Theme.of(context).colorScheme.primary,
        child: Tooltip(message: 'Onglet par défaut', child: icon),
      );
    }

    return Scaffold(
      bottomNavigationBar: NavigationBar(
        onDestinationSelected: (int index) {
          if (index >= bar.length) {
            unawaited(_openMenu());
            return;
          }
          setState(() => _current = bar[index]);
        },
        selectedIndex: selectedIndex,
        destinations: [
          for (final section in bar)
            NavigationDestination(
              selectedIcon: Icon(section.selectedIcon),
              icon: destinationIcon(
                Icon(section.icon),
                isDefault: section == settings.startSection,
              ),
              label: section.label,
            ),
          if (settings.navMenu.isNotEmpty)
            NavigationDestination(
              icon: destinationIcon(
                const Icon(Icons.menu),
                isDefault: settings.navMenu.contains(settings.startSection),
              ),
              label: 'Menu',
            ),
        ],
      ),
      body: switch (_current) {
        AppSection.today => TodayPage(onOpenSection: _openSection),
        AppSection.notes => NotesPage(
          layout: settings.notesLayout,
          sort: settings.notesSort,
          sortDirection: settings.notesSortDirection,
          notifyNewGrades: settings.notifyNewGrades,
        ),
        AppSection.planning => EDTPage(
          onTimetableChanged: _syncDevoirNotifications,
        ),
        AppSection.devoirs => DevoirsPage(draftRequest: _devoirDraftRequest),
        AppSection.settings => SettingsPage(
          settings: settings,
          onSettingsChanged: widget.onSettingsChanged,
          dynamicColorAvailable: widget.dynamicColorAvailable,
        ),
      },
    );
  }
}
