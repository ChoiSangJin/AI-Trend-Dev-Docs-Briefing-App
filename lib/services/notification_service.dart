import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
    : plugin = plugin ?? FlutterLocalNotificationsPlugin();
  final FlutterLocalNotificationsPlugin plugin;
  bool _initialized = false;
  static const messages = [
    '🔥 연속 기록이 깨지기 전에 오늘 나온 해외 AI 개발 문서를 3줄로 확인하세요!',
    '🚀 밤사이 OpenAI와 Anthropic에 어떤 업데이트가 있었을까요? 지금 확인해 보세요.',
    '💡 하루 3분! 남들보다 빠르게 글로벌 AI 트렌드를 한국어로 읽어보세요.',
  ];
  Future<void> initialize() async {
    tzdata.initializeTimeZones();
    final zone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(zone.identifier));
    if (!_initialized) {
      await plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_notification'),
        ),
      );
      _initialized = true;
    }
  }

  static tz.TZDateTime nextOccurrence(TimeOfDay time, tz.TZDateTime now) {
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );
    if (!scheduled.isAfter(now)) {
      scheduled = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day + 1,
        time.hour,
        time.minute,
      );
    }
    return scheduled;
  }

  Future<bool> schedule(
    TimeOfDay time, {
    bool requestPermissions = false,
  }) async {
    await initialize();
    final android = plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (requestPermissions) {
      if (await android?.requestNotificationsPermission() == false) {
        return false;
      }
      // Exact alarms are optional: fall back to an inexact daily reminder when denied.
      await android?.requestExactAlarmsPermission();
    }
    if (await android?.areNotificationsEnabled() == false) return false;
    final exact = await android?.canScheduleExactNotifications() ?? false;
    await plugin.zonedSchedule(
      id: 1,
      title: '오늘의 AI 브리핑',
      body: messages[Random().nextInt(messages.length)],
      scheduledDate: nextOccurrence(time, tz.TZDateTime.now(tz.local)),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'daily_briefing',
          '매일 AI 브리핑',
          channelDescription: '설정한 시간에 하루 한 번 보내는 학습 알림',
          importance: Importance.defaultImportance,
        ),
      ),
      androidScheduleMode: exact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
    return true;
  }

  Future<void> cancel() async {
    await initialize();
    await plugin.cancel(id: 1);
  }
}
