import 'dart:async';
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

class KeyStore extends LocalStore {
  KeyStore(super.prefs);
  @override
  Future<String?> readKey() async =>
      'AIza_test_fixture_not_a_real_key_123456789';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('AI and IT feeds refresh independently', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = KeyStore(prefs);
    const ai = FeedSource(
      id: 'ai-test',
      name: 'AI',
      url: 'https://example.com/ai',
      category: '공식 업데이트',
    );
    const it = FeedSource(
      id: 'it-test',
      name: 'IT',
      url: 'https://example.com/it',
      category: 'IT·개발',
    );
    await store.saveSources([
      ...defaultFeedSources.map((s) => s.withEnabled(false)),
      ai,
      it,
    ]);
    final releaseIt = Completer<void>();
    final client = MockClient((request) async {
      final isIt = request.url.path == '/it';
      if (isIt) await releaseIt.future;
      final title = isIt ? 'Developer design' : 'AI model news';
      final link = isIt
          ? 'https://example.com/it-post'
          : 'https://example.com/ai-post';
      return http.Response(
        '<rss><channel><item><title>$title</title><link>$link</link></item></channel></rss>',
        200,
      );
    });
    final controller = AppController(
      store,
      FeedService(client),
      GeminiService(client, prefs),
      NotificationService(),
    );
    final ready = Completer<void>();
    controller.addListener(() {
      if (!controller.loading &&
          controller.articles.length == 1 &&
          !ready.isCompleted) {
        ready.complete();
      }
    });
    await ready.future.timeout(const Duration(seconds: 3));
    expect(controller.itArticles, isEmpty);
    final itRefresh = controller.refreshIt();
    await controller.refresh();
    expect(controller.itLoading, isTrue);
    expect(controller.articles.single.source.id, ai.id);
    releaseIt.complete();
    await itRefresh;
    expect(controller.itArticles.single.source.id, it.id);
    await controller.setSource(it, false);
    expect(controller.articles.single.source.id, ai.id);
    expect(controller.itArticles, isEmpty);
    controller.dispose();
    client.close();
  });
  test('Design feeds load only when the design tab requests them', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = KeyStore(prefs);
    const design = FeedSource(
      id: 'design-test',
      name: 'Design',
      url: 'https://example.com/design',
      category: '디자인',
    );
    await store.saveSources([
      ...defaultFeedSources.map((s) => s.withEnabled(false)),
      design,
    ]);
    var designRequests = 0;
    final client = MockClient((request) async {
      designRequests++;
      return http.Response(
        '<rss><channel><item><title>Accessible navigation</title><link>https://example.com/design-post</link></item></channel></rss>',
        200,
      );
    });
    final controller = AppController(
      store,
      FeedService(client),
      GeminiService(client, prefs),
      NotificationService(),
    );
    final initialized = Completer<void>();
    controller.addListener(() {
      if (controller.initialized &&
          !controller.loading &&
          !initialized.isCompleted) {
        initialized.complete();
      }
    });
    await initialized.future.timeout(const Duration(seconds: 3));
    expect(designRequests, 0);

    await controller.refreshDesign();
    expect(designRequests, 1);
    expect(controller.designArticles.single.source.id, design.id);
    expect(controller.designLoaded, isTrue);
    controller.dispose();
  });
  test('Cached summaries render first, only new items are batched, and refresh reuses the cache', () async {
    SharedPreferences.setMockInitialValues({'gemini_summary_model_policy': 2});
    final prefs = await SharedPreferences.getInstance();
    final store = KeyStore(prefs);
    await store.saveSources([
      ...defaultFeedSources.map((s) => s.withEnabled(false)),
      const FeedSource(
        id: 'test',
        name: 'Test',
        url: 'https://example.com/feed',
        category: 'test',
      ),
    ]);
    await store.saveCache({
      'https://example.com/a': const Briefing(
        id: 'https://example.com/a',
        title: '저장된 요약',
        lines: ['1', '2', '3'],
        term: '설명',
      ),
    });
    var aiCalls = 0;
    final client = MockClient((r) async {
      if (r.url.host == 'example.com') {
        return http.Response('''<rss><channel>
        <item><title>Old</title><link>https://example.com/a</link></item>
        <item><title>New</title><description>New developer tools improve API integration, error handling, documentation and production workflows with concrete release changes.</description><link>https://example.com/b</link></item>
        </channel></rss>''', 200);
      }
      aiCalls++;
      final body = jsonDecode(r.body);
      final input =
          jsonDecode(body['contents'][0]['parts'][0]['text'] as String) as List;
      expect(input.map((j) => j['id']).toList(), ['https://example.com/b']);
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
                        'id': 'https://example.com/b',
                        'ko_title': '새 소식',
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
    expect(controller.cache['https://example.com/a']?.title, '저장된 요약');
    final ready = Completer<void>();
    controller.addListener(() {
      if (controller.initialized &&
          !controller.loading &&
          !controller.summarizing &&
          controller.cache.length == 2 &&
          !ready.isCompleted) {
        ready.complete();
      }
    });
    await ready.future.timeout(const Duration(seconds: 3));
    expect(aiCalls, 1);
    await controller.refresh();
    expect(aiCalls, 1);
    expect(store.readCache()['https://example.com/b']?.title, '새 소식');
    controller.dispose();
    client.close();
  });
}
