import 'dart:async';

import '../../domain/entities/series.dart';
import '../../domain/repositories/repositories.dart';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../core/error_codes.dart';
import '../../domain/entities/audio_track.dart';
import '../../domain/entities/book_draft.dart';
import '../../domain/entities/book_page.dart';
import '../../domain/entities/content.dart';
import '../../domain/enums/enums.dart';
import '../../domain/repositories/book_authoring_repository.dart';

/// 제작 화면 상태. IO 중 입력을 잠가 늦게 끝난 저장이 새 입력을 덮지 않게 한다.
class AuthoringViewModel extends ChangeNotifier {
  AuthoringViewModel(
    this.repository, {
    this.seriesRepository,
    this.contentRepository,
  });
  final SeriesRepository? seriesRepository;
  final ContentRepository? contentRepository;
  List<Series> seriesList = [];
  String publisherInput = '';
  String seriesInput = '';
  String volumeInput = '';
  Timer? _autosave;
  void _scheduleSave() {
    _autosave?.cancel();
    _autosave = Timer(const Duration(milliseconds: 900), () {
      if (!_disposed && isDirty && !isBusy) save();
    });
  }

  final BookAuthoringRepository repository;
  BookDraft? draft;
  bool isBusy = false;
  bool isDirty = false;
  String? error;
  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<T?> _run<T>(Future<T> Function() action) async {
    if (isBusy) return null;
    _autosave?.cancel();
    isBusy = true;
    error = null;
    _notify();
    try {
      return await action();
    } on AppException catch (e) {
      error = e.errorCode == ErrorCode.conflict
          ? '원본 책이 변경됐어요. 부모 공간으로 돌아가 초안을 확인해 주세요.'
          : (e.detail ?? e.errorCode.userMessage);
    } on Object {
      error = '작업을 마치지 못했어요. 입력은 유지되니 다시 시도해 주세요.';
    } finally {
      isBusy = false;
      _notify();
    }
    return null;
  }

  Future<void> load(String? id, {String? seriesId}) async {
    await _run(() async {
      draft = id == null
          ? await repository.create('')
          : await repository.open(id);
      seriesList = await seriesRepository?.getAll() ?? [];
      final selected = seriesList
          .where((s) => s.id == (seriesId ?? draft!.content.seriesId))
          .firstOrNull;
      publisherInput = draft!.content.publisher ?? selected?.publisher ?? '';
      seriesInput = selected?.title ?? '';
      volumeInput = draft!.content.volume?.toString() ?? '';
      if (id == null && selected != null) {
        final books = await contentRepository?.getAll() ?? [];
        final volumes = books
            .where((b) => b.seriesId == selected.id)
            .map((b) => b.volume ?? 0);
        final next = volumes.fold<int>(0, (a, b) => a > b ? a : b) + 1;
        volumeInput = '$next';
        draft = draft!.copyWith(
          content: draft!.content.copyWith(
            publisher: publisherInput,
            seriesId: selected.id,
            volume: next,
          ),
        );
      }
      isDirty = false;
    });
  }

  void updateClassification({
    String? publisher,
    String? series,
    String? volume,
  }) {
    if (isBusy) return;
    if (publisher != null) publisherInput = publisher;
    if (series != null) seriesInput = series;
    if (volume != null) volumeInput = volume;
    _edit(draft?.content);
  }

  Future<void> _resolveClassification() async {
    if (draft == null || seriesRepository == null) return;
    final volume = int.tryParse(volumeInput.trim());
    if (volumeInput.trim().isNotEmpty && (volume == null || volume < 1)) {
      throw const AppException(
        ErrorCode.badRequest,
        detail: '책 번호는 1 이상의 정수로 입력해 주세요.',
      );
    }
    String? seriesId;
    final publisher = publisherInput.trim();
    final title = seriesInput.trim();
    if (title.isNotEmpty) {
      var selected = seriesList
          .where((s) => s.title == title && (s.publisher ?? '') == publisher)
          .firstOrNull;
      if (selected == null) {
        selected = Series(
          id: const Uuid().v4(),
          title: title,
          publisher: publisher.isEmpty ? null : publisher,
        );
        await seriesRepository!.save(selected);
        seriesList = [...seriesList, selected];
      }
      seriesId = selected.id;
    }
    final json = draft!.content.toJson()
      ..['publisher'] = publisher.isEmpty ? null : publisher
      ..['seriesId'] = seriesId
      ..['volume'] = volume;
    draft = draft!.copyWith(content: Content.fromJson(json));
  }

  void updateTitle(String value) =>
      _edit(draft?.content.copyWith(title: value));
  void _edit(Content? content) {
    if (isBusy || content == null || draft == null) return;
    draft = draft!.copyWith(content: content);
    isDirty = true;
    _scheduleSave();
    _notify();
  }

  void setStep(AuthoringStep step) {
    if (isBusy || draft == null) return;
    draft = draft!.copyWith(step: step);
    isDirty = true;
    _scheduleSave();
    _notify();
  }

  void setText(String pageId, String text) {
    _edit(
      draft?.content.copyWith(
        pages: draft!.content.pages
            .map((p) => p.id == pageId ? p.copyWith(text: text) : p)
            .toList(),
      ),
    );
  }

  void reorder(int from, int to) {
    if (draft == null || isBusy) return;
    final pages = draft!.content.orderedPages;
    if (from < 0 || from >= pages.length || to < 0 || to >= pages.length) {
      return;
    }
    pages.insert(to, pages.removeAt(from));
    _edit(
      draft!.content.copyWith(
        pages: [
          for (var i = 0; i < pages.length; i++)
            pages[i].copyWith(orderIndex: i),
        ],
      ),
    );
  }

  void removePage(String id) {
    if (draft == null) return;
    final pages = draft!.content.orderedPages.where((p) => p.id != id).toList();
    _edit(
      draft!.content.copyWith(
        pages: [
          for (var i = 0; i < pages.length; i++)
            pages[i].copyWith(orderIndex: i),
        ],
      ),
    );
  }

  Future<bool> save() async =>
      await _run(() async {
        if (draft == null) return false;
        await _resolveClassification();
        final next = draft!.copyWith(savedAt: DateTime.now());
        await repository.save(next);
        draft = next;
        isDirty = false;
        return true;
      }) ??
      false;

  Future<void> setCoverPhoto(String path) async {
    await _run(() async {
      final current = draft;
      if (current == null) return;
      final relative = await repository.importMedia(
        current.id,
        path,
        path.toLowerCase().endsWith('.png') ? 'png' : 'jpg',
      );
      draft = current.copyWith(
        content: current.content.copyWith(coverPath: relative),
      );
      isDirty = true;
    });
  }

  /// 연속 촬영은 각 사진을 디스크에 보관한 뒤 성공을 알려 순서/장수를 확정한다.
  Future<bool> capturePage(String path) async =>
      await _run(() async {
        final current = draft;
        if (current == null) return false;
        final relative = await repository.importMedia(
          current.id,
          path,
          path.toLowerCase().endsWith('.png') ? 'png' : 'jpg',
        );
        final next = current.copyWith(
          savedAt: DateTime.now(),
          content: current.content.copyWith(
            pages: [
              ...current.content.orderedPages,
              BookPage(
                id: const Uuid().v4(),
                orderIndex: current.content.pageCount,
                imagePath: relative,
              ),
            ],
          ),
        );
        await repository.save(next);
        draft = next;
        isDirty = false;
        return true;
      }) ??
      false;

  Future<void> addPhoto(String path) async {
    await _run(() async {
      final current = draft;
      if (current == null) return;
      final relative = await repository.importMedia(
        current.id,
        path,
        path.toLowerCase().endsWith('.png') ? 'png' : 'jpg',
      );
      final page = BookPage(
        id: const Uuid().v4(),
        orderIndex: current.content.pages.length,
        imagePath: relative,
      );
      draft = current.copyWith(
        content: current.content.copyWith(
          pages: [...current.content.orderedPages, page],
        ),
      );
      isDirty = true;
    });
  }

  Future<void> replacePagePhoto(String pageId, String path) async {
    await _run(() async {
      final current = draft;
      if (current == null ||
          !current.content.pages.any((p) => p.id == pageId)) {
        return;
      }
      final relative = await repository.importMedia(
        current.id,
        path,
        path.toLowerCase().endsWith('.png') ? 'png' : 'jpg',
      );
      final next = current.copyWith(
        content: current.content.copyWith(
          pages: current.content.pages
              .map((p) => p.id == pageId ? p.copyWith(imagePath: relative) : p)
              .toList(),
        ),
        savedAt: DateTime.now(),
      );
      await repository.save(next);
      draft = next;
      isDirty = false;
    });
  }

  /// [durationMs] 는 녹음한 시간. 내 목소리 자료의 분량을 세는 데 쓴다(2026-11-22).
  Future<void> attachRecording(
    String pageId,
    String path, {
    int? durationMs,
  }) async {
    await _run(() async {
      final current = draft;
      if (current == null) return;
      final relative = await repository.importMedia(current.id, path, 'm4a');
      final track = AudioTrack(
        id: const Uuid().v4(),
        source: AudioSource.parentRecording,
        path: relative,
        durationMs: durationMs,
        createdAt: DateTime.now(),
      );
      draft = current.copyWith(
        content: current.content.copyWith(
          pages: current.content.pages
              .map(
                (p) => p.id == pageId
                    ? p.copyWith(
                        tracks: [
                          ...p.tracks.where(
                            (t) => t.source != AudioSource.parentRecording,
                          ),
                          track,
                        ],
                      )
                    : p,
              )
              .toList(),
        ),
      );
      isDirty = true;
    });
  }

  void useDeviceVoice(String pageId) {
    if (draft == null) return;
    final track = AudioTrack(
      id: const Uuid().v4(),
      source: AudioSource.deviceTts,
      createdAt: DateTime.now(),
    );
    _edit(
      draft!.content.copyWith(
        pages: draft!.content.pages
            .map(
              (p) => p.id == pageId
                  ? p.copyWith(
                      tracks: [
                        ...p.tracks.where(
                          (t) => t.source != AudioSource.deviceTts,
                        ),
                        track,
                      ],
                    )
                  : p,
            )
            .toList(),
      ),
    );
  }

  Future<Content?> publish() => _run(() async {
    if (draft == null) throw const AppException(ErrorCode.badRequest);
    if (seriesInput.trim().isEmpty) {
      throw const AppException(ErrorCode.badRequest, detail: '전집을 입력해 주세요.');
    }
    if (volumeInput.trim().isEmpty) {
      throw const AppException(ErrorCode.badRequest, detail: '책 번호를 입력해 주세요.');
    }
    await _resolveClassification();
    final result = await repository.publish(draft!);
    isDirty = false;
    return result;
  });
  @override
  void dispose() {
    _autosave?.cancel();
    _disposed = true;
    super.dispose();
  }
}
