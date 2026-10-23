import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/feed_service.dart';

void showMessage(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

Future<bool> openWeb(BuildContext context, String value) async {
  try {
    if (!isSafeWebUrl(value)) throw const FormatException();
    final uri = Uri.parse(value);
    var opened = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    if (!opened) {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    if (!opened) throw StateError('No browser');
    return true;
  } catch (_) {
    if (context.mounted) {
      showMessage(context, '페이지를 열 수 없어요. 브라우저와 인터넷 연결을 확인해 주세요.');
    }
    return false;
  }
}

class SoftPanel extends StatelessWidget {
  const SoftPanel({required this.child, this.color = Colors.white, super.key});
  final Widget child;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFFE4E8DF)),
    ),
    child: child,
  );
}
