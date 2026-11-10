import 'dart:convert';

import 'package:ai_briefing/constants/feed_sources.dart';
import 'package:ai_briefing/models/briefing.dart';
import 'package:ai_briefing/screens/home_screen.dart';
import 'package:ai_briefing/services/feed_service.dart';
import 'package:ai_briefing/services/gemini_service.dart';
import 'package:ai_briefing/services/local_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const plain = FeedSource(
  id: 'test',
  name: 'Test',
  url: 'https://example.com/feed',
  category: 'test',
);
const metadata = Article(
  id: 'meta',
  title: 'AI title only',
  link: 'https://example.com/meta',
  excerpt: '',
  source: plain,
);
final body =
    'This SDK release improves error handling, model integration, request validation and developer workflows. ' *
    2;
http.Response jsonResponse(Object data) => http.Response(
  jsonEncode(data),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
FeedSource source(String id) =>
    defaultFeedSources.firstWhere((s) => s.id == id);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('HN linked story uses publisher URL and never fabricates an excerpt from votes', () async {
    final now = DateTime.utc(2026, 11, 10);
    final client = MockClient(
      (r) async => r.url.path.endsWith('newstories.json')
          ? jsonResponse([1])
          : jsonResponse({
              'id': 1,
              'type': 'story',
              'title': 'AI developer tools',
              'url': 'https://publisher.example/article',
              'time': now.millisecondsSinceEpoch ~/ 1000,
              'score': 10,
              'descendants': 5,
            }),
    );
    final result = await FeedService(
      client,
      clock: () => now,
    ).load([source('hn-api')]);
    expect(result.articles.single.link, 'https://publisher.example/article');
    expect(result.articles.single.id, 'https://news.ycombinator.com/item?id=1');
    expect(result.articles.single.excerpt, isEmpty);
    expect(result.articles.single.canSummarize, isFalse);
    client.close();
  });
  test(
    'HN self post with substantial technical text keeps HN as its original',
    () async {
      final now = DateTime.utc(2026, 11, 10);
      final client = MockClient(
        (r) async => r.url.path.endsWith('newstories.json')
            ? jsonResponse([1])
            : jsonResponse({
                'id': 1,
                'type': 'story',
                'title': 'Ask HN: AI developer tools',
                'text': '<p>$body</p>',
                'time': now.millisecondsSinceEpoch ~/ 1000,
              }),
      );
      final article = (await FeedService(
        client,
        clock: () => now,
      ).load([source('hn-api')])).articles.single;
      expect(article.link, 'https://news.ycombinator.com/item?id=1');
      expect(article.canSummarize, isTrue);
      expect(article.excerpt, contains('improves error handling'));
      client.close();
    },
  );
  test('Unrelated and unsafe linked HN stories are excluded', () async {
    final now = DateTime.utc(2026, 11, 10);
    final client = MockClient((r) async {
      if (r.url.path.endsWith('newstories.json')) return jsonResponse([1, 2]);
      final first = r.url.path.endsWith('/1.json');
      return jsonResponse({
        'id': first ? 1 : 2,
        'type': 'story',
        'title': first ? 'How to Become a Lost' : 'AI tools',
        'url': first ? 'https://example.com/lost' : 'https://127.0.0.1/private',
        'time': now.millisecondsSinceEpoch ~/ 1000,
      });
    });
    expect(
      (await FeedService(client, clock: () => now).load([source('hn-api')]))
          .articles,
      isEmpty,
    );
    client.close();
  });
  test('Substantial content fills the briefing before metadata-only source slots', () async {
    final client = MockClient((r) async {
      if (r.url.path == '/meta') {
        return http.Response(
          '<rss><channel><item><title>New title</title><link>https://example.com/meta</link><pubDate>2026-11-10T00:00:00Z</pubDate></item></channel></rss>',
          200,
        );
      }
      return http.Response(
        '<rss><channel>${List.generate(12, (i) => '<item><title>Release $i</title><link>https://example.com/$i</link><description>$body</description><pubDate>2026-11-09T00:00:00Z</pubDate></item>').join()}</channel></rss>',
        200,
      );
    });
    final result = await FeedService(client).load([
      plain,
      const FeedSource(
        id: 'meta',
        name: 'Meta',
        url: 'https://example.com/meta',
        category: 'test',
      ),
    ]);
    expect(result.articles, hasLength(10));
    expect(result.articles.every((a) => a.canSummarize), isTrue);
    client.close();
  });
  test('HNRSS vote/link descriptions do not qualify as article bodies', () async {
    final client = MockClient(
      (_) async => http.Response(
        '<rss><channel><item><title>AI tools</title><link>https://example.com/ai</link><description>$body</description></item></channel></rss>',
        200,
      ),
    );
    expect(
      (await FeedService(client).load([source('hn-ai')]))
          .articles
          .single
          .canSummarize,
      isFalse,
    );
    client.close();
  });
  test('General technical feeds filter off-topic posts and allow Korean AI topics', () async {
    final client = MockClient(
      (_) async => http.Response(
        '<rss><channel><item><title>AI의 새로운 도구</title><link>https://example.com/ai</link><description>$body</description></item><item><title>A walk in the park</title><link>https://example.com/walk</link><description>A pleasant quiet afternoon outside.</description></item></channel></rss>',
        200,
        headers: {'content-type': 'application/rss+xml; charset=utf-8'},
      ),
    );
    final result = await FeedService(client).load([source('geeknews')]);
    expect(result.articles.single.title, 'AI의 새로운 도구');
    client.close();
  });
  test('An all-metadata batch makes zero AI requests', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final client = MockClient(
      (_) async => throw StateError('Must not call Google'),
    );
    expect(
      await GeminiService(client, prefs).summarize('test-key', [metadata]),
      isEmpty,
    );
    expect(prefs.containsKey('gemini_next_request'), isFalse);
    client.close();
  });
  test('Mixed batches send only eligible article IDs to AI', () async {
    SharedPreferences.setMockInitialValues({'gemini_summary_model_policy': 2});
    final prefs = await SharedPreferences.getInstance();
    final client = MockClient((r) async {
      final request = jsonDecode(r.body);
      final input = jsonDecode(
        request['contents'][0]['parts'][0]['text'] as String,
      ) as List;
      expect(input.map((j) => j['id']).toList(), ['real']);
      return jsonResponse({
        'candidates': [
          {
            'finishReason': 'STOP',
            'content': {
              'parts': [
                {
                  'text': jsonEncode([
                    {
                      'id': 'real',
                      'ko_title': 'Release',
                      'summary_lines': ['1', '2', '3'],
                      'term_explanation': 'SDK',
                    },
                  ]),
                },
              ],
            },
          },
        ],
      });
    });
    final result = await GeminiService(client, prefs).summarize('test-key', [
      metadata,
      Article(
        id: 'real',
        title: 'Release',
        link: 'https://example.com/real',
        excerpt: body,
        source: plain,
        canSummarize: true,
      ),
    ]);
    expect(result.single.id, 'real');
    client.close();
  });
  test(
    'Legacy summaries are regenerated once without losing read history',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = LocalStore(prefs);
      const brief = Briefing(
        id: 'meta',
        title: 'Old metadata summary',
        lines: ['1', '2', '3'],
        term: 'Metadata',
      );
      await store.saveCache({'meta': brief});
      await store.markRead('meta');
      await prefs.remove('briefing_content_version');
      expect(store.readCache(), isEmpty);
      expect(store.readIds(), contains('meta'));
      await store.saveCache({'meta': brief});
      expect(store.readCache().keys, contains('meta'));
    },
  );
  testWidgets(
    'Metadata cards ignore old AI titles, lines and glossary entries',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ArticleCard(
              article: metadata,
              briefing: const Briefing(
                id: 'meta',
                title: 'Old metadata summary',
                lines: ['bad1', 'bad2', 'bad3'],
                term: 'Old glossary',
              ),
              read: false,
              onTap: () {},
            ),
          ),
        ),
      );
      expect(find.text('AI title only'), findsOneWidget);
      expect(find.text('Old metadata summary'), findsNothing);
      expect(find.textContaining('Old glossary'), findsNothing);
      expect(find.text('AI 요약 제외 · 제목/정보만 제공'), findsOneWidget);
    },
  );
}
