import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:prepahub/app_settings.dart';
import 'package:prepahub/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('l app se lance sans crash', (tester) async {
    await tester.pumpWidget(const PrepaHubApp());
    await tester.pump(); // laisse le premier frame se construire
    expect(find.byType(MaterialApp), findsOneWidget);
  });

  testWidgets('change le thème depuis les réglages', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const PrepaHubApp());
    await tester.pump();

    await tester.tap(find.text('Réglages'));
    await tester.pumpAndSettle();

    expect(find.text('Apparence'), findsOneWidget);
    expect(find.text('Noir AMOLED'), findsOneWidget);

    await tester.tap(find.text('Sombre'));
    await tester.pumpAndSettle();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
    expect((await AppSettingsStore.load()).themeMode, ThemeMode.dark);
  });
}
