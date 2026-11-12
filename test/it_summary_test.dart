import 'dart:convert';

import 'package:ai_briefing/constants/feed_sources.dart';
import 'package:ai_briefing/models/briefing.dart';
import 'package:ai_briefing/services/feed_service.dart';
import 'package:ai_briefing/services/gemini_service.dart';
import 'package:ai_briefing/services/local_store.dart';
import 'package:ai_briefing/services/notification_service.dart';
import 'package:ai_briefing/state/app_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TestKeyStore extends LocalStore {
  TestKeyStore(super.prefs);
  @override
  Future<String?> readKey() async => 'fixture-key';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'IT excerpt is summarized once and subsequent refresh reuses cache',
    () async {
      SharedPreferences.setMockInitialValues({
        'gemini_summary_model_policy': 2,
      });
      final prefs = await SharedPreferences.getInstance();
      final store = TestKeyStore(prefs);
      const it = FeedSource(
        id: 'it-test',
        name: 'Tech Blog',
        url: 'https://example.com/it',
        category: 'IT·개발',
      );
      await store.saveSources([
        ...defaultFeedSources.map((s) => s.withEnabled(false)),
        it,
      ]);
      var aiCalls = 0;
      final client = MockClient((request) async {
        if (request.url.host == 'example.com') {
          return http.Response(
            '<rss><channel><item><title>Developer tools</title><link>https://example.com/article</link><description>New developer tools improve API integration, error handling, documentation and production workflows with concrete release changes.</description></item></channel></rss>',
            200,
          );
        }
        aiCalls++;
        final body = jsonDecode(request.body) as Map;
        final items = jsonDecode(
          body['contents'][0]['parts'][0]['text'] as String,
        ) as List;
        expect(items.map((item) => item['id']), ['item-0']);
        return http.Response(
          jsonEncode({
            'candidates': [
              {
                'finishReason': 'STOP',
                'content': {
                  'parts': [
                    {
                      'text': jsonEncode([
                        {
                          'id': 'item-0',
                          'ko_title': '개발 도구 소식',
                          'summary_lines': ['첫째', '둘째', '셋째'],
                          'term_explanation': '쉬운 설명',
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
      });
      final controller = AppController(
        store,
        FeedService(client),
        GeminiService(client, prefs),
        NotificationService(),
      );
      await controller.refreshIt();
      expect(controller.itMessage, isNull);
      expect(
        controller.cache['https://example.com/article']?.title,
        '개발 도구 소식',
      );
      expect(aiCalls, 1);
      await controller.refreshIt();
      expect(aiCalls, 1);
      expect(store.readCache()['https://example.com/article']?.lines, [
        '첫째',
        '둘째',
        '셋째',
      ]);
      controller.dispose();
      client.close();
    },
  );
}
