/// 파일 무결성 검증 결과. 앱 데이터의 의미/재생 가능 여부를 보증하지 않는다.
class BackupSummary {
  const BackupSummary({required this.fileCount, required this.totalBytes});
  final int fileCount;
  final int totalBytes;
}

/// 로컬 백업 기반 계약. 호출자는 촬영·녹음·저장 등 쓰기를 중지해야 한다.
/// 아직 UI/활성 저장소 교체에는 연결하지 않는다. 복원은 새 경로만 허용한다.
abstract interface class BackupRepository {
  Future<BackupSummary> create(String destinationPath);
  Future<BackupSummary> verify(String backupPath);
  Future<BackupSummary> restoreToNewDirectory(
    String backupPath,
    String destinationPath,
  );
}
