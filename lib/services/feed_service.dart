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
  FeedService(this.client, {DateTime Function()? clock})
    : clock = clock ?? DateTime.now;
  final http.Client client;
  final DateTime Function() clock;
  final Map<String, DateTime> _retryAt = {};
  final Map<String, ({DateTime fetched, List<Article> articles})> _apiCache =
      {};
  final Map<String, DateTime> _apiPause = {};
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
    if (!source.custom &&
        url == source.url &&
        const [
          'github',
          'hn',
          'dev',
          'hf',
          'stack',
          'arxiv',
        ].contains(source.format)) {
      final cached = _apiCache[source.url];
      if (cached != null &&
          clock().difference(cached.fetched) < const Duration(minutes: 15)) {
        return cached.articles;
      }
      final paused = _apiPause[source.url];
      if (paused != null && paused.isAfter(clock())) {
        throw const _FeedFailure('API 서버 대기 지침·할당량에 따라 잠시 요청을 쉬고 있어요');
      }
      final result = await _loadApi(source);
      _apiCache[source.url] = (fetched: clock(), articles: result);
      return result;
    }
    final response = await _fetchBytes(source, url);
    return parseFeed(utf8.decode(response.bytes), source, response.uri);
  }

  Future<({List<int> bytes, Uri uri})> _fetchBytes(
    FeedSource source,
    String url, {
    bool json = false,
  }) async {
    if (!isSafeWebUrl(url)) throw const FormatException('HTTPS feed required');
    final retryAt = _retryAt[url];
    if (retryAt != null && retryAt.isAfter(clock())) {
      final seconds = (retryAt.difference(clock()).inMilliseconds / 1000)
          .ceil();
      throw _FeedFailure('HTTP 429 · 서버 요청 제한으로 $seconds초 후 다시 시도할 수 있어요');
    }
    // Long-form newsletters can exceed 2MB. Keep a bounded exception for the
    // built-in source; other sources retain the existing limit.
    final limitMB = !source.custom && source.id == 'ahead-ai' ? 8 : 2;
    // Validate redirects as well, rather than forwarding to arbitrary schemes/hosts.
    var uri = Uri.parse(url);
    for (var hop = 0; hop < 4; hop++) {
      final request = http.Request('GET', uri)
        ..followRedirects = false
        ..headers.addAll({
          'Accept': json
              ? (uri.host == 'dev.to'
                    ? 'application/vnd.forem.api-v1+json'
                    : 'application/json')
              : 'application/atom+xml, application/rss+xml, application/xml, text/xml',
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
        if (json &&
            response.statusCode == 403 &&
            uri.host == 'api.github.com' &&
            response.headers['x-ratelimit-remaining'] == '0') {
          final reset = int.tryParse(
            response.headers['x-ratelimit-reset'] ?? '',
          );
          final seconds = reset == null
              ? 3600
              : reset - clock().millisecondsSinceEpoch ~/ 1000;
          _apiPause[source.url] = clock().add(
            Duration(seconds: seconds.clamp(60, 86400)),
          );
          throw const _FeedFailure('HTTP 403 · GitHub 무료 API 호출 한도에 도달했어요');
        }
        if (response.statusCode == 429) {
          final value = response.headers['retry-after'] ?? '';
          final now = clock();
          var seconds = int.tryParse(value);
          if (seconds == null) {
            try {
              seconds = HttpDate.parse(value).difference(now).inSeconds;
            } catch (_) {
              seconds = 300;
            }
          }
          final wait = seconds.clamp(60, 86400);
          _retryAt[url] = now.add(Duration(seconds: wait));
          if (json) _retryAt[source.url] = _retryAt[url]!;
          throw _FeedFailure('HTTP 429 · 서버 요청 제한으로 $wait초 후 다시 시도할 수 있어요');
        }
        throw HttpException('HTTP ${response.statusCode}');
      }
      final bytes = <int>[];
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 15),
      )) {
        bytes.addAll(chunk);
        if (bytes.length > limitMB * 1024 * 1024) {
          throw _FeedFailure('피드 용량이 ${limitMB}MB 제한을 초과했어요');
        }
      }
      return (bytes: bytes, uri: uri);
    }
    throw const FormatException('Too many redirects');
  }

  Future<dynamic> _json(FeedSource source, String url) async => jsonDecode(
    utf8.decode((await _fetchBytes(source, url, json: true)).bytes),
  );

  Future<List<Article>> _loadApi(FeedSource source) async {
    const hosts = {
      'github': 'api.github.com',
      'hn': 'hacker-news.firebaseio.com',
      'dev': 'dev.to',
      'hf': 'huggingface.co',
      'stack': 'api.stackexchange.com',
      'arxiv': 'export.arxiv.org',
    };
    if (Uri.parse(source.url).host != hosts[source.format]) {
      throw const _FeedFailure('API 소스 주소가 올바르지 않아요');
    }
    if (source.format == 'arxiv') {
      final response = await _fetchBytes(source, source.url);
      return parseFeed(utf8.decode(response.bytes), source, response.uri);
    }
    final data = await _json(source, source.url);
    List<dynamic> rows;
    if (source.format == 'hn') {
      if (data is! List) throw const FormatException('Invalid HN list');
      final ids = data.whereType<int>().take(10).toList();
      rows = [];
      // Limit fan-out to five concurrent requests and 10 stories per refresh.
      for (var i = 0; i < ids.length; i += 5) {
        final batch = ids.skip(i).take(5);
        rows.addAll(
          await Future.wait(
            batch.map(
              (id) => _json(
                source,
                'https://hacker-news.firebaseio.com/v0/item/$id.json',
              ),
            ),
          ),
        );
      }
    } else if (source.format == 'stack') {
      if (data is! Map || data['items'] is! List) {
        throw const FormatException('Invalid question list');
      }
      final backoff = data['backoff'];
      if (backoff is num && backoff > 0) {
        _apiPause[source.url] = clock().add(
          Duration(seconds: backoff.toInt().clamp(1, 86400)),
        );
      }
      if (data['quota_remaining'] == 0) {
        _apiPause[source.url] = clock().add(const Duration(hours: 24));
      }
      rows = data['items'] as List;
    } else {
      if (data is! List) throw const FormatException('Invalid API list');
      rows = data;
    }
    String str(dynamic value) => value is String ? value : '';
    DateTime? timestamp(dynamic value) => value is num
        ? DateTime.fromMillisecondsSinceEpoch(value.toInt() * 1000, isUtc: true)
        : DateTime.tryParse(str(value));
    final result = <Article>[];
    for (final row in rows.take(30)) {
      if (row is! Map) continue;
      String title, link, excerpt;
      DateTime? published;
      switch (source.format) {
        case 'github':
          if (row['draft'] == true || row['prerelease'] == true) continue;
          title = str(row['name']).trim().isEmpty
              ? str(row['tag_name'])
              : str(row['name']);
          link = str(row['html_url']);
          excerpt = str(row['body']);
          published = timestamp(row['published_at']);
        case 'hn':
          title = str(row['title']);
          if (row['type'] != 'story' ||
              row['deleted'] == true ||
              row['dead'] == true) {
            continue;
          }
          if (row['id'] is! int) continue;
          link = 'https://news.ycombinator.com/item?id=${row['id']}';
          excerpt =
              'HN 항목 메타데이터 · ${row['score'] is num ? row['score'] : 0} 추천점 · ${row['descendants'] is num ? row['descendants'] : 0} 댓글. ${str(row['text'])}';
          published = timestamp(row['time']);
        case 'dev':
          title = str(row['title']);
          link = str(row['url']);
          excerpt = str(row['description']);
          published = timestamp(row['published_at']);
        case 'hf':
          final id = str(row['id']);
          if (!RegExp(
                r'^[A-Za-z0-9][A-Za-z0-9_.-]*(/[A-Za-z0-9][A-Za-z0-9_.-]*)?$',
              ).hasMatch(id) ||
              row['private'] == true) {
            continue;
          }
          title = '모델 정보 · $id';
          link = 'https://huggingface.co/$id';
          excerpt =
              '공개 모델 메타데이터. 다운로드 ${row['downloads'] is num ? row['downloads'] : 0}, 좋아요 ${row['likes'] is num ? row['likes'] : 0}. 새 릴리스나 성능 검증을 뜻하지 않습니다.';
          published = timestamp(row['createdAt']);
        case 'stack':
          title = str(row['title']);
          link = str(row['link']);
          excerpt =
              '커뮤니티 질문 메타데이터 · 추천 점수 ${row['score'] is num ? row['score'] : 0}, 답변 ${row['answer_count'] is num ? row['answer_count'] : 0}개. 질문 제목만 제공하며 답변 본문이나 검증된 해결책을 제공하는 것은 아닙니다.';
          published = timestamp(row['creation_date']);
        default:
          throw const FormatException('Unknown API format');
      }
      title = plainText(title);
      excerpt = plainText(excerpt);
      if (title.isEmpty || !isSafeWebUrl(link)) continue;
      result.add(
        Article(
          id: link,
          title: title,
          link: link,
          excerpt: String.fromCharCodes(excerpt.runes.take(3500)),
          source: source,
          published: published,
        ),
      );
    }
    return result;
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
          var resolved = (base ?? Uri.parse(source.url)).resolve(link);
          if (source.format == 'arxiv' &&
              resolved.scheme == 'http' &&
              resolved.host == 'arxiv.org') {
            resolved = resolved.replace(scheme: 'https');
          }
          link = resolved.toString();
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
