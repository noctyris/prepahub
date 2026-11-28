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
    expect(settings.notesLayout, NotesLayout.cards);
    expect(settings.notesSort, NotesSort.time);
    expect(settings.notesSortDirection, NotesSortDirection.ascending);
    expect(settings.showNormalDistribution, isTrue);
    expect(settings.highlightDefaultTab, isTrue);
    expect(settings.notifyNewGrades, isTrue);
  });

  test('conserve les réglages enregistrés', () async {
    const settings = AppSettings(
      themeMode: ThemeMode.dark,
      dynamicColor: false,
      amoledBlack: true,
      notesLayout: NotesLayout.grid,
      notesSort: NotesSort.grade,
      notesSortDirection: NotesSortDirection.descending,
      showNormalDistribution: false,
      highlightDefaultTab: false,
      notifyNewGrades: false,
    );

    await AppSettingsStore.save(settings);
    final loaded = await AppSettingsStore.load();

    expect(loaded.themeMode, ThemeMode.dark);
    expect(loaded.dynamicColor, isFalse);
    expect(loaded.amoledBlack, isTrue);
    expect(loaded.notesLayout, NotesLayout.grid);
    expect(loaded.notesSort, NotesSort.grade);
    expect(loaded.notesSortDirection, NotesSortDirection.descending);
    expect(loaded.showNormalDistribution, isFalse);
    expect(loaded.highlightDefaultTab, isFalse);
    expect(loaded.notifyNewGrades, isFalse);
  });
}
