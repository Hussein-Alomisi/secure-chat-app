import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

/// Wraps the [record] package for simple voice message recording.
/// Records to a temp m4a file, tracks duration, returns the path on stop.
class VoiceRecorderService {
  final AudioRecorder _recorder = AudioRecorder();
  DateTime? _startTime;

  /// Requests the microphone permission.
  /// Returns true if granted, false otherwise.
  Future<bool> requestPermission() async {
    final status = await Permission.microphone.request();
    return status == PermissionStatus.granted;
  }

  /// Returns true if the microphone permission is already granted.
  Future<bool> hasPermission() async {
    return await Permission.microphone.isGranted;
  }

  /// Starts recording. Saves to a temp file in the app temp directory.
  /// Returns the output file path so it can be used/cancelled later.
  Future<String> start() async {
    final dir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final path = '${dir.path}/voice_$timestamp.m4a';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 64000,
        sampleRate: 44100,
      ),
      path: path,
    );

    _startTime = DateTime.now();
    return path;
  }

  /// Stops recording and returns the recorded file path.
  /// Returns null if the recorder was not recording.
  Future<String?> stop() async {
    return await _recorder.stop();
  }

  /// Cancels recording and deletes the temp file.
  Future<void> cancel() async {
    final path = await _recorder.stop();
    if (path != null) {
      final file = File(path);
      if (await file.exists()) {
        await file.delete().catchError((_) => file);
      }
    }
    _startTime = null;
  }

  /// Duration in seconds since recording started.
  int get elapsedSeconds {
    if (_startTime == null) return 0;
    return DateTime.now().difference(_startTime!).inSeconds;
  }

  /// Whether the recorder is currently capturing audio.
  Future<bool> get isRecording => _recorder.isRecording();

  void dispose() {
    _recorder.dispose();
  }
}
