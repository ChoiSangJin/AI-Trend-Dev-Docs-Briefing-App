import 'package:ai_briefing/main.dart';
import 'package:ai_briefing/services/local_store.dart';
import 'package:ai_briefing/state/app_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      expect(find.text('Google AI Studio 열기'), findsOneWidget);
      expect(find.text('API 키를 복사해서\n가져오세요.'), findsOneWidget);
      await tester.tap(find.text('다음'));
      await tester.pumpAndSettle();
      expect(find.text('클립보드에서 API 키 붙여넣기'), findsOneWidget);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.getData') {
            return {'text': '  different-prefix-test-key  '};
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.tap(find.text('클립보드에서 API 키 붙여넣기'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'different-prefix-test-key',
      );
      expect(find.textContaining('AIza'), findsNothing);
      expect(find.text('API 키를 복사해서 가져오세요.'), findsNothing);
      await tester.enterText(find.byType(TextField), '   ');
      await tester.ensureVisible(find.text('API 키 확인하고 시작하기'));
      await tester.tap(find.text('API 키 확인하고 시작하기'));
      await tester.pumpAndSettle();
      expect(find.text('API 키를 복사해서 가져오세요.'), findsOneWidget);
      expect(find.text('시작하기 3/3'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
