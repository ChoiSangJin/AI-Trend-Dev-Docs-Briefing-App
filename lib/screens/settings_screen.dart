import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../main.dart';
import '../state/app_controller.dart';
import '../widgets/common.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});
  Future<void> _run(
    BuildContext context,
    Future<void> Function() operation, {
    String? success,
  }) async {
    try {
      await operation();
      if (context.mounted && success != null) showMessage(context, success);
    } catch (e) {
      if (context.mounted) {
        showMessage(
          context,
          e.toString().startsWith('Exception')
              ? '변경하지 못했어요. 다시 시도해 주세요.'
              : e.toString(),
        );
      }
    }
  }

  Future<void> addFeed(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController(), url = TextEditingController();
    String? error;
    bool busy = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('내 피드 추가'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: '이름 (선택)'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: url,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'RSS / Atom 주소',
                    hintText: 'https://…',
                  ),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(context),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      setState(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        await ref
                            .read(controllerProvider)
                            .addSource(name.text, url.text.trim());
                        if (context.mounted) Navigator.pop(context);
                      } catch (e) {
                        if (context.mounted) {
                          setState(() {
                            error = e.toString();
                            busy = false;
                          });
                        }
                      }
                    },
              child: const Text('추가'),
            ),
          ],
        ),
      ),
    );
    // Wait until the route has stopped using its fields before disposing controllers.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    name.dispose();
    url.dispose();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(controllerProvider);
    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        const SizedBox(height: 12),
        const Text(
          '나에게 맞는\n브리핑 습관.',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          '알림부터 소스까지, 내 리듬대로 설정해요.',
          style: TextStyle(color: Color(0xFF60716D)),
        ),
        const SizedBox(height: 28),
        const Text(
          '매일의 작은 약속',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        const SizedBox(height: 12),
        SoftPanel(
          child: Column(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('매일 브리핑 알림'),
                subtitle: const Text(
                  '정확한 알림 권한이 없으면 대략적인 시간에 알려드려요.',
                  style: TextStyle(fontSize: 12),
                ),
                value: app.remindersEnabled,
                onChanged: (value) => _run(
                  context,
                  () => app.setReminder(value, app.reminderTime),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule, color: accent),
                title: const Text('알림 시간'),
                trailing: Text(
                  app.reminderTime.format(context),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                onTap: () async {
                  final time = await showTimePicker(
                    context: context,
                    initialTime: app.reminderTime,
                  );
                  if (time != null && context.mounted) {
                    await _run(
                      context,
                      () => app.setReminder(app.remindersEnabled, time),
                    );
                  }
                },
              ),
              const Text(
                '알림은 직접 켠 뒤 동작해요. 기기 재부팅 시 예약을 복원하며, 시간대를 바꿨다면 앱을 다시 열어 주세요.',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.6,
                  color: Color(0xFF60716D),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        Row(
          children: [
            const Text(
              '내가 읽을 소스',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () => addFeed(context, ref),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('피드 추가'),
            ),
          ],
        ),
        const Text(
          '소스를 변경한 뒤 오늘의 브리핑에서 새로고침해 주세요. 공개 API 소스는 호출 한도를 위해 최대 15분 간격으로 갱신해요.',
          style: TextStyle(fontSize: 12, height: 1.6, color: Color(0xFF60716D)),
        ),
        const SizedBox(height: 12),
        SoftPanel(
          child: Column(
            children: [
              for (final source in app.sources)
                Row(
                  children: [
                    Expanded(
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          source.name,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          source.id == 'papers'
                              ? '커뮤니티 피드 · 실패 시 arXiv'
                              : source.category,
                          style: const TextStyle(fontSize: 11),
                        ),
                        value: source.enabled,
                        onChanged: (value) =>
                            _run(context, () => app.setSource(source, value)),
                      ),
                    ),
                    if (source.custom)
                      IconButton(
                        tooltip: '피드 삭제',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () =>
                            _run(context, () => app.removeSource(source)),
                      ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        const Text(
          'API 키와 데이터',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        const SizedBox(height: 12),
        SoftPanel(
          child: Column(
            children: [
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.lock_outline, color: accent),
                title: Text('Gemini API 키 연결됨'),
                subtitle: Text(
                  '이 기기의 보안 저장소에 암호화 보관',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('API 키 삭제하고 다시 연결'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('API 키를 삭제할까요?'),
                      content: const Text(
                        '기기에 저장한 API 키를 지우고 시작 안내로 돌아가요. 요약과 학습 기록은 유지돼요.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('취소'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('삭제'),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true && context.mounted) {
                    await _run(context, app.forgetKey);
                  }
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('요약 캐시 비우기'),
                subtitle: Text(
                  '${app.cache.length}개 저장됨 · 다시 요약하면 무료 사용량이 소모돼요',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: const Icon(Icons.delete_outline),
                onTap: app.summarizing
                    ? null
                    : () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('저장된 요약을 비울까요?'),
                            content: const Text(
                              '삭제한 요약은 복구할 수 없어요. 연속 기록과 API 키는 유지돼요.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('취소'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('비우기'),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true && context.mounted) {
                          await _run(
                            context,
                            app.clearCache,
                            success: '요약 캐시를 비웠어요.',
                          );
                        }
                      },
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          '로그인도, 별도 서버도 없어요.\n요약할 때만 구글 AI로 제목과 발췌문을 보내요. 무료 제공량과 지역별 이용 조건은 구글 정책을 따라요.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, height: 1.8, color: Color(0xFF60716D)),
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: () =>
                openWeb(context, 'https://ai.google.dev/gemini-api/terms'),
            child: const Text('구글 이용·데이터 정책'),
          ),
        ),
        const Center(
          child: Text(
            'AI 모닝 브리핑 · 1.0.8',
            style: TextStyle(fontSize: 11, color: Color(0xFF60716D)),
          ),
        ),
        const SizedBox(height: 18),
      ],
    );
  }
}
