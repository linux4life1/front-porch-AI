// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/caption/local_caption_service.dart';
import 'package:front_porch_ai/services/capability/vision_support_resolver.dart';
import 'package:front_porch_ai/services/chat/session_state.dart';
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/llm_provider.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/vision_eval.dart';

/// Photo-attachment turn logic, kept out of the send path so the two caption
/// flows (blind-model pre-generation, vision-model post-generation) share ONE
/// stamp helper instead of drifting copies, and so the "which turn does the
/// photo ride on" decision lives in one auditable place.
///
/// Every await is session-token guarded: a chat switch during the
/// multi-second caption/probe awaits must abort the write (and, for the
/// pre-gen blind path, the whole turn) rather than mutate the newly loaded
/// chat.
class PhotoTurns {
  PhotoTurns({
    required ChatSessionState session,
    required StorageService storage,
    required ImageGenService? Function() imageGen,
    required LLMProvider? Function() llmProvider,
    required Future<void> Function() saveChat,
    required bool Function(String? token) sceneChanged,
  }) : _session = session,
       _storage = storage,
       _imageGen = imageGen,
       _llmProvider = llmProvider,
       _saveChat = saveChat,
       _sceneChanged = sceneChanged;

  final ChatSessionState _session;
  final StorageService _storage;
  final ImageGenService? Function() _imageGen;
  final LLMProvider? Function() _llmProvider;
  final Future<void> Function() _saveChat;
  final bool Function(String? token) _sceneChanged;

  /// A photo turn's caption or probe is running. `_isGenerating` is false
  /// during those awaits, so this is what stops a second send interleaving.
  bool get inFlight => _inFlight;
  bool _inFlight = false;

  /// Persist just-attached photo bytes to the images dir AFTER sendMessage has
  /// passed its guards, so a guard bail can never orphan a file on disk (the
  /// composer no longer saves before the turn is accepted). Returns
  /// the saved path, or null when there are no bytes / no image service.
  Future<String?> persistTurnImage(Uint8List? bytes) async {
    if (bytes == null) return null;
    final igs = _imageGen();
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
    final provider = _llmProvider();
    if (provider == null) return true;
    // Held across the awaits below: `_isGenerating` is false during captioning,
    // so this flag is what stops a second send from interleaving the turn.
    _inFlight = true;
    try {
      final support = await VisionSupportResolver.instance.resolveForActiveLlm(
        backend: provider.activeBackend,
        storage: _storage,
      );
      if (_sceneChanged(token)) return false;
      if (support.supported) return true;
      LocalCaptionService.instance.configure(_storage.rootPath);
      final caption = await LocalCaptionService.instance.captionImage(
        imagePath,
      );
      if (_sceneChanged(token)) return false;
      if (caption != null && caption.isNotEmpty) {
        await _stampImageCaption(userMsg, caption);
      }
      return true;
    } finally {
      _inFlight = false;
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
    if (_llmProvider() == null || _sceneChanged(token)) return;
    _inFlight = true;
    try {
      final support = await VisionSupportResolver.instance.resolveForActiveLlm(
        backend: _llmProvider()!.activeBackend,
        storage: _storage,
      );
      if (!support.supported || _sceneChanged(token)) return;
      final caption = await captionChatImage(
        llm: _llmProvider()!.activeService,
        imagePath: imagePath,
      );
      if (caption != null && caption.isNotEmpty && !_sceneChanged(token)) {
        await _stampImageCaption(userMsg, caption);
      }
    } finally {
      _inFlight = false;
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
    final messages = _session.messages;
    if (_llmProvider() == null || messages.isEmpty) return null;
    var lastUserIdx = -1;
    for (var i = messages.length - 1; i >= 0; i--) {
      if (messages[i].isUser) {
        lastUserIdx = i;
        break;
      }
    }
    if (lastUserIdx < 0) return null;
    final md = messages[lastUserIdx].activeMetadata;
    final path = md?['is_user_image'] == true
        ? md!['image_path'] as String?
        : null;
    if (path == null) return null;

    final last = messages.length - 1;
    final isFreshOrRegen = lastUserIdx == last;
    final isContinueOfReply =
        mode == GenerationMode.continue_ &&
        lastUserIdx == last - 1 &&
        !messages.last.isUser;
    if (!isFreshOrRegen && !isContinueOfReply) return null;

    final support = await VisionSupportResolver.instance.resolveForActiveLlm(
      backend: _llmProvider()!.activeBackend,
      storage: _storage,
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
