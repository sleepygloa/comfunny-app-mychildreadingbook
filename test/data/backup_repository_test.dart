import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mychild_reading/core/error_codes.dart';
import 'package:mychild_reading/data/local/json_store.dart';
import 'package:mychild_reading/data/repositories/backup_repository_impl.dart';
import 'package:mychild_reading/data/repositories/content_repository_impl.dart';
import 'package:mychild_reading/data/repositories/index_repositories.dart';
import 'package:mychild_reading/data/repositories/reading_workspace_repositories.dart';
import 'package:mychild_reading/domain/entities/book_draft.dart';
import 'package:mychild_reading/domain/entities/book_page.dart';
import 'package:mychild_reading/domain/entities/content.dart';
import 'package:mychild_reading/domain/entities/playlist.dart';
import 'package:mychild_reading/domain/entities/reading_position.dart';
import 'package:mychild_reading/domain/enums/enums.dart';
import 'package:mychild_reading/domain/repositories/backup_repository.dart';
import 'package:mychild_reading/service_locator.dart';

void main() {
  late Directory temp;
  late Directory source;
  late BackupRepositoryImpl backups;
  String getBackup() => '${temp.path}/backup';
  String getRestore() => '${temp.path}/restored';
  final now = DateTime.utc(2026, 9, 20);
  final failure = isA<AppException>();

  Future<File> write(String relative, List<int> bytes) async {
    final file = File('${source.path}/$relative');
    await file.parent.create(recursive: true);
    return file.writeAsBytes(bytes, flush: true);
  }

  Future<void> changeManifest(
    void Function(Map<String, dynamic>) change,
  ) async {
    final file = File('${getBackup()}/manifest.json');
    final value = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    change(value);
    await file.writeAsString(jsonEncode(value));
  }

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('mcr-backup-test-');
    source = await Directory('${temp.path}/source').create();
    backups = BackupRepositoryImpl(source);
  });
  tearDown(() async {
    await resetLocator();
    await temp.delete(recursive: true);
  });

  test('실제 저장소의 책 사진 녹음 초안 플레이리스트 읽던 위치를 별도 경로에서 복구한다', () async {
    final store = JsonStore(source);
    final book = Content(
      id: 'book-1',
      type: ContentType.pagedBook,
      title: '달빛 산책',
      createdAt: now,
      updatedAt: now,
      pages: const [
        BookPage(id: 'page-1', orderIndex: 0, imagePath: 'pages/1.jpg'),
      ],
    );
    await ContentRepositoryImpl(store).save(book);
    await BookDraftRepositoryImpl(store).save(
      BookDraft(
        content: book.copyWith(title: '편집'),
        savedAt: now,
      ),
    );
    await ReadingPositionRepositoryImpl(store).save(
      ReadingPosition(contentId: book.id, pageId: 'page-1', updatedAt: now),
    );
    await PlaylistRepositoryImpl(store).save(
      Playlist(
        id: 'list-1',
        title: '잠들기 전',
        contentIds: [book.id],
        createdAt: now,
      ),
    );
    await write('library/book-1/pages/1.jpg', [1, 2, 3, 4]);
    await write(
      'library/book-1/audio/voice.m4a',
      List.generate(150000, (i) => i % 256),
    );
    await write('drafts/book-1/assets/edit.jpg', [5, 6, 7]);
    await write('secrets/key.txt', [9]);
    final result = await backups.create(getBackup());
    expect(result.fileCount, 7);
    expect((await backups.verify(getBackup())).totalBytes, result.totalBytes);
    await backups.restoreToNewDirectory(getBackup(), getRestore());
    final restored = JsonStore(Directory(getRestore()));
    expect(
      (await ContentRepositoryImpl(restored).getById(book.id))!.toJson(),
      book.toJson(),
    );
    expect(
      (await BookDraftRepositoryImpl(restored).getById(book.id))!.content.title,
      '편집',
    );
    expect(
      (await ReadingPositionRepositoryImpl(restored).getById(book.id))!.pageId,
      'page-1',
    );
    expect(
      (await PlaylistRepositoryImpl(restored).getAll()).single.contentIds,
      [book.id],
    );
    for (final path in [
      'library/book-1/pages/1.jpg',
      'library/book-1/audio/voice.m4a',
      'drafts/book-1/assets/edit.jpg',
    ]) {
      expect(
        await File('${getRestore()}/$path').readAsBytes(),
        await File('${source.path}/$path').readAsBytes(),
      );
    }
    expect(await File('${getRestore()}/secrets/key.txt').exists(), isFalse);
    expect(await File('${source.path}/secrets/key.txt').readAsBytes(), [9]);
  });

  test('빈 책장도 백업 복원하고 기존 대상은 빈 폴더여도 보존한다', () async {
    expect((await backups.create(getBackup())).fileCount, 0);
    await Directory(getRestore()).create();
    await expectLater(
      backups.restoreToNewDirectory(getBackup(), getRestore()),
      throwsA(failure),
    );
    expect(await Directory(getRestore()).exists(), isTrue);
    await expectLater(backups.create(getBackup()), throwsA(failure));
  });

  test('손상 또는 미래 JSON도 해석하거나 고치지 않고 원문을 보존한다', () async {
    final original = utf8.encode('{"schemaVersion":999,"data":"미래"}');
    await write('library/future/data.json', original);
    await write('drafts/broken/data.json', utf8.encode('{broken'));
    await backups.create(getBackup());
    await backups.restoreToNewDirectory(getBackup(), getRestore());
    expect(
      await File('${getRestore()}/library/future/data.json').readAsBytes(),
      original,
    );
    expect(
      await File('${getRestore()}/drafts/broken/data.json').readAsString(),
      '{broken',
    );
  });

  for (final damage in ['same-size', 'missing', 'extra']) {
    test('백업 파일 $damage 손상은 복원을 거절하고 대상 경로를 만들지 않는다', () async {
      await write('library/book/data.json', [1, 2, 3]);
      await backups.create(getBackup());
      final file = File('${getBackup()}/files/library/book/data.json');
      if (damage == 'same-size') await file.writeAsBytes([4, 5, 6]);
      if (damage == 'missing') await file.delete();
      if (damage == 'extra') {
        await File('${file.parent.path}/extra.jpg').writeAsBytes([7]);
      }
      await expectLater(
        backups.restoreToNewDirectory(getBackup(), getRestore()),
        throwsA(failure),
      );
      expect(await Directory(getRestore()).exists(), isFalse);
      expect(
        await File('${source.path}/library/book/data.json').readAsBytes(),
        [1, 2, 3],
      );
    });
  }

  for (final path in [
    '../escape',
    '/etc/passwd',
    'library/../escape',
    'library/book/../../escape',
    r'library\book\data.json',
    'secrets/key',
    'library/book/data.json/child',
  ]) {
    test('manifest 경로 $path 를 거부한다', () async {
      await write('library/book/data.json', [1]);
      await backups.create(getBackup());
      await changeManifest((map) => map['files'][0]['path'] = path);
      await expectLater(
        backups.restoreToNewDirectory(getBackup(), getRestore()),
        throwsA(failure),
      );
      expect(await Directory(getRestore()).exists(), isFalse);
    });
  }

  for (final mutation in ['version', 'duplicate', 'size', 'digest', 'type']) {
    test('manifest $mutation 오류를 거부한다', () async {
      await write('index/playlists.json', [1]);
      await backups.create(getBackup());
      await changeManifest((map) {
        if (mutation == 'version') map['version'] = 99;
        if (mutation == 'duplicate') map['files'].add(map['files'][0]);
        if (mutation == 'size') {
          map['files'][0]['size'] = BackupRepositoryImpl.maxTotalBytes + 1;
        }
        if (mutation == 'digest') map['files'][0]['sha256'] = 'invalid';
        if (mutation == 'type') map['files'] = 'invalid';
      });
      await expectLater(backups.verify(getBackup()), throwsA(failure));
    });
  }

  test('원본과 백업의 심볼릭 링크를 따라가지 않는다', () async {
    await write('library/book/data.json', [1]);
    await File('${temp.path}/private.txt').writeAsString('private');
    final link = Link('${source.path}/library/book/link');
    await link.create('${temp.path}/private.txt');
    await expectLater(backups.create(getBackup()), throwsA(failure));
    await link.delete();
    await backups.create(getBackup());
    final file = File('${getBackup()}/files/library/book/data.json');
    await file.delete();
    await Link(file.path).create('${temp.path}/private.txt');
    await expectLater(backups.verify(getBackup()), throwsA(failure));
    expect(await File('${temp.path}/private.txt').readAsString(), 'private');
  });

  test('원본 하위 출력과 활성 저장소 복원은 거절한다', () async {
    await expectLater(
      backups.create('${source.path}/backup'),
      throwsA(failure),
    );
    await backups.create(getBackup());
    await expectLater(
      backups.restoreToNewDirectory(getBackup(), source.path),
      throwsA(failure),
    );
    await expectLater(
      backups.restoreToNewDirectory(getBackup(), '${source.path}/restored'),
      throwsA(failure),
    );
  });

  test('임시 저장 잔재가 있으면 백업하지 않고 원본과 잔재를 보존한다', () async {
    await write('index/playlists.json.tmp', [1]);
    await expectLater(
      backups.create(getBackup()),
      throwsA(
        isA<AppException>().having(
          (e) => e.errorCode,
          'code',
          ErrorCode.backupChanged,
        ),
      ),
    );
    expect(await Directory(getBackup()).exists(), isFalse);
    expect(
      await File('${source.path}/index/playlists.json.tmp').readAsBytes(),
      [1],
    );
  });

  test('파일 없는 깊은 디렉터리도 순회 상한으로 거절한다', () async {
    await backups.create(getBackup());
    final nested = List.filled(
      BackupRepositoryImpl.maxDepth + 1,
      'nested',
    ).join('/');
    await Directory('${getBackup()}/files/library/$nested')
        .create(recursive: true);
    await expectLater(backups.verify(getBackup()), throwsA(failure));
    expect(await Directory(getRestore()).exists(), isFalse);
  });

  test('백업 manifest 크기 상한을 거절한다', () async {
    await backups.create(getBackup());
    await File('${getBackup()}/manifest.json')
        .writeAsBytes(List.filled(8 * 1024 * 1024 + 1, 32));
    await expectLater(backups.verify(getBackup()), throwsA(failure));
  });

  test('DI로 조회할 수 있고 실패 이후 재시도와 중복 목적지 경쟁을 처리한다', () async {
    await registerWith(source);
    final repo = sl<BackupRepository>();
    await expectLater(repo.verify('${temp.path}/absent'), throwsA(failure));
    final first = repo.create(getBackup());
    final second = repo.create(getBackup());
    await expectLater(second, throwsA(failure));
    expect((await first).fileCount, 0);
    expect((await repo.verify(getBackup())).fileCount, 0);
  });
}
