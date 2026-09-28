// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of 'image_gen_service.dart';

extension ImageGenStudio on ImageGenService {
  /// One pack. Does not call [generateImage]. A second start while one is
  /// running returns null and does not call [driver].
  Future<List<String>?> startExpressionPack(
    List<String> emotions,
    Future<List<String>> Function(List<String> emotions) driver,
  ) async {
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

  void _endGenerationLock() {
    if (_packFlight) {
      return;
    }
    _isGenerating = false;
  }

  /// One pack frame. While a pack flight holds the lock this does not call
  /// [generateImage]. Outside a flight it is a normal single generation.
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
    if (_packFlight) {
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
}
