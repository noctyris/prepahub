import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'api/parse.dart';
import 'devoirs.dart';
import 'edt.dart';

class DevoirNotificationTap {
  final String? matiere;

  const DevoirNotificationTap({this.matiere});
}

/// Renseigné quand l'utilisateur touche un rappel de devoirs.
final ValueNotifier<DevoirNotificationTap?> devoirNotificationTap =
    ValueNotifier<DevoirNotificationTap?>(null);

class DevoirNotifications {
  DevoirNotifications._();

  static final DevoirNotifications instance = DevoirNotifications._();

  static const _eveningBaseId = 41000;
  static const _courseBaseId = 42000;
  static const _maxCourseNotifications = 40;
  static const _eveningDays = 14;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  Future<void>? _initFuture;
  Future<void> _queue = Future<void>.value();

  bool get isSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

  Future<void> initialize() => _initFuture ??= _initialize();

  Future<void> _initialize() async {
    if (!isSupported) return;
    try {
      tzdata.initializeTimeZones();
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      try {
        tz.setLocalLocation(tz.getLocation('Etc/UTC'));
      } catch (_) {}
    }

    try {
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_devoirs'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
        macOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      );
      await _plugin.initialize(
        settings: settings,
        onDidReceiveNotificationResponse: _onNotificationResponse,
      );
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch != null && launch.didNotificationLaunchApp) {
        _emitTap(launch.notificationResponse?.payload);
      }
    } catch (_) {}
  }

  void _onNotificationResponse(NotificationResponse response) {
    _emitTap(response.payload);
  }

  void _emitTap(String? payload) {
    if (payload == null || !payload.startsWith('devoir:')) return;
    if (payload.startsWith('devoir:course:')) {
      String matiere;
      try {
        matiere = Uri.decodeComponent(
          payload.substring('devoir:course:'.length),
        );
      } catch (_) {
        matiere = '';
      }
      devoirNotificationTap.value = DevoirNotificationTap(
        matiere: matiere.isEmpty ? null : matiere,
      );
      return;
    }
    devoirNotificationTap.value = const DevoirNotificationTap();
  }

  Future<bool> areNotificationsAllowed() async {
    if (!isSupported) return true;
    await initialize();
    try {
      if (Platform.isAndroid) {
        final android = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        return await android?.areNotificationsEnabled() ?? false;
      }
      if (Platform.isIOS) {
        final ios = _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >();
        final options = await ios?.checkPermissions();
        return options?.isEnabled ?? false;
      }
      if (Platform.isMacOS) {
        final macos = _plugin
            .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin
            >();
        final options = await macos?.checkPermissions();
        return options?.isEnabled ?? false;
      }
    } catch (_) {}
    return false;
  }

  Future<bool> requestPermission() async {
    if (!isSupported) return false;
    await initialize();
    try {
      if (Platform.isAndroid) {
        final android = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        final granted = await android?.requestNotificationsPermission();
        return granted ?? await areNotificationsAllowed();
      }
      if (Platform.isIOS) {
        final ios = _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >();
        return await ios?.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            ) ??
            false;
      }
      if (Platform.isMacOS) {
        final macos = _plugin
            .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin
            >();
        return await macos?.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            ) ??
            false;
      }
    } catch (_) {}
    return false;
  }

  /// Resynchronise les rappels. Les appels sont sérialisés pour éviter que
  /// deux modifications rapides ne se marchent dessus.
  Future<void> sync() {
    final completer = Completer<void>();
    _queue = _queue.then((_) async {
      try {
        await _syncNow();
      } catch (_) {
      } finally {
        completer.complete();
      }
    });
    return completer.future;
  }

  Future<void> _syncNow() async {
    await initialize();
    if (!isSupported) return;
    await _cancelScheduled();
    if (!await areNotificationsAllowed()) return;

    final devoirs = await DevoirsStore.load();
    final settings = await DevoirSettingsStore.load();
    if (!settings.eveningEnabled && !settings.endOfClassEnabled) return;

    final now = tz.TZDateTime.now(tz.local);
    if (settings.eveningEnabled) {
      await _scheduleEvening(devoirs, settings, now);
    }
    if (settings.endOfClassEnabled) {
      await _scheduleCourseEnds(now);
    }
  }

  Future<void> _cancelScheduled() async {
    try {
      final pending = await _plugin.pendingNotificationRequests();
      for (final notification in pending) {
        if (notification.id >= _eveningBaseId &&
            notification.id < _courseBaseId + 100) {
          await _plugin.cancel(id: notification.id);
        }
      }
    } catch (_) {}
  }

  Future<void> _scheduleEvening(
    List<Devoir> devoirs,
    DevoirSettings settings,
    tz.TZDateTime now,
  ) async {
    for (var offset = 0; offset < _eveningDays; offset++) {
      final day = DateTime(now.year, now.month, now.day + offset);
      final tomorrow = DateTime(day.year, day.month, day.day + 1);
      final due =
          [
            for (final devoir in devoirs)
              if (!devoir.fait && _sameDay(devoir.echeance, tomorrow)) devoir,
          ]..sort(
            (a, b) =>
                a.matiere.toLowerCase().compareTo(b.matiere.toLowerCase()),
          );
      if (due.isEmpty) continue;

      final scheduled = tz.TZDateTime(
        tz.local,
        day.year,
        day.month,
        day.day,
        settings.eveningHour,
        settings.eveningMinute,
      );
      if (!scheduled.isAfter(now)) continue;

      await _plugin.zonedSchedule(
        id: _eveningBaseId + offset,
        title: 'Devoirs pour demain',
        body: _eveningBody(due),
        scheduledDate: scheduled,
        notificationDetails: _notificationDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: 'devoir:evening',
      );
    }
  }

  String _eveningBody(List<Devoir> devoirs) {
    final parts = [
      for (final devoir in devoirs.take(3))
        devoir.matiere.isEmpty
            ? devoir.titre
            : '${devoir.matiere} : ${devoir.titre}',
    ];
    final remaining = devoirs.length - 3;
    if (remaining > 0) {
      parts.add('+$remaining autre${remaining > 1 ? 's' : ''}');
    }
    final body = parts.join(' · ');
    return body.length <= 180 ? body : '${body.substring(0, 177)}…';
  }

  Future<void> _scheduleCourseEnds(tz.TZDateTime now) async {
    var semestre = defaultEdtSemester(DateTime.now());
    try {
      final prefs = await SharedPreferences.getInstance();
      semestre =
          prefs.getInt(edtSemesterPrefKey) ??
          defaultEdtSemester(DateTime.now());
    } catch (_) {}

    List<Cours> cours;
    try {
      cours = await EdtStore.load();
    } catch (_) {
      return;
    }
    if (cours.isEmpty) return;

    var index = 0;
    final seen = <String>{};
    final today = DateTime(now.year, now.month, now.day);
    for (var offset = 0; offset < 7; offset++) {
      final date = DateTime(today.year, today.month, today.day + offset);
      final monday = DateTime(
        date.year,
        date.month,
        date.day - (date.weekday - 1),
      );
      final week = monday.isoWeekNumber;
      final dayCours =
          [
            for (final c in cours)
              if (c.semestre == semestre &&
                  c.jour == date.weekday &&
                  c.appliesToWeek(week) &&
                  isInstructiveMatiere(c.matiere))
                c,
          ]..sort((a, b) {
            final aEnd = _minutes(a.heureFin) ?? 0;
            final bEnd = _minutes(b.heureFin) ?? 0;
            return aEnd.compareTo(bEnd);
          });

      for (final c in dayCours) {
        final minutes = _minutes(c.heureFin);
        if (minutes == null) continue;
        final scheduled = tz.TZDateTime(
          tz.local,
          date.year,
          date.month,
          date.day,
          minutes ~/ 60,
          minutes % 60,
        );
        if (!scheduled.isAfter(now)) continue;
        final key = '${date.toIso8601String()}|${c.matiere}|${c.heureFin}';
        if (!seen.add(key)) continue;

        await _plugin.zonedSchedule(
          id: _courseBaseId + index,
          title: 'Fin de cours',
          body: '${c.matiere} vient de finir. Un devoir à ajouter ?',
          scheduledDate: scheduled,
          notificationDetails: _notificationDetails,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: 'devoir:course:${Uri.encodeComponent(c.matiere)}',
        );
        index++;
        if (index >= _maxCourseNotifications) return;
      }
    }
  }

  int? _minutes(String raw) {
    final parts = raw.replaceAll('h', ':').split(':');
    final hour = int.tryParse(parts.first);
    if (hour == null || hour < 0 || hour > 23) return null;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    if (minute < 0 || minute > 59) return null;
    return hour * 60 + minute;
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static const NotificationDetails _notificationDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'devoirs_rappels',
      'Devoirs et fins de cours',
      icon: 'ic_stat_devoirs',
      channelDescription: 'Rappels des devoirs du lendemain et fins de cours',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    ),
    iOS: DarwinNotificationDetails(),
    macOS: DarwinNotificationDetails(),
  );
}
