// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of 'avatar_creation_controller.dart';

extension AvatarCreationLifecycle on AvatarCreationController {
  Future<void> _initQcGate() async {
    final support = await peekVisionSupport();
    if (_disposed) return;
    if (support != null &&
        !support.supported &&
        support.source != VisionSource.unknown) {
      qcVisible = false;
    } else {
      qcVisible = true;
      qcKnownSupported = support?.supported ?? false;
    }
    _notify();
  }

  Future<void> _refreshEngine() async {
    connectionOk = null;
    modelOptions = [];
    if (backend != ImageGenBackend.remote) {
      final url = backendProbeUrl(storage);
      if (url.isEmpty) {
        _notify();
        return;
      }
      testingConnection = true;
      _notify();
      final ok = await imageGen.testLocalConnection(url);
      if (_disposed) return;
      testingConnection = false;
      connectionOk = ok;
      if (!ok) {
        _notify();
        return;
      }
    }
    loadingModels = true;
    _notify();
    final options = await fetchBackendModelOptions(imageGen, storage);
    if (_disposed) return;
    modelOptions = options;
    loadingModels = false;
    _notify();
  }

  void _disposeCreator() {
    _disposed = true;
    session?.cancel();
    session?.removeListener(_notify);
    if (session != null) expressionPackBoard.release(session!);
    session?.dispose();
    qc?.cancel();
    qc?.removeListener(_notify);
    qc?.dispose();
    promptController.dispose();
  }
}
