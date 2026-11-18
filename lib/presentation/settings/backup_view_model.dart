import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/services/backup_bundle.dart';
import '../../data/services/restore_transaction.dart';
import '../../data/services/restore_validator.dart';
import '../../data/local/json_store.dart';
import '../../domain/repositories/backup_repository.dart';
import '../../service_locator.dart';
import '../player/playback_queue.dart';

class BackupViewModel extends ChangeNotifier {
  BackupViewModel(this.playback, {this.reloadViews});
  final Future<void> Function()? reloadViews;
  bool requiresRestart = false;
  final PlaybackQueue playback;
  bool mounted = true;
  void _update(VoidCallback action) {
    action();
    if (mounted) notifyListeners();
  }

  @override
  void dispose() {
    mounted = false;
    super.dispose();
  }

  static const _files = MethodChannel('mychild_reading/backup_files');
  bool _busy = false;
  bool get busy => _busy;
  String? get message => _message;
  String get status => _status;
  String? _message;
  String _status = '';

  Future<void> run(bool export) async {
    if (_busy || requiresRestart) return;
    _update(() {
      _busy = true;
      _message = null;
      _status = '저장을 마무리하고 있어요…';
    });
    playback.setEditing(true);
    Directory? job;
    File? imported;
    try {
      // FLOW 1: 백업 화면 밖의 조작을 차단하고 읽던 위치를 포함한 저장을 기다린다.
      await playback.stop();
      if (playback.error != null) throw StateError('playback storage failed');
      await waitForStorageWrites();
      final bundle = BackupBundle();
      if (export) {
        final temp = await getTemporaryDirectory();
        final root = await Directory('${temp.path}/backup-transfer')
            .create(recursive: true);
        job = await root.createTemp('export-');
        final snapshot = Directory('${job.path}/snapshot');
        if (mounted) _update(() => _status = '사진과 녹음을 백업 파일로 모으고 있어요…');
        final repository = sl<BackupRepository>();
        await repository.create(snapshot.path);
        final file = File('${job.path}/library.mcrb');
        final summary = await bundle.pack(snapshot, file, repository);
        if (mounted) _update(() => _status = '백업 파일을 저장할 위치를 선택해 주세요.');
        final saved = await _files.invokeMethod<bool>('exportBackup', {
          'path': file.path,
        });
        _message = saved == true
            ? '백업을 저장했어요. ${summary.fileCount}개 파일 · ${_size(summary.totalBytes)}'
            : '저장을 취소했어요.';
      } else {
        if (mounted) _update(() => _status = '검사할 .mcrb 백업 파일을 선택해 주세요.');
        final path = await _files.invokeMethod<String>('pickBackup');
        if (path == null) {
          _message = '파일 선택을 취소했어요.';
          return;
        }
        final temp = await getTemporaryDirectory();
        final root = await Directory('${temp.path}/backup-transfer')
            .resolveSymbolicLinks();
        final candidate = File(path);
        final resolved = await candidate.resolveSymbolicLinks();
        if (!resolved.startsWith('$root${Platform.pathSeparator}')) {
          throw StateError('invalid cache path');
        }
        imported = File(resolved);
        if (mounted) _update(() => _status = '백업 파일의 손상 여부를 검사하고 있어요…');
        final summary = await bundle.inspect(imported);
        _message =
            '파일 무결성 검사 통과 · ${summary.fileCount}개 파일 · ${_size(summary.totalBytes)}\n현재 책장은 변경하지 않았어요. 복원하려면 백업으로 책장 복원을 선택해 주세요.';
      }
    } on Object {
      _message = '완료하지 못했어요. 파일 형식·손상 여부와 저장 공간을 확인해 주세요. 현재 책장은 그대로예요.';
    } finally {
      // FLOW 9: 앱이 만든 임시 파일만 정리한다. 사용자가 선택한 원본은 유지한다.
      try {
        if (job != null && await job.exists()) {
          await job.delete(recursive: true);
        }
      } on Object {
        /* 캐시는 OS 정리 대상. */
      }
      try {
        if (imported != null && await imported.exists()) {
          await imported.delete();
        }
      } on Object {
        /* 캐시는 OS 정리 대상. */
      }
      playback.setEditing(false);
      if (mounted) _update(() => _busy = false);
    }
  }

  Future<void> restore(Future<bool> Function(RestorePreview) confirm) async {
    if (_busy || requiresRestart) return;
    _update(() {
      _busy = true;
      _message = null;
      _status = '복원할 백업을 선택해 주세요.';
    });
    playback.setEditing(true);
    File? imported;
    Directory? staging;
    var suspended = false;
    var frozen = false;
    final store = sl<JsonStore>();
    try {
      await playback.prepareRestore();
      suspended = true;
      final path = await _files.invokeMethod<String>('pickBackup');
      if (path == null) {
        _message = '복원을 취소했어요. 현재 책장은 그대로예요.';
        return;
      }
      final temp = await getTemporaryDirectory();
      final root = await Directory('${temp.path}/backup-transfer')
          .resolveSymbolicLinks();
      final resolved = await File(path).resolveSymbolicLinks();
      if (!resolved.startsWith('$root${Platform.pathSeparator}')) {
        throw StateError('invalid cache path');
      }
      imported = File(resolved);
      _update(() => _status = '백업의 책과 사진·녹음 연결을 검사하고 있어요…');
      staging = await store.baseDir.createTemp('.restore-stage-');
      final ready = Directory('${staging.path}/ready');
      await BackupBundle().extract(imported, ready);
      final preview = await RestoreValidator().validate(ready);
      if (!mounted || !await confirm(preview)) {
        _message = '복원을 취소했어요. 현재 책장은 그대로예요.';
        return;
      }
      if (!mounted) return;
      _update(() => _status = '책장을 복원하고 있어요. 잠시만 기다려 주세요…');
      // FLOW 1: 확인 후에만 OS 명령과 모든 접수된 저장을 차단/배수한다.
      await store.gate.freeze();
      frozen = true;
      Future<void> reload() async {
        await playback.reloadRestoredLibrary();
        await reloadViews?.call();
      }

      // FLOW 2: 원본 보관 → 교체 → 무음 재조회 → 확정. 실패는 저널로 롤백한다.
      await RestoreTransaction(store.baseDir).apply(ready, reload);
      _message =
          '복원했어요. 책 ${preview.books}권 · 플레이리스트 ${preview.playlists}개 · 만들던 책 ${preview.drafts}권\n책장과 최근재생목록에 반영했어요. 재생은 자동으로 시작하지 않아요.';
    } on RestoreRecoveryFailure {
      requiresRestart = true;
      _message = '복원 정리를 마치지 못했어요. 자료 보호를 위해 변경을 멈췄어요. 앱을 완전히 종료한 뒤 다시 열어 주세요.';
    } on Object {
      _message =
          '복원하지 못했어요. 지원하지 않는 백업·누락된 사진/녹음·저장 공간을 확인해 주세요. 기존 책장을 유지했어요.';
    } finally {
      try {
        if (staging != null && await staging.exists()) {
          await staging.delete(recursive: true);
        }
      } on Object {
        /* 다음 시작 또는 OS 캐시 정리 때 회수한다. */
      }
      try {
        if (imported != null && await imported.exists()) {
          await imported.delete();
        }
      } on Object {
        /* 다음 시작 또는 OS 캐시 정리 때 회수한다. */
      }
      if (!requiresRestart) {
        if (frozen) store.gate.thaw();
        if (suspended) playback.resumeStorage();
        playback.setEditing(false);
      }
      if (mounted) _update(() => _busy = false);
    }
  }

  String _size(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
