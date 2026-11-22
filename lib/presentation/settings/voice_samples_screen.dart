import 'package:flutter/material.dart';

import '../../domain/entities/voice_samples.dart';
import '../../domain/repositories/repositories.dart';
import '../../service_locator.dart';

/// 설정 › 내 목소리 자료. 보호자 직접 녹음과 그 쪽 글이 얼마나 모였는지 보여 준다.
///
/// 왜 지금 만드나: 목소리 만들기(집 Mac, M3)보다 먼저 자료를 모아 두면 도구를 정하자마자 바로
/// 학습할 수 있다(2026-11-22 오너 결정). 이 화면은 세기만 하고 아무것도 기기 밖으로 보내지 않는다.
class VoiceSamplesScreen extends StatefulWidget {
  const VoiceSamplesScreen({super.key});
  @override
  State<VoiceSamplesScreen> createState() => _VoiceSamplesScreenState();
}

class _VoiceSamplesScreenState extends State<VoiceSamplesScreen> {
  late final Future<VoiceSampleSummary> _summary = sl<ContentRepository>()
      .getAll()
      .then(VoiceSampleSummary.fromContents);

  static String _minutes(int ms) {
    final total = (ms / 1000).round();
    final m = total ~/ 60, s = total % 60;
    return m == 0 ? '$s초' : (s == 0 ? '$m분' : '$m분 $s초');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('내 목소리 자료')),
    body: FutureBuilder<VoiceSampleSummary>(
      future: _summary,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('자료를 읽지 못했어요. 다시 열어 주세요.'));
        }
        final summary = snapshot.data;
        if (summary == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final theme = Theme.of(context);
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              summary.reachedTarget
                  ? '목소리를 만들 만큼 모였어요'
                  : '${VoiceSampleSummary.targetMinutes}분쯤 모이면 내 목소리를 만들 수 있어요',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              key: const ValueKey('voice-progress'),
              value: summary.progress,
              minHeight: 10,
              borderRadius: BorderRadius.circular(5),
            ),
            const SizedBox(height: 8),
            Text(
              '${_minutes(summary.knownMs)} / ${VoiceSampleSummary.targetMinutes}분 · '
              '녹음과 글이 함께 있는 쪽 ${summary.pairedPages}쪽',
            ),
            if (summary.unknownLength > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '예전에 녹음한 ${summary.unknownLength}쪽은 길이를 몰라 시간에 넣지 않았어요. 자료로는 쓸 수 있어요.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            if (summary.recordedWithoutText > 0)
              Card(
                margin: const EdgeInsets.only(top: 16),
                child: ListTile(
                  leading: const Icon(Icons.edit_note),
                  title: Text('글이 없는 녹음 ${summary.recordedWithoutText}쪽'),
                  subtitle: const Text('목소리 넣기에서 "사진에서 글자 뽑기"로 글을 채우면 자료가 돼요.'),
                ),
              ),
            const SizedBox(height: 24),
            Text('책별', style: theme.textTheme.titleMedium),
            if (summary.books.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('아직 모인 자료가 없어요. 목소리 넣기에서 쪽마다 녹음해 주세요.'),
              ),
            for (final book in summary.books)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.menu_book_outlined),
                title: Text(book.title),
                trailing: Text(
                  book.ms > 0
                      ? '${book.pages}쪽 · ${_minutes(book.ms)}'
                      : '${book.pages}쪽',
                ),
              ),
            const SizedBox(height: 24),
            Text(
              '보호자 녹음만 세요. 아이 목소리와 사진은 쓰지 않고, 이 화면은 아무것도 밖으로 보내지 않아요.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        );
      },
    ),
  );
}
