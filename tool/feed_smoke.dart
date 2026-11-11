import 'dart:io';

import 'package:http/io_client.dart';
import 'package:ai_briefing/constants/feed_sources.dart';
import 'package:ai_briefing/services/feed_service.dart';

// Read-only live check. The app itself uses the device's normal network route.
Future<void> main() async {
  final io = HttpClient()..findProxy = HttpClient.findProxyFromEnvironment;
  final client = IOClient(io);
  const ids = {
    'google-developers',
    'deepmind',
    'openai',
    'openai-sdk',
    'anthropic-sdk',
    'claude-code',
    'xai-sdk',
  };
  try {
    final service = FeedService(client);
    for (final id in ids) {
      final source = defaultFeedSources.firstWhere((s) => s.id == id);
      final result = await service.load([source]);
      if (result.articles.isEmpty || result.warnings.isNotEmpty) {
        stderr.writeln('Official source $id failed: ${result.warnings}');
        exitCode = 1;
        return;
      }
      stdout.writeln('$id: ${result.articles.length} articles parsed');
    }
    stdout.writeln('Verified ${ids.length} official publisher sources.');
  } finally {
    client.close();
  }
}
