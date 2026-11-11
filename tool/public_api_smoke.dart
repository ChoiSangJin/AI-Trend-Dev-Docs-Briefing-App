import 'dart:io';

import 'package:ai_briefing/constants/feed_sources.dart';
import 'package:ai_briefing/services/feed_service.dart';
import 'package:http/io_client.dart';

Future<void> main() async {
  final io = HttpClient()..findProxy = HttpClient.findProxyFromEnvironment;
  final client = IOClient(io);
  const ids = {
    'xai-sdk',
    'langchain-releases',
    'papers',
    'hf-models',
    'google-genai-sdk',
    'ollama-releases',
    'vllm-releases',
    'transformers-releases',
  };
  try {
    final service = FeedService(client);
    final sources = defaultFeedSources
        .where((s) => ids.contains(s.id))
        .toList();
    for (final source in sources) {
      final result = await service.load([source]);
      if (result.warnings.isNotEmpty || result.articles.isEmpty) {
        stderr.writeln(
          'Public API smoke failed for ${source.id}: ${result.warnings}',
        );
        exitCode = 1;
        return;
      }
    }
    final combined = await service.load(sources);
    if (combined.articles.length > 10) {
      throw StateError('Briefing limit exceeded');
    }
    stdout.writeln(
      'Verified ${sources.length} API sources individually; ${combined.articles.length} selected, ${combined.articles.where((a) => a.canSummarize).length} eligible for summary.',
    );
  } finally {
    client.close();
  }
}
