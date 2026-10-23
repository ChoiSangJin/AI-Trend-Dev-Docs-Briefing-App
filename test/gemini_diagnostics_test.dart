import 'dart:async';
import 'dart:convert';

import 'package:ai_briefing/models/briefing.dart';
import 'package:ai_briefing/services/gemini_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const testKey = 'different-prefix-test-key';
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
http.Response jsonResponse(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Map<String, dynamic> model(
  String name, {
  List<String> methods = const ['generateContent'],
}) => {'name': 'models/$name', 'supportedGenerationMethods': methods};
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
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });
  test('A key works without the retired fixed model, and first summary can run immediately', () async {
    var checks = 0, generations = 0;
    final client = MockClient((r) async {
      expect(r.headers['x-goog-api-key'], testKey);
      expect(r.url.queryParameters.containsKey('key'), isFalse);
      if (r.method == 'GET') {
        checks++;
        return jsonResponse({
          'models': [model('gemini-flash-latest')],
        });
      }
      generations++;
      expect(r.url.path, '/v1beta/models/gemini-flash-latest:generateContent');
      expect(
        (jsonDecode(r.body)['generationConfig'] as Map).containsKey(
          'thinkingConfig',
        ),
        isFalse,
      );
      return generated();
    });
    final service = GeminiService(client, prefs);
    await service.validateKey(testKey);
    expect(prefs.containsKey('gemini_next_request'), isFalse);
    expect(await service.summarize(testKey, [article]), hasLength(1));
    expect(checks, 1);
    expect(generations, 1);
    client.close();
  });
  test('Discovery follows pagination and prefers an available Flash alias over Pro', () async {
    final pages = <String?>[];
    final client = MockClient((r) async {
      pages.add(r.url.queryParameters['pageToken']);
      return pages.length == 1
          ? jsonResponse({
              'models': [model('gemini-pro')],
              'nextPageToken': 'second',
            })
          : jsonResponse({
              'models': [model('gemini-flash-latest')],
            });
    });
    await GeminiService(client, prefs).validateKey(testKey);
    expect(pages, [null, 'second']);
    expect(prefs.getString('gemini_model'), 'gemini-flash-latest');
    client.close();
  });
  test('New stable text Flash versions can be selected without hardcoding their number', () async {
    final client = MockClient(
      (_) async => jsonResponse({
        'models': [
          model('gemini-3.0-flash'),
          model('gemini-4.0-flash-lite'),
          model('gemini-4.0-flash'),
          model('gemini-9.0-pro'),
          model('gemini-9.0-flash-image'),
          model('gemini-9.0-flash-preview'),
        ],
      }),
    );
    await GeminiService(client, prefs).validateKey(testKey);
    expect(prefs.getString('gemini_model'), 'gemini-4.0-flash');
    client.close();
  });
  test(
    'Non-text or non-generating models are not silently substituted',
    () async {
      final client = MockClient(
        (_) async => jsonResponse({
          'models': [
            model('gemini-pro'),
            model('gemini-3.0-flash-image'),
            model('gemini-flash-latest', methods: ['countTokens']),
          ],
        }),
      );
      await expectLater(
        GeminiService(client, prefs).validateKey(testKey),
        throwsA(
          isA<BriefingException>().having(
            (e) => e.message,
            'model diagnostic',
            contains('Flash 모델'),
          ),
        ),
      );
      expect(prefs.containsKey('gemini_model'), isFalse);
      client.close();
    },
  );
  test('Discovery failures preserve the last working model', () async {
    await prefs.setString('gemini_model', 'gemini-2.5-flash');
    final client = MockClient(
      (_) async => jsonResponse({
        'error': {'status': 'PERMISSION_DENIED'},
      }, 403),
    );
    await expectLater(
      GeminiService(client, prefs).validateKey(testKey),
      throwsA(isA<BriefingException>()),
    );
    expect(prefs.getString('gemini_model'), 'gemini-2.5-flash');
    client.close();
  });
  for (final scenario in [
    (
      code: 400,
      status: 'INVALID_ARGUMENT',
      reason: 'API_KEY_INVALID',
      hint: '만료·삭제',
    ),
    (code: 400, status: 'INVALID_ARGUMENT', reason: '', hint: '요청 설정'),
    (code: 400, status: 'FAILED_PRECONDITION', reason: '', hint: '이용 조건'),
    (code: 401, status: 'UNAUTHENTICATED', reason: '', hint: '키를 확인'),
    (
      code: 403,
      status: 'PERMISSION_DENIED',
      reason: 'SERVICE_DISABLED',
      hint: 'API 사용',
    ),
    (
      code: 403,
      status: 'PERMISSION_DENIED',
      reason: 'API_KEY_ANDROID_APP_BLOCKED',
      hint: '앱·주소',
    ),
    (code: 404, status: 'NOT_FOUND', reason: '', hint: 'AI 모델'),
    (code: 429, status: 'RESOURCE_EXHAUSTED', reason: '', hint: '요청 한도'),
    (code: 500, status: 'INTERNAL', reason: '', hint: '서버'),
    (code: 503, status: 'UNAVAILABLE', reason: '', hint: '서버'),
  ]) {
    test(
      'HTTP ${scenario.code} ${scenario.reason} reports its cause without leaking raw provider text',
      () async {
        final client = MockClient(
          (_) async => jsonResponse({
            'error': {
              'status': scenario.status,
              'message': 'Provider echoed $testKey',
              'details': [
                {'reason': scenario.reason},
              ],
            },
          }, scenario.code),
        );
        await expectLater(
          GeminiService(client, prefs).summarize(testKey, [article]),
          throwsA(
            isA<BriefingException>().having(
              (e) => e.message,
              'message',
              allOf(
                contains('HTTP ${scenario.code}'),
                contains(scenario.status),
                contains(scenario.hint),
                isNot(contains(testKey)),
                isNot(contains('Provider echoed')),
              ),
            ),
          ),
        );
        client.close();
      },
    );
  }
  test(
    'Unknown structured status and reason strings are not echoed to the screen',
    () async {
      final client = MockClient(
        (_) async => jsonResponse({
          'error': {
            'status': testKey,
            'message': testKey,
            'details': [
              {'reason': testKey},
            ],
          },
        }, 418),
      );
      await expectLater(
        GeminiService(client, prefs).validateKey(testKey),
        throwsA(
          isA<BriefingException>().having(
            (e) => e.message,
            'safe diagnostic',
            allOf(contains('HTTP 418'), isNot(contains(testKey))),
          ),
        ),
      );
      client.close();
    },
  );
  test('An HTML 503 still reports the HTTP code', () async {
    final client = MockClient(
      (_) async => http.Response('<html>Unavailable</html>', 503),
    );
    await expectLater(
      GeminiService(client, prefs).validateKey(testKey),
      throwsA(
        isA<BriefingException>().having(
          (e) => e.message,
          'HTTP diagnostic',
          contains('HTTP 503'),
        ),
      ),
    );
    client.close();
  });
  test('Network and timeout errors during key checks are distinguished from invalid keys', () async {
    for (final error in [
      TimeoutException('timeout'),
      http.ClientException('connection $testKey'),
    ]) {
      final client = MockClient((_) async => throw error);
      await expectLater(
        GeminiService(client, prefs).validateKey(testKey),
        throwsA(
          isA<BriefingException>().having(
            (e) => e.message,
            'network diagnostic',
            allOf(
              contains('인터넷'),
              isNot(contains(testKey)),
              isNot(contains('HTTP 200')),
            ),
          ),
        ),
      );
      client.close();
    }
  });
  test('Corrupt model responses do not replace the selected model', () async {
    final client = MockClient((_) async => http.Response('{broken', 200));
    await expectLater(
      GeminiService(client, prefs).validateKey(testKey),
      throwsA(
        isA<BriefingException>().having(
          (e) => e.message,
          'response diagnostic',
          contains('모델 목록'),
        ),
      ),
    );
    expect(prefs.containsKey('gemini_model'), isFalse);
    client.close();
  });
}
