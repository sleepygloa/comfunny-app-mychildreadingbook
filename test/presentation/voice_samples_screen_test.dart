import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mychild_reading/domain/entities/audio_track.dart';
import 'package:mychild_reading/domain/entities/book_page.dart';
import 'package:mychild_reading/domain/entities/content.dart';
import 'package:mychild_reading/domain/enums/enums.dart';
import 'package:mychild_reading/domain/repositories/repositories.dart';
import 'package:mychild_reading/presentation/settings/voice_samples_screen.dart';
import 'package:mychild_reading/service_locator.dart';

void main() {
  late Directory tmp;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('voice_ui_');
    await registerWith(tmp);
  });
  tearDown(() async {
    await resetLocator();
    await tmp.delete(recursive: true);
  });

  testWidgets('모인 분량과 글 없는 녹음을 보여 준다', (tester) async {
    final at = DateTime.utc(2026, 11, 22);
    await tester.runAsync(() async {
      await sl<ContentRepository>().save(
        Content(
          id: 'moon',
          type: ContentType.pagedBook,
          title: '달빛 산책',
          createdAt: at,
          updatedAt: at,
          pages: [
            BookPage(
              id: 'p1',
              orderIndex: 0,
              imagePath: 'images/p1.jpg',
              text: '달님 안녕',
              tracks: [
                AudioTrack(
                  id: 'r1',
                  source: AudioSource.parentRecording,
                  path: 'audio/r1.m4a',
                  durationMs: 150000,
                  createdAt: at,
                ),
              ],
            ),
            BookPage(
              id: 'p2',
              orderIndex: 1,
              imagePath: 'images/p2.jpg',
              tracks: [
                AudioTrack(
                  id: 'r2',
                  source: AudioSource.parentRecording,
                  path: 'audio/r2.m4a',
                  createdAt: at,
                ),
              ],
            ),
          ],
        ),
      );
    });
    await tester.pumpWidget(const MaterialApp(home: VoiceSamplesScreen()));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(find.text('20분쯤 모이면 내 목소리를 만들 수 있어요'), findsOneWidget);
    expect(find.textContaining('2분 30초 / 20분'), findsOneWidget);
    expect(find.textContaining('함께 있는 쪽 1쪽'), findsOneWidget);
    expect(find.text('글이 없는 녹음 1쪽'), findsOneWidget);
    expect(find.text('달빛 산책'), findsOneWidget);
    expect(find.text('1쪽 · 2분 30초'), findsOneWidget);
  });
}
