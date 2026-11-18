import 'dart:io';

import 'storage_gate.dart';

import 'package:uuid/uuid.dart';

import '../../core/error_codes.dart';

/// 초안과 게시 미디어는 매번 새 경로를 쓴다. 기존 책의 파일을 교체하지 않는다.
class AuthoringMediaStore {
  AuthoringMediaStore(this.baseDir, {StorageGate? gate})
    : gate = gate ?? StorageGate();
  final StorageGate gate;
  final Directory baseDir;

  void validateId(String id) {
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id)) {
      throw const AppException(ErrorCode.badRequest, detail: '잘못된 콘텐츠 id');
    }
  }

  Future<File> file(String root, String id, String relative) async {
    validateId(id);
    if (!['drafts', 'library'].contains(root) ||
        relative.contains('\\') ||
        relative
            .split('/')
            .any((part) => part.isEmpty || part == '.' || part == '..')) {
      throw const AppException(ErrorCode.badRequest, detail: '허용되지 않은 미디어 경로');
    }
    var path = baseDir.path;
    // FLOW 1: 앱 저장 경계 안의 링크를 따라 다른 책/파일로 빠져나가지 않는다.
    for (final part in [root, id, ...relative.split('/')]) {
      path = '$path/$part';
      if (await FileSystemEntity.type(path, followLinks: false) ==
          FileSystemEntityType.link) {
        throw const AppException(
          ErrorCode.badRequest,
          detail: '미디어 링크는 허용하지 않습니다',
        );
      }
    }
    return File(path);
  }

  Future<bool> hasFile(String root, String id, String relative) async {
    final value = await file(root, id, relative);
    return await value.exists() && await value.length() > 0;
  }

  Future<String> importFile(
    String id,
    String sourcePath,
    String extension,
  ) async {
    if (!['jpg', 'jpeg', 'png', 'm4a', 'wav', 'mp3'].contains(extension)) {
      throw const AppException(ErrorCode.badRequest, detail: '지원하지 않는 미디어 형식');
    }
    final relative = 'assets/${const Uuid().v4()}.$extension';
    await copy(File(sourcePath), await file('drafts', id, relative));
    return relative;
  }

  Future<void> deleteDraftFiles(String id) async {
    final metadata = await file('drafts', id, 'data.json');
    if (await metadata.parent.exists()) {
      await metadata.parent.delete(recursive: true);
    }
  }

  Future<void> copy(File source, File target) async {
    if (!await source.exists() || await source.length() == 0) {
      throw const AppException(ErrorCode.notFound, detail: '미디어 파일이 없거나 비었습니다');
    }
    await target.parent.create(recursive: true);
    await source.copy(target.path);
  }
}
