// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// What an exit the app did not ask for means, said in plain words, and the
// one retry the ROCm flash attention fallback makes.

part of 'kobold_service.dart';

extension KoboldServiceExit on KoboldService {
  void _noteExit(
    int code,
    Process launched, {
    required bool wasReady,
    required String executablePath,
    required int port,
  }) {
    if (identical(_stoppingProcess, launched)) return;
    final failure = classifyKoboldExit(
      log: _logs,
      exitCode: code,
      wasReady: wasReady,
    );
    _lastFailure = failure;
    // Exit 2 has already been explained, naming the file.
    if (failure.kind != KoboldFailureKind.unreadableModel) {
      _addLog(failure.message);
    }

    final b = _storageService.backendSettings;
    if (!koboldRetryWithoutFlashAttention(
      failure: failure,
      rocmWithFlashAttention: _rocmFlashAttentionLaunch,
      alreadyMarked: b.rocmFlashAttentionFailed,
    )) {
      return;
    }
    _addLog(
      'KoboldCpp stopped while answering with flash attention on. Starting '
      'it again without; it stays off on this machine until Flash '
      'Attention is switched back on in Settings.',
    );
    unawaited(() async {
      try {
        await b.setRocmFlashAttentionFailed(true);
        // Settings shows it off; switching it back on clears the mark.
        await b.setFlashAttentionEnabled(false);
        // The port is released a moment after the process ends.
        await Future<void>.delayed(const Duration(seconds: 1));
        await launch(executablePath, port: port);
      } on Object catch (e) {
        _addLog('KoboldCpp could not be started again: $e');
      }
    }());
  }

  /// Whether a staged config runs with flash attention on.
  bool _flashAttentionIn(String stagedJson) {
    try {
      final map = jsonDecode(stagedJson);
      return map is Map && kcppsRunsFlashAttention(map);
    } on FormatException catch (e) {
      debugPrint('[Kobold] staged config is not JSON: $e');
      return false;
    }
  }
}
