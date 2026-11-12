import 'dart:io';

import 'package:ai_briefing/constants/feed_sources.dart';
import 'package:ai_briefing/services/feed_service.dart';
import 'package:http/io_client.dart';

Future<void> main(List<String> args) async {
  final io = HttpClient()..findProxy = HttpClient.findProxyFromEnvironment;
  final client = IOClient(io);
  final service = FeedService(client);
  try {
    final requested = args.toSet();
    final sources = defaultFeedSources.where(
      (s) =>
          s.category == 'IT·개발' &&
          (requested.isEmpty || requested.contains(s.id)),
    );
    for (final source in sources) {
      final result = await service.load([source]);
      if (result.articles.isEmpty || result.warnings.isNotEmpty) {
        stderr.writeln('${source.name}: ${result.warnings}');
        exitCode = 1;
        continue;
      }
      stdout.writeln('${source.name}: ${result.articles.length}개 수집');
    }
  } finally {
    client.close();
  }
}
