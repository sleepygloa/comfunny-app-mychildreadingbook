import 'dart:convert';
import 'dart:io';

import 'storage_gate.dart';

import '../../core/app_logger.dart';
import '../../core/error_codes.dart';
import '../../core/json_codec.dart';

/// 로컬 JSON 파일 읽기/쓰기.
///
/// 이 앱은 **로컬 우선**이라 이 클래스가 사실상 데이터베이스다. 두 가지를 보장한다.
///
/// **① 원자적 쓰기** — 임시파일에 쓰고 `rename` 한다. 쓰는 중 앱이 죽어도 원본이 남는다.
/// 직접 덮어쓰면 절반만 쓰인 파일이 남아 **사용자가 만든 책이 사라진다.**
///
/// **② 스키마 버전 봉투** — 모든 파일을 `{schemaVersion, data}` 로 감싼다.
/// 구버전 앱이 미래 버전 파일을 만나면 **읽지 않고 예외를 던진다** — 덮어쓰면
/// 신버전 데이터가 소실된다([1_DESIGN ADR] · AGENTS.md §3).
///
/// 왜 [baseDir] 를 주입받나: `path_provider` 는 플랫폼 채널이라 단위 테스트에서 못 쓴다.
/// 디렉토리를 받으면 임시 폴더로 테스트할 수 있다.
class JsonStore {
  JsonStore(this.baseDir, {StorageGate? gate}) : gate = gate ?? StorageGate();
  final StorageGate gate;

  final Directory baseDir;

  /// 현재 스키마 버전. **데이터 구조를 깨는 변경 시 올린다.**
  ///
  /// 필드 추가만이라면 올리지 않는다 — 구버전이 모르는 필드를 무시하므로 호환된다.
  /// 필드 삭제·타입 변경·의미 변경일 때만 올린다.
  static const int schemaVersion = 1;

  static const String _kVersion = 'schemaVersion';
  static const String _kData = 'data';

  File _file(String relativePath) =>
      File('${baseDir.path}${Platform.pathSeparator}$relativePath');

  /// 파일이 있나.
  Future<bool> exists(String relativePath) => _file(relativePath).exists();

  /// 맵 하나를 읽는다. 파일이 없으면 `null`.
  ///
  /// 파일이 깨져 있으면 `null` 을 돌려주고 로그를 남긴다 — 예외를 던지면 앱이 기동조차
  /// 못 한다. 한 파일이 깨졌다고 전체를 막지 않는다.
  Future<Map<String, Object?>?> readMap(String relativePath) async {
    final raw = await _readEnvelope(relativePath);
    if (raw == null) return null;
    return raw is Map ? asMap(raw) : null;
  }

  /// 리스트를 읽는다. 파일이 없거나 깨져 있으면 빈 리스트.
  Future<List<Map<String, Object?>>> readList(String relativePath) async {
    final raw = await _readEnvelope(relativePath);
    if (raw is! List) return const [];
    return raw.whereType<Map>().map(asMap).toList();
  }

  /// 봉투를 벗겨 `data` 를 돌려준다.
  Future<Object?> _readEnvelope(String relativePath) async {
    final file = _file(relativePath);
    if (!await file.exists()) return null;

    String text;
    try {
      text = await file.readAsString();
    } on FileSystemException catch (e, st) {
      AppLogger.e('파일 읽기 실패: $relativePath', error: e, stackTrace: st);
      return null;
    }
    if (text.trim().isEmpty) return null;

    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException catch (e, st) {
      // 깨진 JSON. 덮어쓰지 않고 그대로 두어 사용자가 복구할 여지를 남긴다.
      AppLogger.e('JSON 파싱 실패: $relativePath', error: e, stackTrace: st);
      return null;
    }

    if (decoded is! Map) {
      // 봉투가 없는 구형 파일. data 자체로 취급해 호환한다.
      return decoded;
    }
    final map = asMap(decoded);
    if (!map.containsKey(_kVersion)) return map[_kData] ?? decoded;

    final fileVersion = asInt(map[_kVersion], fallback: schemaVersion);
    if (fileVersion > schemaVersion) {
      // 미래 버전이다. 읽지 않는다 — 잘못 해석한 뒤 저장하면 신버전 데이터가 깨진다.
      AppLogger.w(
        '스키마 버전이 앱보다 높다: $relativePath (파일 $fileVersion > 앱 $schemaVersion)',
      );
      throw const AppException(
        ErrorCode.storageFailure,
        detail: '앱 업데이트가 필요합니다 (저장 데이터가 더 새 버전입니다)',
      );
    }
    return map[_kData];
  }

  /// 맵 하나를 원자적으로 쓴다.
  Future<void> writeMap(String relativePath, Map<String, Object?> data) =>
      gate.write(() => _writeEnvelope(relativePath, data));

  /// 리스트를 원자적으로 쓴다.
  Future<void> writeList(
    String relativePath,
    List<Map<String, Object?>> data,
  ) => gate.write(() => _writeEnvelope(relativePath, data));

  /// **임시파일 → rename** 으로 쓴다. rename 은 같은 파일시스템에서 원자적이다.
  Future<void> _writeEnvelope(String relativePath, Object? data) async {
    final file = _file(relativePath);
    await file.parent.create(recursive: true);

    // 왜 `.tmp` 접미인가: 앱이 죽어 잔재가 남아도 실제 데이터 파일과 구분된다.
    final tmp = File('${file.path}.tmp');
    final envelope = <String, Object?>{_kVersion: schemaVersion, _kData: data};

    try {
      // FLOW 1: 임시파일에 전량 기록
      await tmp.writeAsString(jsonEncode(envelope), flush: true);
      // FLOW 2: 원자적 교체 — 이 시점 이전에 죽으면 원본이 온전하다
      await tmp.rename(file.path);
    } on FileSystemException catch (e, st) {
      AppLogger.e('파일 쓰기 실패: $relativePath', error: e, stackTrace: st);
      // FLOW 9: 실패 시 임시파일 정리 (남겨두면 다음 쓰기와 충돌하지 않지만 쓰레기다)
      if (await tmp.exists()) {
        try {
          await tmp.delete();
        } on FileSystemException {
          // 정리 실패는 무시한다 — 본래 실패를 가리면 원인 추적이 어려워진다.
        }
      }
      throw AppException(
        ErrorCode.storageFailure,
        detail: relativePath,
        cause: e,
      );
    }
  }

  /// 파일을 지운다. 없으면 조용히 통과한다(멱등).
  Future<void> delete(String relativePath) => gate.write(() async {
    final file = _file(relativePath);
    if (await file.exists()) await file.delete();
  });

  /// 디렉토리를 통째로 지운다. 콘텐츠 삭제(미디어 포함)에 쓴다.
  Future<void> deleteDirectory(String relativePath) => gate.write(() async {
    final dir = Directory(
      '${baseDir.path}${Platform.pathSeparator}$relativePath',
    );
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  /// 하위 디렉토리 이름 목록. `library/` 스캔에 쓴다.
  Future<List<String>> listSubdirectories(String relativePath) async {
    final dir = Directory(
      '${baseDir.path}${Platform.pathSeparator}$relativePath',
    );
    if (!await dir.exists()) return const [];
    final out = <String>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is Directory) {
        out.add(entity.path.split(Platform.pathSeparator).last);
      }
    }
    out.sort();
    return out;
  }
}
