import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppSection { today, notes, planning, devoirs, settings }

extension AppSectionInfo on AppSection {
  String get label => switch (this) {
    AppSection.today => "Aujourd'hui",
    AppSection.notes => 'Notes',
    AppSection.planning => 'Planning',
    AppSection.devoirs => 'Devoirs',
    AppSection.settings => 'Réglages',
  };

  IconData get icon => switch (this) {
    AppSection.today => Icons.today_outlined,
    AppSection.notes => Icons.pie_chart_outline,
    AppSection.planning => Icons.calendar_month_outlined,
    AppSection.devoirs => Icons.checklist,
    AppSection.settings => Icons.settings_outlined,
  };

  IconData get selectedIcon => switch (this) {
    AppSection.today => Icons.today,
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

enum NotesLayout { cards, grid, list, drawers }

extension NotesLayoutInfo on NotesLayout {
  String get label => switch (this) {
    NotesLayout.cards => 'Cartes',
    NotesLayout.grid => 'Grille',
    NotesLayout.list => 'Liste',
    NotesLayout.drawers => 'Tiroirs',
  };

  String get description => switch (this) {
    NotesLayout.cards => 'Une carte par semaine, à déplier.',
    NotesLayout.grid => 'Deux semaines par ligne, avec un aperçu des notes.',
    NotesLayout.list => 'Toutes les notes à plat, sans dépliage.',
    NotesLayout.drawers =>
      'Une réglette de semaines et les notes de celle choisie.',
  };

  IconData get icon => switch (this) {
    NotesLayout.cards => Icons.view_agenda_outlined,
    NotesLayout.grid => Icons.grid_view_outlined,
    NotesLayout.list => Icons.view_list_outlined,
    NotesLayout.drawers => Icons.vertical_split_outlined,
  };
}

enum NotesSort { time, grade, rank, subject }

extension NotesSortInfo on NotesSort {
  String get label => switch (this) {
    NotesSort.time => 'Temps',
    NotesSort.grade => 'Note',
    NotesSort.rank => 'Rang',
    NotesSort.subject => 'Matière',
  };

  IconData get icon => switch (this) {
    NotesSort.time => Icons.schedule,
    NotesSort.grade => Icons.grade_outlined,
    NotesSort.rank => Icons.leaderboard_outlined,
    NotesSort.subject => Icons.book_outlined,
  };
}

enum NotesSortDirection { ascending, descending }

extension NotesSortDirectionInfo on NotesSortDirection {
  String get label => switch (this) {
    NotesSortDirection.ascending => 'Croissant',
    NotesSortDirection.descending => 'Décroissant',
  };

  String get description => switch (this) {
    NotesSortDirection.ascending => 'Du plus petit au plus grand.',
    NotesSortDirection.descending => 'Du plus grand au plus petit.',
  };

  IconData get icon => switch (this) {
    NotesSortDirection.ascending => Icons.arrow_upward,
    NotesSortDirection.descending => Icons.arrow_downward,
  };
}

class AppSettings {
  final ThemeMode themeMode;
  final bool dynamicColor;
  final bool amoledBlack;
  final NotesLayout notesLayout;
  final NotesSort notesSort;
  final NotesSortDirection notesSortDirection;
  final bool showNormalDistribution;
  final bool highlightDefaultTab;
  final bool notifyNewGrades;
  final bool autoRefresh;
  final bool appLock;
  final List<AppSection> navBar;
  final List<AppSection> navMenu;
  final AppSection startSection;

  const AppSettings({
    required this.themeMode,
    required this.dynamicColor,
    required this.amoledBlack,
    this.notesLayout = NotesLayout.cards,
    this.notesSort = NotesSort.time,
    this.notesSortDirection = NotesSortDirection.ascending,
    this.showNormalDistribution = true,
    this.highlightDefaultTab = true,
    this.notifyNewGrades = true,
    this.autoRefresh = true,
    this.appLock = false,
    this.navBar = const [
      AppSection.today,
      AppSection.notes,
      AppSection.planning,
      AppSection.devoirs,
      AppSection.settings,
    ],
    this.navMenu = const [],
    this.startSection = AppSection.today,
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
    NotesLayout? notesLayout,
    NotesSort? notesSort,
    NotesSortDirection? notesSortDirection,
    bool? showNormalDistribution,
    bool? highlightDefaultTab,
    bool? notifyNewGrades,
    bool? autoRefresh,
    bool? appLock,
    List<AppSection>? navBar,
    List<AppSection>? navMenu,
    AppSection? startSection,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    dynamicColor: dynamicColor ?? this.dynamicColor,
    amoledBlack: amoledBlack ?? this.amoledBlack,
    notesLayout: notesLayout ?? this.notesLayout,
    notesSort: notesSort ?? this.notesSort,
    notesSortDirection: notesSortDirection ?? this.notesSortDirection,
    showNormalDistribution:
        showNormalDistribution ?? this.showNormalDistribution,
    highlightDefaultTab: highlightDefaultTab ?? this.highlightDefaultTab,
    notifyNewGrades: notifyNewGrades ?? this.notifyNewGrades,
    autoRefresh: autoRefresh ?? this.autoRefresh,
    appLock: appLock ?? this.appLock,
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
      notesLayout: notesLayout,
      notesSort: notesSort,
      notesSortDirection: notesSortDirection,
      showNormalDistribution: showNormalDistribution,
      highlightDefaultTab: highlightDefaultTab,
      notifyNewGrades: notifyNewGrades,
      autoRefresh: autoRefresh,
      appLock: appLock,
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
  static const _notesLayoutKey = 'app_notes_layout';
  static const _notesSortKey = 'app_notes_sort';
  static const _notesSortDirectionKey = 'app_notes_sort_direction';
  static const _showNormalDistributionKey = 'app_notes_normal_distribution';
  static const _highlightDefaultTabKey = 'app_highlight_default_tab';
  static const _notifyNewGradesKey = 'app_notify_new_grades';
  static const _autoRefreshKey = 'app_auto_refresh';
  static const _appLockKey = 'app_lock';
  static const _navTodayMigrationKey = 'app_nav_today_migrated';
  static const _navBarKey = 'app_nav_bar';
  static const _navMenuKey = 'app_nav_menu';
  static const _startSectionKey = 'app_start_section';

  static Future<AppSettings> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var navBar =
          _sectionsFrom(prefs.getStringList(_navBarKey)) ??
          AppSettings.defaults.navBar;
      var navMenu =
          _sectionsFrom(prefs.getStringList(_navMenuKey)) ??
          AppSettings.defaults.navMenu;
      if (!(prefs.getBool(_navTodayMigrationKey) ?? false)) {
        if (!navBar.contains(AppSection.today) &&
            !navMenu.contains(AppSection.today)) {
          navBar = [AppSection.today, ...navBar];
        }
        await prefs.setBool(_navTodayMigrationKey, true);
      }
      return AppSettings(
        themeMode: _themeModeFrom(prefs.getString(_themeModeKey)),
        dynamicColor:
            prefs.getBool(_dynamicColorKey) ??
            AppSettings.defaults.dynamicColor,
        amoledBlack:
            prefs.getBool(_amoledBlackKey) ?? AppSettings.defaults.amoledBlack,
        notesLayout: _notesLayoutFrom(prefs.getString(_notesLayoutKey)),
        notesSort: _notesSortFrom(prefs.getString(_notesSortKey)),
        notesSortDirection: _notesSortDirectionFrom(
          prefs.getString(_notesSortDirectionKey),
        ),
        showNormalDistribution:
            prefs.getBool(_showNormalDistributionKey) ??
            AppSettings.defaults.showNormalDistribution,
        highlightDefaultTab:
            prefs.getBool(_highlightDefaultTabKey) ??
            AppSettings.defaults.highlightDefaultTab,
        notifyNewGrades:
            prefs.getBool(_notifyNewGradesKey) ??
            AppSettings.defaults.notifyNewGrades,
        autoRefresh:
            prefs.getBool(_autoRefreshKey) ?? AppSettings.defaults.autoRefresh,
        appLock: prefs.getBool(_appLockKey) ?? AppSettings.defaults.appLock,
        navBar: navBar,
        navMenu: navMenu,
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
    await prefs.setString(_notesLayoutKey, settings.notesLayout.name);
    await prefs.setString(_notesSortKey, settings.notesSort.name);
    await prefs.setString(
      _notesSortDirectionKey,
      settings.notesSortDirection.name,
    );
    await prefs.setBool(
      _showNormalDistributionKey,
      settings.showNormalDistribution,
    );
    await prefs.setBool(_highlightDefaultTabKey, settings.highlightDefaultTab);
    await prefs.setBool(_notifyNewGradesKey, settings.notifyNewGrades);
    await prefs.setBool(_autoRefreshKey, settings.autoRefresh);
    await prefs.setBool(_appLockKey, settings.appLock);
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

  static NotesLayout _notesLayoutFrom(String? value) {
    for (final layout in NotesLayout.values) {
      if (layout.name == value) return layout;
    }
    return AppSettings.defaults.notesLayout;
  }

  static NotesSort _notesSortFrom(String? value) {
    for (final sort in NotesSort.values) {
      if (sort.name == value) return sort;
    }
    return AppSettings.defaults.notesSort;
  }

  static NotesSortDirection _notesSortDirectionFrom(String? value) {
    for (final direction in NotesSortDirection.values) {
      if (direction.name == value) return direction;
    }
    return AppSettings.defaults.notesSortDirection;
  }

  static ThemeMode _themeModeFrom(String? value) {
    for (final mode in ThemeMode.values) {
      if (mode.name == value) return mode;
    }
    return AppSettings.defaults.themeMode;
  }
}
