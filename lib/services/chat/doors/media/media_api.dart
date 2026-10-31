// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// Bridge: the media names ChatService consumers have always called, each a
// one-line call on [ChatService.mediaDoor]. The shell exports this library,
// so callers keep their imports. No private state is reachable from here.

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat_service.dart';

/// `/image` slash command and its prompt review.
extension ChatServiceImages on ChatService {
  String? get pendingImagePromptReview => mediaDoor.pendingImagePromptReview;
  bool get isGeneratingChatImage => mediaDoor.isGeneratingChatImage;
  void resolveImagePromptReview(String? prompt) =>
      mediaDoor.resolveImagePromptReview(prompt);
  Future<String?> craftStudioPrompt(String subject, String instruction) =>
      mediaDoor.craftStudioPrompt(subject, instruction);
}

/// Photo-attachment turns.
extension ChatServicePhoto on ChatService {
  Future<bool> runBlindPhotoCaption(
    ChatMessage userMsg,
    String imagePath,
    String? token,
  ) => mediaDoor.runBlindPhotoCaption(userMsg, imagePath, token);
  Future<void> runVisionPhotoCaption(
    ChatMessage userMsg,
    String imagePath,
    String? token,
  ) => mediaDoor.runVisionPhotoCaption(userMsg, imagePath, token);
  Future<List<String>?> buildTurnImages(GenerationMode mode) =>
      mediaDoor.buildTurnImages(mode);
}

/// Model-initiated and forced `web_search` / `wiki_search`.
extension ChatServiceWebSearch on ChatService {
  /// Shadowed by the class's own `webSearchEnabled`, which always wins.
  bool get webSearchEnabled => mediaDoor.webSearchDefault;
  bool get wikiLookupAvailable => mediaDoor.wikiLookupAvailable;
  String? lookupCommandBlock(String raw) => mediaDoor.lookupCommandBlock(raw);
  void announceLookupForce(String message) =>
      mediaDoor.announceLookupForce(message);
}
