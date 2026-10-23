import 'package:ai_briefing/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as data;
import 'package:timezone/timezone.dart' as tz;

void main() {
  setUp(() {
    data.initializeTimeZones();
  });
  test('Morning reminders schedule today before 8 and tomorrow after 8', () {
    tz.setLocalLocation(tz.getLocation('Asia/Seoul'));
    final before = NotificationService.nextOccurrence(
      const TimeOfDay(hour: 8, minute: 0),
      tz.TZDateTime(tz.local, 2026, 10, 23, 7),
    );
    final after = NotificationService.nextOccurrence(
      const TimeOfDay(hour: 8, minute: 0),
      tz.TZDateTime(tz.local, 2026, 10, 23, 9),
    );
    expect(before.day, 23);
    expect(after.day, 24);
    expect(after.hour, 8);
  });
  test('Scheduling follows civil time across a daylight-saving transition', () {
    tz.setLocalLocation(tz.getLocation('America/New_York'));
    final next = NotificationService.nextOccurrence(
      const TimeOfDay(hour: 8, minute: 0),
      tz.TZDateTime(tz.local, 2026, 10, 31, 9),
    );
    expect(next.day, 1);
    expect(next.month, 11);
    expect(next.hour, 8);
    expect(next.timeZoneOffset, const Duration(hours: -5));
  });
}
