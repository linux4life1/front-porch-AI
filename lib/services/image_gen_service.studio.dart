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
    _isGenerating = true;
    _statusMessage = 'Expression pack';
    _notify();
    try {
      return await driver(List<String>.from(emotions));
    } finally {
      _isGenerating = false;
      _statusMessage = '';
      _notify();
    }
  }
}
