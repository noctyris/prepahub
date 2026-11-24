import 'package:flutter_test/flutter_test.dart';
import 'package:prepahub/api/client.dart';

void main() {
  group('normalizePortal', () {
    test('ajoute https et retire le slash final', () {
      expect(
        normalizePortal(' lycee.example.fr/ '),
        'https://lycee.example.fr',
      );
    });

    test('conserve http, le port et un sous-chemin', () {
      expect(
        normalizePortal('http://10.0.0.1:8080/prepa/'),
        'http://10.0.0.1:8080/prepa',
      );
    });

    test('accepte une URL de connexion ou de notes collée', () {
      expect(
        normalizePortal('lycee.example.fr/account/login/'),
        'https://lycee.example.fr',
      );
      expect(
        normalizePortal('https://lycee.example.fr/colles/mes_notes'),
        'https://lycee.example.fr',
      );
    });

    test('refuse les adresses invalides', () {
      expect(() => normalizePortal(''), throwsA(isA<NetworkException>()));
      expect(
        () => normalizePortal('ftp://lycee.example.fr'),
        throwsA(isA<NetworkException>()),
      );
      expect(
        () => normalizePortal('https://'),
        throwsA(isA<NetworkException>()),
      );
    });
  });

  test('Creds utilise le portail par défaut', () {
    final creds = Creds(username: 'eleve', password: 'secret');
    expect(creds.portal, defaultPortal);
  });
}
