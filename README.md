# PrépaHub
[![Release Build](https://github.com/noctyris/prepahub/actions/workflows/release-build.yaml/badge.svg)](https://github.com/noctyris/prepahub/actions/workflows/release-build.yaml)
> 🇫🇷 [Version française](README.fr.md)

A mobile and desktop app for checking your PRÉPA+ grades straight from your phone, no browser needed.

Built with [Flutter](https://flutter.dev) (Dart), with Material You (Material 3) support — dynamic color included.

## Features

* Log in to your school's PRÉPA+ portal (custom portal URL supported)
* Today dashboard: classes, homework, khôlles and latest grades at a glance
* Grades displayed week by week (subject, grade, teacher, rank, average, standard deviation)
* TD, TP and lecture variants grouped under the same subject
* Weighted average with per-subject coefficients, grade simulator and charts split by subject (using timetable colours)
* Search and filters for grades, homework and khôlles (upcoming, past or all)
* Persistent session: the app logs back in automatically on launch (credentials stored in the platform keychain)
* Optional biometric app lock
* Grades cached on the device and readable offline
* Add a grade locally until it is published on the portal
* Optional notification when a refresh finds new grades, plus background refresh while the app is running
* Khôlle reminders the day before and calendar (.ics) export
* Material You: adapts to your system palette on Android 12+
* Available on Android, Linux, Windows and macOS

## Building

### Prerequisites

* [Flutter](https://docs.flutter.dev/get-started/install) (stable channel)
* For Android: Android SDK (Gradle fetches what it needs)

```shell
flutter doctor
```

### Desktop

```shell
flutter run -d linux
flutter run -d windows
flutter run -d macos
```

Release builds for Linux, Windows and macOS are produced by the
`Release Build` workflow.

### Android (APK)

```shell
flutter build apk --release
```

The APK is generated in `build/app/outputs/flutter-apk/`.

## Security

Credentials are stored in the platform's secure storage (Android Keystore, iOS/macOS Keychain, Windows Credential Locker, libsecret on Linux). If the secure store is unavailable, the app falls back to its private SharedPreferences so login keeps working. Credentials are never sent anywhere other than the portal server you configured. The optional app lock uses the device's biometric or system authentication.

## License

To be determined.

## About

App to gather grades, written in Flutter.
