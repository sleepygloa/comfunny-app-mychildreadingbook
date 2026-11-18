class RecentPlayback {
  RecentPlayback({required List<String> bookIds, this.currentId})
    : bookIds = List.unmodifiable(bookIds);
  final List<String> bookIds;
  final String? currentId;
}

abstract interface class RecentPlaybackRepository {
  Future<RecentPlayback> load();
  Future<void> save(RecentPlayback value);
}
