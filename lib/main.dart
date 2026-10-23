import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/local_store.dart';
import 'state/app_controller.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/settings_screen.dart';

const ink = Color(0xFF182D32);
const accent = Color(0xFFE76A42);
const canvas = Color(0xFFF7F7F0);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final prefs = await SharedPreferences.getInstance();
    runApp(
      ProviderScope(
        overrides: [storeProvider.overrideWithValue(LocalStore(prefs))],
        child: const BriefingApp(),
      ),
    );
  } catch (_) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('기기 저장소를 열지 못했어요.'),
                TextButton(onPressed: main, child: const Text('다시 시도')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class BriefingApp extends StatelessWidget {
  const BriefingApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'AI 모닝 브리핑',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: canvas,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        primary: accent,
        secondary: const Color(0xFF28645C),
        surface: canvas,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: canvas,
        foregroundColor: ink,
        centerTitle: false,
      ),
      textTheme: ThemeData.light().textTheme.apply(
        bodyColor: ink,
        displayColor: ink,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 17),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    ),
    home: const AppShell(),
  );
}

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});
  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver {
  int selected = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(controllerProvider).visit();
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(controllerProvider);
    if (!app.initialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (app.startupError != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(app.startupError!),
                TextButton(
                  onPressed: app.initialize,
                  child: const Text('다시 시도'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (!app.hasKey) return const OnboardingScreen();
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: selected == 0 ? const HomeScreen() : const SettingsScreen(),
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selected,
        onDestinationSelected: (value) => setState(() => selected = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.wb_sunny_outlined),
            selectedIcon: Icon(Icons.wb_sunny),
            label: '오늘의 브리핑',
          ),
          NavigationDestination(icon: Icon(Icons.tune), label: '내 설정'),
        ],
      ),
    );
  }
}
