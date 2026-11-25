import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:prepahub/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('utilise le thème système par défaut', () async {
    final settings = await AppSettingsStore.load();

    expect(settings.themeMode, ThemeMode.system);
    expect(settings.dynamicColor, isTrue);
    expect(settings.amoledBlack, isFalse);
  });

  test('conserve les réglages enregistrés', () async {
    const settings = AppSettings(
      themeMode: ThemeMode.dark,
      dynamicColor: false,
      amoledBlack: true,
    );

    await AppSettingsStore.save(settings);
    final loaded = await AppSettingsStore.load();

    expect(loaded.themeMode, ThemeMode.dark);
    expect(loaded.dynamicColor, isFalse);
    expect(loaded.amoledBlack, isTrue);
  });
}
