import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:prepahub/main.dart';

void main() {
  testWidgets('l app se lance sans crash', (tester) async {
    await tester.pumpWidget(const PrepaHubApp());
    await tester.pump(); // laisse le premier frame se construire
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
