import 'dart:convert';

import 'package:ai_briefing/models/briefing.dart';
import 'package:ai_briefing/services/gemini_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const feed = FeedSource(
  id: 'test',
  name: 'Test',
  url: 'https://example.com/feed',
  category: 'test',
);
const key = 'AIza_test_fixture_not_a_real_key_123456789';
Article article(String id) => Article(
  id: id,
  title: 'Release $id',
  link: 'https://example.com/$id',
  excerpt: 'New tools',
  source: feed,
);
Map<String, dynamic> summary(String id) => {
  'id': id,
  'ko_title': '새 도구 출시',
  'summary_lines': ['첫 번째 내용', '두 번째 내용', '세 번째 내용'],
  'term_explanation': 'SDK: 개발 도구 모음',
};
http.Response response(dynamic value) => http.Response(
  jsonEncode({
    'candidates': [
      {
        'finishReason': 'STOP',
        'content': {
          'parts': [
            {'text': jsonEncode(value)},
          ],
        },
      },
    ],
  }),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
http.Response modelResponse(List<String> names) => http.Response(
  jsonEncode({
    'models': [
      for (final name in names)
        {
          'name': 'models/$name',
          'supportedGenerationMethods': ['generateContent'],
        },
    ],
  }),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late DateTime now;
  setUp(() async {
    SharedPreferences.setMockInitialValues({'gemini_summary_model_policy': 2});
    prefs = await SharedPreferences.getInstance();
    now = DateTime.utc(2026, 10, 23);
  });
  test('Validation accepts any nonempty prefix, trims whitespace and checks with Google', () async {
    var calls = 0;
    String? submittedKey;
    final client = MockClient((request) async {
      calls++;
      submittedKey = request.headers['x-goog-api-key'];
      expect(request.method, 'GET');
      expect(request.url.path, '/v1beta/models');
      return modelResponse(['gemini-flash-latest']);
    });
    await GeminiService(
      client,
      prefs,
    ).validateKey('  different-prefix-test-key  ');
    expect(calls, 1);
    expect(submittedKey, 'different-prefix-test-key');
    expect(prefs.getString('gemini_model'), 'gemini-flash-latest');
    expect(prefs.containsKey('gemini_next_request'), isFalse);
    client.close();
  });
  test(
    'An empty key is rejected without calling Google or consuming quota',
    () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return response('OK');
      });
      await expectLater(
        GeminiService(client, prefs).validateKey('  \n  '),
        throwsA(isA<BriefingException>()),
      );
      expect(calls, 0);
      expect(prefs.containsKey('gemini_next_request'), isFalse);
      client.close();
    },
  );
  test(
    'A nonstandard key rejected by Google is not accepted locally',
    () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return http.Response('{}', 403);
      });
      await expectLater(
        GeminiService(client, prefs).validateKey('different-prefix-test-key'),
        throwsA(isA<BriefingException>()),
      );
      expect(calls, 1);
      client.close();
    },
  );
  test('Ten uncached articles use exactly one structured request with a header key', () async {
    var count = 0;
    final client = MockClient((r) async {
      count++;
      expect(r.url.query, isEmpty);
      expect(r.headers['x-goog-api-key'], key);
      final body = jsonDecode(r.body);
      expect(body['generationConfig']['responseMimeType'], 'application/json');
      final input =
          jsonDecode(body['contents'][0]['parts'][0]['text'] as String) as List;
      expect(input, hasLength(10));
      return response([for (var i = 0; i < 10; i++) summary('$i')]);
    });
    final result = await GeminiService(
      client,
      prefs,
      clock: () => now,
    ).summarize(key, [for (var i = 0; i < 10; i++) article('$i')]);
    expect(count, 1);
    expect(result, hasLength(10));
    client.close();
  });
  test('Empty batches make no network request', () async {
    final client = MockClient((_) async => throw StateError('Unexpected call'));
    expect(await GeminiService(client, prefs).summarize(key, []), isEmpty);
    client.close();
  });
  test('Key checks do not consume generation quota and generation limits survive restart', () async {
    var count = 0;
    final client = MockClient((request) async {
      if (request.method == 'GET') {
        return modelResponse(['gemini-flash-latest']);
      }
      count++;
      return response([summary('a')]);
    });
    await GeminiService(client, prefs, clock: () => now).validateKey(key);
    await GeminiService(
      client,
      prefs,
      clock: () => now,
    ).summarize(key, [article('a')]);
    final restarted = GeminiService(client, prefs, clock: () => now);
    await expectLater(
      restarted.summarize(key, [article('a')]),
      throwsA(isA<BriefingException>()),
    );
    expect(count, 1);
    now = now.add(const Duration(seconds: 66));
    await restarted.summarize(key, [article('a')]);
    expect(count, 2);
    client.close();
  });
  test('429 respects Retry-After and does not automatically retry', () async {
    var count = 0;
    final client = MockClient((_) async {
      count++;
      return http.Response('', 429, headers: {'retry-after': '180'});
    });
    final service = GeminiService(client, prefs, clock: () => now);
    await expectLater(
      service.summarize(key, [article('a')]),
      throwsA(isA<BriefingException>()),
    );
    now = now.add(const Duration(seconds: 90));
    await expectLater(
      service.summarize(key, [article('a')]),
      throwsA(isA<BriefingException>()),
    );
    expect(count, 1);
    client.close();
  });
  for (final invalid in [
    [summary('wrong-id')],
    [summary('a'), summary('a')],
    [
      {
        ...summary('a'),
        'summary_lines': ['only one'],
      },
    ],
    [
      {...summary('a'), 'ko_title': ''},
    ],
  ]) {
    test(
      'Invalid batch is rejected atomically: ${jsonEncode(invalid)}',
      () async {
        final client = MockClient((_) async => response(invalid));
        await expectLater(
          GeminiService(
            client,
            prefs,
            clock: () => now,
          ).summarize(key, [article('a')]),
          throwsA(isA<BriefingException>()),
        );
        client.close();
      },
    );
  }
  test('Truncated output cannot become a cached summary', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'candidates': [
            {
              'finishReason': 'MAX_TOKENS',
              'content': {
                'parts': [
                  {'text': '[]'},
                ],
              },
            },
          ],
        }),
        200,
      ),
    );
    await expectLater(
      GeminiService(client, prefs).summarize(key, [article('a')]),
      throwsA(isA<BriefingException>()),
    );
    client.close();
  });
}
