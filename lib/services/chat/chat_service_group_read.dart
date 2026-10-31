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

/// Per-group-character realism / needs **read** accessors consumed by the UI
/// (sidebar member cards, group member grid, roster). Pure reads over the
/// `_groupRealism` map plus the one mutating reset helper; no orchestration.
///
/// Extracted verbatim from `chat_service.dart` (zero behaviour change) to shrink
/// the god file toward the 500-line cap. As a `part of` the same library, this
/// extension reaches the private `_groupRealism` map, `_getCharacterIdFromCard`,
/// `_activeGroup`, and `isGroupRealismActive` exactly as the in-class methods did.
extension ChatServiceGroupRead on ChatService {
  /// Empty stance fails toward here. Group card glance.
  String _spatialStanceForGroupCharacterImpl(CharacterCard character) {
    final id = _getCharacterIdFromCard(character);
    return _groupRealism[id]?.spatialStance ?? '';
  }

  /// Glance judge for a group card. Null = unknown (keyword fallback).
  bool? _withUserForGroupCharacterImpl(CharacterCard character) {
    final id = _getCharacterIdFromCard(character);
    return _groupRealism[id]?.withUser;
  }

  /// Returns the current emotion label (e.g. "joy", "sadness", "affection") for
  /// the given character when in a realism-enabled group chat. Returns null otherwise.
  String? getEmotionForGroupCharacter(CharacterCard character) {
    if (!isGroupRealismActive) return null;
    final id = _getCharacterIdFromCard(character);
    final raw = _groupRealism[id]?.emotion;
    return (raw != null && raw.isNotEmpty) ? raw : null;
  }

  /// Returns a snapshot of all realism data for a specific character in the
  /// current group (when `isGroupRealismActive` is true). Includes keys like:
  /// 'emotion', 'emotionIntensity', 'affection', 'trust', 'needs', 'fixation',
  /// and (when group size ≤ 4) the hidden 'relationships' map toward other members.
  /// This is primarily for debugging/advanced use; the UI never exposes inter-char data.
  /// Returns null if not in an active realism group or no data for that char.
  Map<String, dynamic>? getRealismStateForGroupCharacter(
    CharacterCard character,
  ) {
    if (!isGroupRealismActive) return null;
    final id = _getCharacterIdFromCard(character);
    final data = _groupRealism[id];
    return (data != null && data.isNotEmpty)
        ? Map.unmodifiable(data.toJson())
        : null;
  }

  // ── Convenient per-character realism accessors for the UI ───────────────

  /// Returns the full needs vector for the given group character.
  /// Empty map if not in group realism mode or no data.
  /// Only official needs keys are returned (legacy bad keys such as 'arousal'/'libido'
  /// from older group data are silently filtered).
  Map<String, int> getNeedsForGroupCharacter(CharacterCard character) {
    if (!isGroupRealismActive) return const {};
    return _groupStore.needsOf(_getCharacterIdFromCard(character));
  }

  int getAffectionForGroupCharacter(CharacterCard character) {
    if (!isGroupRealismActive) return 0;
    final id = _getCharacterIdFromCard(character);
    return _groupRealism[id]?.affection ?? 0;
  }

  /// Long-term bond for one group member.
  ///
  /// This accessor was simply missing, and both clients worked around its
  /// absence by showing something else: the desktop member card passed the
  /// SHORT-term score to both bond rows, and the web facade hard-coded 0 under
  /// a comment claiming long-term is not tracked per member. It is — the
  /// per-speaker load/save pair moves `longTermScore` in and out of the group
  /// blob on every turn, and it grows on its own cadence, so it genuinely
  /// diverges from short-term.
  ///
  /// Falls back to short-term when the key is absent, matching what
  /// [RelationshipService.loadRelationshipScalarsForSpeaker] does when it seeds
  /// a member who predates the key.
  int getLongTermForGroupCharacter(CharacterCard character) {
    if (!isGroupRealismActive) return 0;
    final id = _getCharacterIdFromCard(character);
    final entry = _groupRealism[id];
    return entry?.longTermScore ?? entry?.affection ?? 0;
  }

  int getTrustForGroupCharacter(CharacterCard character) {
    if (!isGroupRealismActive) return 0;
    final id = _getCharacterIdFromCard(character);
    return _groupRealism[id]?.trust ?? 0;
  }

  String? getFixationForGroupCharacter(CharacterCard character) {
    if (!isGroupRealismActive) return null;
    final id = _getCharacterIdFromCard(character);
    final raw = _groupRealism[id]?.fixation;
    return (raw != null && raw.isNotEmpty) ? raw : null;
  }

  int getArousalForGroupCharacter(CharacterCard character) {
    if (!isGroupRealismActive) return 0;
    final id = _getCharacterIdFromCard(character);
    return _groupRealism[id]?.arousal ?? 0;
  }

  /// The member's own recovery in the 1:1 chip's words, with its minutes and
  /// whether it is a soft window: off their own entry, never the live
  /// scalars, which hold whoever was loaded last. Empty while none runs and
  /// while Afterglow does not run for them.
  ({String chip, bool soft, int minutes}) getRefractoryForGroupCharacter(
    CharacterCard character,
  ) {
    if (!isGroupRealismActive || !afterglowRunsFor(character)) {
      return (chip: '', soft: false, minutes: 0);
    }
    final body =
        _groupRealism[_getCharacterIdFromCard(character)]?.refractory ??
        Refractory.none;
    final words = describeRefractory(
      body.minutes,
      clockRunning: _clockRunning,
      soft: body.soft,
      peaks: body.peaksLastHour,
    );
    return (chip: words.chip, soft: body.soft, minutes: body.minutes);
  }

  /// Porch Life's Expressions switch: the phone shows a mood picture only
  /// while it is on, as the desktop sidebar does.
  bool get expressionsEnabled =>
      _storageService.expressionSettings.expressionEnabled;

  /// The face label for [character]. In 1:1, the chat's label. In a group,
  /// the member's own mood: the live label (ONNX) is theirs only when it was
  /// classified from a reply they wrote, never a System row or a streaming
  /// placeholder.
  String? expressionLabelFor(CharacterCard character) {
    if (_activeGroup == null) return currentExpressionLabel;
    if (_storageService.expressionSettings.expressionClassificationMode ==
        'onnx') {
      // Read first: it keeps the classifier following new replies.
      final live = currentExpressionLabel;
      final source = _expressionService.onnxLabelSource;
      final speaker = source == null || source.sender == 'System'
          ? null
          : resolveGroupSpeakerForMessage(
              _groupCharacters,
              source,
              logOnMiss: false,
            );
      if (speaker != null &&
          _getCharacterIdFromCard(speaker) ==
              _getCharacterIdFromCard(character)) {
        return live;
      }
    }
    return _expressionService.labelForEmotion(
      getEmotionForGroupCharacter(character) ?? '',
    );
  }

  String? getEmotionIntensityForGroupCharacter(CharacterCard character) {
    if (!isGroupRealismActive) return null;
    final id = _getCharacterIdFromCard(character);
    final raw = _groupRealism[id]?.emotionIntensity;
    return (raw != null && raw.isNotEmpty) ? raw : null;
  }

  /// The member's whole mood (label, intensity, cause, hold) for the member
  /// card and the phone, or null outside active group realism.
  MoodState? getMoodForGroupCharacter(CharacterCard character) {
    if (!isGroupRealismActive) return null;
    return _mood.memberState(_getCharacterIdFromCard(character));
  }

  /// Returns the remaining lifespan (in turns) for the current fixation of the
  /// given group character, if any. Returns null if not in active group realism
  /// or no fixation data.
  int? getFixationLifespanForGroupCharacter(CharacterCard character) {
    if (!isGroupRealismActive) return null;
    final id = _getCharacterIdFromCard(character);
    return _groupRealism[id]?.fixationLifespan;
  }

  /// Returns the top N most urgent needs (lowest value first) for the character,
  /// as a list of (needName, value) pairs.
  List<(String, int)> getTopUrgentNeedsForGroupCharacter(
    CharacterCard character, {
    int count = 2,
  }) {
    final needs = visibleNeeds(
      getNeedsForGroupCharacter(character),
      character.frontPorchExtensions?.needsOff ?? const [],
    );
    if (needs.isEmpty) return const [];

    final sorted = needs.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value)); // lowest = most urgent

    return sorted.take(count).map((e) => (e.key, e.value)).toList();
  }

  /// Clears the per-character realism state (emotion, bond/affection, trust,
  /// arousal, fixation, needs vector, and any hidden inter-character relationships)
  /// for the specified character in the current group chat session.
  /// Safe to call even if no prior state existed for the character.
  void resetRealismForGroupCharacter(CharacterCard character) {
    if (_activeGroup == null) return;
    final id = _getCharacterIdFromCard(character);
    if (_groupRealism.containsKey(id)) {
      _groupRealism.remove(
        id,
      ); // also clears hidden 'relationships' toward other group members
      // (old checkpoint call removed in v30)
      debugPrint('[GroupRealism] Reset per-character state for $id');
      notifyListeners();
    }
  }

  // ── Clean delegation layer (GroupTurnManager is the real owner); moved
  // verbatim from the god file's field block, zero behaviour change ──
  GroupChat? get _activeGroup => _session.groupManager?.activeGroup;
  List<CharacterCard> get _groupCharacters =>
      _session.groupManager?.characters ?? const <CharacterCard>[];
  bool get _observerMode => _session.groupManager?.observerMode ?? false;
  set _observerMode(bool value) {
    _session.groupManager?.setObserverMode(value);
  }

  /// {{user}} is off stage: a group in Director Mode. Nothing scores the
  /// director's notes, so bond, trust and feelings toward the user hold
  /// still. Every per-speaker system keeps running as in any group turn:
  /// Needs, the clock and weather, and the cast's feelings for each other.
  bool get _directing => _activeGroup != null && _observerMode;

  /// A new chat starts from the group's own Director Mode default; the live
  /// switch is per chat (saved in the session blob).
  void _resetDirectorModeToDefault() {
    _session.groupManager?.setObserverMode(_activeGroup?.directorMode ?? false);
    _directorScene.hydrate(null); // a fresh chat starts with no directions
    _autoChatBudget.clear();
  }

  bool get _autoPlayActive => _session.groupManager?.autoPlayActive ?? false;
  set _autoPlayActive(bool value) {
    if (value) {
      _session.groupManager?.startAutoPlay();
    } else {
      _session.groupManager?.stopAutoPlay();
    }
  }

  double get directorDelaySec =>
      _session.groupManager?.directorDelaySec ?? 15.0;
  set directorDelaySec(double value) {
    if (_session.groupManager != null) {
      _session.groupManager!.directorDelaySec = value;
    }
  }

  /// The saved auto-chat delay both clients show (desktop Director panel,
  /// web director strip).
  double get savedDirectorDelay => _storageService.ttsSettings.directorDelay;

  /// Saves the auto-chat delay and applies it to the running scene.
  Future<void> setSavedDirectorDelay(double seconds) async {
    await _storageService.ttsSettings.setDirectorDelay(seconds);
    directorDelaySec = _storageService.ttsSettings.directorDelay;
    notifyListeners();
  }

  bool get autoPlayActive => _session.groupManager?.autoPlayActive ?? false;

  /// The character who will speak next in group mode: the rotation head,
  /// moved past members who are Away or At work exactly as the pick does.
  /// Null for random turn order (decided at pick time).
  CharacterCard? get nextCharacter => _upcomingGroupSpeaker;

  /// True for group chats where the Realism Engine is enabled, Director Mode
  /// included: the per-character state still shows (held still while the
  /// user is off stage) and the cast's feelings for each other keep moving.
  /// Used by the group sidebar to decide whether to show per-character
  /// emotion / needs indicators.
  bool get isGroupRealismActive => _realismEnabled && isGroupMode;

  /// Phase 3: Hard cap for inter-character relationship tracking.
  /// Hidden inter-character dynamics (seeding, decay, injection, updates)
  /// run only when the group has 2–4 **full** members. Soft (lite) guests
  /// do not count and never join the graph.
  ///
  /// When the group has 5+ full members:
  /// - Inter-character 'relationships' maps remain empty / are ignored.
  /// - Full members still receive per-speaker realism evaluations for
  ///   their feelings **toward the user** (visible bars continue to work).
  bool get _shouldTrackInterCharacterRelationships {
    if (_activeGroup == null) return false;
    return shouldTrackInterCharacterAmong(_groupCharacters);
  }

  /// Set observer mode on/off.
  void setObserverMode(bool value) {
    _observerMode = value;
    if (!value) {
      _autoPlayActive = false;
    }
    if (_sceneGuest.exitUndoUserStep) _clearExitUndo(); // flip beats undo
    if (_activeGroup != null) unawaited(_saveChat()); // saved per chat
    notifyListeners();
  }

  /// Start auto-play: characters keep chatting automatically. A paused run
  /// resumes with the turns it had left.
  void startAutoPlay() {
    if (_activeGroup == null || !_observerMode) return;
    if (!_autoChatBudget.resume()) {
      _autoChatBudget.arm(_storageService.ttsSettings.directorTurnBudget);
    }
    _autoPlayActive = true;
    notifyListeners();
    _autoPlayNext();
  }

  /// Pause auto-play: a reply already running finishes, and the run keeps
  /// its turns for [startAutoPlay] to resume.
  void pauseAutoPlay() {
    if (!_autoPlayActive) return;
    _autoPlayActive = false;
    _autoChatBudget.pause();
    notifyListeners();
  }

  /// Stop auto-play and end the run.
  void stopAutoPlay() {
    _autoPlayActive = false;
    _autoChatBudget.clear();
    notifyListeners();
  }

  /// Auto-chat is paused with turns left to resume.
  bool get autoPlayPaused =>
      _directing && !_autoPlayActive && _autoChatBudget.paused;

  /// Internal: trigger the next auto-play response.
  Future<void> _autoPlayNext() async {
    if (!_autoPlayActive || !_observerMode || _activeGroup == null) return;
    // Both auto-play schedulers (generation.dart and _waitForTtsThenContinue)
    // arm their delay AFTER the awaited post-gen section has already finished,
    // so this is clear by the time they fire; no re-arm machinery is needed.
    if (_isTurnBusy) return; // wait for the current turn to finish settling

    // Each spoken reply post-decides the clock; the next speaker is
    // announced at that time (bucket brigade). No pre-tick.
    _autoChatBudget.turnRunning = true;
    try {
      await _generateResponse(GenerationMode.normal);
    } finally {
      _autoChatBudget.turnRunning = false;
    }
  }

  /// Turns left in this auto-chat run, or null when it has no limit or no
  /// run is going or paused.
  int? get autoChatTurnsLeft =>
      _autoPlayActive || autoPlayPaused ? _autoChatBudget.remaining : null;

  /// The saved auto-chat turn budget (0 = no limit).
  int get savedDirectorTurnBudget =>
      _storageService.ttsSettings.directorTurnBudget;

  Future<void> setSavedDirectorTurnBudget(int turns) async {
    await _storageService.ttsSettings.setDirectorTurnBudget(turns);
    notifyListeners();
  }

  /// After an auto-chat turn: pauses when [reply] speaks to the absent user,
  /// or when the run's budget is spent. True when it paused.
  bool _autoChatPausesAfter(ChatMessage reply) {
    final String why;
    if (replyAddressesUser(
      reply.displayText,
      _userPersonaService.persona.name,
    )) {
      why = 'Auto-chat paused: ${reply.sender} spoke to you.';
    } else if (_autoChatBudget.spend()) {
      why = 'Auto-chat paused: the run of turns is done.';
    } else {
      return false;
    }
    _autoPlayActive = false;
    // Spoken to, the run can resume; spent, there is nothing left.
    _autoChatBudget.pause();
    _setGuestStatus(why);
    notifyListeners();
    return true;
  }
}
