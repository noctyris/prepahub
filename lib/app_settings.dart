import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppSection { notes, planning, devoirs, settings }

extension AppSectionInfo on AppSection {
  String get label => switch (this) {
    AppSection.notes => 'Notes',
    AppSection.planning => 'Planning',
    AppSection.devoirs => 'Devoirs',
    AppSection.settings => 'Réglages',
  };

  IconData get icon => switch (this) {
    AppSection.notes => Icons.pie_chart_outline,
    AppSection.planning => Icons.calendar_month_outlined,
    AppSection.devoirs => Icons.checklist,
    AppSection.settings => Icons.settings_outlined,
  };

  IconData get selectedIcon => switch (this) {
    AppSection.notes => Icons.pie_chart,
    AppSection.planning => Icons.calendar_month,
    AppSection.devoirs => Icons.checklist,
    AppSection.settings => Icons.settings,
  };
}

enum SectionPlacement { bar, menu, hidden }

extension SectionPlacementInfo on SectionPlacement {
  String get label => switch (this) {
    SectionPlacement.bar => 'Barre du bas',
    SectionPlacement.menu => 'Menu',
    SectionPlacement.hidden => 'Masquée',
  };

  String get description => switch (this) {
    SectionPlacement.bar => 'Toujours visible dans la barre.',
    SectionPlacement.menu => 'Accessible depuis le bouton menu.',
    SectionPlacement.hidden => 'Retirée de la navigation.',
  };
}

class AppSettings {
  final ThemeMode themeMode;
  final bool dynamicColor;
  final bool amoledBlack;
  final List<AppSection> navBar;
  final List<AppSection> navMenu;
  final AppSection startSection;

  const AppSettings({
    required this.themeMode,
    required this.dynamicColor,
    required this.amoledBlack,
    this.navBar = const [
      AppSection.notes,
      AppSection.planning,
      AppSection.devoirs,
      AppSection.settings,
    ],
    this.navMenu = const [],
    this.startSection = AppSection.notes,
  });

  static const defaults = AppSettings(
    themeMode: ThemeMode.system,
    dynamicColor: true,
    amoledBlack: false,
  );

  List<AppSection> get hiddenSections => [
    for (final section in AppSection.values)
      if (!navBar.contains(section) && !navMenu.contains(section)) section,
  ];

  bool isAvailable(AppSection section) =>
      navBar.contains(section) || navMenu.contains(section);

  AppSettings copyWith({
    ThemeMode? themeMode,
    bool? dynamicColor,
    bool? amoledBlack,
    List<AppSection>? navBar,
    List<AppSection>? navMenu,
    AppSection? startSection,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    dynamicColor: dynamicColor ?? this.dynamicColor,
    amoledBlack: amoledBlack ?? this.amoledBlack,
    navBar: navBar ?? this.navBar,
    navMenu: navMenu ?? this.navMenu,
    startSection: startSection ?? this.startSection,
  ).normalized();

  /// Garde une navigation utilisable : pas de doublon, au moins deux pages
  /// dans la barre et un chemin vers les réglages.
  AppSettings normalized() {
    final seen = <AppSection>{};
    final bar = <AppSection>[
      for (final section in navBar)
        if (seen.add(section)) section,
    ];
    final menu = <AppSection>[
      for (final section in navMenu)
        if (seen.add(section)) section,
    ];
    for (final fallback in AppSection.values) {
      if (bar.length >= 2) break;
      if (!bar.contains(fallback)) {
        bar.add(fallback);
        menu.remove(fallback);
      }
    }
    if (!bar.contains(AppSection.settings) &&
        !menu.contains(AppSection.settings)) {
      menu.add(AppSection.settings);
    }
    final start = bar.contains(startSection) || menu.contains(startSection)
        ? startSection
        : bar.first;
    return AppSettings(
      themeMode: themeMode,
      dynamicColor: dynamicColor,
      amoledBlack: amoledBlack,
      navBar: List.unmodifiable(bar),
      navMenu: List.unmodifiable(menu),
      startSection: start,
    );
  }
}

class AppSettingsStore {
  static const _themeModeKey = 'app_theme_mode';
  static const _dynamicColorKey = 'app_dynamic_color';
  static const _amoledBlackKey = 'app_amoled_black';
  static const _navBarKey = 'app_nav_bar';
  static const _navMenuKey = 'app_nav_menu';
  static const _startSectionKey = 'app_start_section';

  static Future<AppSettings> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return AppSettings(
        themeMode: _themeModeFrom(prefs.getString(_themeModeKey)),
        dynamicColor:
            prefs.getBool(_dynamicColorKey) ??
            AppSettings.defaults.dynamicColor,
        amoledBlack:
            prefs.getBool(_amoledBlackKey) ?? AppSettings.defaults.amoledBlack,
        navBar:
            _sectionsFrom(prefs.getStringList(_navBarKey)) ??
            AppSettings.defaults.navBar,
        navMenu:
            _sectionsFrom(prefs.getStringList(_navMenuKey)) ??
            AppSettings.defaults.navMenu,
        startSection:
            _sectionFrom(prefs.getString(_startSectionKey)) ??
            AppSettings.defaults.startSection,
      ).normalized();
    } catch (_) {
      return AppSettings.defaults;
    }
  }

  static Future<void> save(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, settings.themeMode.name);
    await prefs.setBool(_dynamicColorKey, settings.dynamicColor);
    await prefs.setBool(_amoledBlackKey, settings.amoledBlack);
    await prefs.setStringList(_navBarKey, [
      for (final section in settings.navBar) section.name,
    ]);
    await prefs.setStringList(_navMenuKey, [
      for (final section in settings.navMenu) section.name,
    ]);
    await prefs.setString(_startSectionKey, settings.startSection.name);
  }

  static List<AppSection>? _sectionsFrom(List<String>? values) {
    if (values == null) return null;
    return [
      for (final value in values)
        for (final section in AppSection.values)
          if (section.name == value) section,
    ];
  }

  static AppSection? _sectionFrom(String? value) {
    for (final section in AppSection.values) {
      if (section.name == value) return section;
    }
    return null;
  }

  static ThemeMode _themeModeFrom(String? value) {
    for (final mode in ThemeMode.values) {
      if (mode.name == value) return mode;
    }
    return AppSettings.defaults.themeMode;
  }
}
