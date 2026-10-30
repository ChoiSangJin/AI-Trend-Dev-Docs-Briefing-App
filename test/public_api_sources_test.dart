import 'dart:convert';

import 'package:ai_briefing/constants/feed_sources.dart';
import 'package:ai_briefing/models/briefing.dart';
import 'package:ai_briefing/services/feed_service.dart';
import 'package:ai_briefing/services/local_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

FeedSource source(String id) =>
    defaultFeedSources.firstWhere((s) => s.id == id);
http.Response jsonResponse(Object? value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Map<String, dynamic> release({
  String url = 'https://github.com/org/repo/releases/tag/v1',
  bool draft = false,
  bool prerelease = false,
}) => {
  'name': 'Release',
  'html_url': url,
  'body': 'New features',
  'published_at': '2026-10-30T00:00:00Z',
  'draft': draft,
  'prerelease': prerelease,
};
Map<String, dynamic> question() => {
  'title': 'AI &amp; reasoning',
  'link': 'https://ai.stackexchange.com/questions/1',
  'body': '<p>Question</p>',
  'score': 2,
  'creation_date': 1793318400,
};

void main() {
  test(
    'HN item rate limits pause the source index as well as the item',
    () async {
      var indexes = 0, items = 0;
      final client = MockClient((r) async {
        if (r.url.path.endsWith('newstories.json')) {
          indexes++;
          return jsonResponse([1]);
        }
        items++;
        return http.Response('', 429, headers: {'retry-after': '180'});
      });
      final service = FeedService(client);
      expect(
        (await service.load([source('hn-api')])).warnings.single,
        contains('HTTP 429'),
      );
      expect(
        (await service.load([source('hn-api')])).warnings.single,
        contains('HTTP 429'),
      );
      expect(indexes, 1);
      expect(items, 1);
      client.close();
    },
  );
  TestWidgetsFlutterBinding.ensureInitialized();
  test('GitHub releases skip drafts, previews and unsafe links, retain stable identity', () async {
    final client = MockClient((r) async {
      expect(r.headers.containsKey('authorization'), isFalse);
      return jsonResponse([
        release(),
        release(draft: true),
        release(prerelease: true),
        release(url: 'javascript:bad'),
      ]);
    });
    final result = await FeedService(client)
        .load([source('langchain-releases')]);
    expect(result.warnings, isEmpty);
    expect(
      result.articles.single.id,
      'https://github.com/org/repo/releases/tag/v1',
    );
    expect(result.articles.single.published, DateTime.utc(2026, 10, 30));
    client.close();
  });
  test('DEV maps public AI article descriptions without treating reactions as views', () async {
    final client = MockClient((r) async {
      expect(r.url.queryParameters['tag'], 'ai');
      expect(r.headers['accept'], 'application/vnd.forem.api-v1+json');
      return jsonResponse([
        {
          'title': 'AI tools',
          'url': 'https://dev.to/author/ai-tools',
          'description': 'Practical tools',
          'published_at': '2026-10-30T00:00:00Z',
        },
      ]);
    });
    final result = await FeedService(client).load([source('dev-api')]);
    expect(result.articles.single.excerpt, 'Practical tools');
    expect(result.articles.single.title, 'AI tools');
    client.close();
  });
  test('Hugging Face data is labelled model metadata and private/invalid IDs are dropped', () async {
    final client = MockClient(
      (_) async => jsonResponse([
        {
          'id': 'org/model',
          'downloads': 120,
          'likes': 3,
          'createdAt': '2026-10-30T00:00:00Z',
        },
        {'id': '../private'},
        {'id': 'org/private', 'private': true},
      ]),
    );
    final result = await FeedService(client).load([source('hf-models')]);
    expect(result.articles.single.title, '모델 정보 · org/model');
    expect(result.articles.single.link, 'https://huggingface.co/org/model');
    expect(
      result.articles.single.excerpt,
      allOf(contains('다운로드 120'), contains('새 릴리스나 성능 검증을 뜻하지 않습니다')),
    );
    client.close();
  });
  test('Stack Exchange public question metadata is decoded safely', () async {
    final client = MockClient(
      (_) async => jsonResponse({
        'items': [question()],
        'quota_remaining': 10,
      }),
    );
    final result = await FeedService(client).load([source('stack-ai')]);
    expect(result.articles.single.title, 'AI & reasoning');
    expect(result.articles.single.excerpt, contains('커뮤니티 질문'));
    expect(result.articles.single.excerpt, isNot(contains('<p>')));
    client.close();
  });
  test(
    'Hacker News bounds fan-out and excludes deleted stories and non-stories',
    () async {
      var calls = 0, active = 0, maximum = 0;
      final client = MockClient((r) async {
        calls++;
        if (r.url.path.endsWith('newstories.json')) {
          return jsonResponse(List.generate(100, (i) => i));
        }
        active++;
        if (active > maximum) maximum = active;
        await Future<void>.delayed(const Duration(milliseconds: 1));
        active--;
        final id = int.parse(r.url.path.split('/').last.split('.').first);
        return jsonResponse({
          'id': id,
          'type': id == 0 ? 'comment' : 'story',
          'deleted': id == 1,
          'title': 'Technology $id',
          'text': '<p>Context</p>',
          'time': 1793318400,
          'score': 5,
          'descendants': 2,
        });
      });
      final result = await FeedService(client).load([source('hn-api')]);
      expect(calls, 11);
      expect(maximum, lessThanOrEqualTo(5));
      expect(result.articles, hasLength(8));
      expect(
        result.articles.first.link,
        startsWith('https://news.ycombinator.com/item?id='),
      );
      expect(result.articles.first.excerpt, contains('5 추천점'));
      client.close();
    },
  );
  test('API refresh uses a 15 minute cache then refetches', () async {
    var now = DateTime.utc(2026, 10, 30), calls = 0;
    final client = MockClient((_) async {
      calls++;
      return jsonResponse([release()]);
    });
    final service = FeedService(client, clock: () => now);
    await service.load([source('langchain-releases')]);
    now = now.add(const Duration(minutes: 14));
    await service.load([source('langchain-releases')]);
    expect(calls, 1);
    now = now.add(const Duration(minutes: 2));
    await service.load([source('langchain-releases')]);
    expect(calls, 2);
    client.close();
  });
  for (final quota in [false, true]) {
    test(
      'Stack Exchange backoff and exhausted quota suppress new requests: $quota',
      () async {
        var now = DateTime.utc(2026, 10, 30), calls = 0;
        final client = MockClient((_) async {
          calls++;
          return jsonResponse({
            'items': [question()],
            'backoff': 3600,
            'quota_remaining': quota ? 0 : 10,
          });
        });
        final service = FeedService(client, clock: () => now);
        await service.load([source('stack-ai')]);
        now = now.add(const Duration(minutes: 16));
        final result = await service.load([source('stack-ai')]);
        expect(calls, 1);
        expect(result.warnings.single, contains('API 서버 대기'));
        now = now.add(
          quota ? const Duration(hours: 25) : const Duration(hours: 2),
        );
        await service.load([source('stack-ai')]);
        expect(calls, 2);
        client.close();
      },
    );
  }
  test('GitHub rate-limit response falls back to Atom and honors reset time', () async {
    var apiCalls = 0;
    final now = DateTime.utc(2026, 10, 30);
    final client = MockClient((r) async {
      if (r.url.host == 'api.github.com') {
        apiCalls++;
        return http.Response(
          'secret provider body',
          403,
          headers: {
            'x-ratelimit-remaining': '0',
            'x-ratelimit-reset':
                '${now.add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000}',
          },
        );
      }
      return http.Response(
        '<feed><entry><title>Release</title><link href="https://github.com/org/repo/releases/tag/v1"/></entry></feed>',
        200,
      );
    });
    final service = FeedService(client, clock: () => now);
    for (var i = 0; i < 2; i++) {
      final result = await service.load([source('langchain-releases')]);
      expect(result.articles, hasLength(1));
      expect(result.warnings.single, contains('대체 피드'));
      expect(result.warnings.single, isNot(contains('secret provider body')));
    }
    expect(apiCalls, 1);
    client.close();
  });
  test(
    'arXiv API upgrades only arxiv.org HTTP article links and caches results',
    () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return http.Response(
          '<feed><entry><title>Paper</title><link href="http://arxiv.org/abs/1234.5678v1"/><summary>Abstract</summary><published>2026-10-30T00:00:00Z</published></entry><entry><title>Unsafe</title><link href="http://example.com/article"/></entry></feed>',
          200,
        );
      });
      final service = FeedService(client);
      final result = await service.load([source('papers')]);
      expect(result.articles.single.link, 'https://arxiv.org/abs/1234.5678v1');
      await service.load([source('papers')]);
      expect(calls, 1);
      client.close();
    },
  );
  test(
    'Existing Atom selections migrate to API without re-enabling toggles',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = LocalStore(prefs);
      await store.saveSources([
        const FeedSource(
          id: 'langchain-releases',
          name: 'Old',
          url: 'https://github.com/langchain-ai/langchain/releases.atom',
          category: 'test',
          enabled: false,
        ),
      ]);
      final migrated = store.readSources().firstWhere(
        (s) => s.id == 'langchain-releases',
      );
      expect(migrated.enabled, isFalse);
      expect(migrated.format, 'github');
      expect(FeedSource.fromJson(migrated.toJson()).format, 'github');
      expect(store.readSources().any((s) => s.id == 'dev-api'), isTrue);
    },
  );
  test(
    'JSON parse failure is isolated and does not display remote body',
    () async {
      final client = MockClient(
        (r) async => r.url.host == 'dev.to'
            ? http.Response('private invalid JSON', 200)
            : jsonResponse([release()]),
      );
      final result = await FeedService(client)
          .load([source('dev-api'), source('langchain-releases')]);
      expect(result.articles, hasLength(1));
      expect(result.warnings.single, isNot(contains('private')));
      client.close();
    },
  );
}
