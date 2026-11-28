<div align="center">
  <img src="assets/icon.png" width="112" alt="PrépaHub icon">
  <h1>PrépaHub</h1>
  <p><strong>Your PRÉPA+ grades, timetable and homework in one focused Flutter app.</strong></p>
  <p>
    <a href="https://github.com/noctyris/prepahub/actions/workflows/release-build.yaml">
      <img src="https://github.com/noctyris/prepahub/actions/workflows/release-build.yaml/badge.svg" alt="Release Build">
    </a>
    <a href="https://github.com/noctyris/prepahub/releases/latest">
      <img src="https://img.shields.io/github/v/release/noctyris/prepahub?display_name=tag&sort=semver" alt="Latest release">
    </a>
    <img src="https://img.shields.io/badge/Android%20%7C%20Linux%20%7C%20macOS-3F51B5?logo=flutter&logoColor=white" alt="Android, Linux and macOS">
    <a href="LICENSE">
      <img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License">
    </a>
  </p>
  <p><strong>English</strong> · <a href="README.fr.md">🇫🇷 Français</a></p>
</div>

---

PrépaHub connects to your school's PRÉPA+ portal and turns its web interface into a fast, native-feeling dashboard. Grades, timetable, khôlles and homework live in one place, with a persistent session, offline access and sensible customization.

## ✨ At a glance

| 📊 Grades | 🗓️ Day to day | 🔐 Peace of mind |
| :--- | :--- | :--- |
| Weekly grades, weighted average, coefficients, simulator, distribution and trends. | Today dashboard, timetable, khôlles, homework and reminders. | Secure session, offline cache, biometric lock and Material You. |

## Features

### Grades

- Log in to your school's PRÉPA+ portal, including custom portal URLs.
- Browse grades week by week: subject, grade, teacher, rank, class average and standard deviation.
- Group TD, TP and lecture variants under the same subject.
- Weighted average with per-subject coefficients, a target-grade simulator and per-subject trends.
- Grade histogram with an optional normal curve based on class averages and standard deviations, highlighting the bucket containing your average.
- Sort grades by time, grade, rank or subject, in ascending or descending order.
- Add a grade locally until it is published on the portal.

### Organisation

- **Today** dashboard with the day's classes, homework, khôlles and latest grades.
- Timetable with subject colours, khôlle management and calendar (`.ics`) export.
- Homework list with due dates, subtasks and evening reminders.
- Search and filters for grades, homework and khôlles.

### Comfort

- Grades cached on the device and readable offline.
- Automatic refresh while the app is open, plus an optional notification when new grades appear.
- Material You dynamic colour on Android 12+, light/dark themes and an AMOLED black option.
- Customizable navigation, grade layout, sorting and default opening page.
- Optional biometric or device-credential app lock.
- Available on **Android**, **Linux** and **macOS**.

## 📥 Installation

Download the latest Android APK, Linux archive or macOS build from the
[Releases](https://github.com/noctyris/prepahub/releases/latest) page.

## 🛠️ Development

### Requirements

- [Flutter](https://docs.flutter.dev/get-started/install) on the stable channel
- Android SDK for Android builds
- Linux: `clang`, `cmake`, `ninja-build`, `pkg-config`, `libgtk-3-dev`, `liblzma-dev` and `libsecret-1-dev`
- macOS: Xcode and the command line tools

### Run locally

```bash
git clone https://github.com/noctyris/prepahub.git
cd prepahub
flutter pub get
flutter run
```

Use `flutter devices` to list available targets, or run `flutter run -d linux` /
`flutter run -d macos` to launch a specific desktop build.

### Checks

```bash
flutter analyze
flutter test
```

### Release builds

```bash
flutter build apk --release
flutter build linux --release
flutter build macos --release
```

Pushing a `v*` tag triggers the `Release Build` workflow. The workflow uses the
tag as the app version and the workflow run number as the build number, so
release artifacts stay aligned with the tag. Keep `version` in `pubspec.yaml`
in sync for local builds.

## 🔒 Privacy

Credentials are stored in the platform's secure storage: Android Keystore,
Apple Keychain on Apple platforms, and `libsecret` on Linux. If secure storage
is unavailable, the app falls back to its private `SharedPreferences` so login
keeps working.

Credentials are only sent to the portal you configure. The only other network
request is GitHub's public release API, used to check for updates. Grades and
local data stay on the device and remain available offline. The optional app
lock uses the device's biometric or system authentication.

## 📄 License

PrépaHub is released under the [MIT License](LICENSE).

---

<p align="center"><sub>Made with Flutter · Not affiliated with PRÉPA+.</sub></p>
