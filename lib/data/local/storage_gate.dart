import 'dart:async';

import '../../core/error_codes.dart';

/// 복원 중 새 변경을 거절하고, 이미 접수한 중첩 저장까지 끝난 뒤 교체한다.
class StorageGate {
  final Object _zoneKey = Object();
  bool _blocked = false;
  int _active = 0;
  Completer<void>? _drained;
  bool get isBlocked => _blocked;

  Future<T> write<T>(Future<T> Function() action) async {
    if (Zone.current[_zoneKey] == this) return action();
    if (_blocked) throw const AppException(ErrorCode.conflict);
    _active++;
    try {
      return await runZoned(action, zoneValues: {_zoneKey: this});
    } finally {
      _active--;
      if (_active == 0) _drained?.complete();
    }
  }

  Future<void> freeze() async {
    if (_blocked) throw const AppException(ErrorCode.conflict);
    _blocked = true;
    if (_active > 0) {
      _drained = Completer<void>();
      await _drained!.future;
      _drained = null;
    }
  }

  void thaw() => _blocked = false;
}
