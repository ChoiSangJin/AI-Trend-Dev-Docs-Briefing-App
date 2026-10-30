import 'dart:io';

import 'package:ai_briefing/constants/feed_sources.dart';
import 'package:ai_briefing/services/feed_service.dart';
import 'package:http/io_client.dart';

Future<void> main() async {
  final io = HttpClient()..findProxy = HttpClient.findProxyFromEnvironment;
  final client = IOClient(io);
  const ids = {'langchain-releases', 'papers', 'hf-models'};
  try {
    final result = await FeedService(client)
        .load(defaultFeedSources.where((s) => ids.contains(s.id)).toList());
    final found = result.articles.map((a) => a.source.id).toSet();
    if (result.warnings.isNotEmpty || !found.containsAll(ids)) {
      stderr.writeln(
        'Public API smoke failed: ${result.warnings}; received $found',
      );
      exitCode = 1;
      return;
    }
    stdout.writeln(
      'Verified GitHub releases, arXiv API and Hugging Face models: ${result.articles.length} selected entries.',
    );
  } finally {
    client.close();
  }
}
