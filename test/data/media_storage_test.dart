import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mychild_reading/core/error_codes.dart';
import 'package:mychild_reading/data/local/media_storage.dart';

/// [MediaStorage] 검증 — 실제 파일 이동.
///
/// 왜 중요한가: 카메라·녹음기는 **임시 경로**에 파일을 만든다. OS 가 그 경로를 언제든
/// 지우므로, 임시 경로를 엔티티에 저장하면 나중에 재생이 조용히 깨진다.
/// "임시 → 콘텐츠 폴더 이동 후 **상대 경로** 반환" 이 정확히 동작해야 한다.
void main() {
  late Directory tmp;
  late Directory scratch;
  late MediaStorage media;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('mcr_media_');
    scratch = await Directory.systemTemp.createTemp('mcr_scratch_');
    media = MediaStorage(tmp);
  });

  tearDown(() async {
    for (final d in [tmp, scratch]) {
      if (await d.exists()) await d.delete(recursive: true);
    }
  });

  /// 카메라·녹음기가 만든 임시 파일을 흉내낸다.
  Future<String> makeTempFile(String name, {int bytes = 64}) async {
    final f = File('${scratch.path}${Platform.pathSeparator}$name');
    await f.writeAsBytes(List.filled(bytes, 1));
    return f.path;
  }

  group('adopt — 임시 파일 받아들이기', () {
    test('상대 경로를 돌려주고 절대 경로는 노출하지 않는다', () async {
      final src = await makeTempFile('shot.jpg');

      final relative = await media.adoptPageImage(
        contentId: 'c1',
        sourcePath: src,
        orderIndex: 0,
      );

      // 엔티티에 저장되는 값은 상대 경로여야 한다.
      expect(relative, 'pages/page_000.jpg');
      expect(relative, isNot(contains(tmp.path)));
    });

    test('원본 임시 파일을 남기지 않는다 (복사가 아니라 이동)', () async {
      final src = await makeTempFile('shot.jpg');
      await media.adoptPageImage(
        contentId: 'c1',
        sourcePath: src,
        orderIndex: 0,
      );

      // 임시 파일이 쌓이면 기기 저장소가 조용히 찬다.
      expect(await File(src).exists(), isFalse);
    });

    test('콘텐츠 폴더의 올바른 위치에 실재한다', () async {
      final src = await makeTempFile('shot.jpg', bytes: 128);
      final relative = await media.adoptPageImage(
        contentId: 'c1',
        sourcePath: src,
        orderIndex: 7,
      );

      final abs = media.absolutePathOf('c1', relative);
      expect(abs, endsWith('library/c1/pages/page_007.jpg'));
      expect(await File(abs).exists(), isTrue);
      expect(await File(abs).length(), 128);
    });

    test('원본이 없으면 notFound 를 던진다', () async {
      expect(
        () => media.adoptPageImage(
          contentId: 'c1',
          sourcePath: '${scratch.path}/nope.jpg',
          orderIndex: 0,
        ),
        throwsA(isA<AppException>().having(
          (e) => e.errorCode.code,
          'errorCode',
          ErrorCode.notFound.code,
        )),
      );
    });

    test('중간 디렉토리를 자동 생성한다', () async {
      final src = await makeTempFile('a.m4a');
      await media.adoptAudio(
        contentId: 'brand-new',
        sourcePath: src,
        pageId: 'p1',
        sourceName: 'parentRecording',
      );
      expect(
        await Directory('${tmp.path}/library/brand-new/audio').exists(),
        isTrue,
      );
    });
  });

  group('adoptAudio — 목소리별 파일 분리', () {
    test('목소리 id 가 다르면 서로 덮어쓰지 않는다', () async {
      final mom = await makeTempFile('mom.m4a', bytes: 10);
      final dad = await makeTempFile('dad.m4a', bytes: 20);

      final rMom = await media.adoptAudio(
        contentId: 'c1',
        sourcePath: mom,
        pageId: 'p1',
        sourceName: 'aiClonedVoice',
        voiceProfileId: 'v-mom',
      );
      final rDad = await media.adoptAudio(
        contentId: 'c1',
        sourcePath: dad,
        pageId: 'p1',
        sourceName: 'aiClonedVoice',
        voiceProfileId: 'v-dad',
      );

      expect(rMom, isNot(rDad));
      // 둘 다 남아 있어야 한다 — 엄마·아빠 목소리를 동시에 보유하는 것이 설계다.
      expect(await File(media.absolutePathOf('c1', rMom)).length(), 10);
      expect(await File(media.absolutePathOf('c1', rDad)).length(), 20);
    });

    test('같은 종류를 다시 받아들이면 덮어쓴다 (재녹음)', () async {
      final first = await makeTempFile('r1.m4a', bytes: 10);
      final second = await makeTempFile('r2.m4a', bytes: 99);

      final r1 = await media.adoptAudio(
        contentId: 'c1',
        sourcePath: first,
        pageId: 'p1',
        sourceName: 'parentRecording',
      );
      final r2 = await media.adoptAudio(
        contentId: 'c1',
        sourcePath: second,
        pageId: 'p1',
        sourceName: 'parentRecording',
      );

      expect(r1, r2); // 같은 경로
      expect(await File(media.absolutePathOf('c1', r2)).length(), 99);
    });
  });

  group('prepareAudioPath — 녹음 목적지 준비', () {
    test('절대 경로를 돌려주고 상위 디렉토리를 만든다 (파일은 아직 없다)', () async {
      final abs = await media.prepareAudioPath(
        contentId: 'c1',
        pageId: 'p1',
        sourceName: 'parentRecording',
      );

      expect(abs, endsWith('library/c1/audio/p1_parentRecording.m4a'));
      expect(await File(abs).parent.exists(), isTrue);
      expect(await File(abs).exists(), isFalse);
    });
  });

  group('exists · deleteRelative · contentSizeBytes', () {
    test('exists 로 죽은 트랙을 걸러낼 수 있다', () async {
      final src = await makeTempFile('a.m4a');
      final rel = await media.adoptAudio(
        contentId: 'c1',
        sourcePath: src,
        pageId: 'p1',
        sourceName: 'parentRecording',
      );

      expect(await media.exists('c1', rel), isTrue);
      expect(await media.exists('c1', 'audio/ghost.m4a'), isFalse);
    });

    test('deleteRelative 는 멱등하다', () async {
      final src = await makeTempFile('a.m4a');
      final rel = await media.adoptAudio(
        contentId: 'c1',
        sourcePath: src,
        pageId: 'p1',
        sourceName: 'parentRecording',
      );

      await media.deleteRelative('c1', rel);
      expect(await media.exists('c1', rel), isFalse);
      // 두 번째 호출도 통과해야 한다.
      await expectLater(media.deleteRelative('c1', rel), completes);
    });

    test('contentSizeBytes 가 하위 전체를 합산한다', () async {
      final img = await makeTempFile('i.jpg', bytes: 100);
      final aud = await makeTempFile('a.m4a', bytes: 250);
      await media.adoptPageImage(
        contentId: 'c1',
        sourcePath: img,
        orderIndex: 0,
      );
      await media.adoptAudio(
        contentId: 'c1',
        sourcePath: aud,
        pageId: 'p1',
        sourceName: 'parentRecording',
      );

      expect(await media.contentSizeBytes('c1'), 350);
    });

    test('없는 콘텐츠는 0 바이트', () async {
      expect(await media.contentSizeBytes('nope'), 0);
    });
  });
}
