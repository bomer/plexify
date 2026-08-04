import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'playback_handler.dart';

/// Connects the audio handler to Windows' media session.
///
/// `audio_service` covers Android's media session but has no Windows
/// implementation, so on desktop the keyboard's media keys reach nothing. The
/// runner registers a System Media Transport Controls session and this keeps it
/// in step: state and metadata out, button presses back in.
///
/// Does nothing off Windows — Android already has a real media session.
void attachWindowsMediaControls(PlexifyAudioHandler handler) {
  if (!Platform.isWindows) return;
  _WindowsMediaControls(handler).start();
}

class _WindowsMediaControls {
  _WindowsMediaControls(this._handler);

  static const _channel = MethodChannel('plexify/media_controls');

  final PlexifyAudioHandler _handler;

  String? _lastTrackId;
  Map<String, Object?>? _lastPlayback;

  void start() {
    _channel.setMethodCallHandler(_onButtonPressed);

    _handler.mediaItem.listen((item) {
      if (item == null || item.id == _lastTrackId) return;
      _lastTrackId = item.id;
      _send('updateMetadata', {
        'title': item.title,
        'artist': item.artist ?? '',
        'album': item.album ?? '',
      });
    });

    _handler.playbackState.listen((state) {
      final queueLength = _handler.queue.value.length;
      final index = state.queueIndex ?? 0;

      final payload = <String, Object?>{
        // Closed rather than paused when nothing is loaded, so the volume
        // flyout doesn't advertise a session with no track behind it.
        'active': state.processingState != AudioProcessingState.idle,
        'playing': state.playing,
        'hasNext': index < queueLength - 1,
        // Previous stays available at the head of the queue because it restarts
        // the track, which is what pressing it there is expected to do.
        'hasPrevious': queueLength > 0,
      };

      // playbackState also fires on buffering and position changes, and this
      // crosses a platform channel — only send when something visible changed.
      if (mapEquals(payload, _lastPlayback)) return;
      _lastPlayback = payload;
      _send('updatePlayback', payload);
    });
  }

  Future<void> _onButtonPressed(MethodCall call) async {
    switch (call.method) {
      case 'play':
        await _handler.play();
      case 'pause':
        await _handler.pause();
      case 'next':
        await _handler.skipToNext();
      case 'previous':
        await _handler.skipToPrevious();
      case 'stop':
        await _handler.stop();
    }
  }

  void _send(String method, Map<String, Object?> arguments) {
    // Fire and forget: a media session that fails to update is a cosmetic
    // problem, and awaiting it would put the platform channel on the path of
    // every playback state change.
    _channel.invokeMethod<void>(method, arguments).catchError((Object _) {});
  }
}
