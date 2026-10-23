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
      expect(result.warnings.single, contains('arXiv'));
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
