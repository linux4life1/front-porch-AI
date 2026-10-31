// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/utils/character_id.dart';
import 'package:front_porch_ai/services/chat/doors/media/image_prompt_crafter.dart';
import 'package:front_porch_ai/services/chat/doors/media/photo_turns.dart';
import 'package:front_porch_ai/services/chat/image_command_service.dart';
import 'package:front_porch_ai/services/chat/lookup_force.dart';
import 'package:front_porch_ai/services/chat/mediawiki_search.dart';
import 'package:front_porch_ai/services/chat/session_state.dart';
import 'package:front_porch_ai/services/chat/web_search_service.dart';
import 'package:front_porch_ai/services/chat/wiki_search_service.dart';
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/llm_provider.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';
import 'package:front_porch_ai/services/world_repository.dart';

/// The chat's status line (the Scene Guest banner): [sticky] keeps it up
/// until the next line, an error lingers a little longer.
typedef ChatStatusLine =
    void Function(String? msg, {bool isError, bool sticky});

/// Pictures and lookups in the open chat: the `/image` command and its
/// prompt review, generated-image messages, photo-attachment turns
/// ([PhotoTurns]), and the model-initiated and forced `web_search` /
/// `wiki_search` dispatch.
///
/// Web search on/off is the Porch Life global, read live. Wiki search is
/// this chat's URL.
class MediaDoor extends ChangeNotifier {
  MediaDoor({
    required ChatSessionState session,
    required StorageService storage,
    required UserPersonaService personas,
    required WorldRepository worlds,
    required ImageGenService? Function() imageGen,
    required LLMProvider? Function() llmProvider,
    required LLMService? Function() craftLlm,
    required Future<void> Function() saveChat,
    // Stand-ins for members of other parts until those become doors too.
    required bool Function() isBusy,
    required ChatStatusLine setStatus,
    required bool Function(String? token) sceneChanged,
    required List<CharacterCard> Function() guestCards,
    required String Function(CharacterCard card) characterIdFor,
    required String? Function() expressionLabel,
    required String Function() timeOfDay,
  }) : _session = session,
       _storage = storage,
       _imageGen = imageGen,
       _saveChat = saveChat,
       _isBusy = isBusy,
       _setStatus = setStatus,
       _sceneChanged = sceneChanged,
       _characterIdFor = characterIdFor,
       _photos = PhotoTurns(
         session: session,
         storage: storage,
         imageGen: imageGen,
         llmProvider: llmProvider,
         saveChat: saveChat,
         sceneChanged: sceneChanged,
       ),
       _crafter = ImagePromptCrafter(
         session: session,
         storage: storage,
         personas: personas,
         worlds: worlds,
         llm: craftLlm,
         guestCards: guestCards,
         expressionLabel: expressionLabel,
         timeOfDay: timeOfDay,
       );

  final ChatSessionState _session;
  final StorageService _storage;
  final ImageGenService? Function() _imageGen;
  final Future<void> Function() _saveChat;
  final bool Function() _isBusy;
  final ChatStatusLine _setStatus;
  final bool Function(String? token) _sceneChanged;
  final String Function(CharacterCard card) _characterIdFor;
  final PhotoTurns _photos;
  final ImagePromptCrafter _crafter;

  /// `/image` slash-command orchestrator, built on first use. Its callbacks
  /// read live state, so it survives chat switches.
  ImageCommandService? _imageCommand;

  /// Prompt-review pause for /image (Chance-Time-style pending flag +
  /// completer): when the review setting is on, the crafted prompt parks
  /// here until the UI (desktop dialog / web modal) resolves it via
  /// [resolveImagePromptReview].
  String? _pendingImagePromptReview;
  Completer<String?>? _imageReviewCompleter;

  /// Named lookup for the next reply only. Cleared when that reply starts.
  String? _pendingForcedWebQuery;
  String? _pendingForcedWikiQuery;

  late final WebSearchService webSearchService = WebSearchService(
    getApiKey: () => _storage.webSearchSettings.searchApiKey,
    getGlobalDefault: () => _storage.webSearchSettings.webSearchDefault,
  );

  late final WikiSearchService wikiSearchService = WikiSearchService(
    getBaseUrl: () =>
        _storage.webSearchSettings.wikiUrlForChat(_session.currentSessionId),
  );

  // ── Images ────────────────────────────────────────────────────────────

  /// The crafted /image prompt awaiting user review (null when none). The
  /// desktop dialog and the web modal both key off this.
  String? get pendingImagePromptReview => _pendingImagePromptReview;

  /// Whether an /image run is live (crafting, awaiting review, or
  /// generating) — drives the in-chat "image coming to life" bubble.
  bool get isGeneratingChatImage => _imageCommand?.generating ?? false;

  /// Resolve a pending prompt review: the (possibly edited) prompt to
  /// generate with, or null to cancel. Safe to call when nothing is pending.
  void resolveImagePromptReview(String? prompt) {
    final completer = _imageReviewCompleter;
    if (completer == null) return;
    _pendingImagePromptReview = null;
    _imageReviewCompleter = null;
    completer.complete(prompt);
    notifyListeners();
  }

  ImageCommandService ensureImageCommand() {
    return _imageCommand ??= ImageCommandService(
      isConfigured: () => _imageGen()?.isConfigured ?? false,
      isBusy: _isBusy,
      onStatus: (message, {bool sticky = false}) =>
          _setStatus(message, isError: message.startsWith('⚠'), sticky: sticky),
      craftPrompt: (request) async {
        final crafted = await _craftImageCommandPrompt(request);
        // '' = craft failure (the leaf surfaces the ⚠); null = stop silently.
        if (crafted == null || crafted.trim().isEmpty) return '';
        if (!_storage.imageGenSettings.imageGenPromptReview) {
          return crafted;
        }
        // Review-first: park the crafted prompt for the UI (desktop dialog /
        // web modal) and wait for the user's edit or cancel.
        _pendingImagePromptReview = crafted;
        _imageReviewCompleter = Completer<String?>();
        notifyListeners();
        final reviewed = await _imageReviewCompleter!.future;
        if (reviewed == null || reviewed.trim().isEmpty) {
          _setStatus('Image generation cancelled.');
          return null;
        }
        return reviewed.trim();
      },
      generate: (prompt, request) => _imageGen()!.generateImage(
        prompt: prompt,
        // Negative prompt for a `/image` generation: the user's default.
        negativePrompt: _storage.imageGenSettings.imageGenNegativePrompt.trim(),
        isPortrait:
            request.kind == ImageCommandKind.me ||
            request.kind == ImageCommandKind.character,
      ),
      saveImage: (bytes) => _imageGen()!.saveImageToDisk(bytes),
      snapshotSession: () => _session.currentSessionId,
      attachToChat: (path, prompt, request, launchToken) async {
        // The gen is slow (1-10 min locally); if the user switched chats
        // meanwhile, DON'T append this image to the now-active chat — it was
        // crafted from the ORIGINAL chat's scene and would land on the wrong
        // character. Surface a status and report "not attached".
        if (_sceneChanged(launchToken as String?)) {
          _setStatus(
            '🎨 Image is ready, but you left the chat it was made for — '
            'open that chat and use /image again to add it.',
            isError: true,
          );
          return false;
        }
        final speaker = _crafter.speakerFor(request);
        await addGeneratedImageMessage(
          path,
          prompt,
          senderName: speaker?.name,
          characterId: _session.activeGroup != null && speaker != null
              ? _characterIdFor(speaker)
              : null,
        );
        return true;
      },
      notifyRunStateChanged: notifyListeners,
    );
  }

  Future<String?> _craftImageCommandPrompt(
    ImageCommandRequest request, {
    String? instruction,
  }) async {
    final igs = _imageGen();
    if (igs == null) return null;
    return _crafter.craft(igs, request, instruction: instruction);
  }

  /// The prompt the Image Studio's "Write it for me" writes for the chat that
  /// is open: [subject] is `free` (what the person typed, or the scene when
  /// nothing was typed), `char` (the character on screen) or `persona`.
  /// Null when no image backend is set up.
  Future<String?> craftStudioPrompt(String subject, String instruction) {
    final typed = instruction.trim();
    // As the desktop Studio does: the subject picks the mode, and whatever is
    // in the prompt box is guidance for the writer to parse. Freeform with
    // nothing typed describes the scene.
    final request = ImageCommandRequest(switch (subject) {
      'char' => ImageCommandKind.character,
      'persona' => ImageCommandKind.me,
      _ => ImageCommandKind.scene,
    });
    return _craftImageCommandPrompt(
      request,
      instruction: typed.isEmpty ? null : typed,
    );
  }

  /// Append an already-saved generated image to the conversation as a
  /// character message (empty text; the bubble renders the image from
  /// metadata). Shared by the /image slash command, the Image Studio's
  /// "Send to chat", and the web insert-image endpoint.
  Future<void> addGeneratedImageMessage(
    String path,
    String prompt, {
    String? senderName,
    String? characterId,
  }) async {
    if (_session.activeCharacter == null && _session.activeGroup == null) {
      return;
    }
    _session.messages.add(
      ChatMessage(
        text: '',
        sender: senderName ?? _session.activeCharacter?.name ?? 'Narrator',
        isUser: false,
        characterId: characterId,
        metadata: {
          'is_generated_image': true,
          'image_path': path,
          'image_prompt': prompt,
        },
      ),
    );
    await _saveChat();
    notifyListeners();
  }

  // ── Photo turns ([PhotoTurns]) ────────────────────────────────────────

  /// A photo turn's caption or probe is running (see [PhotoTurns.inFlight]).
  bool get photoTurnInFlight => _photos.inFlight;

  Future<String?> persistTurnImage(Uint8List? bytes) =>
      _photos.persistTurnImage(bytes);

  Future<bool> runBlindPhotoCaption(
    ChatMessage userMsg,
    String imagePath,
    String? token,
  ) => _photos.runBlindPhotoCaption(userMsg, imagePath, token);

  Future<void> runVisionPhotoCaption(
    ChatMessage userMsg,
    String imagePath,
    String? token,
  ) => _photos.runVisionPhotoCaption(userMsg, imagePath, token);

  Future<List<String>?> buildTurnImages(GenerationMode mode) =>
      _photos.buildTurnImages(mode);

  // ── Web and wiki lookups ──────────────────────────────────────────────

  /// This chat's wiki base URL ('' when none).
  String get wikiBaseUrl =>
      _storage.webSearchSettings.wikiUrlForChat(_session.currentSessionId);

  /// The Porch Life web search default, read live.
  bool get webSearchDefault => _storage.webSearchSettings.webSearchDefault;

  bool get wikiLookupAvailable => parseWikiBaseUrl(wikiBaseUrl) != null;

  /// Either lookup may run this turn.
  bool get lookupsActive =>
      webSearchService.isActive || wikiSearchService.isActive;

  void beginUserSend() {
    webSearchService.beginUserSend();
    wikiSearchService.beginUserSend();
  }

  void resetForFreshChat() {
    webSearchService.resetForFreshChat();
    wikiSearchService.resetForFreshChat();
  }

  void armForcedLookup({String? webQuery, String? wikiQuery}) {
    final web = webQuery?.trim() ?? '';
    final wiki = wikiQuery?.trim() ?? '';
    _pendingForcedWebQuery = web.isEmpty ? null : web;
    _pendingForcedWikiQuery = wiki.isEmpty ? null : wiki;
  }

  /// The forced web and wiki queries armed for this reply, cleared as read.
  (String?, String?) takeForcedLookup() {
    final armed = (_pendingForcedWebQuery, _pendingForcedWikiQuery);
    _pendingForcedWebQuery = null;
    _pendingForcedWikiQuery = null;
    return armed;
  }

  /// Banner text when [raw] is a lookup command that must not send.
  /// Null when the line is ordinary chat or a lookup that can run.
  String? lookupCommandBlock(String raw) {
    final parsed = parseLookupForce(raw);
    if (!parsed.attempted) return null;
    if (parsed.error != null) return parsed.error;
    return lookupForceUnavailable(
      webQuery: parsed.webQuery,
      wikiQuery: parsed.wikiQuery,
      webEnabled: webSearchDefault,
      hasWiki: wikiLookupAvailable,
    );
  }

  void announceLookupForce(String message) {
    _setStatus(message, isError: true);
  }

  /// Runs the words the user named for this reply. Null when none were.
  Future<ForcedLookupOutcome?> runForcedLookup({
    String? webQuery,
    String? wikiQuery,
  }) async {
    if ((webQuery == null || webQuery.isEmpty) &&
        (wikiQuery == null || wikiQuery.isEmpty)) {
      return null;
    }
    beginUserSend();
    return runForcedLookups(
      web: webSearchService,
      wiki: wikiSearchService,
      webQuery: webQuery,
      wikiQuery: wikiQuery,
    );
  }

  Future<void> setWikiBaseUrl(String url) async {
    final settings = _storage.webSearchSettings;
    await settings.applyWikiUrlForSession(_session.currentSessionId, url);
    final canonical = url.trim().isEmpty
        ? ''
        : (parseWikiBaseUrl(url)?.origin ?? '');
    final card = _session.activeCharacter;
    if (_session.activeGroup == null && card != null && canonical.isNotEmpty) {
      await settings.setWikiUrlForCharacter(card.stableGroupId, canonical);
    }
    notifyListeners();
  }

  /// New 1:1 session: seed this chat from the character's last picked wiki.
  /// Groups stay session-only — do not guess a host character.
  Future<void> seedWikiForNewSession() async {
    final sid = _session.currentSessionId;
    if (sid == null || sid.isEmpty) return;
    final url = _storage.webSearchSettings.wikiUrlToSeedForNewChat(
      isGroup: _session.activeGroup != null,
      characterId: _session.activeCharacter?.stableGroupId,
    );
    if (url == null) return;
    await _storage.webSearchSettings.setChatWikiUrl(sid, url);
  }

  /// Forks keep the parent's per-chat wiki (including explicit off).
  Future<void> copyWikiForForkedSession(String oldSessionId) async {
    final sid = _session.currentSessionId;
    if (sid == null || sid.isEmpty) return;
    final settings = _storage.webSearchSettings;
    if (!settings.hasSessionWikiOverride(oldSessionId)) return;
    await settings.setChatWikiUrl(sid, settings.wikiUrlForChat(oldSessionId));
  }
}
