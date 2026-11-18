/// 새 쓰기를 UI에서 막은 뒤 이미 시작한 저장의 완료를 기다린다.
abstract interface class PendingWrites {
  Future<void> waitForWrites();
}
