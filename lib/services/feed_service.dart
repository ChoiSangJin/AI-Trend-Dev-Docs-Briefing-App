import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../models/briefing.dart';

class _FeedFailure implements Exception {
  const _FeedFailure(this.hint);
  final String hint;
}

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
        } catch (error) {
          if (s.fallbackUrl != null) {
            try {
              final items = await _fetch(s, s.fallbackUrl!);
              warnings.add('${s.name}: 대체 피드를 사용하고 있어요.');
              return items;
            } catch (_) {
              /* Report the source without exposing remote error bodies. */
            }
          }
          final hint = error is _FeedFailure
              ? error.hint
              : error is TimeoutException
              ? '시간 초과'
              : error is HttpException &&
                    RegExp(r'^HTTP \d{3}$').hasMatch(error.message)
              ? error.message
              : error is FormatException
              ? '피드 형식 오류'
              : '연결 오류';
          warnings.add('${s.name} 피드를 불러오지 못했어요. ($hint)');
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
    // Give every available source a place before taking a second article from
    // any source. A high-volume community feed must not crowd out official news.
    final bySource = <String, List<Article>>{};
    for (final item in items) {
      bySource.putIfAbsent(item.source.id, () => []).add(item);
    }
    final selected = <Article>[];
    for (var round = 0; selected.length < 10; round++) {
      var added = false;
      for (final group in bySource.values) {
        if (round < group.length) {
          selected.add(group[round]);
          added = true;
          if (selected.length == 10) break;
        }
      }
      if (!added) break;
    }
    return FeedResult(selected, warnings);
  }

  Future<List<Article>> _fetch(FeedSource source, String url) async {
    if (!isSafeWebUrl(url)) throw const FormatException('HTTPS feed required');
    // Validate redirects as well, rather than forwarding to arbitrary schemes/hosts.
    var uri = Uri.parse(url);
    for (var hop = 0; hop < 4; hop++) {
      final request = http.Request('GET', uri)
        ..followRedirects = false
        ..headers.addAll({
          'Accept': 'application/atom+xml, application/rss+xml, application/xml, text/xml',
          'User-Agent': 'AI-Morning-Briefing RSS Reader',
        });
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
        throw HttpException('HTTP ${response.statusCode}');
      }
      final bytes = <int>[];
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 15),
      )) {
        bytes.addAll(chunk);
        if (bytes.length > 2 * 1024 * 1024) {
          throw const _FeedFailure('피드 용량이 2MB 제한을 초과했어요');
        }
      }
      final articles = parseFeed(utf8.decode(bytes), source, uri);
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
  final root = doc.rootElement;
  final valid =
      root.name.local == 'feed' ||
      root.name.local == 'rss' ||
      (root.name.local == 'RDF' &&
          root.name.namespaceUri ==
              'http://www.w3.org/1999/02/22-rdf-syntax-ns#');
  if (!valid) throw const _FeedFailure('RSS/Atom 대신 다른 문서를 받았어요');
  String field(XmlElement e, List<String> names) {
    for (final name in names) {
      final matches = e.childElements.where((c) => c.name.local == name);
      if (matches.isNotEmpty && matches.first.innerText.trim().isNotEmpty) {
        return matches.first.innerText.trim();
      }
    }
    return '';
  }

  DateTime? date(String raw) {
    final iso = DateTime.tryParse(raw);
    if (iso != null) return iso;
    // HttpDate accepts HTTP's GMT dates, but RSS commonly uses RFC 822 numeric
    // offsets. Interpret the offset instead of dropping otherwise valid dates.
    final rss = RegExp(
      r'^(?:[A-Za-z]{3},?\s+)?(\d{1,2})\s+([A-Za-z]{3})\s+(\d{2}|\d{4})\s+(\d{2}):(\d{2})(?::(\d{2}))?\s+([+-])(\d{2}):?(\d{2})$',
    ).firstMatch(raw.trim());
    if (rss != null) {
      const months = [
        'jan',
        'feb',
        'mar',
        'apr',
        'may',
        'jun',
        'jul',
        'aug',
        'sep',
        'oct',
        'nov',
        'dec',
      ];
      final month = months.indexOf(rss.group(2)!.toLowerCase()) + 1;
      var year = int.parse(rss.group(3)!);
      if (year < 100) year += year < 50 ? 2000 : 1900;
      final hourOffset = int.parse(rss.group(8)!);
      final minuteOffset = int.parse(rss.group(9)!);
      if (month != 0 && hourOffset <= 23 && minuteOffset < 60) {
        final local = DateTime.utc(
          year,
          month,
          int.parse(rss.group(1)!),
          int.parse(rss.group(4)!),
          int.parse(rss.group(5)!),
          int.parse(rss.group(6) ?? '0'),
        );
        final offset = Duration(
          minutes:
              (hourOffset * 60 + minuteOffset) * (rss.group(7) == '+' ? 1 : -1),
        );
        return local.subtract(offset);
      }
    }
    try {
      return HttpDate.parse(raw);
    } catch (_) {
      return null;
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
