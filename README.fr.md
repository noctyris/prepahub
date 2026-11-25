# PrépaHub
[![Release Build](https://github.com/noctyris/prepahub/actions/workflows/release-build.yaml/badge.svg)](https://github.com/noctyris/prepahub/actions/workflows/release-build.yaml)
> 🇬🇧 [English version](README.md)

Une appli mobile et desktop pour consulter tes notes PRÉPA+ directement depuis ton téléphone, sans passer par un navigateur.

Réalisée avec [Flutter](https://flutter.dev) (Dart), avec support Material You (Material 3) — couleurs dynamiques comprises.

## Fonctionnalités

* Connexion au portail PRÉPA+ de ton lycée (URL personnalisable)
* Notes affichées semaine par semaine (matière, note, professeur, classement, moyenne, écart-type)
* Session persistante : l'application se reconnecte automatiquement au lancement (identifiants stockés localement sur l'appareil)
* Notes mises en cache sur l'appareil et consultables hors ligne
* Ajout local d'une note en attendant sa publication sur le portail
* Notification optionnelle lorsqu'une actualisation détecte de nouvelles notes
* Material You : s'adapte à la palette de ton système sur Android 12+
* Disponible sur Android et desktop (Linux, Windows et macOS)

## Feuille de route

* [ ] Intégration Pronote
* [ ] Widgets sur l'écran d'accueil
* [x] Notification des nouvelles notes lors d'une actualisation
* [ ] Gestion des erreurs (identifiants invalides, pas de réseau, spinners…)
* [ ] Builds pour plusieurs architectures de téléphone
* [x] Cache hors-ligne des notes
* [x] Emploi du temps des khôlles hors-ligne
* [x] Conserver les identifiants entre les lancements
* [x] Couleurs dynamiques Material You

## Compilation

### Prérequis

* [Flutter](https://docs.flutter.dev/get-started/install) (canal stable)
* Pour Android : le SDK Android (Gradle télécharge ce qu'il faut)

```shell
flutter doctor
```

### Desktop

```shell
flutter run -d linux
flutter run -d windows
flutter run -d macos
```

Les versions de publication sont construites par le workflow `Release Build`
pour Linux, Windows et macOS.

### Android (APK)

```shell
flutter build apk --release
```

L'APK est généré dans `build/app/outputs/flutter-apk/`.

## Sécurité

Les identifiants sont stockés dans le répertoire privé de l'application (SharedPreferences) et ne sont jamais envoyés ailleurs qu'au serveur du portail que tu as configuré.

## Licence

À définir.

## À propos

Application de consultation de notes, écrite en Flutter.

