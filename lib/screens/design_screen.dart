import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../main.dart';
import '../state/app_controller.dart';
import '../widgets/common.dart';
import 'home_screen.dart';

class DesignScreen extends ConsumerWidget {
  const DesignScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(controllerProvider);
    return RefreshIndicator(
      onRefresh: app.refreshDesign,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 28),
        children: [
          Row(
            children: [
              const Icon(Icons.palette_outlined, color: accent),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '디자인·UI/UX',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: '새 소식 불러오기',
                onPressed: app.designLoading || app.designSummarizing
                    ? null
                    : app.refreshDesign,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${app.designArticles.length}개의 소식 · UI/UX 원리와 디자인 실무',
            style: const TextStyle(color: Color(0xFF60716D)),
          ),
          const SizedBox(height: 20),
          if (app.designLoading || app.designSummarizing)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      app.designLoading
                          ? '디자인 소식을 모으고 있어요…'
                          : 'AI 요약 요청 간격에 맞춰 기다리거나 요약하고 있어요…',
                    ),
                  ),
                ],
              ),
            ),
          if (app.designMessage != null)
            SoftPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(app.designMessage!),
                  TextButton(
                    onPressed: app.designSummarizing
                        ? null
                        : app.summarizeDesign,
                    child: const Text('요약 다시 시도'),
                  ),
                ],
              ),
            ),
          if (app.designWarnings.isNotEmpty)
            ExpansionTile(
              title: Text('일부 소스 안내 (${app.designWarnings.length})'),
              children: [
                for (final warning in app.designWarnings)
                  ListTile(title: Text(warning)),
              ],
            ),
          if (app.designArticles.isEmpty && !app.designLoading)
            const SoftPanel(
              child: Text('아직 도착한 디자인 소식이 없어요. 설정에서 소스를 확인하거나 새로고침해 주세요.'),
            ),
          for (final article in app.designArticles)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: ArticleCard(
                article: article,
                briefing: article.canSummarize ? app.cache[article.id] : null,
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
