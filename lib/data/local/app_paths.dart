/// 로컬 파일 레이아웃의 경로 규칙. **[1_DESIGN §1.3] 과 일치해야 한다.**
///
/// ```
/// {AppDocumentsDir}/
/// ├── library/{contentId}/
/// │   ├── data.json
/// │   ├── cover.jpg
/// │   ├── pages/page_000.jpg …
/// │   ├── audio/{pageId}_{source}[_{voiceProfileId}].mp3
/// │   └── video.mp4
/// └── index/{series,playlists,children,voice_profiles,reading_events}.json
/// ```
///
/// 왜 문자열을 흩뿌리지 않고 여기 모으나: 경로 규칙이 코드 여러 곳에 복사되면
/// 하나를 고칠 때 나머지가 남아 조용히 어긋난다. 백업/복구도 이 규칙에 의존한다.
class AppPaths {
  AppPaths._();

  // ── 최상위 ────────────────────────────────────────────────
  static const String libraryDir = 'library';
  static const String indexDir = 'index';
  static const String draftsDir = 'drafts';
  static const String readingPositionsDir = 'reading_positions';

  /// 기기 설정. **백업 루트가 아니다** — 기기마다 다른 선택이라 백업 · 복원에서 뺀다.
  static const String settingsDir = 'settings';
  static const String watchSettingsFile = '$settingsDir/watch.json';

  // ── 인덱스 파일 (앱 문서 디렉토리 기준 상대) ──────────────
  static const String seriesFile = '$indexDir/series.json';
  static const String playlistsFile = '$indexDir/playlists.json';
  static const String childrenFile = '$indexDir/children.json';
  static const String voiceProfilesFile = '$indexDir/voice_profiles.json';
  static const String readingEventsFile = '$indexDir/reading_events.json';
  static const String topicsFile = '$indexDir/topics.json';
  static const String bookTagsFile = '$indexDir/book_tags.json';

  // ── 콘텐츠별 ──────────────────────────────────────────────

  /// `library/{contentId}`
  static String contentDir(String contentId) => '$libraryDir/$contentId';

  /// `library/{contentId}/data.json` — 이 콘텐츠의 진실.
  static String contentDataFile(String contentId) =>
      '${contentDir(contentId)}/data.json';

  /// 콘텐츠 폴더 **기준 상대** 경로들. `Content` 엔티티에 저장되는 값이다.
  ///
  /// ⚠️ 절대 경로를 저장하지 않는다 — iOS 앱 문서 디렉토리 경로는 재설치·복원 시
  /// 바뀌므로 절대 경로를 저장하면 백업 복구 후 전부 깨진다.
  static const String coverRelative = 'cover.jpg';
  static const String videoRelative = 'video.mp4';
  static const String pagesSubdir = 'pages';
  static const String audioSubdir = 'audio';

  /// `pages/page_000.jpg` — 순서를 3자리로 채워 파일명 정렬이 페이지 순서와 맞게 한다.
  static String pageImageRelative(int orderIndex) =>
      '$pagesSubdir/page_${orderIndex.toString().padLeft(3, '0')}$_imageExt';

  /// `audio/{pageId}_{source}[_{voiceProfileId}].{ext}`
  ///
  /// [voiceProfileId] 를 파일명에 넣는 이유: 같은 페이지에 엄마·아빠 목소리가
  /// 동시에 존재할 수 있으므로 이름이 겹치면 서로 덮어쓴다.
  static String audioRelative({
    required String pageId,
    required String sourceName,
    String? voiceProfileId,
    String extension = 'm4a',
  }) {
    final suffix = (voiceProfileId == null || voiceProfileId.isEmpty)
        ? ''
        : '_$voiceProfileId';
    return '$audioSubdir/${pageId}_$sourceName$suffix.$extension';
  }

  static const String _imageExt = '.jpg';
}
