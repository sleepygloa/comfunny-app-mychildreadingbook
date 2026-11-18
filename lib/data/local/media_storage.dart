import 'dart:io';

import 'storage_gate.dart';

import '../../core/app_logger.dart';
import '../../core/error_codes.dart';
import 'app_paths.dart';

/// 미디어 파일(사진·오디오·영상)의 물리 저장을 담당한다.
///
/// 왜 별도 클래스인가: 카메라·녹음기는 **임시 경로**에 파일을 만든다. OS 가 그 경로를
/// 언제든 지울 수 있어서, 임시 경로를 엔티티에 저장하면 나중에 재생이 깨진다.
/// 이 클래스가 "임시 → 콘텐츠 폴더" 이동을 책임지고 **상대 경로만** 돌려준다.
///
/// [JsonStore] 와 나눈 이유: 그쪽은 JSON 텍스트(원자적 쓰기·스키마 봉투), 이쪽은
/// 바이너리 파일 이동이다. 관심사가 다르다.
class MediaStorage {
  MediaStorage(this.baseDir, {StorageGate? gate})
    : gate = gate ?? StorageGate();
  final StorageGate gate;

  /// 앱 문서 디렉토리. `path_provider` 로 얻은 값을 주입받는다.
  ///
  /// 왜 주입인가: `path_provider` 는 플랫폼 채널이라 단위 테스트에서 못 쓴다.
  /// 디렉토리를 받으면 임시 폴더로 테스트할 수 있다.
  final Directory baseDir;

  String _abs(String relative) =>
      '${baseDir.path}${Platform.pathSeparator}$relative';

  /// 콘텐츠 폴더 기준 상대 경로 → 절대 경로. 재생·표시할 때 쓴다.
  String absolutePathOf(String contentId, String relativeInContent) =>
      _abs('${AppPaths.contentDir(contentId)}/$relativeInContent');

  /// 임시 파일을 콘텐츠 폴더로 **이동**하고 콘텐츠 기준 상대 경로를 돌려준다.
  ///
  /// 왜 복사가 아니라 이동인가: 임시 파일을 남기면 기기 저장소가 조용히 찬다.
  /// 같은 파일시스템이면 `rename` 이라 비용도 거의 없다.
  Future<String> adopt({
    required String contentId,
    required String sourcePath,
    required String relativeInContent,
  }) => gate.write(() async {
    // FLOW 1: 원본 확인 — 없으면 엔티티에 죽은 경로를 심게 된다
    final src = File(sourcePath);
    if (!await src.exists()) {
      throw AppException(ErrorCode.notFound, detail: '원본 파일 없음: $sourcePath');
    }
    // FLOW 2: 목적지 디렉토리 확보
    final destAbs = absolutePathOf(contentId, relativeInContent);
    final dest = File(destAbs);
    await dest.parent.create(recursive: true);

    // FLOW 3: 이동 시도. 파일시스템이 다르면 rename 이 실패하므로 복사로 폴백한다
    //         (임시 디렉토리가 다른 볼륨에 있는 경우가 실제로 있다)
    try {
      await src.rename(destAbs);
    } on FileSystemException {
      await src.copy(destAbs);
      try {
        await src.delete();
      } on FileSystemException {
        // 원본 삭제 실패는 치명적이지 않다 — 복사는 됐다.
        AppLogger.w('임시 파일 삭제 실패(무시): $sourcePath');
      }
    }
    // FLOW 9: 엔티티에 저장할 값은 **상대 경로**다
    return relativeInContent;
  });

  /// 페이지 이미지를 받아들인다. 반환값을 `BookPage.imagePath` 에 넣는다.
  Future<String> adoptPageImage({
    required String contentId,
    required String sourcePath,
    required int orderIndex,
  }) => adopt(
    contentId: contentId,
    sourcePath: sourcePath,
    relativeInContent: AppPaths.pageImageRelative(orderIndex),
  );

  /// 녹음/합성 오디오를 받아들인다. 반환값을 `AudioTrack.path` 에 넣는다.
  Future<String> adoptAudio({
    required String contentId,
    required String sourcePath,
    required String pageId,
    required String sourceName,
    String? voiceProfileId,
    String extension = 'm4a',
  }) => adopt(
    contentId: contentId,
    sourcePath: sourcePath,
    relativeInContent: AppPaths.audioRelative(
      pageId: pageId,
      sourceName: sourceName,
      voiceProfileId: voiceProfileId,
      extension: extension,
    ),
  );

  /// 녹음을 시작할 **절대 경로**를 만든다 (아직 파일은 없다).
  ///
  /// 왜 이 메서드가 필요한가: 녹음기는 목적지를 미리 받아야 한다. 임시 경로에 녹음한 뒤
  /// 옮기는 것보다 처음부터 최종 위치에 쓰는 편이 단계가 하나 적다.
  Future<String> prepareAudioPath({
    required String contentId,
    required String pageId,
    required String sourceName,
    String? voiceProfileId,
    String extension = 'm4a',
  }) => gate.write(() async {
    final relative = AppPaths.audioRelative(
      pageId: pageId,
      sourceName: sourceName,
      voiceProfileId: voiceProfileId,
      extension: extension,
    );
    final abs = absolutePathOf(contentId, relative);
    await File(abs).parent.create(recursive: true);
    return abs;
  });

  /// 콘텐츠 폴더 기준 상대 경로를 지운다. 없으면 조용히 통과(멱등).
  Future<void> deleteRelative(String contentId, String relativeInContent) =>
      gate.write(() async {
        final file = File(absolutePathOf(contentId, relativeInContent));
        if (await file.exists()) await file.delete();
      });

  /// 파일이 실재하나. 재생 전에 확인해 죽은 트랙을 걸러낸다.
  Future<bool> exists(String contentId, String relativeInContent) =>
      File(absolutePathOf(contentId, relativeInContent)).exists();

  /// 콘텐츠가 차지하는 용량(바이트). 설정 화면의 저장공간 표시에 쓴다.
  Future<int> contentSizeBytes(String contentId) async {
    final dir = Directory(_abs(AppPaths.contentDir(contentId)));
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        try {
          total += await entity.length();
        } on FileSystemException {
          // 집계 중 파일이 사라질 수 있다. 무시하고 계속 센다.
        }
      }
    }
    return total;
  }
}
