import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../data/local/authoring_media_store.dart';
import '../../data/local/json_store.dart';
import '../../data/services/device_tts_service.dart';
import '../../data/services/recording_service.dart';
import '../../core/app_logger.dart';
import '../../core/error_codes.dart';
import '../../domain/services/text_extractor.dart';
import '../../domain/entities/book_page.dart';
import '../../domain/enums/enums.dart';
import '../../service_locator.dart';
import 'authoring_view_model.dart';
import 'capture_screen.dart';
import 'photo_edit_screen.dart';
import '../player/playback_queue.dart';

class AuthoringScreen extends StatefulWidget {
  const AuthoringScreen({super.key, this.voiceOnly = false});
  final bool voiceOnly;
  @override
  State<AuthoringScreen> createState() => _AuthoringScreenState();
}

class _AuthoringScreenState extends State<AuthoringScreen>
    with WidgetsBindingObserver {
  RecordingService? _recorder;
  AudioPlayer? _preview;
  String? _recordingPage;
  bool _recordBusy = false;
  int _mediaGeneration = 0;
  DeviceTtsService? _previewTts;
  bool _allowPop = false;
  String? _message;
  late AuthoringViewModel _vm;

  /// 글자 뽑기 중인 쪽. 한 번에 한 쪽만 — 인식기는 하나다.
  String? _extractingPage;

  /// 글을 큰 글씨로 펼쳐 둔 쪽들. 녹음하면서 보고 읽는다.
  final Set<String> _bigText = {};

  /// 글 입력칸을 새 값으로 다시 그리기 위한 쪽별 번호.
  /// 왜: 입력칸은 initialValue 로 한 번만 채워진다. 뽑은 글을 넣으면 key 를 바꿔 새로 만든다.
  final Map<String, int> _textRevision = {};
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _vm = context.read<AuthoringViewModel>();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _mediaGeneration++;
      _preview?.stop();
      _previewTts?.stop();
      if (_vm.isDirty && !_vm.isBusy && _recordingPage == null) _vm.save();
      if (_recordingPage != null && !_recordBusy) _stopRecording();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _mediaGeneration++;
    _recorder?.dispose();
    _previewTts?.stop();
    _preview?.dispose();
    super.dispose();
  }

  Future<void> _leave() async {
    if (_recordBusy || _vm.isBusy) return;
    if (_recordingPage != null) await _stopRecording();
    if (!mounted) return;
    // 자동저장 화면의 뒤로 가기는 최신 입력을 저장한 뒤 닫는다.
    if (_vm.isDirty && !await _vm.save()) return;
    if (mounted) {
      setState(() => _allowPop = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.pop();
      });
    }
  }

  Future<void> _record(String pageId) async {
    if (_recordBusy) return;
    if (_recordingPage != null) {
      await _stopRecording();
      return;
    }
    final generation = ++_mediaGeneration;
    setState(() => _recordBusy = true);
    try {
      await _preview?.stop();
      await _previewTts?.stop();
      _recorder ??= RecordingService();
      final tmp = await getTemporaryDirectory();
      if (!mounted || generation != _mediaGeneration) return;
      await _recorder!.start('${tmp.path}/${const Uuid().v4()}.m4a');
      if (!mounted || generation != _mediaGeneration) {
        await _recorder!.cancel();
        return;
      }
      if (mounted) setState(() => _recordingPage = pageId);
    } on Object {
      if (mounted) setState(() => _message = '녹음을 시작하지 못했어요. 마이크 권한을 확인해 주세요.');
    } finally {
      if (mounted) setState(() => _recordBusy = false);
    }
  }

  Future<void> _stopRecording() async {
    final id = _recordingPage;
    if (id == null) return;
    setState(() => _recordBusy = true);
    try {
      final path = await _recorder?.stop();
      if (path != null) {
        await _vm.attachRecording(id, path);
        if (!_vm.isBusy && _vm.error == null) await _vm.save();
      }
      if (mounted) {
        setState(
          () =>
              _message = path == null ? '녹음이 너무 짧아요. 다시 녹음해 주세요.' : '녹음을 마쳤어요.',
        );
      }
    } on Object {
      if (mounted) setState(() => _message = '녹음을 저장하지 못했어요. 다시 시도해 주세요.');
    } finally {
      if (mounted) {
        setState(() {
          _recordBusy = false;
          _recordingPage = null;
        });
      }
    }
  }

  Future<void> _listen(BookPage page) async {
    final generation = ++_mediaGeneration;
    try {
      await _preview?.stop();
      await _previewTts?.stop();
      final track = page.tracks
          .where((t) => t.source == AudioSource.parentRecording && t.hasFile)
          .firstOrNull;
      if (track == null) {
        if (page.hasText &&
            page.tracks.any((t) => t.source == AudioSource.deviceTts)) {
          _previewTts ??= sl<DeviceTtsService>();
          if (!mounted || generation != _mediaGeneration) return;
          await _previewTts!.speak(page.text!);
          if (!mounted || generation != _mediaGeneration) {
            await _previewTts?.stop();
          }
        } else if (mounted) {
          setState(() => _message = '먼저 부모 목소리를 녹음해 주세요.');
        }
        return;
      }
      final file = await AuthoringMediaStore(sl<JsonStore>().baseDir)
          .file('drafts', _vm.draft!.id, track.path!);
      if (!mounted || generation != _mediaGeneration) return;
      _preview ??= AudioPlayer();
      await _preview!.play(DeviceFileSource(file.path));
      if (!mounted || generation != _mediaGeneration) await _preview?.stop();
    } on Object {
      if (mounted) setState(() => _message = '미리 듣지 못했어요. 녹음을 확인해 주세요.');
    }
  }

  /// 사진에서 글자를 뽑아 그 쪽 글을 채운다.
  Future<void> _extractText(BookPage page) async {
    // FLOW 1: 다른 작업 중이면 하지 않는다. 이미 쓴 글은 덮기 전에 묻는다
    if (_extractingPage != null || _vm.isBusy || _vm.draft == null) return;
    final extractor = sl<TextExtractor>();
    if (!extractor.isAvailable) {
      setState(() => _message = '이 기기에서는 아직 글자 뽑기를 쓸 수 없어요. 글을 직접 적어 주세요.');
      return;
    }
    if (page.hasText) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('지금 글을 바꿀까요?'),
          content: const Text('사진에서 새로 뽑은 글로 바꿔요.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('그대로 두기'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('바꾸기'),
            ),
          ],
        ),
      );
      if (replace != true || !mounted) return;
    }
    setState(() {
      _extractingPage = page.id;
      _message = null;
    });
    try {
      // FLOW 2: 초안 폴더의 실제 사진 파일을 찾는다
      final file = await AuthoringMediaStore(sl<JsonStore>().baseDir)
          .file('drafts', _vm.draft!.id, page.imagePath);
      // FLOW 3: 기기 안에서 읽고 녹음하기 좋게 다듬는다
      final text = tidyExtractedText(await extractor.extract(file.path));
      if (!mounted) return;
      if (text.isEmpty) {
        setState(
          () => _message = '글자를 찾지 못했어요. 사진을 "글자 또렷하게"로 보정한 뒤 다시 해 보세요.',
        );
        return;
      }
      // FLOW 4: 글을 채우고 큰 글씨로 펼친다 — 바로 보고 녹음할 수 있게
      _vm.setText(page.id, text);
      setState(() {
        _textRevision[page.id] = (_textRevision[page.id] ?? 0) + 1;
        _bigText.add(page.id);
        _message = '글을 뽑았어요. 틀린 글자는 "글 · 기기 읽기"에서 고쳐 주세요.';
      });
    } on Object catch (e) {
      // 글 내용·파일 경로는 남기지 않는다 [A-08]
      AppLogger.w('${ErrorCode.textExtractFailure} 글자 뽑기 실패: ${e.runtimeType}');
      if (mounted) {
        setState(() => _message = ErrorCode.textExtractFailure.userMessage);
      }
    } finally {
      // FLOW 9: 버튼을 다시 켠다
      if (mounted) setState(() => _extractingPage = null);
    }
  }

  /// 뽑은 글을 큰 칸에서 바로 고친다.
  /// 왜: 기존 입력칸은 "글 · 기기 읽기" 안에 접혀 있어 찾기 어렵다(2026-11-22 오너 요청).
  Future<void> _editText(BookPage page) async {
    // FLOW 1: 지금 글로 고치기 창을 연다
    final edited = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _EditTextSheet(initial: page.text ?? ''),
    );
    // FLOW 2: 고친 글을 쪽에 담고 입력칸도 새 값으로 다시 그린다
    if (edited == null || !mounted) return;
    // 자동 저장이 도는 중이면 입력이 잠겨 고친 글이 버려진다 — 저장이 끝날 때까지 잠깐 기다린다
    for (var i = 0; i < 100 && _vm.isBusy; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (!mounted) return;
    }
    _vm.setText(page.id, edited.trim());
    // FLOW 9: 화면을 새로 그린다
    setState(() => _textRevision[page.id] = (_textRevision[page.id] ?? 0) + 1);
  }

  Widget _image(String path) => FutureBuilder<File>(
    future: AuthoringMediaStore(sl<JsonStore>().baseDir)
        .file('drafts', _vm.draft!.id, path),
    builder: (context, snapshot) => snapshot.data == null
        ? const SizedBox(
            height: 120,
            child: Center(child: Icon(Icons.image_outlined)),
          )
        : ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.file(
              snapshot.data!,
              height: 180,
              width: double.infinity,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const SizedBox(
                height: 100,
                child: Center(child: Text('사진을 찾을 수 없어요')),
              ),
            ),
          ),
  );
  Future<void> _capture({bool cover = false}) async {
    await _preview?.stop();
    await _previewTts?.stop();
    if (!mounted) return;
    if (_vm.isDirty && !await _vm.save()) return;
    if (!mounted) return;
    final path = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            CaptureScreen(onPageCaptured: cover ? null : _vm.capturePage),
      ),
    );
    if (path != null && mounted) {
      if (cover) {
        await _vm.setCoverPhoto(path);
      } else {
        await _vm.addPhoto(path);
      }
      if (_vm.error == null) await _vm.save();
    }
  }

  Future<void> _editPhoto({BookPage? page}) async {
    if (_vm.isDirty && !await _vm.save()) return;
    final relative = page?.imagePath ?? _vm.draft?.content.coverPath;
    if (relative == null) return;
    try {
      final file = await AuthoringMediaStore(sl<JsonStore>().baseDir)
          .file('drafts', _vm.draft!.id, relative);
      if (!mounted) return;
      final result = await Navigator.push<String>(
        context,
        MaterialPageRoute(builder: (_) => PhotoEditScreen(path: file.path)),
      );
      if (result == null || !mounted) return;
      if (page == null) {
        await _vm.setCoverPhoto(result);
        if (_vm.error == null) await _vm.save();
      } else {
        await _vm.replacePagePhoto(page.id, result);
      }
    } on Object {
      if (mounted) setState(() => _message = '사진을 열지 못했어요. 다시 시도해 주세요.');
    }
  }

  Future<void> _saveBook() async {
    await _preview?.stop();
    await _previewTts?.stop();
    final result = await _vm.publish();
    if (!mounted) return;
    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_vm.error ?? '저장하지 못했어요. 다시 시도해 주세요.')),
      );
      return;
    }
    await context.read<PlaybackQueue>().refreshBook(result);
    if (!mounted) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.pop();
    });
  }

  Widget _classificationField(
    String label,
    String initial,
    Iterable<String> choices,
    ValueChanged<String> changed,
    bool enabled,
  ) {
    return Autocomplete<String>(
      initialValue: TextEditingValue(text: initial),
      optionsBuilder: (value) => choices.toSet().where(
        (s) => s.toLowerCase().contains(value.text.toLowerCase()),
      ),
      onSelected: changed,
      fieldViewBuilder: (context, controller, focus, submit) => TextField(
        controller: controller,
        focusNode: focus,
        enabled: enabled,
        decoration: InputDecoration(labelText: label),
        onChanged: changed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<AuthoringViewModel>();
    final draft = vm.draft;
    final locked = vm.isBusy || _recordBusy || _recordingPage != null;
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            onPressed: _leave,
            icon: const Icon(Icons.arrow_back),
            tooltip: '책장으로',
          ),
          title: Text(widget.voiceOnly ? '목소리 넣기' : '책 만들기'),
          actions: [
            TextButton(
              onPressed: locked ? null : _saveBook,
              child: const Text('저장'),
            ),
          ],
        ),
        body: SafeArea(
          child: draft == null
              ? Center(
                  child: vm.error == null
                      ? const CircularProgressIndicator()
                      : Text(vm.error!),
                )
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        Text(
                          widget.voiceOnly ? '페이지마다 목소리를 담아요' : '사진으로 만드는 우리 책',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          vm.isBusy
                              ? '저장하는 중…'
                              : vm.isDirty
                              ? '변경사항을 저장할게요'
                              : '작성 내용이 자동 보관돼요',
                        ),
                        const SizedBox(height: 20),
                        if (vm.error != null || _message != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Text(
                              vm.error ?? _message!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        if (!widget.voiceOnly) ...[
                          TextFormField(
                            key: ValueKey('title-${draft.id}'),
                            initialValue: draft.content.title,
                            enabled: !locked,
                            decoration: const InputDecoration(
                              labelText: '책 제목',
                            ),
                            onChanged: vm.updateTitle,
                          ),
                          const SizedBox(height: 12),
                          ExpansionTile(
                            title: const Text('출판사 · 전집 · 책 번호'),
                            initiallyExpanded: true,
                            tilePadding: EdgeInsets.zero,
                            children: [
                              _classificationField(
                                '출판사 (선택)',
                                vm.publisherInput,
                                vm.seriesList
                                    .map((s) => s.publisher ?? '')
                                    .where((s) => s.isNotEmpty),
                                (v) => vm.updateClassification(publisher: v),
                                !locked,
                              ),
                              const SizedBox(height: 12),
                              _classificationField(
                                '전집 (필수)',
                                vm.seriesInput,
                                vm.seriesList
                                    .where(
                                      (s) =>
                                          (s.publisher ?? '') ==
                                          vm.publisherInput.trim(),
                                    )
                                    .map((s) => s.title),
                                (v) => vm.updateClassification(series: v),
                                !locked,
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                initialValue: vm.volumeInput,
                                enabled: !locked,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: '책 번호 (필수)',
                                ),
                                onChanged: (v) =>
                                    vm.updateClassification(volume: v),
                              ),
                              const SizedBox(height: 12),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '책 표지',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                              ),
                              TextButton.icon(
                                onPressed: locked
                                    ? null
                                    : () => _capture(cover: true),
                                icon: const Icon(Icons.photo_camera_outlined),
                                label: Text(
                                  draft.content.coverPath == null
                                      ? '표지 촬영'
                                      : '표지 다시 촬영',
                                ),
                              ),
                            ],
                          ),
                          if (draft.content.coverPath != null)
                            _image(draft.content.coverPath!),
                          if (draft.content.coverPath != null)
                            TextButton.icon(
                              onPressed: locked ? null : () => _editPhoto(),
                              icon: const Icon(Icons.crop),
                              label: const Text('표지 자르기 · 보정'),
                            ),
                          const Text('책장에서 보이는 표지예요. 본문에는 포함되지 않아요.'),
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '내용 ${draft.content.pageCount}쪽',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                              ),
                              TextButton.icon(
                                onPressed: locked ? null : () => _capture(),
                                icon: const Icon(Icons.add_a_photo_outlined),
                                label: const Text('내용 연속 촬영'),
                              ),
                            ],
                          ),
                          if (draft.content.pages.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 32),
                              child: Text(
                                '책을 펼쳐 내용을 촬영해 주세요. 사진만으로도 책을 저장할 수 있어요.',
                              ),
                            ),
                        ],
                        for (final page in draft.content.orderedPages)
                          Card(
                            key: ValueKey(page.id),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${page.orderIndex + 1}쪽',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                  const SizedBox(height: 12),
                                  _image(page.imagePath),
                                  const SizedBox(height: 12),
                                  if (widget.voiceOnly) ...[
                                    Text(
                                      page.tracks.any(
                                            (t) =>
                                                t.source ==
                                                    AudioSource
                                                        .parentRecording &&
                                                t.hasFile,
                                          )
                                          ? '녹음이 있어요'
                                          : page.tracks.isNotEmpty
                                          ? '기기 읽기를 사용해요'
                                          : '목소리를 담아 주세요',
                                    ),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        FilledButton.icon(
                                          onPressed:
                                              vm.isBusy ||
                                                  _recordBusy ||
                                                  (_recordingPage != null &&
                                                      _recordingPage != page.id)
                                              ? null
                                              : () => _record(page.id),
                                          icon: Icon(
                                            _recordingPage == page.id
                                                ? Icons.stop
                                                : Icons.mic_none,
                                          ),
                                          label: Text(
                                            _recordingPage == page.id
                                                ? '녹음 마치기'
                                                : '녹음',
                                          ),
                                        ),
                                        OutlinedButton.icon(
                                          onPressed: locked
                                              ? null
                                              : () => _listen(page),
                                          icon: const Icon(Icons.play_arrow),
                                          label: const Text('들어보기'),
                                        ),
                                        OutlinedButton.icon(
                                          onPressed:
                                              locked ||
                                                  _extractingPage != null ||
                                                  _recordingPage != null
                                              ? null
                                              : () => _extractText(page),
                                          icon: _extractingPage == page.id
                                              ? const SizedBox.square(
                                                  dimension: 18,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                )
                                              : const Icon(
                                                  Icons
                                                      .document_scanner_outlined,
                                                ),
                                          label: Text(
                                            _extractingPage == page.id
                                                ? '글자 읽는 중'
                                                : '사진에서 글자 뽑기',
                                          ),
                                        ),
                                        if (page.hasText)
                                          TextButton.icon(
                                            onPressed: () => setState(
                                              () => _bigText.contains(page.id)
                                                  ? _bigText.remove(page.id)
                                                  : _bigText.add(page.id),
                                            ),
                                            icon: Icon(
                                              _bigText.contains(page.id)
                                                  ? Icons.text_decrease
                                                  : Icons.text_increase,
                                            ),
                                            label: Text(
                                              _bigText.contains(page.id)
                                                  ? '큰 글씨 접기'
                                                  : '글 크게 보기',
                                            ),
                                          ),
                                      ],
                                    ),
                                    if (page.hasText &&
                                        _bigText.contains(page.id))
                                      _BigText(
                                        key: ValueKey('big-text-${page.id}'),
                                        text: page.text!,
                                        onEdit: locked
                                            ? null
                                            : () => _editText(page),
                                      ),
                                  ],
                                  if (!widget.voiceOnly)
                                    TextButton.icon(
                                      onPressed: locked
                                          ? null
                                          : () => _editPhoto(page: page),
                                      icon: const Icon(Icons.crop),
                                      label: const Text('자르기 · 보정'),
                                    ),
                                  ExpansionTile(
                                    title: Text(
                                      widget.voiceOnly
                                          ? '글 · 기기 읽기'
                                          : '페이지 순서 · 삭제',
                                    ),
                                    tilePadding: EdgeInsets.zero,
                                    children: [
                                      if (widget.voiceOnly)
                                        TextFormField(
                                          key: ValueKey(
                                            'text-${page.id}-${_textRevision[page.id] ?? 0}',
                                          ),
                                          initialValue: page.text,
                                          enabled: !locked,
                                          maxLines: 3,
                                          decoration: const InputDecoration(
                                            labelText: '읽어줄 글 (직접 녹음은 생략 가능)',
                                          ),
                                          onChanged: (v) =>
                                              vm.setText(page.id, v),
                                        ),
                                      Wrap(
                                        spacing: 8,
                                        children: [
                                          if (widget.voiceOnly)
                                            TextButton(
                                              onPressed: locked || !page.hasText
                                                  ? null
                                                  : () async {
                                                      final available =
                                                          await sl<
                                                                DeviceTtsService
                                                              >()
                                                              .isKoreanAvailable();
                                                      if (!mounted) return;
                                                      if (available) {
                                                        vm.useDeviceVoice(
                                                          page.id,
                                                        );
                                                      } else {
                                                        setState(
                                                          () => _message = '오프라인 한국어 음성을 확인할 수 없어 직접 녹음이 필요해요.',
                                                        );
                                                      }
                                                    },
                                              child: const Text('기기 읽기 사용'),
                                            ),
                                          if (!widget.voiceOnly)
                                            IconButton(
                                              tooltip: '앞으로',
                                              onPressed:
                                                  locked || page.orderIndex == 0
                                                  ? null
                                                  : () => vm.reorder(
                                                      page.orderIndex,
                                                      page.orderIndex - 1,
                                                    ),
                                              icon: const Icon(
                                                Icons.arrow_upward,
                                              ),
                                            ),
                                          if (!widget.voiceOnly)
                                            IconButton(
                                              tooltip: '뒤로',
                                              onPressed:
                                                  locked ||
                                                      page.orderIndex ==
                                                          draft
                                                                  .content
                                                                  .pageCount -
                                                              1
                                                  ? null
                                                  : () => vm.reorder(
                                                      page.orderIndex,
                                                      page.orderIndex + 1,
                                                    ),
                                              icon: const Icon(
                                                Icons.arrow_downward,
                                              ),
                                            ),
                                          if (!widget.voiceOnly)
                                            TextButton(
                                              onPressed: locked
                                                  ? null
                                                  : () async {
                                                      final remove = await showDialog<bool>(
                                                        context: context,
                                                        builder: (ctx) => AlertDialog(
                                                          title: const Text(
                                                            '페이지를 뺄까요?',
                                                          ),
                                                          content: const Text(
                                                            '이 초안에서 사진과 연결된 녹음을 제외해요.',
                                                          ),
                                                          actions: [
                                                            TextButton(
                                                              onPressed: () =>
                                                                  Navigator.pop(
                                                                    ctx,
                                                                    false,
                                                                  ),
                                                              child: const Text(
                                                                '취소',
                                                              ),
                                                            ),
                                                            FilledButton(
                                                              onPressed: () =>
                                                                  Navigator.pop(
                                                                    ctx,
                                                                    true,
                                                                  ),
                                                              child: const Text(
                                                                '빼기',
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      );
                                                      if (remove == true) {
                                                        vm.removePage(page.id);
                                                      }
                                                    },
                                              child: const Text('페이지 빼기'),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        const SizedBox(height: 24),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

/// 녹음하면서 보고 읽는 큰 글씨 칸.
///
/// 왜 높이를 고정하나: 글이 길면 칸이 화면을 다 차지해 녹음 · 멈춤 버튼이 밀려난다
/// (2026-11-22 오너 실기기 사용). 칸 안에서만 스크롤하고 버튼은 칸 위에 둔다.
class _BigText extends StatefulWidget {
  const _BigText({super.key, required this.text, this.onEdit});
  final String text;
  final VoidCallback? onEdit;

  static const maxHeight = 220.0;

  @override
  State<_BigText> createState() => _BigTextState();
}

class _BigTextState extends State<_BigText> {
  // 왜 직접 쥐나: 바깥 화면도 스크롤이라 기본(primary) 컨트롤러를 쓸 수 없다.
  // 스크롤 막대를 늘 보이게 하려면 칸 전용 컨트롤러가 필요하다.
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: _BigText.maxHeight),
            child: Scrollbar(
              controller: _scroll,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  widget.text,
                  style: theme.textTheme.headlineSmall?.copyWith(height: 1.5),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: widget.onEdit,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('글 고치기'),
            ),
          ),
        ],
      ),
    );
  }
}

/// 글 고치기 창. 입력 컨트롤러를 창이 직접 쥔다.
/// 왜: 창이 닫히는 애니메이션 동안에도 입력칸이 컨트롤러를 쓴다. 부르는 쪽에서 바로 해제하면 오류가 난다.
class _EditTextSheet extends StatefulWidget {
  const _EditTextSheet({required this.initial});
  final String initial;

  @override
  State<_EditTextSheet> createState() => _EditTextSheetState();
}

class _EditTextSheetState extends State<_EditTextSheet> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      16,
      0,
      16,
      16 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('글 고치기', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('edit-text-field'),
          controller: _controller,
          autofocus: true,
          minLines: 4,
          maxLines: 10,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('고친 글 쓰기'),
        ),
      ],
    ),
  );
}
