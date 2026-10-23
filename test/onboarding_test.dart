import 'package:ai_briefing/main.dart';
import 'package:ai_briefing/services/local_store.dart';
import 'package:ai_briefing/state/app_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EmptyKeyStore extends LocalStore {
  EmptyKeyStore(super.prefs);
  @override
  Future<String?> readKey() async => null;
}

void main() {
  testWidgets(
    'New users see three onboarding pages and can enter a key manually',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = EmptyKeyStore(await SharedPreferences.getInstance());
      await tester.pumpWidget(
        ProviderScope(
          overrides: [storeProvider.overrideWithValue(store)],
          child: const BriefingApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('AI의 오늘을,\n내 언어로 읽어요.'), findsOneWidget);
      await tester.tap(find.text('다음'));
      await tester.pumpAndSettle();
      expect(find.text('구글 무료 AI 열쇠 받으러 가기'), findsOneWidget);
      await tester.tap(find.text('다음'));
      await tester.pumpAndSettle();
      expect(find.text('클립보드에서 열쇠 붙여넣기'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'invalid');
      await tester.ensureVisible(find.text('열쇠 확인하고 시작하기'));
      await tester.tap(find.text('열쇠 확인하고 시작하기'));
      await tester.pumpAndSettle();
      expect(find.text('AIza로 시작하는 열쇠를 빠짐없이 복사해 주세요.'), findsOneWidget);
      expect(find.text('시작하기 3/3'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
