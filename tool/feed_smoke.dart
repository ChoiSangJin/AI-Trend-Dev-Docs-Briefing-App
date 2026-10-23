import 'dart:io';

import 'package:http/io_client.dart';
import 'package:ai_briefing/constants/feed_sources.dart';
import 'package:ai_briefing/services/feed_service.dart';

// Read-only live check. The app itself uses the device's normal network route.
Future<void> main() async {
  final io = HttpClient()..findProxy = HttpClient.findProxyFromEnvironment;
  final client = IOClient(io);
  try {
    final result = await FeedService(client).load([
      defaultFeedSources.firstWhere((s) => s.id == 'openai-sdk'),
      defaultFeedSources.firstWhere((s) => s.id == 'anthropic-sdk'),
    ]);
    if (result.articles.isEmpty || result.warnings.isNotEmpty) {
      stderr.writeln(
        'Live feed smoke check failed: ${result.warnings.join('; ')}',
      );
      exitCode = 1;
      return;
    }
    stdout.writeln('Parsed ${result.articles.length} live SDK releases.');
    for (final article in result.articles.take(2)) {
      stdout.writeln('${article.source.name}: ${article.title}');
    }
  } finally {
    client.close();
  }
}
