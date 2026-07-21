import 'dart:io';

import 'package:front_porch_ai/services/emotional_voice_dsp.dart';

/// Applies emotion-adaptive audio DSP to TTS output files.
///
/// Uses pure-Dart STFT processing — no Python process, no external
/// dependencies. The 27-emotion profile table and 6-parameter DSP
/// pipeline (pitch shift, pitch variance, brightness, tension,
/// breathiness, time-stretch) match the original Python reference.
class EmotionalVoiceProcessor {
  bool _disposed = false;

  /// Whether the processor is available (always true — pure Dart).
  bool get isAvailable => true;

  /// Process [audioFile] with the given [emotion] label.
  ///
  /// Returns a new [File] with the emotion-adapted audio content.
  /// The caller owns the returned file (it is a new temp file).
  Future<File> process(File audioFile, String emotion) async {
    if (_disposed) throw Exception('EmotionalVoiceProcessor is disposed');
    return EmotionalVoiceDsp.process(audioFile, emotion);
  }

  /// Dispose — no-op (no process to kill).
  Future<void> dispose() async {
    _disposed = true;
  }
}
