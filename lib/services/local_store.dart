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
      if (prefs.getInt('briefing_content_version') != 1) return {};
      final raw = jsonDecode(prefs.getString('briefings') ?? '[]') as List;
      final cache = {
        for (final j in raw)
          (j['id'] as String): Briefing.fromJson(
            Map<String, dynamic>.from(j as Map),
          ),
      };
      if (prefs.getInt('hn_summary_provenance') != 1) {
        cache.removeWhere(
          (id, _) => id.startsWith('https://news.ycombinator.com/item?id='),
        );
      }
      return cache;
    } catch (_) {
      return {};
    }
  }

  Future<void> saveCache(Map<String, Briefing> cache) async {
    await prefs.setString(
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
    await prefs.setInt('hn_summary_provenance', 1);
    await prefs.setInt('briefing_content_version', 1);
  }

  List<FeedSource> readSources() {
    try {
      final raw = prefs.getString('sources');
      if (raw == null) return List.of(defaultFeedSources);
      final saved = (jsonDecode(raw) as List)
          .map((j) => FeedSource.fromJson(Map<String, dynamic>.from(j as Map)))
          .where((s) => s.custom || retiredBlogFeeds[s.id] != s.url)
          .toList();
      // Keep user toggles/custom feeds and append newly shipped built-ins.
      for (var i = 0; i < saved.length; i++) {
        final source = saved[i];
        final updated = defaultFeedSources
            .where((s) => s.id == source.id)
            .firstOrNull;
        if (!source.custom &&
            updated != null &&
            (source.url == updated.url ||
                source.url == updated.fallbackUrl ||
                (source.id == 'papers' &&
                    source.url ==
                        'https://rsshub.app/huggingface/daily-papers'))) {
          saved[i] = updated.withEnabled(source.enabled);
        }
      }
      final ids = saved.map((s) => s.id).toSet();
      return [
        ...saved,
        ...defaultFeedSources.where((s) => !ids.contains(s.id)),
      ];
    } catch (_) {
      return List.of(defaultFeedSources);
    }
  }

  Future<void> saveSources(List<FeedSource> sources) => prefs.setString(
    'sources',
    jsonEncode(sources.map((s) => s.toJson()).toList()),
  );

  List<Article> readArticles(String section) {
    try {
      final raw = jsonDecode(prefs.getString('articles_$section') ?? '[]');
      return (raw as List).take(10).map((value) {
        final item = Map<String, dynamic>.from(value as Map);
        final source = FeedSource.fromJson(
          Map<String, dynamic>.from(item['source'] as Map),
        );
        final id = item['id'] as String;
        final link = item['link'] as String;
        final idUri = Uri.parse(id), linkUri = Uri.parse(link);
        if (idUri.scheme != 'https' || linkUri.scheme != 'https') {
          throw const FormatException('Unsafe cached article');
        }
        return Article(
          id: id,
          title: item['title'] as String,
          link: link,
          excerpt: item['excerpt'] as String,
          source: source,
          published: DateTime.tryParse(item['published'] as String? ?? ''),
          canSummarize: item['canSummarize'] as bool? ?? false,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveArticles(String section, List<Article> articles) async {
    await prefs.setString(
      'articles_$section',
      jsonEncode([
        for (final article in articles.take(10))
          {
            'id': article.id,
            'title': article.title,
            'link': article.link,
            'excerpt': article.excerpt,
            'source': article.source.toJson(),
            'published': article.published?.toUtc().toIso8601String(),
            'canSummarize': article.canSummarize,
          },
      ]),
    );
  }

  bool isFeedFresh(String section, DateTime now) {
    final fetched = prefs.getInt('articles_${section}_fetched_at');
    return fetched != null &&
        now.millisecondsSinceEpoch - fetched <
            const Duration(minutes: 15).inMilliseconds;
  }

  Future<void> markFeedFetched(String section, DateTime now) => prefs.setInt(
    'articles_${section}_fetched_at',
    now.millisecondsSinceEpoch,
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
