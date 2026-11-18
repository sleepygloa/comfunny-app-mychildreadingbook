import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mychild_reading/core/error_codes.dart';
import 'package:mychild_reading/data/local/app_paths.dart';
import 'package:mychild_reading/data/local/json_store.dart';

/// [JsonStore] 검증 — **실제 파일 IO** 로 돌린다.
///
/// 왜 mock 을 쓰지 않나: 검증하려는 것이 바로 파일시스템 동작(원자적 rename, 깨진 파일
/// 처리, 디렉토리 스캔)이다. mock 으로 바꾸면 정작 확인하려던 것이 사라진다.
void main() {
  late Directory tmp;
  late JsonStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('mcr_store_test_');
    store = JsonStore(tmp);
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  /// 파일 원문을 그대로 읽는다 (봉투 구조 확인용).
  Future<String> rawOf(String rel) =>
      File('${tmp.path}${Platform.pathSeparator}$rel').readAsString();

  group('writeMap / readMap', () {
    test('쓴 값을 그대로 읽는다', () async {
      await store.writeMap('index/x.json', {'a': 1, 'b': '문자'});
      final out = await store.readMap('index/x.json');

      expect(out, isNotNull);
      expect(out!['a'], 1);
      expect(out['b'], '문자');
    });

    test('파일이 없으면 null', () async {
      expect(await store.readMap('index/none.json'), isNull);
    });

    test('중간 디렉토리를 자동 생성한다', () async {
      await store.writeMap('library/c1/data.json', {'id': 'c1'});
      expect(await store.exists('library/c1/data.json'), isTrue);
    });

    test('스키마 버전 봉투로 감싼다', () async {
      await store.writeMap('index/x.json', {'k': 'v'});
      final decoded = jsonDecode(await rawOf('index/x.json')) as Map;

      expect(decoded['schemaVersion'], JsonStore.schemaVersion);
      expect((decoded['data'] as Map)['k'], 'v');
    });

    test('임시파일(.tmp)을 남기지 않는다', () async {
      await store.writeMap('index/x.json', {'k': 'v'});
      expect(await File('${tmp.path}/index/x.json.tmp').exists(), isFalse);
    });
  });

  group('writeList / readList', () {
    test('리스트 round-trip', () async {
      await store.writeList('index/list.json', [
        {'id': 'a'},
        {'id': 'b'},
      ]);
      final out = await store.readList('index/list.json');

      expect(out.length, 2);
      expect(out.map((e) => e['id']), ['a', 'b']);
    });

    test('파일이 없으면 빈 리스트', () async {
      expect(await store.readList('index/none.json'), isEmpty);
    });

    test('맵이 아닌 요소는 걸러낸다', () async {
      final f = File('${tmp.path}/index/mixed.json');
      await f.parent.create(recursive: true);
      await f.writeAsString(jsonEncode({
        'schemaVersion': JsonStore.schemaVersion,
        'data': [
          {'id': 'ok'},
          'string',
          42,
          null,
        ],
      }));

      final out = await store.readList('index/mixed.json');
      expect(out.length, 1);
      expect(out.single['id'], 'ok');
    });
  });

  group('손상 내구성 — 깨져도 앱을 막지 않는다', () {
    test('깨진 JSON 은 null 을 돌려주고 예외를 던지지 않는다', () async {
      final f = File('${tmp.path}/index/broken.json');
      await f.parent.create(recursive: true);
      await f.writeAsString('{ this is not json ');

      expect(await store.readMap('index/broken.json'), isNull);
      expect(await store.readList('index/broken.json'), isEmpty);
    });

    test('빈 파일도 null', () async {
      final f = File('${tmp.path}/index/empty.json');
      await f.parent.create(recursive: true);
      await f.writeAsString('   ');

      expect(await store.readMap('index/empty.json'), isNull);
    });

    test('봉투 없는 구형 파일도 읽는다 (하위 호환)', () async {
      final f = File('${tmp.path}/index/legacy.json');
      await f.parent.create(recursive: true);
      // schemaVersion 도입 이전 형태 — data 로 감싸지 않은 원본
      await f.writeAsString(jsonEncode({'id': 'legacy', 'title': '구형'}));

      final out = await store.readMap('index/legacy.json');
      expect(out, isNotNull);
      expect(out!['title'], '구형');
    });
  });

  group('미래 스키마 방어 — 다운그레이드 데이터 유실 방지', () {
    test('앱보다 높은 버전이면 예외를 던지고 읽지 않는다', () async {
      final f = File('${tmp.path}/index/future.json');
      await f.parent.create(recursive: true);
      await f.writeAsString(jsonEncode({
        'schemaVersion': JsonStore.schemaVersion + 1,
        'data': {'id': 'from-newer-app'},
      }));

      // 잘못 해석한 뒤 저장하면 신버전 데이터가 깨진다 → 읽기를 거부하는 것이 맞다.
      expect(
        () => store.readMap('index/future.json'),
        throwsA(isA<AppException>().having(
          (e) => e.errorCode.code,
          'errorCode',
          ErrorCode.storageFailure.code,
        )),
      );
    });

    test('같은 버전은 정상 통과', () async {
      await store.writeMap('index/same.json', {'ok': true});
      expect(await store.readMap('index/same.json'), isNotNull);
    });
  });

  group('삭제 · 디렉토리 스캔', () {
    test('delete 는 멱등하다 (없는 파일도 통과)', () async {
      await store.writeMap('index/x.json', {'k': 'v'});
      await store.delete('index/x.json');
      expect(await store.exists('index/x.json'), isFalse);

      // 두 번째 호출도 예외 없이 통과해야 한다.
      await expectLater(store.delete('index/x.json'), completes);
    });

    test('deleteDirectory 는 미디어까지 통째로 지운다', () async {
      await store.writeMap('library/c1/data.json', {'id': 'c1'});
      final img = File('${tmp.path}/library/c1/pages/page_000.jpg');
      await img.parent.create(recursive: true);
      await img.writeAsBytes([1, 2, 3]);

      await store.deleteDirectory('library/c1');

      expect(await Directory('${tmp.path}/library/c1').exists(), isFalse);
      expect(await img.exists(), isFalse); // 고아 미디어가 남지 않는다
    });

    test('listSubdirectories 는 폴더만, 이름순으로', () async {
      await store.writeMap('library/c2/data.json', {'id': 'c2'});
      await store.writeMap('library/c1/data.json', {'id': 'c1'});
      // 파일도 하나 섞어 둔다 — 결과에 포함되면 안 된다.
      await File('${tmp.path}/library/stray.txt').writeAsString('x');

      final dirs = await store.listSubdirectories('library');
      expect(dirs, ['c1', 'c2']);
    });

    test('없는 디렉토리는 빈 리스트', () async {
      expect(await store.listSubdirectories('library'), isEmpty);
    });
  });

  group('AppPaths — 경로 규칙', () {
    test('콘텐츠 경로', () {
      expect(AppPaths.contentDir('c1'), 'library/c1');
      expect(AppPaths.contentDataFile('c1'), 'library/c1/data.json');
    });

    test('페이지 이미지는 3자리 0채움 — 파일명 정렬 = 페이지 순서', () {
      expect(AppPaths.pageImageRelative(0), 'pages/page_000.jpg');
      expect(AppPaths.pageImageRelative(7), 'pages/page_007.jpg');
      expect(AppPaths.pageImageRelative(123), 'pages/page_123.jpg');

      // 정렬해도 순서가 유지되는지 (0채움이 없으면 10 이 2 보다 앞에 온다)
      final names = [10, 2, 1].map(AppPaths.pageImageRelative).toList()..sort();
      expect(names, [
        'pages/page_001.jpg',
        'pages/page_002.jpg',
        'pages/page_010.jpg',
      ]);
    });

    test('오디오 파일명에 목소리 id 가 들어가 서로 덮어쓰지 않는다', () {
      final mom = AppPaths.audioRelative(
        pageId: 'p1',
        sourceName: 'aiClonedVoice',
        voiceProfileId: 'v-mom',
      );
      final dad = AppPaths.audioRelative(
        pageId: 'p1',
        sourceName: 'aiClonedVoice',
        voiceProfileId: 'v-dad',
      );

      expect(mom, 'audio/p1_aiClonedVoice_v-mom.m4a');
      expect(dad, isNot(mom));
    });

    test('목소리 id 가 없으면 접미를 붙이지 않는다', () {
      expect(
        AppPaths.audioRelative(pageId: 'p1', sourceName: 'parentRecording'),
        'audio/p1_parentRecording.m4a',
      );
    });
  });
}
