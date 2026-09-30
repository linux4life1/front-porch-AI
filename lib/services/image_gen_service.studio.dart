// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of 'image_gen_service.dart';

/// Expression packs and stopping a job. These are extension members, not
/// class members, because test doubles that only `implement` this service
/// have none of its private fields.
extension ImageGenStudio on ImageGenService {
  /// False on a test double, which has no lock of its own.
  bool _lockIsOnThisInstance() {
    try {
      return identical(_isGenerating, _isGenerating);
    } on NoSuchMethodError {
      return false;
    }
  }

  /// Runs one pack inside a single hold of the generation lock, so nothing
  /// else can start between two of its frames. Null (and the status says
  /// "Already generating.") when a generation is already running, without
  /// calling [driver]. On a test double the pack simply runs.
  Future<List<String>?> startExpressionPack(
    List<String> emotions,
    Future<List<String>> Function(List<String> emotions) driver,
  ) async {
    if (!_lockIsOnThisInstance()) {
      return driver(List<String>.from(emotions));
    }
    if (_isGenerating) {
      _statusMessage = kAlreadyGeneratingMessage;
      _notify();
      return null;
    }
    _packFlight = true;
    _isGenerating = true;
    _statusMessage = 'Expression pack';
    _notify();
    try {
      return await driver(List<String>.from(emotions));
    } finally {
      _packFlight = false;
      _isGenerating = false;
      _statusMessage = '';
      _notify();
    }
  }

  /// Ends a generation's hold on the lock, unless a pack holds it.
  void _endGenerationLock() {
    if (_packFlight) return;
    _isGenerating = false;
  }

  /// One pack frame. Inside a pack flight it runs under the flight's lock;
  /// otherwise it is an ordinary single generation.
  Future<Uint8List?> expressionFrame({
    required String prompt,
    String? negativePrompt,
    String? size,
    Uint8List? referenceImage,
    int? seed,
    double? denoise,
    StudioIntent intent = StudioIntent.create,
    double? editStrength,
  }) {
    if (_lockIsOnThisInstance() && _packFlight) {
      return _generateImageImpl(
        prompt: prompt,
        negativePrompt: negativePrompt,
        size: size,
        referenceImage: referenceImage,
        seed: seed,
        denoise: denoise,
        intent: intent,
        editStrength: editStrength,
        fromPack: true,
      );
    }
    return generateImage(
      prompt: prompt,
      negativePrompt: negativePrompt,
      size: size,
      referenceImage: referenceImage,
      seed: seed,
      denoise: denoise,
      intent: intent,
      editStrength: editStrength,
    );
  }

  /// Stops the job the server is running for this service: on ComfyUI the
  /// prompt is taken off the queue or interrupted. The other backends have no
  /// job to stop from here; they finish the picture they are on.
  Future<void> cancelJob() async {
    if (!_lockIsOnThisInstance()) return;
    await _comfyUi?.cancelRun();
  }
}
