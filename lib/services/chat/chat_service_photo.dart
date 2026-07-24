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

part of '../chat_service.dart';

/// Photo-attachment turn logic, extracted from the `sendMessage` god path so
/// the two caption flows (blind-model pre-generation, vision-model post-
/// generation) share ONE stamp helper instead of drifting copies, and so the
/// "which turn does the photo ride on" decision lives in one auditable place.
///
/// All methods are session-token guarded on EVERY await: a chat switch during
/// the multi-second caption/probe awaits must abort the write (and, for the
/// pre-gen blind path, the whole turn) rather than mutate the newly loaded
/// chat. Private members, so safe on an extension.
extension ChatServicePhoto on ChatService {
  /// Persist just-attached photo bytes to the images dir AFTER sendMessage has
  /// passed its guards, so a guard bail can never orphan a file on disk (the
  /// composer no longer saves before ChatService accepts the turn). Returns
  /// the saved path, or null when there are no bytes / no image service.
  Future<String?> _persistTurnImage(Uint8List? bytes) async {
    if (bytes == null) return null;
    final igs = _imageGenService;
    if (igs == null) return null;
    return igs.saveImageToDisk(bytes);
  }

  /// Blind-model pre-generation caption: when the active model can't see, run
  /// the offline captioner so THIS turn's history already carries the gist.
  /// Returns false when the scene changed during any await (caller must abort
  /// the turn — the fix for a mid-caption chat switch generating into the
  /// wrong chat). Vision-capable models return true immediately; their caption
  /// runs post-generation via [runVisionPhotoCaption].
  Future<bool> runBlindPhotoCaption(
    ChatMessage userMsg,
    String imagePath,
    String? token,
  ) async {
    if (_llmProvider == null) return true;
    // Held across the awaits below: `_isGenerating` is false during captioning,
    // so this flag is what stops a second send from interleaving the turn.
    _photoTurnInFlight = true;
    try {
      final support = await VisionSupportResolver.instance.resolveForActiveLlm(
        backend: _llmProvider!.activeBackend,
        storage: _storageService,
      );
      if (_sceneChanged(token)) return false;
      if (support.supported) return true;
      LocalCaptionService.instance.configure(_storageService.rootPath);
      final caption = await LocalCaptionService.instance.captionImage(
        imagePath,
      );
      if (_sceneChanged(token)) return false;
      if (caption != null && caption.isNotEmpty) {
        await _stampImageCaption(userMsg, caption);
      }
      return true;
    } finally {
      _photoTurnInFlight = false;
    }
  }

  /// Vision-model post-generation caption: the pixels already rode along this
  /// turn; describe them once so LATER turns' flattened history can still say
  /// what the photo showed. No-op for blind models and on scene change.
  Future<void> runVisionPhotoCaption(
    ChatMessage userMsg,
    String imagePath,
    String? token,
  ) async {
    if (_llmProvider == null || _sceneChanged(token)) return;
    _photoTurnInFlight = true;
    try {
      final support = await VisionSupportResolver.instance.resolveForActiveLlm(
        backend: _llmProvider!.activeBackend,
        storage: _storageService,
      );
      if (!support.supported || _sceneChanged(token)) return;
      final caption = await captionChatImage(
        llm: _llmProvider!.activeService,
        imagePath: imagePath,
      );
      if (caption != null && caption.isNotEmpty && !_sceneChanged(token)) {
        await _stampImageCaption(userMsg, caption);
      }
    } finally {
      _photoTurnInFlight = false;
    }
  }

  /// The one place that writes `image_caption` — both caption paths funnel
  /// here so the merge-with-existing-metadata and save behave identically.
  Future<void> _stampImageCaption(ChatMessage userMsg, String caption) async {
    userMsg.activeMetadata = {
      ...?userMsg.activeMetadata,
      'image_caption': caption,
    };
    await _saveChat();
  }

  /// Base64 pixels to attach to THIS generation's request, or null. The photo
  /// rides only on the response that directly answers the turn it was sent on
  /// — never on a later idle/AFK narration, group auto-advance, or guest turn
  /// (which would re-upload an hours-old photo every turn and, once its caption
  /// is stamped, send both the pixels AND the history marker for the same
  /// image). "Directly answers" means the photo message is the last message
  /// (fresh turn, a regenerate that removed the reply, or the first group
  /// speaker) or we are continuing the assistant reply that immediately
  /// followed it. Blind backends get null (they rely on the history marker).
  Future<List<String>?> buildTurnImages(GenerationMode mode) async {
    if (_llmProvider == null || _messages.isEmpty) return null;
    var lastUserIdx = -1;
    for (var i = _messages.length - 1; i >= 0; i--) {
      if (_messages[i].isUser) {
        lastUserIdx = i;
        break;
      }
    }
    if (lastUserIdx < 0) return null;
    final md = _messages[lastUserIdx].activeMetadata;
    final path = md?['is_user_image'] == true
        ? md!['image_path'] as String?
        : null;
    if (path == null) return null;

    final last = _messages.length - 1;
    final isFreshOrRegen = lastUserIdx == last;
    final isContinueOfReply =
        mode == GenerationMode.continue_ &&
        lastUserIdx == last - 1 &&
        !_messages.last.isUser;
    if (!isFreshOrRegen && !isContinueOfReply) return null;

    final support = await VisionSupportResolver.instance.resolveForActiveLlm(
      backend: _llmProvider!.activeBackend,
      storage: _storageService,
    );
    if (!support.supported) return null;
    try {
      return [base64Encode(await File(path).readAsBytes())];
    } catch (e) {
      debugPrint('[Vision] cannot read attached photo: $e');
      return null;
    }
  }
}
