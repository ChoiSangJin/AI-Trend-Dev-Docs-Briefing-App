import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../main.dart';
import '../state/app_controller.dart';
import '../widgets/common.dart';
import 'home_screen.dart';

class ItScreen extends ConsumerWidget {
  const ItScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(controllerProvider);
    return RefreshIndicator(
      onRefresh: app.refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 28),
        children: [
          Row(
            children: [
              const Icon(Icons.code, color: accent),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'IT·개발 소식',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: '새 소식 불러오기',
                onPressed: app.loading ? null : app.refresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${app.itArticles.length}개의 소식 · 기술 블로그와 개발자 공식 소식',
            style: const TextStyle(color: Color(0xFF60716D)),
          ),
          const SizedBox(height: 20),
          if (app.loading) const Center(child: CircularProgressIndicator()),
          if (app.itWarnings.isNotEmpty)
            ExpansionTile(
              title: Text('일부 소스 안내 (${app.itWarnings.length})'),
              children: [
                for (final warning in app.itWarnings)
                  ListTile(title: Text(warning)),
              ],
            ),
          if (app.itArticles.isEmpty && !app.loading)
            const SoftPanel(
              child: Text('아직 도착한 IT·개발 소식이 없어요. 설정에서 소스를 확인하거나 새로고침해 주세요.'),
            ),
          for (final article in app.itArticles)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: ArticleCard(
                article: article,
                briefing: null,
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
        ],
      ),
    );
  }
}
