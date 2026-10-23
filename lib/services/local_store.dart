import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/briefing.dart';
import '../constants/feed_sources.dart';

class LocalStore {
  LocalStore(this.prefs, {FlutterSecureStorage? secure})
    : secure =
          secure ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(resetOnError: false),
          );
  final SharedPreferences prefs;
  final FlutterSecureStorage secure;
  Future<String?> readKey() => secure.read(key: 'gemini_key');
  Future<void> writeKey(String key) =>
      secure.write(key: 'gemini_key', value: key);
  Future<void> deleteKey() => secure.delete(key: 'gemini_key');
  Map<String, Briefing> readCache() {
    try {
      final raw = jsonDecode(prefs.getString('briefings') ?? '[]') as List;
      return {
        for (final j in raw)
          (j['id'] as String): Briefing.fromJson(
            Map<String, dynamic>.from(j as Map),
          ),
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> saveCache(Map<String, Briefing> cache) => prefs.setString(
    'briefings',
    jsonEncode(
      cache.values
          .toList()
          .reversed
          .take(500)
          .toList()
          .reversed
          .map((b) => b.toJson())
          .toList(),
    ),
  );
  List<FeedSource> readSources() {
    try {
      final raw = prefs.getString('sources');
      if (raw == null) return List.of(defaultFeedSources);
      return (jsonDecode(raw) as List)
          .map((j) => FeedSource.fromJson(Map<String, dynamic>.from(j as Map)))
          .toList();
    } catch (_) {
      return List.of(defaultFeedSources);
    }
  }

  Future<void> saveSources(List<FeedSource> sources) => prefs.setString(
    'sources',
    jsonEncode(sources.map((s) => s.toJson()).toList()),
  );
  Streak readStreak() =>
      Streak(prefs.getInt('streak') ?? 0, prefs.getString('last_day'));
  Future<Streak> visit(DateTime now) async {
    final value = readStreak().visit(now);
    await prefs.setInt('streak', value.days);
    await prefs.setString('last_day', value.lastDay!);
    return value;
  }

  Set<String> readIds() => (prefs.getStringList('read_ids') ?? []).toSet();
  Future<void> markRead(String id) async {
    final ids = readIds()
      ..remove(id)
      ..add(id);
    await prefs.setStringList(
      'read_ids',
      ids.toList().reversed.take(2000).toList().reversed.toList(),
    );
  }
}
