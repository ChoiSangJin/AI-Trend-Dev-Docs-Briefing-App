import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../models/briefing.dart';

class FeedResult {
  const FeedResult(this.articles, this.warnings);
  final List<Article> articles;
  final List<String> warnings;
}

bool isSafeWebUrl(String value) {
  final u = Uri.tryParse(value);
  if (u == null ||
      u.scheme != 'https' ||
      u.host.isEmpty ||
      u.userInfo.isNotEmpty) {
    return false;
  }
  final host = u.host.toLowerCase();
  if (host == 'localhost' ||
      host.endsWith('.localhost') ||
      host.endsWith('.local') ||
      !host.contains('.')) {
    return false;
  }
  final ip = InternetAddress.tryParse(host);
  if (ip != null) {
    final b = ip.rawAddress;
    if (ip.type == InternetAddressType.IPv6) return false;
    if (b[0] == 0 ||
        b[0] == 10 ||
        b[0] == 127 ||
        b[0] >= 224 ||
        (b[0] == 169 && b[1] == 254) ||
        (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
        (b[0] == 192 && b[1] == 168) ||
        (b[0] == 100 && b[1] >= 64 && b[1] <= 127)) {
      return false;
    }
  }
  return true;
}

class FeedService {
  FeedService(this.client);
  final http.Client client;
  Future<FeedResult> load(List<FeedSource> sources) async {
    final warnings = <String>[];
    final groups = await Future.wait(
      sources.where((s) => s.enabled).map((s) async {
        try {
          return await _fetch(s, s.url);
        } catch (_) {
          if (s.fallbackUrl != null) {
            try {
              final items = await _fetch(s, s.fallbackUrl!);
              warnings.add('${s.name}: arXiv 대체 피드를 사용하고 있어요.');
              return items;
            } catch (_) {
              /* Report the source without exposing remote error bodies. */
            }
          }
          warnings.add('${s.name} 피드를 불러오지 못했어요.');
          return <Article>[];
        }
      }),
    );
    final byId = <String, Article>{};
    for (final a in groups.expand((g) => g)) {
      byId.putIfAbsent(a.id, () => a);
    }
    final items = byId.values.toList()
      ..sort(
        (a, b) => (b.published ?? DateTime(1970)).compareTo(
          a.published ?? DateTime(1970),
        ),
      );
    return FeedResult(items.take(10).toList(), warnings);
  }

  Future<List<Article>> _fetch(FeedSource source, String url) async {
    if (!isSafeWebUrl(url)) throw const FormatException('HTTPS feed required');
    // Validate redirects as well, rather than forwarding to arbitrary schemes/hosts.
    var uri = Uri.parse(url);
    for (var hop = 0; hop < 4; hop++) {
      final request = http.Request('GET', uri)..followRedirects = false;
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 15));
      if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
        final location = response.headers['location'];
        await response.stream.drain<void>();
        if (location == null) throw const FormatException('Missing redirect');
        uri = uri.resolve(location);
        if (!isSafeWebUrl(uri.toString())) {
          throw const FormatException('Unsafe redirect');
        }
        continue;
      }
      if (response.statusCode != 200) {
        await response.stream.drain<void>();
        throw const HttpException('Feed unavailable');
      }
      final bytes = <int>[];
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 15),
      )) {
        bytes.addAll(chunk);
        if (bytes.length > 2 * 1024 * 1024) {
          throw const FormatException('Feed too large');
        }
      }
      final articles = parseFeed(utf8.decode(bytes), source, uri);
      if (articles.isEmpty) throw const FormatException('No feed entries');
      return articles;
    }
    throw const FormatException('Too many redirects');
  }
}

String plainText(String raw) => raw
    .replaceAll(RegExp(r'<[^>]*>'), ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&nbsp;', ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

List<Article> parseFeed(String raw, FeedSource source, [Uri? base]) {
  final doc = XmlDocument.parse(raw);
  String field(XmlElement e, List<String> names) {
    for (final name in names) {
      final matches = e.childElements.where((c) => c.name.local == name);
      if (matches.isNotEmpty) return matches.first.innerText.trim();
    }
    return '';
  }

  DateTime? date(String raw) {
    try {
      return DateTime.parse(raw);
    } catch (_) {
      try {
        return HttpDate.parse(raw);
      } catch (_) {
        return null;
      }
    }
  }

  return doc.descendants
      .whereType<XmlElement>()
      .where((e) => e.name.local == 'item' || e.name.local == 'entry')
      .take(30)
      .map((e) {
        var link = '';
        for (final node in e.childElements.where(
          (c) => c.name.local == 'link',
        )) {
          final rel = node.getAttribute('rel');
          if (rel == null || rel == 'alternate') {
            link = node.getAttribute('href') ?? node.innerText.trim();
            if (link.isNotEmpty) break;
          }
        }
        if (link.isNotEmpty) {
          link = (base ?? Uri.parse(source.url)).resolve(link).toString();
        }
        final excerpt = plainText(
          field(e, ['description', 'summary', 'encoded', 'content']),
        );
        return Article(
          id: link,
          title: plainText(field(e, ['title'])),
          link: link,
          excerpt: excerpt.length > 3500 ? excerpt.substring(0, 3500) : excerpt,
          source: source,
          published: date(
            field(e, ['pubDate', 'published', 'updated', 'date']),
          ),
        );
      })
      .where((a) => a.title.isNotEmpty && isSafeWebUrl(a.link))
      .toList();
}
