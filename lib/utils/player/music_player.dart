import 'package:just_audio/just_audio.dart';
import 'package:lx_music_flutter/app/sql/music_sql_manager.dart';
import 'package:lx_music_flutter/models/music_item.dart';
import 'package:lx_music_flutter/utils/log/logger.dart';
import 'package:rxdart/rxdart.dart';

/// 音乐播放器
class MusicPlayer {
  factory MusicPlayer() => _instance ?? MusicPlayer._();

  MusicPlayer._() {
  }

  static MusicPlayer? _instance;

  final player = AudioPlayer();

  ///播放列表
  final ConcatenatingAudioSource playList = ConcatenatingAudioSource(children: []);

  Stream<PositionData> get positionDataStream => Rx.combineLatest3<Duration, Duration, Duration?, PositionData>(
      player.positionStream,
      player.bufferedPositionStream,
      player.durationStream,
      (position, bufferedPosition, duration) => PositionData(position, bufferedPosition, duration ?? Duration.zero));

  void init() async {

    player.setAudioSource(playList);
    player.seek(Duration.zero, index: 0);

    player.playbackEventStream.listen((PlaybackEvent event) {
      Logger.debug('processingState: ${event.processingState}');
      final processingState = event.processingState;
      if (processingState == ProcessingState.loading || processingState == ProcessingState.buffering) {
        Logger.debug('loading');
      } else if (processingState == ProcessingState.ready) {
        Logger.debug('ready');
      } else if (processingState == ProcessingState.completed) {
        Logger.debug('completed');
      } else if (processingState == ProcessingState.idle) {
        Logger.debug('idle');
      }
    }, onError: (Object e, StackTrace stackTrace) {
      Logger.error('A stream error occurred: $e');
    });
  }

  /// 添加一首歌曲到播放列表
  Future<void> add(MusicItem item) async {
    String? url = await item.getUrl();
    if (url == null) {
      return;
    }
    playList.insert(0, AudioSource.uri(Uri.parse(url), tag: item));
    player.seek(Duration.zero, index: 0);
    player.play();
  }

  Future<void> remove(int index) async {
    playList.removeAt(index);
  }

  Future<void> play() async {
    player.play();
  }

  Future<void> pause() async {
    player.pause();
  }

  Future<void> stop() async {
    player.stop();
  }

  Future<void> seekDuration(Duration position) async {
    player.seek(position);
  }

  /// 跳转到某时刻
  /// [length] 秒
  Future<void> seek({int length = 0, int? index}) async {
    player.seek(Duration(milliseconds: length * 1000), index: index);
  }

  Future setVolume(double volume) async {
    player.setVolume(volume);
  }
}

class PlayStatus {
  static const int playing = 1;
  static const int pause = 2;
  static const int stop = 3;
}

class PositionData {
  final Duration position;
  final Duration bufferedPosition;
  final Duration duration;

  PositionData(this.position, this.bufferedPosition, this.duration);
}
