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

// ── Stable identities for the two listeners this library registers on other
// notifiers ────────────────────────────────────────────────────────────────
//
// EXTENSION-METHOD TEAR-OFFS ARE NOT CANONICALIZED IN DART. For a plain
// instance method `a.m == a.m` is true; for an extension member it is FALSE —
// each mention builds a fresh closure. Both callbacks below live in the
// extension in this file, so every `removeListener(_onSomething)` here was
// handed a closure the notifier had never seen and silently removed
// nothing: ChatService.dispose left itself attached to StorageService, the
// LLMProvider and the CharacterRepository (a leaked service kept receiving
// notifications for the rest of the run), and swapping either dependency
// stacked a second live callback on top of the first.
//
// An Expando holds ONE closure per service — weakly, so it cannot itself keep
// a disposed ChatService alive — which is the thing removeListener can find
// again. Anything registered on another notifier from this library must go
// through these; a bare `_onFoo` tear-off is unremovable.
final Expando<VoidCallback> _backendIdentityListener = Expando(
  'ChatService backend-identity listener',
);
final Expando<VoidCallback> _characterLibraryListener = Expando(
  'ChatService character-library listener',
);

/// Grab-bag of small, single-purpose accessors and one-shot setup setters that
/// had no other natural home when the god file was shrunk toward the 1,000-line
/// ratchet (docs/design/god-file-elimination.md). Extracted verbatim (zero
/// behaviour change); none of these are overridden by any `implements
/// ChatService` test double, so — unlike the members left in the class body —
/// moving them here as extension members is safe (extension members are
/// statically dispatched and cannot be overridden via `implements`).
extension ChatServiceAccessors on ChatService {
  /// Point this service — and the MemoryService it owns — at [db].
  ///
  /// Used both to wire the database in at startup and to re-point it after a
  /// swap (stable-DB import, storage-root move, backup restore). The
  /// MemoryService caches its own handle, so leaving it out meant RAG memory
  /// kept querying the closed database until the app was restarted; it is null
  /// during startup wiring, which the null-aware call covers.
  void updateDatabase(AppDatabase db) {
    _db = db;
    _memoryService?.updateDatabase(db);
  }

  /// Set the database instance after construction. Alias of [updateDatabase]
  /// so startup wiring and post-swap rebinding can never drift apart.
  void setDatabase(AppDatabase db) => updateDatabase(db);

  /// The chat-scoped lorebook: lore that lives and dies with this one
  /// conversation. The sidebar edits it directly (live instance) and calls
  /// [commitChatLorebookEdit] to notify + persist.
  Lorebook get chatLorebook => _loreTimedEffects.chatLorebook;

  Future<void> commitChatLorebookEdit() async {
    notifyListeners();
    await _saveChat();
  }

  /// Names of lore entries dropped by the token budget on the last
  /// generation, plus the meter numbers the sidebar shows.
  List<String> get lastLoreOverflow => _lastLoreOverflow;
  int get lastLoreTokens => _lastLoreTokens;
  int get lastLoreBudget => _lastLoreBudget;

  /// Read surface for the sidebar's sticky/cooldown countdown pills.
  LorebookTimedEffects get loreTimedEffects => _loreTimedEffects;

  /// Mutation-free "would trigger next" preview for the composer draft.
  Set<LorebookEntry> previewLoreTriggers(String draft) =>
      _lorebookScanner.previewTriggers(draft);

  /// The post-group-filter active lore set — what is ACTUALLY injected this
  /// turn. Sidebar dots and the web facade read this so they never show an
  /// inclusion-group loser as active.
  Set<LorebookEntry> currentlyActiveLoreEntries() => _lorebookInjector
      .activeEntries(sessionSeed: _currentSessionId ?? '')
      .toSet();

  /// Public attach surface for chat tools / UI (Living Worlds).
  /// Primary-first then lore (compatible with lore collectors).
  List<String> get chatWorldIds => List.unmodifiable(_chatPlaceSlots.allIds);

  /// Setting slot (0..1) — owns weather / room description for this chat.
  String? get chatPrimaryWorldId => _chatPlaceSlots.primaryId;

  /// Lore slots (0..N) — lorebook entries only; never drive weather.
  List<String> get chatLoreWorldIds =>
      List.unmodifiable(_chatPlaceSlots.loreIds);

  /// Coarse absence bucket ("a few days"), or null under the threshold /
  /// fresh chat. Words only — never digits (see AbsenceTracker).
  String? get absencePhrase => AbsenceTracker.bucketPhrase(
    _absenceGap,
    thresholdHours: _storageService.realismSettings.absenceThresholdHours,
  );

  /// [absencePhrase] gated by the welcome-back-banner setting — the ONE gate
  /// both the desktop banner and the web facade read, so they can't drift.
  String? get absenceBannerPhrase =>
      _storageService.realismSettings.absenceBannerEnabled
      ? absencePhrase
      : null;

  // ── Thin public surface for flat members still read/written by
  // UI/pages/dialogs. Full impl in the respective *Service (chaos_mode_service,
  // relationship_service, expression_classifier in chat/). 1:1 vs group parity
  // via the services' cbs + god impersonation dance (unchanged). ──
  ExpressionService get expressionService => _expressionService;
  int get chaosPressure => _chaosModeService.chaosPressure;
  String get activeFixation => _relationshipService.activeFixation;
  bool get pendingTrustRepair => _relationshipService.pendingTrustRepair;

  /// Returns the standard expression label for the current emotion.
  ///
  /// If a manual expression is set via [setManualExpression], returns that.
  /// When classification mode is 'onnx', uses the ONNX classifier result.
  /// Otherwise maps the nuanced emotion to a standard label using
  /// [EmotionLabels.nuancedToStandard]. Delegates to _expressionService;
  /// prefer calling that directly in new code. (Historical note: an earlier
  /// comment here claimed this getter, resolveExpressionAvatar,
  /// setManualExpression, and setExpressionClassifierService had all been
  /// "excised". They had not — chat_page.dart and main.dart still call them
  /// live. A cleanup that trusted the old comment would have deleted working
  /// code; don't repeat that mistake.)
  String? get currentExpressionLabel =>
      _expressionService.currentExpressionLabel;
  AvatarImage? resolveExpressionAvatar(
    CharacterCard character, {
    bool rerollIfSame = false,
  }) => _expressionService.resolveExpressionAvatar(
    character,
    rerollIfSame: rerollIfSame,
  );

  /// True when the Realism Engine (and Needs) should actually run for the
  /// current chat mode. In group chats this is only true when *not* in
  /// Director/observerMode (per design — Director is narrative control,
  /// not simulation).
  bool get _realismActiveThisMode =>
      _realismEnabled &&
      !_autoResponseInProgress &&
      (_activeGroup == null || !_observerMode);

  /// The one-shot decision for THIS turn — the tri-state setting resolved
  /// against the live backend (pure policy in resolveOneShotMode; the
  /// probe verdict and locality are the only inputs storage can't know).
  /// Consulted by the pre-generation dance, the regen replay, and the
  /// retroactive baseline scan, so all three paths flip together.
  bool get _oneShotActive => resolveOneShotMode(
    mode: _storageService.realismSettings.oneShotMode,
    isLocal: testLlmServiceOverride != null
        ? testIsLocalOverride
        : (_llmProvider?.isLocal ?? true),
    toolSupport: _toolProbe.supportFor(_evalBackendIdentity),
    // A live voice call upgrades Off to Auto's fuse-where-safe rule — one
    // eval call instead of three before the character can speak.
    callMode: _callMode,
    preferTextEvals: _storageService.realismSettings.preferTextEvals,
  );

  /// The story clock advances on its OWN eval this turn: the engine is off and
  /// the user opted in (docs/design/feature-independence.md). Keyed on
  /// [_realismEnabled], deliberately NOT [_realismActiveThisMode] — the latter
  /// also goes false during AFK auto-response and in group Director mode,
  /// where the engine is merely paused and already has its own clock handling.
  /// Letting standalone fill those gaps would change behaviour for engine-ON
  /// users, who never asked for it.
  bool get _standaloneClockActive =>
      !_realismEnabled &&
      _timeService.passageOfTimeEnabled &&
      _storageService.realismSettings.standaloneClockEnabled;

  /// The story clock is actually moving, by whichever driver. This is the
  /// gate for everything that reads the clock rather than advancing it — the
  /// time prompt fragment, weather, dreams — because what those needed all
  /// along was a MOVING clock, not the engine. With the engine off and the
  /// standalone clock off it is false, which is exactly the frozen-clock state
  /// the old realism gate produced, so nothing changes by default.
  bool get _clockRunning => StoryClock.isRunning(
    passageOfTimeEnabled: _timeService.passageOfTimeEnabled,
    realismEnabled: _realismEnabled,
    standaloneClockEnabled:
        _storageService.realismSettings.standaloneClockEnabled,
  );

  /// Objectives are actually running for this chat: the per-chat switch AND the
  /// global one (docs/design/feature-independence.md). Objectives depend on
  /// nothing but their own eval cost — not the Realism Engine, not the Journal.
  ///
  /// The global is applied LIVE here rather than AND-ed into `_objectivesEnabled`
  /// at seed time the way Needs does it. That difference is deliberate: the
  /// stored-AND means flipping the global off leaves every already-open chat
  /// running, which for Needs is merely surprising but here would defeat the
  /// switch's whole purpose — stopping a recurring model call. Checking live
  /// means "off" takes effect on the next turn, everywhere.
  bool get _objectivesActiveImpl =>
      _objectivesEnabled && _storageService.realismSettings.objectivesEnabled;

  bool get isCancellingRealismEval => _isCancellingRealismEval;

  void _onBackendIdentityMaybeChanged() {
    if (_disposed) return;
    ToolChoiceStyleProbe.instance.reset(_evalBackendIdentity);
    _toolSupportTester.onBackendMaybeChanged();
  }

  /// The removable identity of [_onBackendIdentityMaybeChanged] — see the
  /// Expando note at the top of this file. Register/unregister ONLY this.
  VoidCallback get _onBackendIdentity =>
      _backendIdentityListener[this] ??= _onBackendIdentityMaybeChanged;

  /// The removable identity of [_onCharacterLibraryChanged].
  VoidCallback get _onCharacterLibrary =>
      _characterLibraryListener[this] ??= _onCharacterLibraryChanged;

  /// Human-readable mood label containing exact emotion string and valence direction.
  String get moodLabel {
    if (_characterEmotion.isEmpty) return 'Neutral';
    final capEmotion =
        _characterEmotion.substring(0, 1).toUpperCase() +
        _characterEmotion.substring(1);
    final intensity = _emotionIntensity.isNotEmpty
        ? ' ($_emotionIntensity)'
        : '';
    return '$capEmotion$intensity';
  }

  /// Returns whether the currently active character enjoys low hygiene.
  /// We always prefer the live value from the character's FrontPorchExtensions
  /// so that toggling the setting on the character immediately affects any
  /// already-loaded chats (no database change required).
  bool get enjoysLowHygiene {
    // Group chats have no single "active character" hygiene preference — it is
    // strictly per-speaker (the injection builders resolve it from each
    // member's own card). Never fall through to the 1:1 scalar in a group, or a
    // preference carried in from a previous 1:1 (e.g. a "enjoys being dirty"
    // character) would stay stale and invert every group member's hygiene.
    if (_activeGroup != null) {
      return _activeCharacter?.frontPorchExtensions?.enjoysLowHygiene ?? false;
    }
    return _activeCharacter?.frontPorchExtensions?.enjoysLowHygiene ??
        _enjoysLowHygiene;
  }

  /// Re-reads the "Enjoys low hygiene" preference from the currently active
  /// character's FrontPorchExtensions. Call this after editing the character
  /// so that existing chats immediately pick up the new setting without a
  /// database change.
  void refreshEnjoysLowHygieneFromActiveCharacter() {
    if (_activeCharacter != null) {
      _enjoysLowHygiene =
          _activeCharacter!.frontPorchExtensions?.enjoysLowHygiene ?? false;
      notifyListeners();
    }
  }

  /// Set the CharacterRepository so group mode can look up characters.
  void setCharacterRepository(CharacterRepository repo) {
    if (identical(_characterRepository, repo)) return;
    _characterRepository?.removeListener(_onCharacterLibrary);
    _characterRepository = repo;
    _characterRepository!.addListener(_onCharacterLibrary);
  }

  /// Silently prune Scene Guests whose library card no longer exists. Deleting a
  /// character PNG is a deliberate user action, so a deleted guest is dropped
  /// from the open scene with NO `/exit` narration — `_resolveSceneGuestCards`
  /// removes any id that no longer resolves. Self-heals the "deleted card but
  /// still treated as present" case (e.g. cast detection skipping a re-narrated
  /// character because the stale guest was still in the scene list).
  void _onCharacterLibraryChanged() {
    if (_disposed || _sceneGuest.busy || _sceneGuest.ids.isEmpty) return;
    // Defer out of the repository's notify callback so we never start a DB read
    // from inside its in-progress write/transaction; re-check guards (and that
    // the chat hasn't switched) on the microtask. _resolveSceneGuestCards also
    // self-guards on the token, so a stale resolve can't write the wrong chat.
    final token = _currentSessionId;
    scheduleMicrotask(() {
      if (_sceneChanged(token) || _sceneGuest.busy || _sceneGuest.ids.isEmpty) {
        return;
      }
      _resolveSceneGuestCards();
    });
  }

  /// Wired by main.dart so that group member loading works for all call sites
  /// (creation, home taps, fork, etc.) without every caller having to pass the repo.
  void setGroupChatRepository(GroupChatRepository repo) {
    _groupChatRepository = repo;
  }

  /// Set the LLMProvider after construction (to break circular dependency in provider tree).
  void setLLMProvider(LLMProvider provider) {
    // Idempotent like [setCharacterRepository]: the ProxyProvider `update` that
    // owns this wiring re-runs on every Kobold log line, so an unguarded
    // addListener would append one callback per frame, forever.
    if (identical(_llmProvider, provider)) return;
    _llmProvider?.removeListener(_onBackendIdentity);
    _llmProvider = provider;
    // Backend switches and local-engine ready transitions flow through the
    // provider — retest tool support when the identity changes and is ready.
    provider.addListener(_onBackendIdentity);
  }

  /// Set the TtsService after construction (for TTS-aware auto-play delay).
  void setTtsService(TtsService service) {
    _ttsService = service;
  }

  /// Test-only: arm Porch Night force-ack for [diaryCharacterId] so Continue
  /// strip coverage can prove `porch_night` is cleared (audit P0.3).
  @visibleForTesting
  void debugArmPorchNightForTest({
    required String diaryCharacterId,
    required String injectionText,
  }) {
    _porchMemoryImport.ackState.arm(
      diaryCharacterId: diaryCharacterId,
      injectionText: injectionText,
      journalCardIds: const [],
    );
  }

  /// Set the MemoryService after construction (for RAG memory retrieval).
  void setMemoryService(MemoryService service) {
    _memoryService = service;
  }

  /// Body for the class-pinned [lastRagReceipt] (fakes override the class
  /// member; see chat_service.dart). Reads the PUBLIC [messages] getter so
  /// a FakeChatService that implements ChatService from outside this library
  /// is never probed for `_messages`.
  Map<String, dynamic>? get _lastRagReceiptImpl {
    for (final m in messages.reversed) {
      if (m.isUser || m.sender == 'System') continue;
      return (m.activeMetadata?['rag_receipt'] as Map?)
          ?.cast<String, dynamic>();
    }
    return null;
  }

  /// Set the ImageGenService after construction (for background Scene Guest
  /// portraits). Optional — when absent or unconfigured, guests just keep their
  /// initials avatar.
  void setImageGenService(ImageGenService service) {
    _imageGenService = service;
  }

  /// Set the ExpressionClassifierService after construction (for ONNX emotion classification).
  void setExpressionClassifierService(ExpressionClassifierService service) =>
      _expressionService.setExpressionClassifierService(service);

  /// Returns a stable ID string for a character card.
  /// Delegates to the canonical stable ID for group contexts.
  /// See [StableGroupId.stableGroupId] in lib/utils/character_id.dart
  String _getCharacterIdFromCard(CharacterCard card) => card.stableGroupId;

  String _getCharacterId() {
    if (_activeGroup != null) {
      return 'group_${_activeGroup!.id}';
    }
    if (_activeCharacter == null) return "unknown";
    return _getCharacterIdFromCard(_activeCharacter!);
  }

  /// Helper used when constructing messages.
  String? _getCharacterIdForCard(CharacterCard card) {
    return _getCharacterIdFromCard(card);
  }

  /// Safely parse a JSON string into a mutable `Map<String, String>`.
  /// Returns an empty map if [json] is null, empty, or invalid.
  Map<String, String> _tryParseJsonMap(String? json) {
    if (json == null || json.isEmpty || json == '{}') return {};
    try {
      final decoded = jsonDecode(json);
      if (decoded is Map) {
        return decoded.map(
          (k, v) => MapEntry(k.toString(), v?.toString() ?? ''),
        );
      }
    } catch (_) {}
    return {};
  }

  // ── Round-4b forwarder bodies ──────────────────────────────────────────
  // These back one-line `class` forwarders left in chat_service.dart because
  // FakeChatService (test/golden/support/fakes.dart) — or a fake that extends
  // it, e.g. _RecordingChatService in chat_insert_image_test.dart —
  // `@override`s them, and extension members are statically dispatched and
  // cannot be overridden via `implements`/`extends`. Verbatim bodies, moved
  // as part of the round-4b god-file shrink (docs/design/god-file-elimination.md).

  /// Append an already-saved generated image to the conversation as a
  /// character message (empty text; the bubble renders the image from
  /// metadata). Shared by the /image slash command, the Image Studio's
  /// "Send to chat", and the web insert-image endpoint.
  Future<void> _addGeneratedImageMessageImpl(
    String path,
    String prompt, {
    String? senderName,
    String? characterId,
  }) async {
    if (_activeCharacter == null && _activeGroup == null) return;
    _messages.add(
      ChatMessage(
        text: '',
        sender: senderName ?? _activeCharacter?.name ?? 'Narrator',
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

  /// Everything [ChatService.dispose] does except the mandatory
  /// `super.dispose()` call, which only the class body can make.
  void _disposeCleanupImpl() {
    _disposed = true;
    _cancelIdleTimer();
    _cancelStreamNotifyThrottle();
    _sceneGuest.statusClearTimer?.cancel();
    _characterRepository?.removeListener(_onCharacterLibrary);
    _storageService.removeListener(_onBackendIdentity);
    _llmProvider?.removeListener(_onBackendIdentity);
    _toolProbe.removeListener(notifyListeners);
  }

  /// Everything the [ChatService] constructor does. Called as the
  /// constructor's single statement (round-4b shrink).
  ///
  /// `notifyListeners` is a plain instance method, so its tear-off IS
  /// canonicalized and stays `==`-equal to the one [_disposeCleanupImpl]
  /// passes to `removeListener`. [_onBackendIdentityMaybeChanged] is NOT —
  /// it is an extension member, so it is registered through the Expando-backed
  /// [_onBackendIdentity] instead (see the note at the top of this file). The
  /// comment that used to sit here claimed both were canonicalized; the
  /// removals it blessed were silently doing nothing.
  void _initImpl() {
    // Probe verdicts land from background passes and the manual test alike —
    // rebroadcast so the sidebar's tool-calling pill repaints live.
    _toolProbe.addListener(notifyListeners);
    // Local model path / remote model name changes alter the eval identity —
    // retest tool support for the new model (sidebar pill contract).
    _storageService.addListener(_onBackendIdentity);
    _onTodayAbandoned = (held) {
      // Sour mood first — deactivate is DB I/O and must not gate the
      // feeling. Day-ate already journals then deactivates; abandon
      // used to wait on the isolate and leave emotion empty under load.
      unawaited(_journalResolvedToday(held, fate: PlannerTodayFate.abandoned));
      unawaited(_deactivateTodayObjective());
    };
  }
}
