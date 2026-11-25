import 'package:flutter_test/flutter_test.dart';
import 'package:prepahub/edt.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('attribue des couleurs distinctes et stables par matière', () async {
    final first = await EdtColorStore.load(['Maths', 'Physique']);
    expect(first['maths'], isNotNull);
    expect(first['physique'], isNotNull);
    expect(first['maths'], isNot(first['physique']));

    final second = await EdtColorStore.load([' Maths ', 'PHYSIQUE']);
    expect(second['maths'], first['maths']);
    expect(second['physique'], first['physique']);
  });

  test('conserve une couleur modifiée', () async {
    await EdtColorStore.save({'maths': 0xFFC62828});

    final colors = await EdtColorStore.load(['Maths']);
    expect(colors['maths'], 0xFFC62828);
  });
}
