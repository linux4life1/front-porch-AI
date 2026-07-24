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

/// Group membership lifecycle: forking a 1:1 into a group, creating group member
/// rows, and adding/removing members live. Extracted verbatim from
/// `chat_service.dart` (zero behaviour change) to shrink the god file. As
/// `part of` the same library, these reach the private group repo / db / manager
/// / entrance state exactly as the in-class methods did.
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
    if (_isGenerating) return null;
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
    final String? hostSessionId = _currentSessionId; // 1:1 session (objectives source)
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
        : [
            _activeCharacter!.name,
            ...arrivals.map((c) => c.name),
          ].join(' & ');

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

  /// Create a group member (decoupled model): copy the character's avatar into
  /// the group's private storage and insert a group_members row.
  /// Shared by [addCharacterToGroup] (live add) and [forkToGroupChat] (initial
  /// membership when forking a 1:1 chat into a group).
  ///
  /// This is the core of the fix originally contributed in PR #44 by @MisterLotto.
  Future<void> _createGroupMember(
    String groupId,
    CharacterCard character,
  ) async {
    final mid = const Uuid().v4();
    final avDir = Directory(
      path.join(_storageService.groupsDir.path, groupId, 'avatars'),
    );
    await avDir.create(recursive: true);

    await _characterRepository!.duplicateCharacter(
      character,
      targetDirOverride: avDir.path,
      forcedBasename: mid,
      skipLibraryInsert: true,
    );

    final db = await AppDatabase.instance();
    await db.insertGroupMember(
      GroupMembersCompanion(
        id: drift.Value(mid),
        groupId: drift.Value(groupId),
        name: drift.Value(character.name),
        description: drift.Value(character.description),
        personality: drift.Value(character.personality),
        scenario: drift.Value(character.scenario),
        firstMessage: drift.Value(character.firstMessage),
        mesExample: drift.Value(character.mesExample),
        systemPrompt: drift.Value(character.systemPrompt),
        postHistoryInstructions: drift.Value(character.postHistoryInstructions),
        alternateGreetings: drift.Value(
          jsonEncode(character.alternateGreetings),
        ),
        tags: drift.Value(jsonEncode(character.tags)),
        avatarFilename: drift.Value('$mid.png'),
        ttsVoice: drift.Value(character.ttsVoice),
        lorebook: drift.Value(
          character.lorebook != null
              ? jsonEncode(character.lorebook!.toJson())
              : null,
        ),
        worldNames: drift.Value(jsonEncode(character.worldNames)),
        frontPorchExtensions: drift.Value(
          character.frontPorchExtensions != null
              ? jsonEncode(character.frontPorchExtensions!.toJson())
              : null,
        ),
        rawExtensions: drift.Value(
          character.rawExtensions != null
              ? jsonEncode(character.rawExtensions!)
              : null,
        ),
        // Provenance: stamp which library character this member was copied from
        // so a chat can later collapse back to a 1:1 with the original (no orphans).
        memberState: drift.Value(
          GroupMember.encodeProvenance(
            originStableId: character.stableGroupId,
            originLibraryDbId: character.dbId,
          ),
        ),
      ),
    );
  }

  /// Add a character to the currently active group chat.
  Future<bool> addCharacterToGroup(
    CharacterCard character,
    GroupChatRepository groupRepo,
  ) async {
    if (_activeGroup == null || _characterRepository == null) return false;
    if (_isGenerating) return false;

    // D5 — one instance per library character per chat. Refuse to add a
    // character already present (the host or an existing member), matched by
    // stable LIBRARY identity (Phase 0 originStableId), with a name fallback for
    // legacy members that predate provenance stamping.
    final incomingId = _getCharacterIdFromCard(character);
    final incomingName = character.name.trim().toLowerCase();
    final existingMembers = await groupRepo.getMembersForGroup(_activeGroup!.id);
    final alreadyPresent = existingMembers.any((m) {
      final origin = m.originStableId;
      if (origin != null && origin == incomingId) return true;
      return m.name.trim().toLowerCase() == incomingName;
    });
    if (alreadyPresent) {
      _setGuestStatus(
        '⚠ ${character.name} is already in this chat.',
        isError: true,
      );
      return false;
    }

    // Decoupled model: copy the character's avatar into the group's private
    // storage and insert a group_members row. Shared with forkToGroupChat
    // via _createGroupMember (ported from the fix originally contributed in
    // PR #44 by @MisterLotto).
    await _createGroupMember(_activeGroup!.id, character);

    await groupRepo.save(_activeGroup!);

    // Re-resolve from private members (decoupled).
    final resolved = <CharacterCard>[];
    final memberRows = await groupRepo.getMembersForGroup(_activeGroup!.id);
    for (final m in memberRows) {
      if (m.avatarFilename != null) {
        final p = path.join(
          _storageService.groupsDir.path,
          _activeGroup!.id,
          'avatars',
          m.avatarFilename!,
        );
        if (await File(p).exists()) {
          resolved.add(m.toCharacterCard(resolvedImagePath: p));
        }
      }
    }
    _inheritGroupExpressionAvatars(resolved);
    _groupManager?.refreshCharacters(resolved);

    debugPrint(
      '[ChatService] \u{2795} Added ${character.name} to group ${_activeGroup!.name}',
    );
    notifyListeners();
    return true;
  }

  /// Re-resolve the group's live roster from the member table and push it to the
  /// turn manager, returning the resolved cards. Members whose private avatar is
  /// missing are skipped (same rule as the initial group load). Shared by member
  /// removal (after the delete) and the deferred-exit undo (after a soft-remove,
  /// where the row still exists so the member comes straight back).
  Future<List<CharacterCard>> _reloadGroupRoster() async {
    final repo = _groupChatRepository;
    if (_activeGroup == null || repo == null) return const <CharacterCard>[];
    final rows = await repo.getMembersForGroup(_activeGroup!.id);
    final resolved = <CharacterCard>[];
    for (final m in rows) {
      if (m.avatarFilename != null) {
        final p = path.join(
          _storageService.groupsDir.path,
          _activeGroup!.id,
          'avatars',
          m.avatarFilename!,
        );
        if (await File(p).exists()) {
          resolved.add(m.toCharacterCard(resolvedImagePath: p));
        }
      }
    }
    _inheritGroupExpressionAvatars(resolved);
    _groupManager?.refreshCharacters(resolved);
    return resolved;
  }

  /// Remove a character from the active group chat: deletes the member's row,
  /// private avatar, and ALL per-member state (realism / notes / prompts / RAG /
  /// objectives / embeddings / data-bank), then re-resolves the surviving cast.
  /// When the removal leaves exactly ONE member the group auto-collapses back
  /// into a 1:1 with that member's ORIGINAL library character (a one-character
  /// group is nonsense) — see [_collapseGroupToSolo].
  Future<bool> removeCharacterFromGroup(
    CharacterCard character,
    GroupChatRepository groupRepo,
  ) async {
    if (_activeGroup == null || _characterRepository == null) return false;
    if (_isGenerating) return false;

    final charId = _getCharacterIdFromCard(character); // member instance id (mid)

    // Find the member's avatar filename before the row is deleted.
    final beforeRows = await groupRepo.getMembersForGroup(_activeGroup!.id);
    String? removedAvatar;
    for (final m in beforeRows) {
      if (m.id == charId) {
        removedAvatar = m.avatarFilename;
        break;
      }
    }

    // Delete the row + avatar + per-member DB state + in-memory maps.
    await _deleteMemberCleanup(charId, removedAvatar);
    await groupRepo.save(_activeGroup!);

    // Re-resolve the surviving members from the (now smaller) member table.
    final resolved = await _reloadGroupRoster();

    debugPrint(
      '[ChatService] \u{2796} Removed ${character.name} from group '
      '${_activeGroup!.name} (${resolved.length} left)',
    );

    // Persist the cleaned per-character maps to the session now, so the removed
    // member's realism/notes/etc. can't re-enter the group_realism_state blob on
    // a later save.
    await _saveChat();

    // A one-character group is nonsense — collapse straight back to a 1:1 with
    // the survivor's original library character (auto, no prompt). If the collapse
    // can't proceed (origin unresolvable, or the group has other saved
    // conversations), _collapseGroupToSolo surfaces a banner and we stay a
    // one-member cast.
    if (resolved.length == 1) {
      await _collapseGroupToSolo(groupRepo);
      return true;
    }

    notifyListeners();
    return true;
  }
}
