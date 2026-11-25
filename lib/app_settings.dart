import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  final ThemeMode themeMode;
  final bool dynamicColor;
  final bool amoledBlack;

  const AppSettings({
    required this.themeMode,
    required this.dynamicColor,
    required this.amoledBlack,
  });

  static const defaults = AppSettings(
    themeMode: ThemeMode.system,
    dynamicColor: true,
    amoledBlack: false,
  );

  AppSettings copyWith({
    ThemeMode? themeMode,
    bool? dynamicColor,
    bool? amoledBlack,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    dynamicColor: dynamicColor ?? this.dynamicColor,
    amoledBlack: amoledBlack ?? this.amoledBlack,
  );
}

class AppSettingsStore {
  static const _themeModeKey = 'app_theme_mode';
  static const _dynamicColorKey = 'app_dynamic_color';
  static const _amoledBlackKey = 'app_amoled_black';

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
      );
    } catch (_) {
      return AppSettings.defaults;
    }
  }

  static Future<void> save(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, settings.themeMode.name);
    await prefs.setBool(_dynamicColorKey, settings.dynamicColor);
    await prefs.setBool(_amoledBlackKey, settings.amoledBlack);
  }

  static ThemeMode _themeModeFrom(String? value) {
    for (final mode in ThemeMode.values) {
      if (mode.name == value) return mode;
    }
    return AppSettings.defaults.themeMode;
  }
}
