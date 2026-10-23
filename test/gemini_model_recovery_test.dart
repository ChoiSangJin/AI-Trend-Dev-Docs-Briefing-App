import 'dart:async';
import 'dart:convert';

import 'package:ai_briefing/models/briefing.dart';
import 'package:ai_briefing/services/gemini_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const key = 'fixture-key-must-not-leak';
const article = Article(
  id: 'one',
  title: 'News',
  link: 'https://example.com/one',
  excerpt: 'Update',
  source: FeedSource(
    id: 'test',
    name: 'Test',
    url: 'https://example.com/feed',
    category: 'test',
  ),
);
http.Response jsonResponse(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
http.Response models(List<String> names) => jsonResponse({
  'models': [
    for (final name in names)
      {
        'name': 'models/$name',
        'supportedGenerationMethods': ['generateContent'],
      },
  ],
});
http.Response errorResponse(int code) => jsonResponse({
  'error': {
    'status': code == 404 ? 'NOT_FOUND' : 'UNAVAILABLE',
    'message': 'private $key',
  },
}, code);
http.Response generated() => jsonResponse({
  'candidates': [
    {
      'finishReason': 'STOP',
      'content': {
        'parts': [
          {
            'text': jsonEncode([
              {
                'id': 'one',
                'ko_title': '뉴스',
                'summary_lines': ['첫째', '둘째', '셋째'],
                'term_explanation': '설명',
              },
            ]),
          },
        ],
      },
    },
  ],
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late DateTime now;
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'gemini_summary_model_policy': 2,
      'gemini_model': 'gemini-3.5-flash-lite',
    });
    prefs = await SharedPreferences.getInstance();
    now = DateTime.utc(2026, 10, 23);
  });
  test('Current stable Lite models win over legacy models, aliases and heavier models', () async {
    final client = MockClient(
      (_) async => models([
        'gemini-2.5-flash-lite',
        'gemini-2.5-flash',
        'gemini-flash-lite-latest',
        'gemini-3.1-flash-lite',
        'gemini-3.5-flash-lite',
        'gemini-3.8-flash',
        'gemini-9.0-pro',
        'gemini-9.0-flash-image',
        'gemini-9.0-flash-preview',
      ]),
    );
    await GeminiService(client, prefs).validateKey(key);
    expect(prefs.getString('gemini_model'), 'gemini-3.5-flash-lite');
    client.close();
  });
  test(
    'An old installation never posts to 2.5 even if the catalog still lists it',
    () async {
      await prefs.setInt('gemini_summary_model_policy', 1);
      await prefs.setString('gemini_model', 'gemini-2.5-flash-lite');
      final calls = <String>[];
      final client = MockClient((r) async {
        calls.add('${r.method} ${r.url.path}');
        if (r.method == 'GET') {
          return models(['gemini-2.5-flash-lite', 'gemini-3.5-flash-lite']);
        }
        return generated();
      });
      expect(
        await GeminiService(client, prefs).summarize(key, [article]),
        hasLength(1),
      );
      expect(calls, [
        'GET /v1beta/models',
        'POST /v1beta/models/gemini-3.5-flash-lite:generateContent',
      ]);
      client.close();
    },
  );
  test(
    'A legacy-only catalog is reported without calling generation',
    () async {
      await prefs.setInt('gemini_summary_model_policy', 1);
      var posts = 0;
      final client = MockClient((r) async {
        if (r.method == 'POST') posts++;
        return models(['gemini-2.5-flash-lite', 'gemini-2.5-flash']);
      });
      await expectLater(
        GeminiService(client, prefs).summarize(key, [article]),
        throwsA(
          isA<BriefingException>().having(
            (e) => e.message,
            'available model diagnostic',
            contains('최신 텍스트 Flash'),
          ),
        ),
      );
      expect(posts, 0);
      expect(prefs.containsKey('gemini_next_request'), isFalse);
      client.close();
    },
  );
  test('404 refreshes the catalog once and excludes a model still advertised there', () async {
    var gets = 0;
    final posts = <String>[];
    final bodies = <String>[];
    final client = MockClient((r) async {
      expect(r.headers['x-goog-api-key'], key);
      expect(r.url.queryParameters.containsKey('key'), isFalse);
      if (r.method == 'GET') {
        gets++;
        return models([
          'gemini-2.5-flash-lite',
          'gemini-3.5-flash-lite',
          'gemini-3.1-flash-lite',
          'gemini-3.8-flash',
        ]);
      }
      posts.add(r.url.path);
      bodies.add(r.body);
      return posts.length == 1 ? errorResponse(404) : generated();
    });
    final service = GeminiService(client, prefs, clock: () => now);
    expect((await service.summarize(key, [article])).single.id, 'one');
    expect(posts, [
      '/v1beta/models/gemini-3.5-flash-lite:generateContent',
      '/v1beta/models/gemini-3.1-flash-lite:generateContent',
    ]);
    expect(bodies.toSet(), hasLength(1));
    expect(gets, 1);
    expect(prefs.getStringList('gemini_rejected_models'), [
      'gemini-3.5-flash-lite',
    ]);
    expect(prefs.getString('gemini_model'), 'gemini-3.1-flash-lite');
    final restarted = GeminiService(client, prefs, clock: () => now);
    await expectLater(
      restarted.summarize(key, [article]),
      throwsA(isA<BriefingException>()),
    );
    expect(posts, hasLength(2));
    now = now.add(const Duration(seconds: 66));
    await restarted.summarize(key, [article]);
    expect(posts.last, '/v1beta/models/gemini-3.1-flash-lite:generateContent');
    expect(gets, 1);
    client.close();
  });
  test(
    'Two unavailable models stop at two posts and are skipped after restart',
    () async {
      var gets = 0, posts = 0;
      final client = MockClient((r) async {
        if (r.method == 'GET') {
          gets++;
          return models(['gemini-3.5-flash-lite', 'gemini-3.1-flash-lite']);
        }
        posts++;
        return errorResponse(404);
      });
      await expectLater(
        GeminiService(
          client,
          prefs,
          clock: () => now,
        ).summarize(key, [article]),
        throwsA(
          isA<BriefingException>().having(
            (e) => e.message,
            'safe 404',
            allOf(
              contains('HTTP 404'),
              contains('NOT_FOUND'),
              isNot(contains(key)),
            ),
          ),
        ),
      );
      expect(posts, 2);
      expect(gets, 1);
      expect(
        prefs.getStringList('gemini_rejected_models'),
        containsAll(['gemini-3.5-flash-lite', 'gemini-3.1-flash-lite']),
      );
      now = now.add(const Duration(seconds: 66));
      await expectLater(
        GeminiService(
          client,
          prefs,
          clock: () => now,
        ).summarize(key, [article]),
        throwsA(
          isA<BriefingException>().having(
            (e) => e.message,
            'exhausted models',
            contains('최신 텍스트 Flash'),
          ),
        ),
      );
      expect(posts, 2);
      expect(gets, 2);
      client.close();
    },
  );
  test('A lone 404 model cannot be reselected from the catalog', () async {
    var posts = 0;
    final client = MockClient((r) async {
      if (r.method == 'GET') return models(['gemini-3.5-flash-lite']);
      posts++;
      return errorResponse(404);
    });
    await expectLater(
      GeminiService(client, prefs).summarize(key, [article]),
      throwsA(
        isA<BriefingException>().having(
          (e) => e.message,
          'original 404 retained',
          allOf(
            contains('HTTP 404'),
            contains('최신 텍스트 Flash'),
            isNot(contains(key)),
          ),
        ),
      ),
    );
    expect(posts, 1);
    client.close();
  });
  test(
    'Discovery failure retains both the original 404 and safe recovery error',
    () async {
      var posts = 0;
      final client = MockClient((r) async {
        if (r.method == 'GET') return errorResponse(503);
        posts++;
        return errorResponse(404);
      });
      await expectLater(
        GeminiService(client, prefs).summarize(key, [article]),
        throwsA(
          isA<BriefingException>().having(
            (e) => e.message,
            'safe recovery diagnosis',
            allOf(
              contains('HTTP 404'),
              contains('HTTP 503'),
              isNot(contains(key)),
              isNot(contains('private')),
            ),
          ),
        ),
      );
      expect(posts, 1);
      client.close();
    },
  );
  for (final code in [400, 401, 403, 429, 500, 503]) {
    test(
      'HTTP $code never triggers model discovery or a replacement post',
      () async {
        var gets = 0, posts = 0;
        final client = MockClient((r) async {
          if (r.method == 'GET') {
            gets++;
          } else {
            posts++;
          }
          return errorResponse(code);
        });
        await expectLater(
          GeminiService(client, prefs).summarize(key, [article]),
          throwsA(isA<BriefingException>()),
        );
        expect(gets, 0);
        expect(posts, 1);
        expect(prefs.containsKey('gemini_rejected_models'), isFalse);
        client.close();
      },
    );
  }
  test(
    'A concurrent summary cannot send while 404 recovery is waiting',
    () async {
      final discovering = Completer<void>();
      final release = Completer<void>();
      var posts = 0;
      final client = MockClient((r) async {
        if (r.method == 'GET') {
          discovering.complete();
          await release.future;
          return models(['gemini-3.1-flash-lite']);
        }
        posts++;
        return posts == 1 ? errorResponse(404) : generated();
      });
      final service = GeminiService(client, prefs, clock: () => now);
      final first = service.summarize(key, [article]);
      await discovering.future;
      now = now.add(const Duration(seconds: 66));
      await expectLater(
        service.summarize(key, [article]),
        throwsA(isA<BriefingException>()),
      );
      expect(posts, 1);
      release.complete();
      expect(await first, hasLength(1));
      expect(posts, 2);
      client.close();
    },
  );
  test(
    'Explicit key registration resets model failures from a previous project',
    () async {
      await prefs.setStringList('gemini_rejected_models', [
        'gemini-3.5-flash-lite',
      ]);
      final client = MockClient((_) async => models(['gemini-3.5-flash-lite']));
      await GeminiService(client, prefs).validateKey('new-project-key');
      expect(prefs.getString('gemini_model'), 'gemini-3.5-flash-lite');
      expect(prefs.containsKey('gemini_rejected_models'), isFalse);
      client.close();
    },
  );
}
