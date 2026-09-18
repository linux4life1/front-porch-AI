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

/// 1:1→group fork. Live add / remove / create-member live in
/// chat_service_group_members.dart (same library).
extension ChatServiceGroupMembership on ChatService {
  /// Fork the current 1:1 chat into a new group chat, copying all messages.
  /// The original 1:1 session remains untouched.
  Future<GroupChat?> forkToGroupChat(
    List<CharacterCard> additionalCharacters,
    GroupChatRepository groupRepo, {
    String? groupName,
    String? scenario,
    TurnOrder turnOrder = TurnOrder.roundRobin,
    Map<String, ({String text, bool creative})> entrances = const {},
  }) async {
    if (_isTurnBusy) return null;
    if (_activeCharacter == null || _characterRepository == null) return null;
    if (_messages.isEmpty) return null;
    // 1:1 → group only. Forking from an existing group would rebuild a group
    // from just the active speaker (dropping the other members), so refuse it —
    // use "Add Character to Group" for an existing group instead.
    if (_activeGroup != null) return null;

    final originalCharId = _getCharacterIdFromCard(_activeCharacter!);

    // Capture the host's full live 1:1 state BEFORE the fork switches into group
    // mode (setActiveGroup, below, resets the working registers). It is carried
    // onto the host member after the switch so the converted group keeps the
    // host's realism, the enable-flags, and author note intact — making
    // 1:1->group lossless. Growth rings are session-scoped DB rows and carry
    // via _growthStore.carryOwnerGrowth in the fork carry (no capture needed).
    // Present lite guests carried no realism (by design) and become full
    // members seeded with neutral defaults on first entry.
    final String hostName = _activeCharacter!.name;
    final String? hostSessionId =
        _currentSessionId; // 1:1 session (objectives source)
    // Capture UNCONDITIONALLY: the enable-flags, author note, and objectives
    // must carry even when realism is OFF (a user can have quests or an author
    // note with realism disabled). Only the realism snapshot itself is
    // realism-gated.
    final Map<String, dynamic> hostState = <String, dynamic>{
      'realismOn': _realismEnabled,
      if (_realismEnabled) ..._captureRealismState(),
      'needsSimEnabled': _needsSimEnabled,
      'nsfwCooldownEnabled': _nsfwService.nsfwCooldownEnabled,
      'passageOfTimeEnabled': _timeService.passageOfTimeEnabled,
      'chaosModeEnabled': _chaosModeService.chaosModeEnabled,
      'chaosPressure': _chaosModeService.chaosPressure,
      'authorNote': _authorNote,
      'authorNoteStrength': _authorNoteStrength,
      // Live kit, regardless of realism — collapse copies this back onto
      // `_pockets`; the fork must plant it on the host member the same way.
      if (_pockets != null) 'pockets': _pockets!.toJson(),
    };

    // D5 — one instance per library character per chat. Drop any arrival that
    // repeats the host or another arrival (matched by stable identity). The
    // in-app callers (joinFull / promoteSceneToFull) already dedup, but the web
    // /api/groups/fork path forwards raw character_ids — this is the single
    // chokepoint that keeps every conversion path duplicate-free.
    final seenMemberIds = <String>{originalCharId};
    final arrivals = <CharacterCard>[
      for (final c in additionalCharacters)
        if (seenMemberIds.add(_getCharacterIdFromCard(c))) c,
    ];

    // Build a default group name
    final name = groupName?.isNotEmpty == true
        ? groupName!
        : [_activeCharacter!.name, ...arrivals.map((c) => c.name)].join(' & ');

    // Create the group
    final group = GroupChat(
      id: 'group_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      // characterIds removed (decoupled). Members handled via group_members + private storage.
      turnOrder: turnOrder,
      scenario: scenario ?? '',
      // v31 columns — new groups start with clean defaults.
      // baselineRealismState remains '{}' until the caller (or UI) seeds explicit values.
      baselineRealismState: '{}',
    );
    await groupRepo.save(group);

    // Rotation order rule for the new group: original participant(s) first,
    // then arrivals WITH an entrance (in the order added), then arrivals
    // WITHOUT an entrance at the end. Member insertion order *is* the
    // round-robin order (the members table has no explicit sort column), so we
    // insert in exactly that order.
    bool hasEntrance(CharacterCard c) =>
        (entrances[_getCharacterIdFromCard(c)]?.text.trim().isNotEmpty) ??
        false;
    final entranceArrivals = arrivals.where(hasEntrance).toList();
    final silentArrivals = arrivals.where((c) => !hasEntrance(c)).toList();
    final orderedArrivals = [...entranceArrivals, ...silentArrivals];

    // Decoupled model: ensure members exist for the original 1:1 character
    // and every additional character. Without this, the group loads empty
    // (setActiveGroup / GroupTurnManager will have no one to speak).
    // Ported from the fix originally contributed in PR #44 by @MisterLotto.
    await _createGroupMember(group.id, _activeCharacter!);
    for (final c in orderedArrivals) {
      await _createGroupMember(group.id, c);
    }

    // Create a new session for the group and copy all messages
    final newSessionId = DateTime.now().millisecondsSinceEpoch.toString();
    final copiedMessages = <MessagesCompanion>[];
    for (int i = 0; i < _messages.length; i++) {
      final m = _messages[i];
      // Back-fill characterId on AI messages (null in 1:1 mode)
      String? charId = m.characterId;
      if (!m.isUser && charId == null) {
        charId = originalCharId;
      }
      copiedMessages.add(
        MessagesCompanion(
          sessionId: drift.Value(newSessionId),
          position: drift.Value(i),
          sender: drift.Value(m.sender),
          isUser: drift.Value(m.isUser),
          characterId: drift.Value(charId),
          swipes: drift.Value(jsonEncode(m.swipes)),
          swipeIndex: drift.Value(m.swipeIndex),
          swipeDurations: drift.Value(jsonEncode(m.swipeDurations)),
          // Metadata is NOT optional bookkeeping: a generated image is an
          // empty-text message whose only content is metadata['image_path'],
          // and realism_state / needs_pre_turn_vector / pockets_before are the
          // baseline every later regen, swipe and delete rewinds to. Omitting
          // these two columns inserted NULLs, and setActiveGroup below then
          // re-hydrates _messages from exactly these rows — so the converted
          // group lost every image and every stamp on the whole transcript.
          // Encoded identically to _replaceSessionMessages (the other copy
          // path) so both write the same shape.
          metadata: drift.Value(
            m.metadata != null ? jsonEncode(m.metadata) : null,
          ),
          swipeMetadata: drift.Value(
            m.swipeMetadata.any((e) => e != null)
                ? jsonEncode(m.swipeMetadata)
                : null,
          ),
        ),
      );
    }

    // Insert the new session
    await _db.upsertSession(
      SessionsCompanion.insert(
        id: newSessionId,
        groupId: drift.Value(group.id),
        name: drift.Value(_sessionName),
        description: drift.Value(_sessionDescription),
        authorNote: drift.Value(_authorNote),
        authorNoteDepth: drift.Value(_authorNoteStrength),
        summary: drift.Value(_summary.isEmpty ? null : _summary),
        summaryLastIndex: drift.Value(
          _summaryLastIndex > 0 ? _summaryLastIndex : null,
        ),
        parentSession: drift.Value(_currentSessionId),
        forkIndex: drift.Value(_messages.length - 1),
        trustLevel: drift.Value(_relationshipService.trustLevel),
        activeFixation: drift.Value(_relationshipService.activeFixation),
        fixationLifespan: drift.Value(_relationshipService.fixationLifespan),
        spatialStance: drift.Value(_relationshipService.spatialStance),
        startDayOfWeek: drift.Value(_timeService.startDayOfWeekAnchor),
        storyClock: drift.Value(_timeService.storyClockIso),
        storyStartDate: drift.Value(_timeService.storyStartDateIso),
        createdAt: drift.Value(DateTime.now()),
        updatedAt: drift.Value(DateTime.now()),
      ),
    );
    if (copiedMessages.isNotEmpty) {
      await _db.insertMessages(copiedMessages);
    }

    debugPrint(
      '[ChatService] \u{1F500} Forked 1:1 chat to group "${group.name}" '
      '(${_messages.length} messages copied)',
    );

    // Switch to the new group (this loads the session we just created)
    await setActiveGroup(group, groupRepo: groupRepo);

    // Carry the captured 1:1 host realism into the host member's per-character
    // store now that group mode is active (the group-scoped writes are gated on
    // _activeGroup != null). Without this the converted group opens realism-off
    // with the host's relationship/needs reset to defaults (the /promote bug).
    await _carryHostStateIntoForkedGroup(
      hostName,
      originalCharId,
      hostSessionId,
      hostState,
    );

    // Run any custom entrances WITHOUT blocking the caller, so the wizard can
    // navigate to the group immediately and the entrance messages stream into
    // the now-visible chat instead of waiting behind a spinner. Entrants cut in
    // one-by-one in the order they were added.
    if (entranceArrivals.isNotEmpty) {
      _entrancesInFlight = true; // block user turns until the sequence finishes
      unawaited(() async {
        try {
          for (final addCard in entranceArrivals) {
            final entry = entrances[_getCharacterIdFromCard(addCard)]!;
            final text = entry.text.trim();

            // Members are copied under fresh UUIDs on fork, so resolve by name
            // (stable) and use the resolved member's id — else the entrance
            // attributes to the wrong member.
            final resolved = _groupCharacters.firstWhere(
              (c) => c.name == addCard.name,
              orElse: () => addCard,
            );
            final resolvedId = _getCharacterIdFromCard(resolved);

            if (entry.creative) {
              // Hidden one-shot directive; the member writes their own entrance.
              // Shared with live /join --full + sidebar adds via the helper.
              final ok = await _generateMemberEntrance(resolved, text);
              if (!ok) {
                // Surface the failure so the user isn't left wondering why the
                // group loaded with no entrance.
                _messages.add(
                  ChatMessage(
                    text:
                        '⚠ ${resolved.name}\'s entrance could not be generated.',
                    sender: 'System',
                    isUser: false,
                  ),
                );
                await _saveChat();
                notifyListeners();
              }
            } else {
              // Opening line: the entrance IS the user's text, verbatim — it
              // becomes the character's message as-is, no LLM generation.
              _messages.add(
                ChatMessage(
                  text: text,
                  sender: resolved.name,
                  isUser: false,
                  characterId: resolvedId,
                ),
              );
              await _saveChat();
              notifyListeners();
            }
          }
        } catch (e) {
          debugPrint('[Fork:Entrance] sequence failed: $e');
        } finally {
          // The entrances are one-off cut-ins. In round-robin the next turn goes
          // to whoever falls right after the LAST entrant in the rotation order
          // (originals, then entrance arrivals, then silent arrivals) — i.e. the
          // first silent arrival, or wrapping back to the original if there are
          // none. advanceAfterRegeneration parks the pointer at last-entrant + 1.
          // Done in `finally` so a generation hiccup can't leave the rotation
          // stuck on the entrant. Random needs no fix-up.
          final lastEntrantName = entranceArrivals.last.name;
          if (turnOrder == TurnOrder.roundRobin &&
              _groupCharacters.any((c) => c.name == lastEntrantName)) {
            final lastEntrant = _groupCharacters.firstWhere(
              (c) => c.name == lastEntrantName,
            );
            _groupManager?.advanceAfterRegeneration(lastEntrant);
          }
          _entrancesInFlight = false; // user turns allowed again
          // The turn pointer changed after generation finished. GroupTurnManager
          // notifies its own listeners, but the chat UI watches ChatService, so
          // we must propagate here — otherwise the next-speaker indicator keeps
          // showing the (stale) entrant even though the pointer is correct.
          notifyListeners();
        }
      }());
    }

    return group;
  }
}
