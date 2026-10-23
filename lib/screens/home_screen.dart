import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../main.dart';
import '../models/briefing.dart';
import '../state/app_controller.dart';
import '../widgets/common.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String category = '전체';
  @override
  Widget build(BuildContext context) {
    final app = ref.watch(controllerProvider);
    final now = DateTime.now();
    final categories = [
      '전체',
      '공식 업데이트',
      '리서치 & 인사이트',
      if (app.sources.any((s) => s.custom)) '내 피드',
    ];
    final articles = app.articles
        .where((a) => category == '전체' || a.source.category == category)
        .toList();
    return RefreshIndicator(
      onRefresh: app.refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: accent, size: 22),
              const SizedBox(width: 8),
              const Text(
                'AI 모닝 브리핑',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const Spacer(),
              IconButton(
                tooltip: '새 소식 불러오기',
                onPressed: app.loading || app.summarizing ? null : app.refresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            '${now.month}월 ${now.day}일 · 오늘의 시야를 넓히는 시간',
            style: const TextStyle(
              color: Color(0xFF60716D),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            '세상은 빠르게,\n나는 세 줄로.',
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w800,
              height: 1.25,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '새로운 AI 소식부터 개발 문서까지, 가볍게 읽어요.',
            style: TextStyle(color: Color(0xFF60716D), height: 1.6),
          ),
          const SizedBox(height: 24),
          SoftPanel(
            color: const Color(0xFF1F4E46),
            child: Row(
              children: [
                const Text('🔥', style: TextStyle(fontSize: 32)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '연속 ${app.streak.days}일째 AI 트렌드 학습 중!',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        '작은 호기심이 내일의 차이를 만들어요.',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              const Text(
                '오늘의 브리핑',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              Text(
                '${app.articles.length}개의 소식',
                style: const TextStyle(color: Color(0xFF60716D), fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (app.articles.isNotEmpty) ...[
            Text(
              '${app.articles.map((a) => a.source.id).toSet().length}개 출처의 최신 소식을 골랐어요.',
              style: const TextStyle(color: Color(0xFF60716D), fontSize: 12),
            ),
            const SizedBox(height: 8),
          ],
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final item in categories)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(item),
                      selected: category == item,
                      onSelected: (_) => setState(() => category = item),
                    ),
                  ),
              ],
            ),
          ),
          if (app.loading || app.summarizing)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      app.loading
                          ? '새 소식을 모으고 있어요…'
                          : 'Google AI가 소식을 정리하고 있어요. 최대 2분 정도 걸릴 수 있어요…',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          if (app.message != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: SoftPanel(
                color: const Color(0xFFFFECDC),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(app.message!, style: const TextStyle(height: 1.5)),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: app.summarizing || app.loading
                          ? null
                          : app.summarize,
                      child: const Text('요약 다시 시도'),
                    ),
                  ],
                ),
              ),
            ),
          if (app.warnings.isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(
                '일부 소스 안내 (${app.warnings.length})',
                style: const TextStyle(fontSize: 13),
              ),
              children: [
                for (final warning in app.warnings)
                  ListTile(
                    dense: true,
                    title: Text(warning, style: const TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          const SizedBox(height: 12),
          if (articles.isEmpty && !app.loading)
            SoftPanel(
              child: Column(
                children: [
                  const Icon(Icons.rss_feed, size: 40, color: accent),
                  const SizedBox(height: 16),
                  Text(
                    app.sources.every((s) => !s.enabled)
                        ? '켜진 소스가 없어요'
                        : '아직 도착한 소식이 없어요',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '설정에서 소스를 켜거나, 아래로 당겨 다시 불러와 주세요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(height: 1.6),
                  ),
                ],
              ),
            ),
          for (final article in articles)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: ArticleCard(
                article: article,
                briefing: app.cache[article.id],
                read: app.readIds.contains(article.id),
                onTap: () async {
                  await app.markRead(article.id);
                  if (!context.mounted) return;
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ArticleScreen(article: article),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 10),
          const Text(
            'AI 요약은 피드 발췌문을 바탕으로 작성돼요. 중요한 내용은 원문에서 확인해 주세요.',
            style: TextStyle(
              fontSize: 11,
              color: Color(0xFF60716D),
              height: 1.7,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class ArticleCard extends StatelessWidget {
  const ArticleCard({
    required this.article,
    required this.briefing,
    required this.read,
    required this.onTap,
    super.key,
  });
  final Article article;
  final Briefing? briefing;
  final bool read;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(22),
    child: InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    article.source.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
                if (read)
                  const Icon(
                    Icons.check_circle_outline,
                    size: 16,
                    color: Color(0xFF28645C),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              briefing?.title ?? article.title,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 20,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            if (briefing != null) ...[
              for (var i = 0; i < briefing!.lines.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '0${i + 1}',
                        style: const TextStyle(
                          color: accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          briefing!.lines[i],
                          style: const TextStyle(
                            fontSize: 13,
                            height: 1.7,
                            color: Color(0xFF52666A),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: canvas,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '💡 ${briefing!.term}',
                  style: const TextStyle(fontSize: 12, height: 1.6),
                ),
              ),
            ] else
              Text(
                article.excerpt.isEmpty
                    ? '아직 AI 요약이 없어요. 원문을 먼저 확인할 수 있어요.'
                    : article.excerpt,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.7,
                  color: Color(0xFF60716D),
                ),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  briefing == null ? '원문 미리보기' : 'AI 세 줄 요약',
                  style: const TextStyle(
                    color: Color(0xFF60716D),
                    fontSize: 11,
                  ),
                ),
                const Spacer(),
                const Text(
                  '자세히 읽기',
                  style: TextStyle(
                    color: accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 5),
                const Icon(Icons.arrow_forward, size: 16, color: accent),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class ArticleScreen extends ConsumerWidget {
  const ArticleScreen({required this.article, super.key});
  final Article article;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final briefing = ref.watch(controllerProvider).cache[article.id];
    return Scaffold(
      appBar: AppBar(title: Text(article.source.name)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                briefing?.title ?? article.title,
                style: const TextStyle(
                  fontSize: 28,
                  height: 1.4,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 24),
              if (briefing != null) ...[
                for (final line in briefing.lines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: Text(
                      '• $line',
                      style: const TextStyle(fontSize: 17, height: 1.8),
                    ),
                  ),
                SoftPanel(
                  child: Text(
                    '💡 ${briefing.term}',
                    style: const TextStyle(height: 1.7),
                  ),
                ),
                const SizedBox(height: 24),
              ],
              if (article.excerpt.isNotEmpty) ...[
                const Text(
                  '피드 발췌문',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                SelectableText(
                  article.excerpt,
                  style: const TextStyle(height: 1.8, color: Color(0xFF52666A)),
                ),
                const SizedBox(height: 24),
              ],
              FilledButton.icon(
                onPressed: () => openWeb(context, article.link),
                icon: const Icon(Icons.open_in_new),
                label: const Text('원문에서 확인하기'),
              ),
              const SizedBox(height: 16),
              const Text(
                'AI는 실수할 수 있어요. 피드에 없는 내용은 요약에 포함되지 않을 수 있어요.',
                style: TextStyle(fontSize: 12, height: 1.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
