import 'package:ai_briefing/models/briefing.dart';
import 'package:ai_briefing/services/feed_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const source = FeedSource(
  id: 'test',
  name: 'Test',
  url: 'https://example.com/feed',
  category: 'test',
);
const rss = '''<rss version="2.0"><channel><item><title>SDK &amp; news</title>
<link>https://example.com/article</link><description><![CDATA[<p>New <b>tools</b></p>]]></description>
<pubDate>Wed, 21 Oct 2026 09:00:00 GMT</pubDate></item></channel></rss>''';

void main() {
  test('An empty valid RSS is successful and does not trigger fallback', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return http.Response(
        '<rss version="2.0"><channel><title>No updates</title></channel></rss>',
        200,
      );
    });
    final result = await FeedService(client).load([
      const FeedSource(
        id: 'empty',
        name: 'Empty',
        url: 'https://example.com/feed',
        fallbackUrl: 'https://example.com/fallback',
        category: 'test',
      ),
    ]);
    expect(result.articles, isEmpty);
    expect(result.warnings, isEmpty);
    expect(calls, 1);
    client.close();
  });
  test(
    'HTML received with HTTP 200 is distinguished from an empty feed',
    () async {
      final client = MockClient(
        (_) async => http.Response('<html><body>Blocked</body></html>', 200),
      );
      final result = await FeedService(client).load([source]);
      expect(result.warnings.single, contains('다른 문서'));
      client.close();
    },
  );
  test(
    'Large feed failures explain the byte limit without disclosing content',
    () async {
      final client = MockClient(
        (_) async => http.Response('x' * (2 * 1024 * 1024 + 1), 200),
      );
      final result = await FeedService(client).load([source]);
      expect(result.warnings.single, contains('2MB'));
      client.close();
    },
  );
  for (final zone in ['+0900', '+0000', '-0500', '+09:00']) {
    test('RSS numeric timezone $zone is converted to UTC', () {
      final article = parseFeed(rss.replaceFirst('GMT', zone), source).single;
      final offset = zone == '+0000'
          ? 0
          : zone == '-0500'
          ? -5
          : 9;
      expect(
        article.published,
        DateTime.utc(2026, 10, 21, 9).subtract(Duration(hours: offset)),
      );
    });
  }
  test('High-volume feeds cannot crowd out official or undated sources', () async {
    final client = MockClient((r) async {
      final busy = r.url.path == '/busy';
      return http.Response(
        '<rss><channel>${[for (var i = 0; i < (busy ? 20 : 1); i++) '<item><title>News $i</title><link>https://example.com${r.url.path}/$i</link>'
              '${busy ? '<pubDate>2026-10-23T12:00:00Z</pubDate>' : ''}</item>'].join()}</channel></rss>',
        200,
      );
    });
    final result = await FeedService(client).load([
      for (final id in ['busy', 'official', 'undated'])
        FeedSource(
          id: id,
          name: id,
          url: 'https://example.com/$id',
          category: 'test',
        ),
    ]);
    expect(result.articles, hasLength(10));
    expect(result.articles.map((a) => a.source.id).take(3), [
      'busy',
      'official',
      'undated',
    ]);
    expect(result.articles.where((a) => a.source.id == 'busy'), hasLength(8));
    expect(result.warnings, isEmpty);
    client.close();
  });
  test(
    'Ten available sources each get a place, using their actual newest article',
    () async {
      final client = MockClient(
        (r) async => http.Response('''<rss><channel>
      <item><title>Old</title><link>https://example.com${r.url.path}/old</link><pubDate>Wed, 21 Oct 2026 09:00:00 +0900</pubDate></item>
      <item><title>New</title><link>https://example.com${r.url.path}/new</link><pubDate>Wed, 21 Oct 2026 08:00:00 +0000</pubDate></item>
      </channel></rss>''', 200),
      );
      final result = await FeedService(client).load([
        for (var i = 0; i < 10; i++)
          FeedSource(
            id: '$i',
            name: '$i',
            url: 'https://example.com/$i',
            category: 'test',
          ),
      ]);
      expect(result.articles, hasLength(10));
      expect(result.articles.map((a) => a.source.id).toSet(), hasLength(10));
      expect(result.articles.every((a) => a.title == 'New'), isTrue);
      client.close();
    },
  );
  test(
    'An unavailable feed reports a safe HTTP diagnosis without its body',
    () async {
      final client = MockClient(
        (_) async => http.Response('private error body', 403),
      );
      final result = await FeedService(client).load([source]);
      expect(result.warnings.single, contains('HTTP 403'));
      expect(result.warnings.single, isNot(contains('private error body')));
      client.close();
    },
  );
  test('RSS parses text, canonical article identity and RFC 822 dates', () {
    final article = parseFeed(rss, source).single;
    expect(article.title, 'SDK & news');
    expect(article.id, 'https://example.com/article');
    expect(article.excerpt, 'New tools');
    expect(article.published, DateTime.utc(2026, 10, 21, 9));
  });
  test(
    'Atom uses alternate link instead of self link and resolves relative URLs',
    () {
      final article = parseFeed(
        '''<feed xmlns="http://www.w3.org/2005/Atom"><entry>
      <title>Release</title><id>tag:example.com,2026:one</id>
      <link rel="self" href="https://example.com/entry.atom"/>
      <link rel="alternate" href="/release"/>
      <updated>2026-10-21T09:00:00Z</updated><content type="html">&lt;p&gt;Hello&lt;/p&gt;</content>
      </entry></feed>''',
        source,
      ).single;
      expect(article.link, 'https://example.com/release');
      expect(article.excerpt, 'Hello');
    },
  );
  test('Missing, unsafe and executable article links are excluded', () {
    final articles = parseFeed('''<rss><channel>
      <item><title>Missing</title></item>
      <item><title>Unsafe</title><link>javascript:alert(1)</link></item>
      <item><title>Private</title><link>https://127.0.0.1/admin</link></item>
      </channel></rss>''', source);
    expect(articles, isEmpty);
    expect(isSafeWebUrl('https://user:password@example.com'), isFalse);
    expect(isSafeWebUrl('https://192.168.1.1/feed'), isFalse);
    expect(isSafeWebUrl('http://example.com/feed'), isFalse);
  });
  test(
    'Failed primary source falls back, disabled sources are never requested',
    () async {
      final requests = <String>[];
      final client = MockClient((request) async {
        requests.add(request.url.toString());
        return request.url.path == '/fallback'
            ? http.Response(rss, 200)
            : http.Response('unavailable', 503);
      });
      final result = await FeedService(client).load([
        const FeedSource(
          id: 'papers',
          name: 'Papers',
          url: 'https://example.com/primary',
          fallbackUrl: 'https://example.com/fallback',
          category: 'research',
        ),
        const FeedSource(
          id: 'off',
          name: 'Off',
          url: 'https://example.com/off',
          category: 'test',
          enabled: false,
        ),
      ]);
      expect(requests, [
        'https://example.com/primary',
        'https://example.com/fallback',
      ]);
      expect(result.articles, hasLength(1));
      expect(result.warnings.single, contains('대체 피드'));
      client.close();
    },
  );
  test(
    'Source failures are isolated and duplicate articles are removed',
    () async {
      final client = MockClient(
        (r) async => r.url.path == '/bad'
            ? http.Response('<html>Not a feed</html>', 200)
            : http.Response(rss, 200),
      );
      final result = await FeedService(client).load([
        source,
        const FeedSource(
          id: 'copy',
          name: 'Copy',
          url: 'https://example.com/copy',
          category: 'test',
        ),
        const FeedSource(
          id: 'bad',
          name: 'Bad',
          url: 'https://example.com/bad',
          category: 'test',
        ),
      ]);
      expect(result.articles, hasLength(1));
      expect(result.warnings, hasLength(1));
      client.close();
    },
  );
  test('Redirects to private addresses are rejected', () async {
    final requests = <Uri>[];
    final client = MockClient((r) async {
      requests.add(r.url);
      return http.Response(
        '',
        302,
        headers: {'location': 'https://127.0.0.1/internal'},
      );
    });
    final result = await FeedService(client).load([source]);
    expect(requests, hasLength(1));
    expect(result.articles, isEmpty);
    expect(result.warnings, hasLength(1));
    client.close();
  });
}
