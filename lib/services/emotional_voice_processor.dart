import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Persistent process wrapper around emotional_voice.py.
///
/// Spawns a single Python worker that stays alive between requests
/// and applies emotion-adaptive audio DSP to TTS output files.
class EmotionalVoiceProcessor {
  Process? _process;
  int _requestId = 0;
  bool _disposed = false;

  /// Whether the underlying Python script is available.
  bool get isAvailable => _helperScriptPath != null;

  String? get _helperScriptPath {
    // The script lives at the project root alongside kokoro_tts.py.
    final script = p.join(p.current, 'emotional_voice.py');
    return File(script).existsSync() ? script : null;
  }

  /// Ensure the worker process is running.
  Future<void> _ensureStarted() async {
    if (_disposed) return;
    if (_process != null) return;

    final script = _helperScriptPath;
    if (script == null) {
      throw Exception('emotional_voice.py not found');
    }

    _process = await Process.start(
      Platform.isWindows ? 'python' : 'python3',
      [script],
      includeParentEnvironment: true,
    );
  }

  /// Process [audioFile] with the given [emotion] label.
  ///
  /// Returns a new [File] with the emotion-adapted audio content.
  /// The caller owns the returned file (it is a new temp file).
  Future<File> process(File audioFile, String emotion) async {
    if (_disposed) throw Exception('EmotionalVoiceProcessor is disposed');

    await _ensureStarted();

    final requestId = ++_requestId;
    final outputPath =
        '${audioFile.parent.path}/emotional_${p.basenameWithoutExtension(audioFile.path)}_$requestId.wav';

    final request = jsonEncode({
      'id': requestId,
      'audio_path': audioFile.path,
      'emotion': emotion,
      'output_path': outputPath,
    });

    // Try once; if the process died since _ensureStarted, restart and retry.
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        _process!.stdin.writeln(request);
        await _process!.stdin.flush();
        break;
      } catch (_) {
        _process = null;
        if (attempt == 0) {
          await _ensureStarted();
        } else {
          throw Exception('EmotionalVoice: failed to start worker process');
        }
      }
    }

    // Read one response line from stdout
    final line = await _process!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first;

    final response = jsonDecode(line) as Map<String, dynamic>;
    if (response['error'] != null) {
      throw Exception('EmotionalVoice error: ${response['error']}');
    }

    final resultFile = File(outputPath);
    if (!await resultFile.exists()) {
      throw Exception('EmotionalVoice: output file not created');
    }

    return resultFile;
  }

  /// Dispose the worker process.
  Future<void> dispose() async {
    _disposed = true;
    try {
      _process?.stdin.close();
    } catch (_) {}
    try {
      await _process?.kill();
    } catch (_) {}
    _process = null;
  }
}
