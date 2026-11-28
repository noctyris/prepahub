<div align="center">
  <img src="assets/icon.png" width="112" alt="Icône de PrépaHub">
  <h1>PrépaHub</h1>
  <p><strong>Tes notes, ton emploi du temps et tes devoirs PRÉPA+ dans une application Flutter claire et rapide.</strong></p>
  <p>
    <a href="https://github.com/noctyris/prepahub/actions/workflows/release-build.yaml">
      <img src="https://github.com/noctyris/prepahub/actions/workflows/release-build.yaml/badge.svg" alt="Release Build">
    </a>
    <a href="https://github.com/noctyris/prepahub/releases/latest">
      <img src="https://img.shields.io/github/v/release/noctyris/prepahub?display_name=tag&sort=semver" alt="Dernière version">
    </a>
    <img src="https://img.shields.io/badge/Android%20%7C%20Linux%20%7C%20macOS-3F51B5?logo=flutter&logoColor=white" alt="Android, Linux et macOS">
    <a href="LICENSE">
      <img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="Licence MIT">
    </a>
  </p>
  <p><a href="README.md">🇬🇧 English</a> · <strong>Français</strong></p>
</div>

---

PrépaHub se connecte au portail PRÉPA+ de ton lycée et transforme son interface web en un tableau de bord rapide et lisible. Notes, emploi du temps, khôlles et devoirs sont réunis au même endroit, avec une session persistante, un accès hors ligne et quelques réglages pour personnaliser l'application.

## ✨ En un coup d'œil

| 📊 Notes | 🗓️ Au quotidien | 🔐 Tranquillité |
| :--- | :--- | :--- |
| Notes par semaine, moyenne pondérée, coefficients, simulateur, répartition et évolution. | Accueil, emploi du temps, khôlles, devoirs et rappels. | Session sécurisée, cache hors ligne, verrouillage biométrique et Material You. |

## Fonctionnalités

### Notes

- Connexion au portail PRÉPA+ de ton lycée, avec une URL personnalisable.
- Notes affichées semaine par semaine : matière, note, professeur, rang, moyenne de classe et écart type.
- Regroupement des TD, TP et cours sous une même matière.
- Moyenne pondérée avec coefficients par matière, simulateur de note cible et évolution par matière.
- Histogramme des notes avec, en option, une courbe normale basée sur les moyennes et écarts types de classe, et la tranche contenant ta moyenne mise en évidence.
- Tri des notes par temps, note, rang ou matière, en ordre croissant ou décroissant.
- Ajout local d'une note en attendant sa publication sur le portail.

### Organisation

- Écran **Aujourd'hui** avec les cours, devoirs, khôlles et dernières notes du jour.
- Emploi du temps avec couleurs par matière, gestion des khôlles et export calendrier (`.ics`).
- Liste des devoirs avec échéances, sous-tâches et rappels du soir.
- Recherche et filtres pour les notes, les devoirs et les khôlles.

### Confort

- Notes mises en cache sur l'appareil et consultables hors ligne.
- Actualisation automatique pendant que l'application est ouverte, avec notification optionnelle des nouvelles notes.
- Material You sur Android 12+, thèmes clair/sombre et option noir AMOLED.
- Navigation, disposition des notes, tri et page d'ouverture personnalisables.
- Verrouillage biométrique ou par code de l'appareil, en option.
- Disponible sur **Android**, **Linux** et **macOS**.

## 📥 Installation

Télécharge le dernier APK Android, l'archive Linux ou le build macOS depuis la
page [Releases](https://github.com/noctyris/prepahub/releases/latest).

## 🛠️ Développement

### Prérequis

- [Flutter](https://docs.flutter.dev/get-started/install) sur le canal stable
- Le SDK Android pour les builds Android
- Linux : `clang`, `cmake`, `ninja-build`, `pkg-config`, `libgtk-3-dev`, `liblzma-dev` et `libsecret-1-dev`
- macOS : Xcode et les outils en ligne de commande

### Lancer le projet

```bash
git clone https://github.com/noctyris/prepahub.git
cd prepahub
flutter pub get
flutter run
```

Utilise `flutter devices` pour lister les cibles disponibles, ou lance
`flutter run -d linux` / `flutter run -d macos` pour ouvrir un build desktop.

### Vérifications

```bash
flutter analyze
flutter test
```

### Builds de release

```bash
flutter build apk --release
flutter build linux --release
flutter build macos --release
```

Pousser un tag `v*` déclenche le workflow `Release Build`. Le workflow utilise
le tag comme version de l'application et le numéro du run comme build number,
ainsi les artefacts restent alignés sur le tag. Garde le champ `version` de
`pubspec.yaml` à jour pour les builds locaux.

## 🔒 Confidentialité

Les identifiants sont stockés dans le stockage sécurisé de la plateforme :
Keystore Android, trousseau Apple sur les plateformes Apple et `libsecret` sous
Linux. Si ce stockage est indisponible, l'application se replie sur ses
`SharedPreferences` privées pour ne pas bloquer la connexion.

Les identifiants ne sont envoyés qu'au portail configuré. La seule autre
requête réseau est l'API publique des releases GitHub, utilisée pour vérifier
les mises à jour. Les notes et les données locales restent sur l'appareil et
restent consultables hors ligne. Le verrouillage optionnel utilise la
biométrie ou l'authentification système de l'appareil.

## 📄 Licence

PrépaHub est distribué sous [licence MIT](LICENSE).

---

<p align="center"><sub>Fait avec Flutter · Non affilié à PRÉPA+.</sub></p>
