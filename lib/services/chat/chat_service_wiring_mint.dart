// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Slice 7 mint seam: the chat-side half of "minted places" — hold the
// proposal, hand it to PlaceFactory on the tap, remember ignores.
// Split from wiring_injection (the 500-line ratchet and one-responsibility
// per seam file); the move seam stayed there because it is two methods
// deep in the slots law. The door builders (WP2 of
// docs/design/chat-service-decomposition.md) sit at the end.

part of '../chat_service.dart';

extension ChatServicePlaceMint on ChatService {
  /// A proposed NEW place the judge heard named in the narration,
  /// awaiting the tap. Nothing exists in the library until then.
  ProposedPlace? get pendingPlaceMint => _sceneMoves.mints.pending;

  void flagSuggestedPlaceMint(String name, String descriptor) {
    if (name.trim().isEmpty) return;
    final setting = chatPrimaryWorldId == null
        ? null
        : _worldRepository.worldById(chatPrimaryWorldId!);
    _sceneMoves.mints.pending = ProposedPlace(
      name: name.trim(),
      descriptor: descriptor.trim(),
      settingName: setting?.name ?? '',
    );
    debugPrint('[Realism:Mint] suggested place pending: $name');
    notifyListeners();
  }

  /// Add (and optionally move the scene into) the minted place. The
  /// mint reads the live narration window for grounding, saves through
  /// the ONE repository law, and on 'alsoMove' runs the SAME slot swap
  /// a manual move runs (old setting demotes to top of Lore). Returns
  /// the result so the dialog can speak; the pending flag clears on
  /// success or honest failure — a refused draft must not nag, the
  /// author just declined a bad guess.
  Future<PlaceMintResult> acceptMintedPlace({required bool alsoMove}) async {
    final proposal = _sceneMoves.mints.pending;
    final settingId = chatPrimaryWorldId;
    if (proposal == null) {
      return const PlaceMintResult.failure('nothing is being proposed');
    }
    final setting = settingId == null
        ? null
        : _worldRepository.worldById(settingId);
    if (setting == null) {
      _sceneMoves.mints.resolve();
      notifyListeners();
      return const PlaceMintResult.failure(
        'the scene has no setting to place it under',
      );
    }
    final grounding = [
      for (final m
          in _session.messages.length <= 6
              ? _session.messages
              : _session.messages.sublist(_session.messages.length - 6))
        if (m.displayText.trim().isNotEmpty) m.displayText.trim(),
    ].join('\n');
    // Constructed at the call site like SceneGuestFactory (this file is
    // an extension and holds no fields); the eval seams make a local
    // KoboldCpp able to mint too — tools first, text floor (design §7).
    final factory = PlaceFactory(
      _worldRepository,
      fireToolEval: _fireToolEval,
      fireTextEval: (p, {onChunk}) => _fireLLMEval(p, onChunk: onChunk),
      probe: _toolProbe,
      getBackendIdentity: () => _evalBackendIdentity,
    );
    final result = await factory.mint(
      name: proposal.name,
      descriptor: proposal.descriptor,
      setting: setting,
      sceneGrounding: grounding,
    );
    _sceneMoves.mints.resolve();
    if (result.ok && alsoMove && result.world != null) {
      await setChatPlaceSlots(
        primaryId: result.world!.id,
        loreIds: [
          setting.id,
          for (final l in _chatPlaceSlots.loreIds)
            if (l != setting.id) l,
        ],
      );
    }
    notifyListeners();
    return result;
  }

  /// Ignore: remember the name for this chat — it will not be proposed
  /// again until the chat is re-opened (session-reset law, Scene-Guest
  /// names).
  void ignoreMintedPlace() {
    final proposal = _sceneMoves.mints.pending;
    if (proposal == null) return;
    _sceneMoves.mints.ignore(proposal.name);
    notifyListeners();
  }
}

/// Builds the doors the shell owns. Each callback below stands in for a
/// private member of another part until that part becomes a door too.
extension ChatServiceDoorWiring on ChatService {
  MediaDoor _buildMediaDoor() => MediaDoor(
    session: _session,
    storage: _storageService,
    personas: _userPersonaService,
    worlds: _worldRepository,
    imageGen: () => _imageGenService,
    llmProvider: () => _llmProvider,
    craftLlm: () => testLlmServiceOverride ?? _llmProvider?.activeService,
    saveChat: _saveChat,
    isBusy: () => _isTurnBusy || _sceneGuest.busy,
    setStatus: _setGuestStatus,
    sceneChanged: _sceneChanged,
    guestCards: () => _sceneGuest.cards,
    characterIdFor: _getCharacterIdFromCard,
    expressionLabel: () => currentExpressionLabel,
    timeOfDay: () => _timeService.timeOfDay,
  );

  ActionsDoor _buildActionsDoor() => ActionsDoor(
    session: _session,
    personas: _userPersonaService,
    mouthLlm: () => _mouthLlm,
    mouthStream: _mouthGenerateStream,
  );
}
