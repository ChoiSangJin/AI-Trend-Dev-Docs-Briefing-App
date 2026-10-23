import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../main.dart';
import '../state/app_controller.dart';
import '../services/gemini_service.dart';
import '../widgets/common.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});
  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final pages = PageController();
  final keyInput = TextEditingController();
  int step = 0;
  bool busy = false, reveal = false;
  String? error;
  @override
  void dispose() {
    pages.dispose();
    keyInput.clear();
    keyInput.dispose();
    super.dispose();
  }

  Future<void> paste() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (!mounted) return;
      keyInput.text = data?.text?.trim() ?? '';
      setState(
        () => error = keyInput.text.isEmpty ? 'API 키를 복사해서 가져오세요.' : null,
      );
    } catch (_) {
      if (mounted) setState(() => error = '붙여넣기가 어려우면 API 키를 직접 입력해 주세요.');
    }
  }

  Future<void> register() async {
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref.read(controllerProvider).registerKey(keyInput.text);
    } on BriefingException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = 'API 키를 안전하게 저장하지 못했어요. 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget card({
    required IconData icon,
    required String eyebrow,
    required String title,
    required String body,
    required List<Widget> children,
  }) => SingleChildScrollView(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            color: const Color(0xFFFFE4D4),
            borderRadius: BorderRadius.circular(28),
          ),
          child: Icon(icon, size: 42, color: accent),
        ),
        const SizedBox(height: 28),
        Text(
          eyebrow,
          style: const TextStyle(
            color: accent,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.3,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          title,
          style: const TextStyle(
            fontSize: 32,
            height: 1.25,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          body,
          style: const TextStyle(
            fontSize: 16,
            height: 1.65,
            color: Color(0xFF52666A),
          ),
        ),
        const SizedBox(height: 28),
        ...children,
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  children: [
                    const Icon(Icons.auto_awesome, color: accent),
                    const SizedBox(width: 10),
                    const Text(
                      'AI 모닝 브리핑',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const Spacer(),
                    Text(
                      '시작하기 ${step + 1}/3',
                      style: const TextStyle(color: Color(0xFF52666A)),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: PageView(
                  controller: pages,
                  onPageChanged: (i) => setState(() => step = i),
                  children: [
                    card(
                      icon: Icons.wb_sunny_outlined,
                      eyebrow: '하루 3분, 새로운 시야',
                      title: 'AI의 오늘을,\n내 언어로 읽어요.',
                      body: '복잡한 해외 소식도 한국어 세 줄로. 서버나 광고 없이, 구글에서 받은 개인 Gemini API 키를 기기에 안전하게 보관해요.',
                      children: [
                        const SoftPanel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '작게 시작하는 매일의 습관',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 17,
                                ),
                              ),
                              SizedBox(height: 12),
                              Text(
                                '✓ 공식 소식과 개발 문서를 한곳에\n✓ 세 줄 요약과 쉬운 용어 풀이\n✓ 매일 알림과 나만의 연속 기록',
                                style: TextStyle(height: 2),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          '구글의 무료 제공량 안에서 사용할 수 있어요. 제공 조건과 사용 한도는 구글 정책에 따라 달라질 수 있어요.',
                          style: TextStyle(fontSize: 12, height: 1.6),
                        ),
                      ],
                    ),
                    card(
                      icon: Icons.vpn_key_outlined,
                      eyebrow: 'API 키 준비하기',
                      title: 'API 키를 복사해서\n가져오세요.',
                      body: 'Google AI Studio에서 API 키를 복사해서 가져오세요. 돌아오면 바로 이어서 등록할 수 있어요.',
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () => openWeb(
                              context,
                              'https://aistudio.google.com/app/apikey',
                            ),
                            icon: const Icon(Icons.open_in_new),
                            label: const Text('Google AI Studio 열기'),
                          ),
                        ),
                        const SizedBox(height: 20),
                        const SoftPanel(
                          child: Text(
                            '1. 구글 계정으로 로그인하세요.\n\n2. “Create API key” 버튼을 누르세요.\n\n3. 생성된 API 키 옆 복사 아이콘을 누르고, 닫기(X) 또는 뒤로가기로 돌아오세요.',
                            style: TextStyle(height: 1.6),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          '화면과 버튼 이름은 구글에서 변경할 수 있어요.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                    card(
                      icon: Icons.lock_outline,
                      eyebrow: '안전하게 연결하기',
                      title: 'API 키를 붙여넣고,\n브리핑을 열어보세요.',
                      body: 'API 키가 잘 작동하는지 확인한 뒤, 이 기기의 보안 저장소에만 보관해요.',
                      children: [
                        OutlinedButton.icon(
                          onPressed: busy ? null : paste,
                          icon: const Icon(Icons.content_paste),
                          label: const Text('클립보드에서 API 키 붙여넣기'),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: keyInput,
                          obscureText: !reveal,
                          autocorrect: false,
                          enableSuggestions: false,
                          enableIMEPersonalizedLearning: false,
                          onChanged: (_) {
                            if (error != null) setState(() => error = null);
                          },
                          decoration: InputDecoration(
                            labelText: 'Gemini API 키',
                            hintText: '복사한 API 키를 붙여넣으세요',
                            suffixIcon: IconButton(
                              tooltip: reveal ? 'API 키 가리기' : 'API 키 보기',
                              onPressed: () => setState(() => reveal = !reveal),
                              icon: Icon(
                                reveal
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (error != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Text(
                              error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: busy ? null : register,
                            child: busy
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('API 키 확인하고 시작하기'),
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          '요약을 요청하면 선택된 소식의 제목·발췌문과 API 키가 구글로 전송돼요. Google AI Studio 무료 제공 서비스의 데이터 이용 정책을 확인해 주세요. 이 앱의 별도 서버로는 전송하지 않아요.',
                          style: TextStyle(fontSize: 12, height: 1.6),
                        ),
                        TextButton(
                          onPressed: () => openWeb(
                            context,
                            'https://ai.google.dev/gemini-api/terms',
                          ),
                          child: const Text('구글 이용·데이터 정책 보기'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  children: [
                    for (var i = 0; i < 3; i++)
                      Container(
                        margin: const EdgeInsets.only(right: 7),
                        width: i == step ? 26 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: i == step ? accent : const Color(0xFFCFD6CE),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    const Spacer(),
                    if (step > 0)
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => pages.previousPage(
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeOut,
                              ),
                        child: const Text('이전'),
                      ),
                    if (step < 2)
                      FilledButton(
                        onPressed: () => pages.nextPage(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut,
                        ),
                        child: const Text('다음'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
