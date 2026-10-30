class FeedSource {
  const FeedSource({
    required this.id,
    required this.name,
    required this.url,
    required this.category,
    this.fallbackUrl,
    this.enabled = true,
    this.custom = false,
    this.format = 'rss',
  });
  final String id, name, url, category;
  final String? fallbackUrl;
  final bool enabled, custom;
  final String format;
  FeedSource withEnabled(bool value) => FeedSource(
    id: id,
    name: name,
    url: url,
    category: category,
    fallbackUrl: fallbackUrl,
    enabled: value,
    custom: custom,
    format: format,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    'category': category,
    'fallbackUrl': fallbackUrl,
    'enabled': enabled,
    'custom': custom,
    'format': format,
  };
  factory FeedSource.fromJson(Map<String, dynamic> j) => FeedSource(
    id: j['id'] as String,
    name: j['name'] as String,
    url: j['url'] as String,
    category: j['category'] as String,
    fallbackUrl: j['fallbackUrl'] as String?,
    enabled: j['enabled'] as bool? ?? true,
    custom: j['custom'] as bool? ?? false,
    format: j['format'] as String? ?? 'rss',
  );
}

class Article {
  const Article({
    required this.id,
    required this.title,
    required this.link,
    required this.excerpt,
    required this.source,
    this.published,
  });
  final String id, title, link, excerpt;
  final FeedSource source;
  final DateTime? published;
}

class Briefing {
  const Briefing({
    required this.id,
    required this.title,
    required this.lines,
    required this.term,
  });
  final String id, title, term;
  final List<String> lines;
  factory Briefing.fromJson(Map<String, dynamic> j) {
    final lines = (j['summary_lines'] as List).cast<String>();
    final id = j['id'] as String;
    final title = j['ko_title'] as String;
    final term = j['term_explanation'] as String;
    if (id.isEmpty ||
        title.trim().isEmpty ||
        term.trim().isEmpty ||
        lines.length != 3 ||
        lines.any((s) => s.trim().isEmpty)) {
      throw const FormatException('Incomplete briefing');
    }
    return Briefing(
      id: id,
      title: title,
      lines: List.unmodifiable(lines),
      term: term,
    );
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'ko_title': title,
    'summary_lines': lines,
    'term_explanation': term,
  };
}

class Streak {
  const Streak(this.days, this.lastDay);
  final int days;
  final String? lastDay;
  static String dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  Streak visit(DateTime now) {
    final today = dayKey(now);
    if (today == lastDay) return this;
    final previous = DateTime.tryParse(lastDay ?? '');
    final gap = previous == null
        ? 0
        : DateTime.utc(now.year, now.month, now.day)
              .difference(
                DateTime.utc(previous.year, previous.month, previous.day),
              )
              .inDays;
    return Streak(gap == 1 ? days + 1 : 1, today);
  }
}
