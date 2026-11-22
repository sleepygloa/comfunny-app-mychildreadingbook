import '../../core/json_codec.dart';
import '../../domain/repositories/repositories.dart';
import '../local/app_paths.dart';
import '../local/json_store.dart';

/// `settings/watch.json` — `{schemaVersion: 1, data: {allowMirroring}}`.
class WatchSettingsRepositoryImpl implements WatchSettingsRepository {
  WatchSettingsRepositoryImpl(this.store);
  final JsonStore store;

  @override
  Future<bool> allowMirroring() async {
    // 파일이 없거나 깨졌으면 막음(기본값)으로 읽는다 — 설정 하나 때문에 보기가 멈추면 안 된다.
    try {
      final raw = await store.readMap(AppPaths.watchSettingsFile);
      return asBool(raw?['allowMirroring']);
    } on Object {
      return false;
    }
  }

  @override
  Future<void> setAllowMirroring(bool value) =>
      store.writeMap(AppPaths.watchSettingsFile, {'allowMirroring': value});
}
