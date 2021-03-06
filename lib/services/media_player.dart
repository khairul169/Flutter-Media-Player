import 'dart:async';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:cmp/public/utils.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

enum AudioRepeatMode { None, Single, All }

class MediaPlayerState {
  AudioPlaybackState state;
  int position;
  MediaPlayerItem media;

  MediaPlayerState({this.state, this.position, this.media});

  copyWith({
    AudioPlaybackState state,
    int position,
    MediaPlayerItem media,
  }) {
    return MediaPlayerState(
      state: state ?? this.state,
      position: position ?? this.position,
      media: media ?? this.media,
    );
  }
}

class MediaPlayer {
  final player = AudioPlayer();

  MediaPlayerState _state;
  List<MediaPlayerItem> queue;
  int curIndex = -1;
  AudioRepeatMode repeatMode = AudioRepeatMode.None;
  bool queueMode = false;
  StreamController<MediaPlayerState> _stateController;
  Stream<MediaPlayerState> stateEvent;

  MediaPlayer() {
    _state = MediaPlayerState();
    _stateController = StreamController.broadcast();
    stateEvent = _stateController.stream;
  }

  Function init() {
    // Listen to state change
    var playCompleteListener = player.playbackStateStream
        .where((state) => state == AudioPlaybackState.completed)
        .listen((state) => onPlaybackComplete());

    // Position change
    var positionListener =
        player.getPositionStream(Duration(milliseconds: 1000)).listen((data) {
      var position = data?.inMilliseconds ?? 0;
      _setState(position: position);
    });

    return () {
      _stateController.close();
      playCompleteListener.cancel();
      positionListener.cancel();
    };
  }

  void play() async {
    if (isBusy || isPlaying) return;

    await player.play();
    _setState();
  }

  void stop() async {
    if (!isPlaying) return;

    await player.stop();
    _setState();
  }

  void pause() async {
    if (!isPlaying) return;

    await player.pause();
    _setState();
  }

  void skipToNext() {
    if (!queueMode || queue == null) return;
    skipIndex(1);
  }

  void skipToPrevious() {
    if (!queueMode || queue == null) return;
    skipIndex(-1);
  }

  void setQueue(List<MediaPlayerItem> items) {
    if (queue != items) {
      queue = items;
    }
  }

  Future<int> _playMedia(MediaPlayerItem media) async {
    String url = media.url;
    bool local = media.local ?? false;

    if (url == null) return 0;
    if (isPlaying) stop();

    // Update state
    _setState(media: media);

    print('Playing $url, local=$local');

    // Set url / path
    Duration duration;
    if (local) {
      // Local file isn't exist
      if (!await File(url).exists()) return 0;

      duration = await player.setFilePath(url);
    } else {
      duration = await player.setUrl(url);
    }

    // Workaround for web build
    if (kIsWeb) await Future.delayed(Duration(milliseconds: 100));

    // Play media
    play();

    // Update media duration
    _setState(media: media.copyWith(duration: duration?.inMilliseconds));

    return duration.inMilliseconds;
  }

  Future<int> playMediaItem(MediaPlayerItem media) async {
    if (isBusy) return 0;

    queueMode = false;
    return await _playMedia(media);
  }

  Future<int> playMediaId(int id) async {
    if (isBusy) return 0;

    curIndex = (id < 0 ? 0 : (id >= queue.length ? queue.length - 1 : id));
    queueMode = true;

    return await _playMedia(queue[curIndex]);
  }

  void skipIndex(int rel) {
    var newIndex = curIndex + rel;
    if (newIndex < 0) {
      newIndex = queue.length - 1;
    } else if (newIndex >= queue.length) {
      newIndex = 0;
    }
    playMediaId(newIndex);
  }

  void setVolume(double volume) => player.setVolume(volume);

  void onPlaybackComplete() {
    if (!queueMode || queue == null) return;

    // Repeat media
    if (repeatMode == AudioRepeatMode.Single) {
      playMediaId(curIndex);
    } else {
      if (curIndex < queue.length - 1 || repeatMode == AudioRepeatMode.All) {
        skipIndex(1);
      }
    }
  }

  void _setState({
    AudioPlaybackState state,
    int position,
    MediaPlayerItem media,
  }) {
    // Playback position
    final iState = player.playbackState;
    final iPosition = player.playbackEvent.position?.inMilliseconds;
    final iMedia = _state.media;

    _state = _state.copyWith(
      state: state ?? iState,
      position: position ?? iPosition,
      media: media ?? iMedia,
    );

    _stateController.add(_state);
  }

  MediaPlayerState get state => _state;

  bool get isPlaying => player.playbackState == AudioPlaybackState.playing;

  bool get isPaused => player.playbackState == AudioPlaybackState.paused;

  bool get isBusy => player.playbackState == AudioPlaybackState.connecting;
}

class MediaPlayerItem {
  final int id;
  final String title;
  final String artist;
  final String album;
  final String image;
  final int duration;
  final String url;
  final bool local;

  MediaPlayerItem({
    this.id,
    this.title,
    this.artist,
    this.album,
    this.image,
    this.duration,
    this.url,
    this.local,
  });

  factory MediaPlayerItem.fromMediaItem(MediaItem mediaItem) {
    if (mediaItem == null) return null;
    return MediaPlayerItem(
      id: int.parse(mediaItem.id),
      title: mediaItem.title,
      artist: mediaItem.artist,
      album: mediaItem.album,
      image: mediaItem.artUri,
      duration: mediaItem.duration,
      url: mediaItem.extras['url'],
      local: mediaItem.extras['local'],
    );
  }

  MediaItem toMediaItem() {
    return MediaItem(
      id: id.toString(),
      title: title ?? '',
      artist: Utils.isEmpty(artist) ? 'Unknown' : artist,
      album: album ?? '',
      artUri: image ?? '',
      duration: duration ?? 0,
      extras: {
        'url': url,
        'local': local,
      },
    );
  }

  MediaPlayerItem copyWith({
    int id,
    String title,
    String artist,
    String album,
    String image,
    int duration,
    String url,
    bool local,
  }) {
    return MediaPlayerItem(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      image: image ?? this.image,
      duration: duration ?? this.duration,
      url: url ?? this.url,
      local: local ?? this.local,
    );
  }

  bool equals(MediaItem mediaItem) {
    return (mediaItem != null &&
        id == int.parse(mediaItem.id) &&
        title == mediaItem.title &&
        artist == mediaItem.artist &&
        album == mediaItem.album &&
        image == mediaItem.artUri &&
        duration == mediaItem.duration);
  }
}
