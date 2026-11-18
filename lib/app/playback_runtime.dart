import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart'
    hide AndroidAudioFocus, AVAudioSessionCategory;
import 'package:audioplayers/audioplayers.dart';

import '../data/local/media_storage.dart';
import '../data/services/device_tts_service.dart';
import '../data/services/page_audio_player.dart';
import '../domain/repositories/recent_playback_repository.dart';
import '../domain/repositories/reading_workspace_repositories.dart';
import '../domain/repositories/repositories.dart';
import '../presentation/player/playback_queue.dart';
import '../presentation/player/player_view_model.dart';
import '../service_locator.dart';

PlaybackQueue createPlaybackQueue({AudioSession? session}) => PlaybackQueue(
  recentRepository: sl<RecentPlaybackRepository>(),
  releaseAudio: session == null
      ? null
      : () async {
          await session.setActive(false);
        },
  resolveBook: (id) => sl<ContentRepository>().getById(id),
  createPlayer: (book) {
    final audio = AudioPlayer();
    return PlayerViewModel(
      content: book,
      audioPlayer: PageAudioPlayerImpl(
        filePlayer: audio,
        tts: sl<DeviceTtsService>(),
        prepareAudio: session == null
            ? null
            : () async {
                // 녹음 플러그인 사용 후에도 읽기용 세션으로 돌아온다.
                await audio.setAudioContext(
                  AudioContext(
                    android: const AudioContextAndroid(
                      contentType: AndroidContentType.speech,
                      usageType: AndroidUsageType.media,
                      audioFocus: AndroidAudioFocus.none,
                      stayAwake: true,
                    ),
                    iOS: AudioContextIOS(
                      category: AVAudioSessionCategory.playback,
                    ),
                  ),
                );
                await session.configure(
                  const AudioSessionConfiguration.speech(),
                );
                return session.setActive(true);
              },
      ),
      mediaStorage: sl<MediaStorage>(),
      readingEventRepository: sl<ReadingEventRepository>(),
      positionRepository: sl<ReadingPositionRepository>(),
    );
  },
);

/// 모든 화면과 OS 미디어 제어가 동일한 큐를 조작한다. 오디오를 중복 생성하지 않는다.
class ReadingAudioHandler extends BaseAudioHandler {
  ReadingAudioHandler(this.playback) {
    playback.addListener(_sync);
    _sync();
  }
  final PlaybackQueue playback;

  void _sync() {
    final p = playback.player;
    final items = playback.items
        .map(
          (book) => MediaItem(id: book.id, title: book.title, album: '작은 도서관'),
        )
        .toList();
    queue.add(items);
    // 사진·음성·본문을 OS 미디어 메타데이터로 노출하지 않는다.
    mediaItem.add(
      p == null
          ? null
          : MediaItem(
              id: p.content.id,
              title: p.content.title,
              album: '작은 도서관',
              artist: '${p.index + 1} / ${p.pageCount}쪽',
            ),
    );
    playbackState.add(
      PlaybackState(
        controls: [
          if (playback.currentIndex > 0) MediaControl.skipToPrevious,
          p?.isPlaying == true ? MediaControl.pause : MediaControl.play,
          if (playback.currentIndex >= 0 &&
              playback.currentIndex + 1 < items.length)
            MediaControl.skipToNext,
          MediaControl.stop,
        ],
        processingState:
            p == null ||
                (p.isFinished && playback.currentIndex == items.length - 1)
            ? AudioProcessingState.idle
            : AudioProcessingState.ready,
        playing: p?.isPlaying == true,
        queueIndex: playback.currentIndex < 0 ? null : playback.currentIndex,
      ),
    );
  }

  @override
  Future<void> play() => playback.play();
  @override
  Future<void> pause() => playback.pause();
  @override
  Future<void> stop() => playback.stop();
  @override
  Future<void> skipToNext() => playback.nextBook();
  @override
  Future<void> skipToPrevious() => playback.previousBook();
  @override
  Future<void> skipToQueueItem(int index) async {
    if (index >= 0 && index < playback.items.length) {
      await playback.select(playback.items[index].id);
    }
  }

  @override
  Future<void> onTaskRemoved() => stop();

  void detach() => playback.removeListener(_sync);
}

/// 앱 수명 동안 OS 오디오 중단을 구독한다. 통화/이어폰 분리 후 자동 재개하지 않는다.
class PlaybackInterruptions {
  PlaybackInterruptions(AudioSession session, PlaybackQueue playback)
    : _interruptions = session.interruptionEventStream.listen((event) {
        if (event.begin) unawaited(playback.pause());
      }),
      _noisy = session.becomingNoisyEventStream.listen((_) {
        unawaited(playback.pause());
      });
  final StreamSubscription<AudioInterruptionEvent> _interruptions;
  final StreamSubscription<void> _noisy;
  Future<void> dispose() async {
    await _interruptions.cancel();
    await _noisy.cancel();
  }
}
