import 'dart:async';
import 'dart:convert';

import 'package:ai_briefing/models/briefing.dart';
import 'package:ai_briefing/services/gemini_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const source = FeedSource(
  id: 'test',
  name: 'Test',
  url: 'https://example.com/feed',
  category: 'test',
);
Article article({String? title, String? excerpt}) => Article(
  id: 'one',
  title: title ?? 'News',
  link: 'https://example.com/one',
  excerpt: excerpt ?? 'Update',
  source: source,
);
http.Response generated() => http.Response(
  jsonEncode({
    'candidates': [
      {
        'finishReason': 'STOP',
        'content': {
          'parts': [
            {
              'text': jsonEncode([
                {
                  'id': 'one',
                  'ko_title': '소식',
                  'summary_lines': ['1', '2', '3'],
                  'term_explanation': '설명',
                },
              ]),
            },
          ],
        },
      },
    ],
  }),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
http.Response models(List<String> names) => http.Response(
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
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({'gemini_summary_model_policy': 2});
    prefs = await SharedPreferences.getInstance();
  });
  test(
    'Existing heavy model selections migrate once to an available Lite model',
    () async {
      await prefs.setInt('gemini_summary_model_policy', 1);
      await prefs.setString('gemini_model', 'gemini-2.5-flash-lite');
      var discoveries = 0, generations = 0;
      var now = DateTime.utc(2026, 10, 23);
      final client = MockClient((r) async {
        if (r.method == 'GET') {
          discoveries++;
          return models([
            'gemini-flash-latest',
            'gemini-flash-lite-latest',
            'gemini-2.5-flash-lite',
            'gemini-3.1-flash-lite',
            'gemini-3.5-flash-lite',
          ]);
        }
        generations++;
        expect(
          r.url.path,
          '/v1beta/models/gemini-3.5-flash-lite:generateContent',
        );
        expect(
          (jsonDecode(r.body)['generationConfig'] as Map).containsKey(
            'thinkingConfig',
          ),
          isFalse,
        );
        return generated();
      });
      final service = GeminiService(client, prefs, clock: () => now);
      await service.summarize('test-key', [article()]);
      now = now.add(const Duration(seconds: 66));
      await service.summarize('test-key', [article()]);
      expect(discoveries, 1);
      expect(generations, 2);
      expect(prefs.getInt('gemini_summary_model_policy'), 2);
      client.close();
    },
  );
  test('An available Lite alias is preferred to heavy Flash without inventing model options', () async {
    final client = MockClient((r) async {
      if (r.method == 'GET') {
        return models(['gemini-flash-latest', 'gemini-flash-lite-latest']);
      }
      expect(
        r.url.path,
        '/v1beta/models/gemini-flash-lite-latest:generateContent',
      );
      expect(
        (jsonDecode(r.body)['generationConfig'] as Map).containsKey(
          'thinkingConfig',
        ),
        isFalse,
      );
      return generated();
    });
    final service = GeminiService(client, prefs);
    await service.validateKey('test-key');
    await service.summarize('test-key', [article()]);
    client.close();
  });
  test(
    'An older installation without a saved model discovers before generating',
    () async {
      await prefs.remove('gemini_summary_model_policy');
      final calls = <String>[];
      final client = MockClient((r) async {
        calls.add(r.method);
        return r.method == 'GET'
            ? models(['gemini-4.0-flash-lite'])
            : generated();
      });
      await GeminiService(client, prefs).summarize('test-key', [article()]);
      expect(calls, ['GET', 'POST']);
      expect(prefs.getString('gemini_model'), 'gemini-4.0-flash-lite');
      client.close();
    },
  );
  test(
    'Generation input is bounded without splitting Unicode characters',
    () async {
      final client = MockClient((r) async {
        final body = jsonDecode(r.body);
        final input = (jsonDecode(
          body['contents'][0]['parts'][0]['text'] as String,
        ) as List).single;
        expect((input['title'] as String).runes.length, 180);
        expect((input['feed_excerpt'] as String).runes.length, 1200);
        expect(input['feed_excerpt'], List.filled(1200, '😀').join());
        expect(body['generationConfig']['maxOutputTokens'], 6144);
        return generated();
      });
      await GeminiService(client, prefs).summarize('test-key', [
        article(title: 'N' * 1000, excerpt: '😀' * 3500),
      ]);
      client.close();
    },
  );
  testWidgets('A valid response taking over 60 seconds is still accepted', (
    tester,
  ) async {
    final client = MockClient((_) async {
      await Future<void>.delayed(const Duration(seconds: 61));
      return generated();
    });
    var done = false;
    final pending = GeminiService(client, prefs)
        .summarize('test-key', [article()])
        .then((value) {
          done = true;
          return value;
        });
    await tester.pump();
    await tester.pump(const Duration(seconds: 61));
    expect(done, isTrue);
    expect(await pending, hasLength(1));
    client.close();
  });
  for (final responseStarted in [false, true]) {
    test(
      'Timeout aborts the transport including a stalled body: $responseStarted',
      () async {
        var calls = 0;
        final cancelled = Completer<void>();
        var now = DateTime.utc(2026, 10, 23);
        final client = MockClient.streaming((r, body) async {
          await body.drain<void>();
          calls++;
          expect(r, isA<http.AbortableRequest>());
          if (calls > 1) {
            final result = generated();
            return http.StreamedResponse(
              Stream.value(result.bodyBytes),
              200,
              headers: result.headers,
            );
          }
          final abort = (r as http.AbortableRequest).abortTrigger!;
          if (!responseStarted) {
            await abort;
            cancelled.complete();
            throw http.RequestAbortedException();
          }
          final stream = StreamController<List<int>>();
          unawaited(
            abort.then((_) {
              cancelled.complete();
              stream.addError(http.RequestAbortedException());
              return stream.close();
            }),
          );
          return http.StreamedResponse(stream.stream, 200);
        });
        final service = GeminiService(
          client,
          prefs,
          clock: () => now,
          requestTimeout: const Duration(milliseconds: 30),
        );
        await expectLater(
          service.summarize('test-key', [article()]),
          throwsA(
            isA<BriefingException>().having(
              (e) => e.message,
              'timeout diagnostic',
              allOf(contains('제한 시간'), isNot(contains('test-key'))),
            ),
          ),
        );
        await cancelled.future;
        expect(calls, 1); // No automatic retry consumes more quota.
        now = now.add(const Duration(seconds: 121));
        expect(await service.summarize('test-key', [article()]), hasLength(1));
        expect(calls, 2);
        client.close();
      },
    );
  }
}
