// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:front_porch_ai/services/engine_health.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/stt/sherpa_whisper_engine.dart';
import 'package:front_porch_ai/services/stt/call_session.dart';

export 'package:front_porch_ai/services/stt/call_session.dart'
    show CallSession, CallStatus;

/// Speech-to-text service using the in-process sherpa-onnx Whisper engine
/// (docs/design/sidecar-retirement.md phase 3 — the Python sidecar is gone).
///
/// Handles microphone recording via the `record` package and transcription
/// via [SherpaWhisperEngine]. Supports both push-to-talk and continuous
/// call mode.
class SttService extends ChangeNotifier {
  final StorageService _storageService;
  final AudioRecorder _recorder = AudioRecorder();

  // ---- Push-to-talk state ----
  bool _isRecording = false;
  bool _isTranscribing = false;
  String? _lastTranscription;
  String? _lastError;
  String? _recordingPath;

  // ---- Device selection ----
  List<InputDevice> _inputDevices = [];
  String? _selectedDeviceId;

  // ---- Call mode ----
  /// The voice-call state machine (see call_session.dart). SttService
  /// provides the audio I/O; the call overlay drives the turn loop.
  late final CallSession call = CallSession(
    startRecording: startRecording,
    cancelRecording: cancelRecording,
    stopAndTranscribe: stopRecordingAndTranscribe,
  );

  Timer? _amplitudeTimer;
  double _currentAmplitude = 0.0; // 0.0 – 1.0 normalized

  // ---- Getters ----
  bool get isRecording => _isRecording;
  bool get isTranscribing => _isTranscribing;
  bool get isBusy => _isRecording || _isTranscribing;
  String? get lastTranscription => _lastTranscription;
  String? get lastError => _lastError;
  double get currentAmplitude => _currentAmplitude;
  List<InputDevice> get inputDevices => _inputDevices;
  String? get selectedDeviceId => _selectedDeviceId;

  SttService(this._storageService) {
    _selectedDeviceId = _storageService.selectedMicId;
    // The overlay listens to SttService — surface the session's changes.
    call.addListener(notifyListeners);
  }

  // ---- Device Management ----

  /// Refresh the list of available input devices.
  Future<List<InputDevice>> refreshInputDevices() async {
    try {
      _inputDevices = await _recorder.listInputDevices();
      debugPrint('STT: found ${_inputDevices.length} input devices');
      // If selected device no longer exists, reset to default
      if (_selectedDeviceId != null &&
          !_inputDevices.any((d) => d.id == _selectedDeviceId)) {
        _selectedDeviceId = null;
        await _storageService.setSelectedMicId(null);
      }
      notifyListeners();
      return _inputDevices;
    } catch (e) {
      debugPrint('STT: failed to list devices: $e');
      _inputDevices = [];
      notifyListeners();
      return [];
    }
  }

  /// Set the selected microphone device.
  Future<void> setSelectedDevice(String? deviceId) async {
    _selectedDeviceId = deviceId;
    await _storageService.setSelectedMicId(deviceId);
    notifyListeners();
  }

  /// Find the InputDevice object for the selected ID.
  InputDevice? get _selectedDevice {
    if (_selectedDeviceId == null) return null;
    try {
      return _inputDevices.firstWhere((d) => d.id == _selectedDeviceId);
    } catch (_) {
      return null;
    }
  }

  /// Check if any microphone is available. Returns false if none found.
  Future<bool> checkMicAvailable() async {
    await refreshInputDevices();
    // Also check permission
    final hasPerm = await _recorder.hasPermission();
    return hasPerm;
  }

  // ---- Engine availability ----

  /// The in-process sherpa-onnx engine ships with the app, so STT is
  /// usable whenever the feature is enabled (the model downloads on
  /// demand).
  bool get isAvailable => _storageService.sttEnabled;

  // ---- Model Download ----
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String _downloadStatus = '';
  String? _downloadError;
  bool get isDownloading => _isDownloading;
  double get downloadProgress => _downloadProgress;
  String get downloadStatus => _downloadStatus;
  String? get downloadError => _downloadError;

  /// Pre-download the selected Whisper model so it's ready for use.
  ///
  /// Whether the currently selected whisper model's files are on disk
  /// (verified sizes, not just existence).
  bool get isSelectedModelDownloaded {
    final root = _storageService.rootPath;
    if (root == null) return false;
    return SherpaWhisperEngine.isModelPresent(
      root,
      _storageService.whisperModel,
    );
  }

  Future<bool> downloadModel() async {
    if (_isDownloading) return false;
    _isDownloading = true;
    _downloadProgress = 0.0;
    _downloadStatus = 'Starting download...';
    _downloadError = null;
    notifyListeners();

    try {
      final modelSize = _storageService.whisperModel;
      final root =
          _storageService.rootPath ??
          (await getApplicationDocumentsDirectory()).path;
      debugPrint('STT: pre-downloading model=$modelSize');

      await SherpaWhisperEngine.downloadModel(
        root,
        modelSize,
        onProgress: (fraction) {
          _downloadProgress = fraction;
          _downloadStatus = 'Downloading... ${(fraction * 100).round()}%';
          notifyListeners();
        },
      );
      // Never claim success on faith — verify the files actually landed
      // (all three present, ONNX graphs plausibly sized). Drop a saved
      // CDN error page so the next tap is not skip-poisoned.
      final ok = SherpaWhisperEngine.isModelPresent(root, modelSize);
      if (!ok) {
        SherpaWhisperEngine.purgeImplausibleFiles(root, modelSize);
        _downloadError =
            'Download finished but the model files failed '
            'verification — please try again.';
      }

      if (ok) {
        _downloadProgress = 1.0;
        _downloadStatus = 'Complete!';
      }
      _isDownloading = false;
      notifyListeners();
      return ok;
    } catch (e) {
      _downloadError = 'Download error: $e';
      debugPrint('STT: download error: $e');
      _isDownloading = false;
      notifyListeners();
      return false;
    }
  }

  // ==== Push-to-Talk (Phase 1) ====

  Future<void> startRecording() async {
    if (_isRecording || _isTranscribing) return;

    if (!await _recorder.hasPermission()) {
      _lastError = 'Microphone permission denied';
      notifyListeners();
      return;
    }

    try {
      final tempDir = Directory.systemTemp;
      _recordingPath = p.join(
        tempDir.path,
        'stt_recording_${DateTime.now().millisecondsSinceEpoch}.wav',
      );

      await _recorder.start(
        RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
          autoGain: true,
          echoCancel: true,
          noiseSuppress: true,
          device: _selectedDevice,
        ),
        path: _recordingPath!,
      );

      _isRecording = true;
      _lastError = null;
      _lastTranscription = null;
      _startAmplitudeMonitor();
      notifyListeners();
      debugPrint('STT: recording started → $_recordingPath');
    } catch (e) {
      _lastError = 'Failed to start recording: $e';
      debugPrint('STT: $e');
      notifyListeners();
    }
  }

  /// Transcribe an already-saved audio file (any format Whisper/ffmpeg can read).
  /// Used by the web server when a browser uploads mic audio recorded on the
  /// client — the host never records. Reuses the same Whisper helper path as the
  /// desktop recorder. The caller owns the file's lifecycle.
  Future<String?> transcribeAudioFile(String audioPath) async {
    if (!File(audioPath).existsSync()) {
      _lastError = 'Audio file not found';
      return null;
    }
    _isTranscribing = true;
    notifyListeners();
    try {
      final result = await _transcribe(audioPath);
      if (result != null && result.isNotEmpty) {
        _lastTranscription = result;
        _lastError = null;
      }
      return result;
    } finally {
      _isTranscribing = false;
      notifyListeners();
    }
  }

  Future<String?> stopRecordingAndTranscribe() async {
    if (!_isRecording) return null;

    try {
      _stopAmplitudeMonitor();
      final path = await _recorder.stop();
      _isRecording = false;
      debugPrint('STT: recording stopped → $path');

      if (path == null || !File(path).existsSync()) {
        _lastError = 'Recording file not found';
        notifyListeners();
        return null;
      }

      final fileSize = File(path).lengthSync();
      if (fileSize < 1000) {
        _lastError = 'Recording too short';
        _cleanupRecording(path);
        notifyListeners();
        return null;
      }

      _isTranscribing = true;
      notifyListeners();

      final result = await _transcribe(path);
      _isTranscribing = false;
      _cleanupRecording(path);

      if (result != null && result.isNotEmpty) {
        _lastTranscription = result;
        _lastError = null;
      } else {
        _lastError = _lastError ?? 'No speech detected';
      }

      notifyListeners();
      return _lastTranscription;
    } catch (e) {
      _isRecording = false;
      _isTranscribing = false;
      _lastError = 'Transcription failed: $e';
      debugPrint('STT error: $e');
      notifyListeners();
      return null;
    }
  }

  Future<void> cancelRecording() async {
    if (!_isRecording) return;
    _stopAmplitudeMonitor();
    try {
      final path = await _recorder.stop();
      if (path != null) _cleanupRecording(path);
    } catch (_) {}
    _isRecording = false;
    notifyListeners();
  }

  // ==== Amplitude Monitoring ====

  void _startAmplitudeMonitor() {
    _stopAmplitudeMonitor();
    _amplitudeTimer = Timer.periodic(const Duration(milliseconds: 100), (
      _,
    ) async {
      if (!_isRecording) return;
      try {
        final amp = await _recorder.getAmplitude();
        final dbfs = amp.current;
        _currentAmplitude = ((dbfs + 60) / 60).clamp(0.0, 1.0);
        // Calibration sampling and silence auto-send live in the session.
        call.onAmplitude(_currentAmplitude);
        notifyListeners();
      } catch (_) {}
    });
  }

  void _stopAmplitudeMonitor() {
    _amplitudeTimer?.cancel();
    _amplitudeTimer = null;
    _currentAmplitude = 0.0;
  }

  // ==== Transcription (in-process sherpa-onnx) ====

  Future<String?> _transcribe(String audioPath) async {
    try {
      final modelSize = _storageService.whisperModel;
      final root =
          _storageService.rootPath ??
          (await getApplicationDocumentsDirectory()).path;

      debugPrint('STT: transcribing with model=$modelSize');

      // WAV input only: the desktop recorder always produces WAV, and the
      // web UI encodes its mic capture to WAV client-side. Anything else
      // (e.g. an old service-worker-cached web page still uploading webm)
      // is a hard error — there is no Python decoder anymore.
      if (!SherpaWhisperEngine.canDecode(audioPath)) {
        _lastError =
            'Unsupported audio format — only WAV is supported. If this '
            'came from the web UI, refresh the page to update it.';
        EngineHealth.instance.reportFailure(
          EngineHealth.whisper,
          'non-WAV audio uploaded (stale web page?)',
        );
        return null;
      }

      if (!SherpaWhisperEngine.isModelPresent(root, modelSize)) {
        // First use on a fresh install: the sherpa export downloads on
        // demand, surfaced through the same progress UI as the settings
        // button.
        await downloadModel();
      }
      if (!SherpaWhisperEngine.isModelPresent(root, modelSize)) {
        _lastError = _downloadError ?? 'Whisper model is not downloaded yet.';
        EngineHealth.instance.reportFailure(
          EngineHealth.whisper,
          'model missing after download attempt',
          expected: true,
        );
        return null;
      }

      final text = await SherpaWhisperEngine.transcribe(
        root: root,
        size: modelSize,
        audioPath: audioPath,
      );
      debugPrint(
        '[STT-Native] transcribed "${text.length > 60 ? '${text.substring(0, 60)}...' : text}"',
      );
      EngineHealth.instance.reportNative(EngineHealth.whisper);
      return text.isEmpty ? null : text;
    } catch (e) {
      _lastError = 'Transcription error: $e';
      EngineHealth.instance.reportFailure(
        EngineHealth.whisper,
        'transcription failed: $e',
      );
      debugPrint('STT error: $e');
      return null;
    }
  }

  // ---- Utilities ----

  void _cleanupRecording(String path) {
    try {
      File(path).deleteSync();
    } catch (_) {}
  }

  @override
  void dispose() {
    call.dispose();
    cancelRecording();
    _recorder.dispose();
    super.dispose();
  }
}
