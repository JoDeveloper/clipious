import 'package:better_player/better_player.dart';
import 'package:easy_debounce/easy_debounce.dart';
import 'package:easy_debounce/easy_throttle.dart';
import 'package:flutter/src/services/hardware_keyboard.dart';
import 'package:flutter/src/widgets/focus_manager.dart';
import 'package:get/get.dart';
import 'package:invidious/controllers/videoPlayerController.dart';
import 'package:invidious/globals.dart';
import 'package:invidious/models/baseVideo.dart';
import 'package:invidious/models/videoInList.dart';
import 'package:logging/logging.dart';

import '../models/video.dart';
import '../utils.dart';

const Duration controlFadeOut = Duration(seconds: 4);
const Duration throttleDuration = Duration(milliseconds: 250);

const defaultStep = 10;
const stepMultiplier = 0.2;

class TvPlayerController extends GetxController {
  Logger log = Logger('TvPlayerController');

  late List<BaseVideo> videos;

  static TvPlayerController? to() => safeGet();
  double progress = 0;
  double controlsOpacity = 0;
  Duration currentPosition = Duration.zero;
  bool buffering = true;
  bool loading = true;
  bool showSettings = false;
  bool showQueue = false;
  bool showControls = false;
  late Video currentlyPlaying;
  int forwardStep = defaultStep, rewindStep = defaultStep;

  Duration get videoLength => Duration(seconds: VideoPlayerController.to()?.video?.lengthSeconds ?? 0);

  TvPlayerController({required this.videos});

  togglePlayPause() {
    showUi();
    if (isPlaying) {
      log.info('Pausing video');
      VideoPlayerController.to()?.videoController?.pause();
    } else {
      VideoPlayerController.to()?.videoController?.pause();
    }
    update();
  }

  play() {
    log.info('Playing video');
    VideoPlayerController.to()?.videoController?.play();
  }

  pause() {
    log.info('Pausing video');
    PlayerController.to()?.videoController?.pause();
  }

  @override
  void onReady() async {
    currentlyPlaying = await service.getVideo(videos[0].videoId);
    loading = false;
    update();
  }

  bool get isShowUi => controlsOpacity == 1;

  @override
  void onClose() {
    super.onClose();
  }

  bool get isPlaying => VideoPlayerController.to()?.videoController?.isPlaying() ?? false;

  int get currentlyPlayingIndex => videos.indexWhere((element) => element.videoId == currentlyPlaying.videoId);

  handleVideoEvent(BetterPlayerEvent event) {
    switch (event.betterPlayerEventType) {
      case BetterPlayerEventType.progress:
        Duration currentPosition = (event.parameters?['progress'] as Duration);
        setProgress(currentPosition);
        break;
      case BetterPlayerEventType.seekTo:
        Duration currentPosition = (event.parameters?['duration'] as Duration);
        setProgress(currentPosition);
        break;
      case BetterPlayerEventType.finished:
        playNext();
        break;
      case BetterPlayerEventType.bufferingStart:
        buffering = true;
        break;
      case BetterPlayerEventType.bufferingEnd:
        buffering = false;
        break;
      default:
        break;
    }
    update();
  }

  setProgress(Duration currentPosition) {
    this.currentPosition = currentPosition;
    progress = currentPosition.inSeconds / videoLength.inSeconds;
    update();
  }

  showUi() {
    controlsOpacity = 1;
    update();
    hideControls();
  }

  hideControls() {
    EasyDebounce.debounce('tv-controls', controlFadeOut, () {
      controlsOpacity = 0;
      showSettings = false;
      showQueue = false;
      showControls = false;
      update();
    });
  }

  fastForward() {
    VideoPlayerController.to()?.videoController?.seekTo(currentPosition + Duration(seconds: forwardStep));
    forwardStep += (forwardStep * stepMultiplier).floor();
    EasyDebounce.debounce('fast-forward-step', const Duration(seconds: 1), () {
      forwardStep = defaultStep;
    });
  }

  fastRewind() {
    VideoPlayerController.to()?.videoController?.seekTo(currentPosition - Duration(seconds: rewindStep));
    rewindStep += (rewindStep * stepMultiplier).floor();
    EasyDebounce.debounce('fast-rewind-step', const Duration(seconds: 1), () {
      rewindStep = defaultStep;
    });
  }

  playNext() async {
    int current = currentlyPlayingIndex;
    int newIndex = 0;
    if (current == videos.length - 1) {
      newIndex = 0;
    } else {
      newIndex = current + 1;
    }

    loading = true;
    update();
    currentlyPlaying = await service.getVideo(videos[newIndex].videoId);
    VideoPlayerController.to()?.switchVideo(currentlyPlaying);
    loading = false;
    update();
  }

  playPrevious() async {
    int current = currentlyPlayingIndex;
    int newIndex = 0;
    if (current == 0) {
      newIndex = videos.length - 1;
    } else {
      newIndex = current - 1;
    }
    loading = true;
    update();
    currentlyPlaying = await service.getVideo(videos[newIndex].videoId);
    VideoPlayerController.to()?.switchVideo(currentlyPlaying);
    loading = false;
    update();
  }

  displaySettings() {
    showSettings = true;
    showControls = false;
    update();
  }

  displayQueue() {
    showQueue = true;
    showControls = false;
    update();
  }

  KeyEventResult handleRemoteEvents(FocusNode node, KeyEvent event) {
    bool timeLineControl = !showQueue && !showSettings && !showControls;
    log.fine('Key: ${event.logicalKey}, Timeline control: $timeLineControl, showQueue: $showQueue, showSettings: $showSettings, showControls: $showControls}');
    showUi();

    // looks like back is activate on pressdown and not press up
    if (event is KeyUpEvent && !timeLineControl && event.logicalKey == LogicalKeyboardKey.goBack) {
      if (showQueue || showSettings) {
        showQueue = false;
        showSettings = false;
        showControls = true;
      } else {
        showQueue = false;
        showSettings = false;
        showControls = false;
      }
      update();
      return KeyEventResult.handled;
    } else if (event is KeyUpEvent) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.mediaPlay:
          play();
          break;
        case LogicalKeyboardKey.mediaPause:
          pause();
          break;
        case LogicalKeyboardKey.mediaPlayPause:
          togglePlayPause();
          break;

        case LogicalKeyboardKey.mediaFastForward:
        case LogicalKeyboardKey.mediaStepForward:
        case LogicalKeyboardKey.mediaSkipForward:
          fastForward();
          break;
        case LogicalKeyboardKey.mediaRewind:
        case LogicalKeyboardKey.mediaStepBackward:
        case LogicalKeyboardKey.mediaSkipBackward:
          fastRewind();
          break;
        case LogicalKeyboardKey.mediaTrackNext:
          playNext();
          break;
        case LogicalKeyboardKey.mediaTrackPrevious:
          playPrevious();
          break;
      }

      if (timeLineControl) {
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          fastForward();
        } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          fastRewind();
        } else if (event.logicalKey == LogicalKeyboardKey.select) {
          showControls = true;
          update();
        }
      } else {}
    }
    if (event is KeyRepeatEvent) {
      if (timeLineControl) {
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          EasyThrottle.throttle('hold-seek-forward', throttleDuration, fastForward);
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          EasyThrottle.throttle('hold-seek-backward', throttleDuration, fastRewind);
        }
      }
    }
    return KeyEventResult.ignored;
  }

  Future<void> playFromQueue(VideoInList video) async {
    print('hello');
    showQueue = false;
    loading = true;
    update();
    currentlyPlaying = await service.getVideo(video.videoId);
    VideoPlayerController.to()?.switchVideo(currentlyPlaying);
    loading = false;
    update();
  }
}
