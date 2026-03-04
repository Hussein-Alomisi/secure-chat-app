import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// Centralized audio playback controller.
///
/// A single [AudioPlayer] is shared across all audio bubbles.
/// Only one message can play at a time – starting a new one stops the previous.
class AudioPlaybackManager extends ChangeNotifier {
  final AudioPlayer _player = AudioPlayer();

  String? _activeMessageId;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _total = Duration.zero;

  // ── Public getters ────────────────────────────────────────────────────────

  String? get activeMessageId => _activeMessageId;
  bool get isPlaying => _isPlaying;
  Duration get position => _position;
  Duration get total => _total;

  /// Progress in [0.0, 1.0] for the active message.
  double get progress => _total.inMilliseconds > 0
      ? (_position.inMilliseconds / _total.inMilliseconds).clamp(0.0, 1.0)
      : 0.0;

  /// Whether [messageId] is currently the active (possibly paused) track.
  bool isActive(String messageId) => _activeMessageId == messageId;

  /// Whether [messageId] is actively playing right now.
  bool isPlayingMessage(String messageId) =>
      _activeMessageId == messageId && _isPlaying;

  AudioPlaybackManager() {
    _player.playingStream.listen((playing) {
      _isPlaying = playing;
      notifyListeners();
    });

    _player.positionStream.listen((pos) {
      _position = pos;
      notifyListeners();
    });

    _player.durationStream.listen((dur) {
      if (dur != null) {
        _total = dur;
        notifyListeners();
      }
    });

    // Reset when playback completes – this fixes the infinite-loop bug.
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _player.seek(Duration.zero);
        _player.stop();
        _isPlaying = false;
        notifyListeners();
      }
    });
  }

  // ── Public methods ────────────────────────────────────────────────────────

  /// Play [filePath] for [messageId].
  /// If [messageId] is already playing → pause.
  /// If [messageId] is paused → resume.
  /// Any other message that is playing → stopped first.
  Future<void> togglePlay(String messageId, String filePath) async {
    if (_activeMessageId == messageId) {
      // Same track: toggle pause / resume.
      if (_isPlaying) {
        await _player.pause();
      } else {
        await _player.play();
      }
      return;
    }

    // Different track: stop current and start new.
    await _player.stop();
    _activeMessageId = messageId;
    _position = Duration.zero;
    _total = Duration.zero;
    _isPlaying = false;
    notifyListeners();

    await _player.setFilePath(filePath);
    await _player.play();
  }

  /// Stop playback and clear active state.
  Future<void> stop() async {
    await _player.stop();
    _activeMessageId = null;
    _isPlaying = false;
    _position = Duration.zero;
    notifyListeners();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
