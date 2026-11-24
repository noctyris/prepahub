import 'package:flutter_test/flutter_test.dart';
import 'package:prepahub/devoirs.dart';

void main() {
  group('Devoir', () {
    test('survit à un aller-retour JSON', () {
      final devoir = Devoir(
        id: '42',
        titre: 'DM n°4',
        matiere: 'Maths',
        description: 'Suites et intégrales',
        sousTaches: [
          DevoirSousTache(id: 's1', texte: 'Suites', fait: true),
          DevoirSousTache(id: 's2', texte: 'Intégrales'),
        ],
        echeance: DateTime(2026, 11, 25),
        fait: true,
        creeLe: DateTime(2026, 11, 20, 18, 30),
      );

      final copy = Devoir.fromJson(devoir.toJson());

      expect(copy.id, devoir.id);
      expect(copy.titre, devoir.titre);
      expect(copy.matiere, devoir.matiere);
      expect(copy.description, 'Suites et intégrales');
      expect(copy.type, DevoirType.devoirMaison);
      expect(copy.sousTaches, hasLength(2));
      expect(copy.sousTaches.first.texte, 'Suites');
      expect(copy.sousTaches.first.fait, isTrue);
      expect(copy.echeance, devoir.echeance);
      expect(copy.fait, isTrue);
      expect(copy.creeLe, devoir.creeLe);
    });

    test('reste compatible avec un ancien fichier', () {
      final devoir = Devoir.fromJson({
        'id': '1',
        'titre': 'Éval de maths',
        'matiere': 'Maths',
        'echeance': '2026-11-25T00:00:00.000',
        'fait': false,
        'creeLe': '2026-11-20T00:00:00.000',
      });

      expect(devoir.description, isEmpty);
      expect(devoir.sousTaches, isEmpty);
      expect(devoir.type, DevoirType.evaluation);
    });

    test('classe les échéances par jour', () {
      final today = DateTime(2026, 11, 24);
      Devoir due(DateTime date, {bool fait = false}) => Devoir(
        id: date.toIso8601String(),
        titre: 'Travail',
        matiere: 'Maths',
        echeance: date,
        fait: fait,
      );

      expect(due(DateTime(2026, 11, 23)).bucket(today), DevoirBucket.overdue);
      expect(due(DateTime(2026, 11, 24)).bucket(today), DevoirBucket.today);
      expect(due(DateTime(2026, 11, 25)).bucket(today), DevoirBucket.tomorrow);
      expect(due(DateTime(2026, 11, 26)).bucket(today), DevoirBucket.thisWeek);
      expect(due(DateTime(2026, 12, 2)).bucket(today), DevoirBucket.later);
      expect(
        due(DateTime(2026, 11, 24), fait: true).bucket(today),
        DevoirBucket.done,
      );
    });

    test('compare les dates sans se laisser piéger par l’heure', () {
      expect(
        daysBetween(DateTime(2026, 3, 28, 23), DateTime(2026, 3, 30, 1)),
        2,
      );
    });
  });

  group('détection du type', () {
    test('reconnaît les évaluations', () {
      expect(detectDevoirType('Éval de maths jeudi'), DevoirType.evaluation);
      expect(detectDevoirType('DS n°3'), DevoirType.evaluation);
      expect(detectDevoirType('Contrôle continu'), DevoirType.evaluation);
      expect(detectDevoirType('Khôlle d’anglais'), DevoirType.evaluation);
    });

    test('reconnaît les devoirs maison et les exercices', () {
      expect(detectDevoirType('DM n°4'), DevoirType.devoirMaison);
      expect(detectDevoirType('Devoir maison'), DevoirType.devoirMaison);
      expect(detectDevoirType('Exercices 12 à 15'), DevoirType.exercices);
      expect(detectDevoirType('TD de physique'), DevoirType.exercices);
    });

    test('reconnaît les révisions et le reste', () {
      expect(detectDevoirType('Relire le cours'), DevoirType.revision);
      expect(detectDevoirType('Fiche de formules'), DevoirType.revision);
      expect(detectDevoirType('Acheter des copies'), DevoirType.autre);
      expect(detectDevoirType(''), DevoirType.autre);
    });

    test('le constructeur déduit le type des détails', () {
      final devoir = Devoir(
        id: '1',
        titre: 'Maths jeudi',
        matiere: 'Maths',
        description: 'Les notions à voir',
        sousTaches: [DevoirSousTache(id: 'sub', texte: 'Éval sur les suites')],
        echeance: DateTime(2026, 11, 26),
      );

      expect(devoir.type, DevoirType.evaluation);
    });
  });

  group('DevoirsStore', () {
    test('encode et décode une liste', () {
      final devoirs = [
        Devoir(
          id: '1',
          titre: 'Exercices',
          matiere: 'Physique',
          echeance: DateTime(2026, 11, 26),
        ),
        Devoir(
          id: '2',
          titre: 'Révisions',
          matiere: '',
          echeance: DateTime(2026, 11, 27),
          fait: true,
        ),
      ];

      final decoded = DevoirsStore.decode(DevoirsStore.encode(devoirs));

      expect(decoded, hasLength(2));
      expect(decoded.first.titre, 'Exercices');
      expect(decoded.last.fait, isTrue);
    });
  });

  group('cours instructifs', () {
    test('garde les matières classiques', () {
      expect(isInstructiveMatiere('Maths'), isTrue);
      expect(isInstructiveMatiere('Physique'), isTrue);
      expect(isInstructiveMatiere('Anglais'), isTrue);
      expect(isInstructiveMatiere('Informatique'), isTrue);
    });

    test('écarte le sport et les DS', () {
      expect(isInstructiveMatiere('EPS'), isFalse);
      expect(isInstructiveMatiere('Sport'), isFalse);
      expect(isInstructiveMatiere('Éducation physique'), isFalse);
      expect(isInstructiveMatiere('DS de maths'), isFalse);
      expect(isInstructiveMatiere('Maths - DS'), isFalse);
      expect(isInstructiveMatiere('Devoir surveillé'), isFalse);
      expect(isInstructiveMatiere('Contrôle continu'), isFalse);
    });
  });
}
