import 'package:ai_briefing/models/briefing.dart';
import 'package:ai_briefing/services/local_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Streak counts one visit per civil day, crosses months, and resets on gaps',
    () {
      var streak = const Streak(0, null).visit(DateTime(2026, 10, 31, 23));
      expect(streak.days, 1);
      streak = streak.visit(DateTime(2026, 10, 31, 23, 59));
      expect(streak.days, 1);
      streak = streak.visit(DateTime(2026, 11, 1));
      expect(streak.days, 2);
      streak = streak.visit(DateTime(2026, 11, 3));
      expect(streak.days, 1);
    },
  );
  test('Streak survives a year boundary and leap day', () {
    expect(const Streak(5, '2025-12-31').visit(DateTime(2026, 1, 1)).days, 6);
    expect(const Streak(5, '2028-02-28').visit(DateTime(2028, 2, 29)).days, 6);
  });
  test('Saved cache and read state survive reopening local storage', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = LocalStore(prefs);
    const briefing = Briefing(
      id: 'article',
      title: '제목',
      lines: ['하나', '둘', '셋'],
      term: '설명',
    );
    await store.saveCache({'article': briefing});
    await store.markRead('article');
    final reopened = LocalStore(prefs);
    expect(reopened.readCache()['article']?.lines, ['하나', '둘', '셋']);
    expect(reopened.readIds(), contains('article'));
    await reopened.visit(DateTime(2026, 10, 23));
    await reopened.visit(DateTime(2026, 10, 23, 23));
    expect(reopened.readStreak().days, 1);
  });
  test('Corrupt cache is discarded without losing source settings', () async {
    SharedPreferences.setMockInitialValues({'briefings': '{corrupt'});
    final store = LocalStore(await SharedPreferences.getInstance());
    expect(store.readCache(), isEmpty);
    final sources = store.readSources();
    expect(sources, hasLength(10));
    await store.saveSources([sources.first.withEnabled(false)]);
    expect(store.readSources().single.enabled, isFalse);
  });
  test('Cache remains bounded to the latest 500 summaries', () async {
    SharedPreferences.setMockInitialValues({});
    final store = LocalStore(await SharedPreferences.getInstance());
    await store.saveCache({
      for (var i = 0; i < 510; i++)
        '$i': Briefing(
          id: '$i',
          title: '제목',
          lines: ['1', '2', '3'],
          term: '용어',
        ),
    });
    expect(store.readCache(), hasLength(500));
    expect(store.readCache().containsKey('0'), isFalse);
    expect(store.readCache().containsKey('509'), isTrue);
  });
}
