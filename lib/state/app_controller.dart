import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:http/http.dart' as http;

import '../models/briefing.dart';
import '../services/feed_service.dart';
import '../services/gemini_service.dart';
import '../services/local_store.dart';
import '../services/notification_service.dart';

final storeProvider = Provider<LocalStore>(
  (ref) => throw StateError('Store not initialized'),
);
final clientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});
final controllerProvider = ChangeNotifierProvider<AppController>((ref) {
  final store = ref.watch(storeProvider);
  final client = ref.watch(clientProvider);
  return AppController(
    store,
    FeedService(client),
    GeminiService(client, store.prefs),
    NotificationService(),
  );
});

class AppController extends ChangeNotifier {
  AppController(this.store, this.feeds, this.gemini, this.notifications) {
    sources = store.readSources();
    cache = store.readCache();
    articles = store.readArticles('ai');
    itArticles = store.readArticles('it');
    designArticles = store.readArticles('design');
    readIds = store.readIds();
    streak = store.readStreak();
    Future.microtask(initialize);
  }
  final LocalStore store;
  final FeedService feeds;
  final GeminiService gemini;
  final NotificationService notifications;
  bool initialized = false,
      hasKey = false,
      loading = false,
      summarizing = false;
  String? startupError, message;
  List<String> warnings = [];
  List<Article> articles = [];
  List<Article> itArticles = [];
  List<String> itWarnings = [];
  bool itLoading = false, itLoaded = false, itSummarizing = false;
  String? itMessage;
  List<Article> designArticles = [];
  List<String> designWarnings = [];
  bool designLoading = false, designLoaded = false, designSummarizing = false;
  String? designMessage;
  String? _activeSummary;
  Future<void> _summaryQueue = Future<void>.value();
  late List<FeedSource> sources;
  late Map<String, Briefing> cache;
  late Set<String> readIds;
  late Streak streak;
  bool get remindersEnabled => store.prefs.getBool('reminders') ?? false;
  TimeOfDay get reminderTime => TimeOfDay(
    hour: store.prefs.getInt('reminder_hour') ?? 8,
    minute: store.prefs.getInt('reminder_minute') ?? 0,
  );
  int pendingSummaries(List<Article> values) => values
      .where(
        (article) => article.canSummarize && !cache.containsKey(article.id),
      )
      .length;
  String summaryStatus(String section, List<Article> values) {
    final pending = pendingSummaries(values);
    final total = values.where((article) => article.canSummarize).length;
    if (_activeSummary != section) {
      return 'AI 요약 대기 중 · 미완료 $pending개';
    }
    final next = store.prefs.getInt('gemini_next_request') ?? 0;
    final seconds = ((next - DateTime.now().millisecondsSinceEpoch) / 1000)
        .ceil();
    if (seconds > 0) {
      return '무료 요청 간격으로 $seconds초 대기 중 · 미완료 $pending개';
    }
    return 'AI 요약 중 · ${total - pending}/$total개 저장됨';
  }

  Future<void> initialize() async {
    startupError = null;
    try {
      hasKey = (await store.readKey())?.isNotEmpty ?? false;
      if (hasKey) streak = await store.visit(DateTime.now());
      if (remindersEnabled) {
        try {
          await notifications.schedule(reminderTime);
        } catch (_) {
          message = '알림을 복원하지 못했어요. 설정에서 다시 켜 주세요.';
        }
      }
    } catch (_) {
      startupError = '기기의 보안 저장소를 열지 못했어요. 다시 시도해 주세요.';
    }
    initialized = true;
    notifyListeners();
    if (hasKey) await refresh();
  }

  Future<void> registerKey(String key) async {
    await gemini.validateKey(key.trim());
    await store.writeKey(key.trim());
    hasKey = true;
    streak = await store.visit(DateTime.now());
    notifyListeners();
    // Key checks do not consume generation quota; load and summarize immediately.
    await refresh();
  }

  Future<void> forgetKey() async {
    await store.deleteKey();
    hasKey = false;
    notifyListeners();
  }

  Future<void> visit() async {
    if (!hasKey) return;
    streak = await store.visit(DateTime.now());
    if (remindersEnabled) {
      try {
        await notifications.schedule(reminderTime);
      } catch (_) {
        /* Settings permits retry. */
      }
    }
    notifyListeners();
  }

  Future<void> refresh({bool force = false}) async {
    if (loading) return;
    if (!force &&
        articles.isNotEmpty &&
        store.isFeedFresh('ai', DateTime.now())) {
      unawaited(summarize());
      return;
    }
    loading = true;
    message = null;
    notifyListeners();
    try {
      final aiSources = sources
          .where((s) => s.category != 'IT·개발' && s.category != '디자인')
          .toList();
      final result = await feeds.load(aiSources);
      // Preserve an existing view when the device is temporarily offline.
      if (result.articles.isNotEmpty || aiSources.every((s) => !s.enabled)) {
        articles = result.articles;
        await store.saveArticles('ai', articles);
      }
      await store.markFeedFetched('ai', DateTime.now());
      warnings = result.warnings;
      loading = false;
      notifyListeners();
      unawaited(summarize());
    } catch (_) {
      message = '소식을 불러오지 못했어요. 아래로 당겨 다시 시도해 주세요.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> refreshNow() => refresh(force: true);

  Future<void> refreshIt({bool force = false}) async {
    if (itLoading) return;
    itLoaded = true;
    if (!force &&
        itArticles.isNotEmpty &&
        store.isFeedFresh('it', DateTime.now())) {
      notifyListeners();
      unawaited(summarizeIt());
      return;
    }
    itLoading = true;
    notifyListeners();
    try {
      final itSources = sources.where((s) => s.category == 'IT·개발').toList();
      final result = await feeds.load(itSources);
      if (result.articles.isNotEmpty || itSources.every((s) => !s.enabled)) {
        itArticles = result.articles;
        await store.saveArticles('it', itArticles);
      }
      await store.markFeedFetched('it', DateTime.now());
      itWarnings = result.warnings;
      itLoaded = true;
      itLoading = false;
      notifyListeners();
      unawaited(summarizeIt());
    } catch (_) {
      itWarnings = ['IT·개발 소식을 불러오지 못했어요. 다시 시도해 주세요.'];
      itLoaded = true;
    } finally {
      itLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshItNow() => refreshIt(force: true);

  Future<void> refreshDesign({bool force = false}) async {
    if (designLoading) return;
    designLoaded = true;
    if (!force &&
        designArticles.isNotEmpty &&
        store.isFeedFresh('design', DateTime.now())) {
      notifyListeners();
      unawaited(summarizeDesign());
      return;
    }
    designLoading = true;
    notifyListeners();
    try {
      final designSources = sources.where((s) => s.category == '디자인').toList();
      final result = await feeds.load(designSources);
      if (result.articles.isNotEmpty ||
          designSources.every((s) => !s.enabled)) {
        designArticles = result.articles;
        await store.saveArticles('design', designArticles);
      }
      await store.markFeedFetched('design', DateTime.now());
      designWarnings = result.warnings;
      designLoaded = true;
      designLoading = false;
      notifyListeners();
      unawaited(summarizeDesign());
    } catch (_) {
      designWarnings = ['디자인 소식을 불러오지 못했어요. 다시 시도해 주세요.'];
      designLoaded = true;
    } finally {
      designLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshDesignNow() => refreshDesign(force: true);

  Future<void> _queueSummary(Future<void> Function() operation) {
    final result = _summaryQueue.then((_) => operation());
    _summaryQueue = result.catchError((Object _) {});
    return result;
  }

  Future<void> summarize() => _summarizeArticles(it: false);
  Future<void> summarizeIt() => _summarizeArticles(it: true);
  Future<void> summarizeDesign() => _summarizeArticles(it: false, design: true);

  Future<void> _summarizeArticles({
    required bool it,
    bool design = false,
  }) async {
    final isSummarizing = design
        ? designSummarizing
        : it
        ? itSummarizing
        : summarizing;
    if (!hasKey || isSummarizing) return;
    final targetArticles = design
        ? designArticles
        : it
        ? itArticles
        : articles;
    final missing = targetArticles
        .where((a) => a.canSummarize && !cache.containsKey(a.id))
        .toList();
    if (missing.isEmpty) return;
    if (design) {
      designSummarizing = true;
      designMessage = null;
    } else if (it) {
      itSummarizing = true;
      itMessage = null;
    } else {
      summarizing = true;
      message = null;
    }
    notifyListeners();
    try {
      await _queueSummary(() async {
        final section = design
            ? 'design'
            : it
            ? 'it'
            : 'ai';
        _activeSummary = section;
        notifyListeners();
        final key = await store.readKey();
        if (key == null) {
          throw const BriefingException('설정에서 Gemini API 키를 다시 등록해 주세요.');
        }
        // The free-tier generation interval also applies across both tabs.
        final next = store.prefs.getInt('gemini_next_request') ?? 0;
        final delayMs = next - DateTime.now().millisecondsSinceEpoch;
        if (delayMs > 65000) {
          throw BriefingException(
            '${(delayMs / 1000).ceil()}초 후 다시 시도해 주세요. 무료 사용량을 보호하고 있어요.',
          );
        }
        if (delayMs > 0) {
          var remaining = delayMs;
          while (remaining > 0) {
            final step = remaining.clamp(1, 1000);
            await Future<void>.delayed(Duration(milliseconds: step));
            remaining -= step;
            notifyListeners();
          }
        }
        final pending = missing.where((a) => !cache.containsKey(a.id)).toList();
        if (pending.isEmpty) return;
        final batchSize = (store.prefs.getInt('gemini_batch_size') ?? 10).clamp(
          2,
          10,
        );
        final result = await gemini.summarize(
          key,
          pending.take(batchSize).toList(),
        );
        cache.addEntries(result.map((b) => MapEntry(b.id, b)));
        await store.saveCache(cache);
        final warning = gemini.lastSummaryWarning;
        final remaining = targetArticles
            .where(
              (article) =>
                  article.canSummarize && !cache.containsKey(article.id),
            )
            .length;
        final progress =
            warning ??
            (remaining > 0
                ? '$remaining개 기사 요약이 남아 있어요. 요청 간격이 지난 뒤 이어서 시도할 수 있어요.'
                : null);
        if (remaining == 0 && warning == null) {
          await store.prefs.setInt('gemini_batch_size', 10);
        }
        if (progress != null) {
          if (design) {
            designMessage = progress;
          } else if (it) {
            itMessage = progress;
          } else {
            message = progress;
          }
        }
      });
    } on BriefingException catch (e) {
      if (e.code == 'max_tokens') {
        final current = store.prefs.getInt('gemini_batch_size') ?? 10;
        final reduced = current > 5 ? 5 : 2;
        await store.prefs.setInt('gemini_batch_size', reduced);
      }
      if (design) {
        designMessage = e.code == 'max_tokens'
            ? '${e.message} 다음 시도는 더 작은 묶음으로 처리해요.'
            : e.message;
      } else if (it) {
        itMessage = e.code == 'max_tokens'
            ? '${e.message} 다음 시도는 더 작은 묶음으로 처리해요.'
            : e.message;
      } else {
        message = e.code == 'max_tokens'
            ? '${e.message} 다음 시도는 더 작은 묶음으로 처리해요.'
            : e.message;
      }
    } catch (_) {
      if (design) {
        designMessage = '요약을 저장하지 못했어요. 잠시 후 다시 시도해 주세요.';
      } else if (it) {
        itMessage = '요약을 저장하지 못했어요. 잠시 후 다시 시도해 주세요.';
      } else {
        message = '요약을 저장하지 못했어요. 잠시 후 다시 시도해 주세요.';
      }
    } finally {
      _activeSummary = null;
      if (design) {
        designSummarizing = false;
      } else if (it) {
        itSummarizing = false;
      } else {
        summarizing = false;
      }
      notifyListeners();
    }
  }

  Future<void> setSource(FeedSource source, bool value) async {
    final updated = sources
        .map((s) => s.id == source.id ? s.withEnabled(value) : s)
        .toList();
    await store.saveSources(updated);
    sources = updated;
    if (source.category == 'IT·개발') itLoaded = false;
    if (source.category == '디자인') designLoaded = false;
    articles = articles
        .where((a) => sources.any((s) => s.id == a.source.id && s.enabled))
        .toList();
    itArticles = itArticles
        .where((a) => sources.any((s) => s.id == a.source.id && s.enabled))
        .toList();
    designArticles = designArticles
        .where((a) => sources.any((s) => s.id == a.source.id && s.enabled))
        .toList();
    await Future.wait([
      store.saveArticles('ai', articles),
      store.saveArticles('it', itArticles),
      store.saveArticles('design', designArticles),
    ]);
    notifyListeners();
  }

  Future<void> addSource(String name, String url) async {
    if (!isSafeWebUrl(url)) {
      throw const BriefingException('공개된 https:// 피드 주소를 입력해 주세요.');
    }
    if (sources.any((s) => s.url == url)) {
      throw const BriefingException('이미 추가한 피드예요.');
    }
    if (sources.where((s) => s.custom).length >= 30) {
      throw const BriefingException('사용자 피드는 최대 30개까지 추가할 수 있어요.');
    }
    final updated = [
      ...sources,
      FeedSource(
        id: 'custom:${Uri.parse(url)}',
        name: name.trim().isEmpty ? Uri.parse(url).host : name.trim(),
        url: url,
        category: '내 피드',
        custom: true,
      ),
    ];
    await store.saveSources(updated);
    sources = updated;
    notifyListeners();
  }

  Future<void> removeSource(FeedSource source) async {
    if (!source.custom) return;
    final updated = sources.where((s) => s.id != source.id).toList();
    await store.saveSources(updated);
    sources = updated;
    articles = articles.where((a) => a.source.id != source.id).toList();
    itArticles = itArticles.where((a) => a.source.id != source.id).toList();
    designArticles = designArticles
        .where((a) => a.source.id != source.id)
        .toList();
    await Future.wait([
      store.saveArticles('ai', articles),
      store.saveArticles('it', itArticles),
      store.saveArticles('design', designArticles),
    ]);
    notifyListeners();
  }

  Future<void> markRead(String id) async {
    await store.markRead(id);
    readIds.add(id);
    notifyListeners();
  }

  Future<void> setReminder(bool enabled, TimeOfDay time) async {
    if (enabled) {
      if (!await notifications.schedule(time, requestPermissions: true)) {
        throw const BriefingException('알림 권한이 꺼져 있어요. 기기 설정에서 허용해 주세요.');
      }
    } else {
      await notifications.cancel();
    }
    await store.prefs.setBool('reminders', enabled);
    await store.prefs.setInt('reminder_hour', time.hour);
    await store.prefs.setInt('reminder_minute', time.minute);
    notifyListeners();
  }

  Future<void> clearCache() async {
    await store.saveCache({});
    cache = {};
    notifyListeners();
  }
}
