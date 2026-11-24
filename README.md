# PrépaHub
[![Release Build](https://github.com/noctyris/prepahub/actions/workflows/release-build.yaml/badge.svg)](https://github.com/noctyris/prepahub/actions/workflows/release-build.yaml)
> 🇫🇷 [Version française](README.fr.md)

A mobile and desktop app for checking your PRÉPA+ grades straight from your phone, no browser needed.

Built with [Flutter](https://flutter.dev) (Dart), with Material You (Material 3) support — dynamic color included.

## Features

* Log in to a PRÉPA+ account from within the app
* Grades displayed week by week (subject, grade, teacher, rank, average, standard deviation)
* Persistent session: the app logs back in automatically on launch (credentials stored locally on the device)
* Material You: adapts to your system palette on Android 12+
* Available on Android and desktop (Linux)

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
```

### Android (APK)

```shell
flutter build apk --release
```

The APK is generated in `build/app/outputs/flutter-apk/`.

## Security

Credentials are stored in the app's private data directory (SharedPreferences) and are never sent anywhere other than the PRÉPA+ server.

## License

To be determined.

## About

App to gather grades, written in Flutter.
