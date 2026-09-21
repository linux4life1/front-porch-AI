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

part of 'create_group_chat_page.dart';

/// Persist the new group and optionally open the chat.
extension _GroupWizardCommit on _CreateGroupChatPageState {
  Future<void> _createGroup({bool enterChat = true}) async {
    if (_members.length < 2) {
      _showSnack('A group needs at least 2 characters.');
      rebuildState(() => _currentStep = 0);
      return;
    }
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showSnack('Please give the group a name.');
      rebuildState(() => _currentStep = 1);
      return;
    }

    final repo = Provider.of<CharacterRepository>(context, listen: false);
    final groupRepo = Provider.of<GroupChatRepository>(context, listen: false);
    Provider.of<TtsService>(
      context,
      listen: false,
    ); // voices already resolved earlier

    // Per-char system prompts + realism/needs/dynamics seeds must be keyed by the
    // RUNTIME member id (the fresh `mid` generated per member in the insert loop
    // below), NOT the source library card's id. Every runtime read — the realism
    // engine (`_groupRealism[id]`), baseline lookups, and per-member prompt reads
    // — keys off the member's own UUID. So we collect the source-id → mid mapping
    // while inserting members and build both blobs (and the prompt map) from that
    // mapping AFTER the loop. Historically these were keyed by the source id and
    // were therefore never found at runtime (bond/trust/emotion/relationships and
    // per-member prompts silently fell back to defaults). See remapSeedsToMemberIds
    // + test/utils/group_realism_blobs_test.dart for the reachability proof.
    final charPrompts = <String, String>{};
    final memberIdMap = <String, String>{}; // source stableId → member mid

    // Serialize group lorebook
    final lb = Lorebook(entries: List.from(_groupLoreEntries));
    final groupLoreJson = jsonEncode(lb.toJson());

    String baselineJson = '{}';
    String defaultMemberJson = '{}';

    final groupId = 'group_${DateTime.now().millisecondsSinceEpoch}';

    // Persist decoupled members to private storage + typed table (extends this existing method;
    // reuses generalized duplicateCharacter for copy+ V2 embed into groups/<id>/avatars/).
    // No new private methods. Library untouched (sole bridge remains explicit "Separate...").
    final storage = Provider.of<StorageService>(context, listen: false);
    final database = Provider.of<db.AppDatabase>(context, listen: false);
    for (final source in _members) {
      final mid = const Uuid().v4();
      final avDir = Directory(
        p.join(storage.groupsDir.path, groupId, 'avatars'),
      );
      await avDir.create(recursive: true);

      await repo.duplicateCharacter(
        source,
        targetDirOverride: avDir.path,
        forcedBasename: mid,
        skipLibraryInsert: true,
      );

      // Per-member authority + verif flags + needs strength (exponent 1-5) must propagate
      // to the GroupMember row's frontPorchExtensions (the source of truth for runtime _groupCharacters cards
      // via toCharacterCard + god impersonation cb reads of .frontPorchExtensions.* ).
      // Seeds already feed full (incl short keys) to defaultMemberRealismState perChar; baseline scalars only.
      // Patch here (not mutate source library card) so group instance gets UI choice; duplicate only for avatar/PNG.
      // Consistent for all flags; other add-member paths use passed card's ext.
      final id = _stableId(source);
      // Record source-id → mid so the realism/baseline blobs (built after this
      // loop) and per-member prompts are keyed by the id the runtime reads.
      memberIdMap[id] = mid;
      final promptCtrl = _characterSystemPrompts[id];
      if (promptCtrl != null && promptCtrl.text.trim().isNotEmpty) {
        charPrompts[mid] = promptCtrl.text.trim();
      }
      final seed = _memberRealismSeeds[id] ?? _defaultRealismSeedFor(source);
      FrontPorchExtensions? memberFp;
      if (source.frontPorchExtensions != null) {
        memberFp = source.frontPorchExtensions!.copyWith(
          enjoysLowHygiene:
              (seed['enjoysLowHygiene'] as bool?) ??
              source.frontPorchExtensions!.enjoysLowHygiene,
          realismVerificationEnabled:
              (seed['verificationEnabled'] as bool?) ??
              source.frontPorchExtensions!.realismVerificationEnabled,
          realismVerificationMaxReprocesses:
              (seed['verificationMaxReprocesses'] as int?) ??
              source.frontPorchExtensions!.realismVerificationMaxReprocesses,
          realismVerificationStrictness:
              (seed['verificationStrictness'] as int?) ??
              source.frontPorchExtensions!.realismVerificationStrictness,
          realismNeedsDirectorAuthority:
              (seed['needsDirectorAuthority'] as bool?) ??
              source.frontPorchExtensions!.realismNeedsDirectorAuthority,
          needsSimStrength:
              (seed['needsSimStrength'] as int?) ??
              source.frontPorchExtensions!.needsSimStrength,
          // Carry the group-creator's per-member needs baselines + decay
          // choices (the seed). Without these two blocks, cards that already
          // ship a FrontPorchExtensions (the common case) silently lost every
          // baseline/decay adjustment made in the creator at save time.
          needsBaselineHunger:
              (seed['needsBaselineHunger'] as int?) ??
              source.frontPorchExtensions!.needsBaselineHunger,
          needsBaselineBladder:
              (seed['needsBaselineBladder'] as int?) ??
              source.frontPorchExtensions!.needsBaselineBladder,
          needsBaselineEnergy:
              (seed['needsBaselineEnergy'] as int?) ??
              source.frontPorchExtensions!.needsBaselineEnergy,
          needsBaselineSocial:
              (seed['needsBaselineSocial'] as int?) ??
              source.frontPorchExtensions!.needsBaselineSocial,
          needsBaselineFun:
              (seed['needsBaselineFun'] as int?) ??
              source.frontPorchExtensions!.needsBaselineFun,
          needsBaselineHygiene:
              (seed['needsBaselineHygiene'] as int?) ??
              source.frontPorchExtensions!.needsBaselineHygiene,
          needsBaselineComfort:
              (seed['needsBaselineComfort'] as int?) ??
              source.frontPorchExtensions!.needsBaselineComfort,
          needsDecayHunger:
              (seed['needsDecayHunger'] as int?) ??
              source.frontPorchExtensions!.needsDecayHunger,
          needsDecayBladder:
              (seed['needsDecayBladder'] as int?) ??
              source.frontPorchExtensions!.needsDecayBladder,
          needsDecayEnergy:
              (seed['needsDecayEnergy'] as int?) ??
              source.frontPorchExtensions!.needsDecayEnergy,
          needsDecaySocial:
              (seed['needsDecaySocial'] as int?) ??
              source.frontPorchExtensions!.needsDecaySocial,
          needsDecayFun:
              (seed['needsDecayFun'] as int?) ??
              source.frontPorchExtensions!.needsDecayFun,
          needsDecayHygiene:
              (seed['needsDecayHygiene'] as int?) ??
              source.frontPorchExtensions!.needsDecayHygiene,
          needsDecayComfort:
              (seed['needsDecayComfort'] as int?) ??
              source.frontPorchExtensions!.needsDecayComfort,
        );
      } else if (_realismEnabled) {
        memberFp = FrontPorchExtensions(
          enjoysLowHygiene: (seed['enjoysLowHygiene'] as bool?) ?? false,
          realismVerificationEnabled:
              (seed['verificationEnabled'] as bool?) ?? false,
          realismVerificationMaxReprocesses:
              (seed['verificationMaxReprocesses'] as int?) ?? 1,
          realismVerificationStrictness:
              (seed['verificationStrictness'] as int?) ?? 3,
          realismNeedsDirectorAuthority:
              (seed['needsDirectorAuthority'] as bool?) ?? false,
          needsBaselineHunger: (seed['needsBaselineHunger'] as int?) ?? 80,
          needsBaselineBladder: (seed['needsBaselineBladder'] as int?) ?? 80,
          needsBaselineEnergy: (seed['needsBaselineEnergy'] as int?) ?? 80,
          needsBaselineSocial: (seed['needsBaselineSocial'] as int?) ?? 80,
          needsBaselineFun: (seed['needsBaselineFun'] as int?) ?? 80,
          needsBaselineHygiene: (seed['needsBaselineHygiene'] as int?) ?? 80,
          needsBaselineComfort: (seed['needsBaselineComfort'] as int?) ?? 80,
          needsDecayHunger: (seed['needsDecayHunger'] as int?) ?? 5,
          needsDecayBladder: (seed['needsDecayBladder'] as int?) ?? 5,
          needsDecayEnergy: (seed['needsDecayEnergy'] as int?) ?? 5,
          needsDecaySocial: (seed['needsDecaySocial'] as int?) ?? 5,
          needsDecayFun: (seed['needsDecayFun'] as int?) ?? 5,
          needsDecayHygiene: (seed['needsDecayHygiene'] as int?) ?? 5,
          needsDecayComfort: (seed['needsDecayComfort'] as int?) ?? 5,
          needsSimStrength: (seed['needsSimStrength'] as int?) ?? 1,
        );
        memberFp.ensureStableId();
      }

      // Insert typed GroupMember row using the database instance.
      await database.insertGroupMember(
        db.GroupMembersCompanion(
          id: Value(mid),
          groupId: Value(groupId),
          name: Value(source.name),
          description: Value(source.description),
          personality: Value(source.personality),
          scenario: Value(source.scenario),
          firstMessage: Value(source.firstMessage),
          mesExample: Value(source.mesExample),
          systemPrompt: Value(source.systemPrompt),
          postHistoryInstructions: Value(source.postHistoryInstructions),
          alternateGreetings: Value(jsonEncode(source.alternateGreetings)),
          tags: Value(jsonEncode(source.tags)),
          avatarFilename: Value('$mid.png'),
          ttsVoice: Value(source.ttsVoice),
          lorebook: Value(
            source.lorebook != null
                ? jsonEncode(source.lorebook!.toJson())
                : null,
          ),
          worldNames: Value(jsonEncode(source.worldNames)),
          frontPorchExtensions: Value(
            memberFp != null
                ? jsonEncode(memberFp.toJson())
                : (source.frontPorchExtensions != null
                      ? jsonEncode(source.frontPorchExtensions!.toJson())
                      : null),
          ),
          rawExtensions: Value(
            source.rawExtensions != null
                ? jsonEncode(source.rawExtensions!)
                : null,
          ),
          // Provenance: stamp the source library character so this member can
          // later be traced back / collapsed to a 1:1 with the original.
          memberState: Value(
            GroupMember.encodeProvenance(
              originStableId: source.stableGroupId,
              originLibraryDbId: source.dbId,
            ),
          ),
        ),
      );
    }

    // Build the realism/needs/dynamics blobs from seeds re-keyed to member mids
    // (the ids the runtime reads). Done here — after the insert loop populated
    // memberIdMap — so the creator's per-member bond/trust/emotion/needs and
    // intragroup relationships actually take effect in chat.
    if (_realismEnabled) {
      final seeds = <String, Map<String, dynamic>>{
        for (final c in _members)
          _stableId(c):
              _memberRealismSeeds[_stableId(c)] ?? _defaultRealismSeedFor(c),
      };
      final blobs = buildGroupRealismBlobs(
        seeds: remapSeedsToMemberIds(seeds, memberIdMap),
        needsEnabled: _needsSimEnabled,
        timeOfDay: _globalTimeOfDay,
        dayCount: _globalDayCount,
        storyStartDate: _globalStoryStartDate,
        storyStartTime: _globalStoryStartTime,
        alternateGreetings: _altGreetings,
        greetingSeeds: _altGreetingSeeds,
      );
      defaultMemberJson = blobs.defaultMemberJson;
      baselineJson = blobs.baselineJson;
    }

    final group = GroupChat(
      id: groupId,
      name: name,
      // characterIds removed (clean break). Members persisted above to group_members + private avatars.
      turnOrder: _turnOrder,
      autoAdvance: _autoAdvance,
      directorMode: _directorMode,
      firstMessage: _firstMessageController.text.trim(),
      alternateGreetings: List.from(_altGreetings),
      greetingSeeds: List.from(_altGreetingSeeds),
      scenario: _scenarioController.text.trim(),
      systemPrompt: _groupSystemController.text.trim(),
      characterSystemPrompts: charPrompts,
      worldIds: List.from(_worldIds),
      groupLorebook: groupLoreJson,
      inheritCharacterLorebooks: _inheritCharacterLorebooks,
      chaosModeEnabled: _chaosModeEnabled,
      chaosNsfwEnabled: _chaosNsfwEnabled,
      baselineRealismState: baselineJson,
      defaultMemberRealismState: defaultMemberJson,
    );

    await groupRepo.save(group);

    // Apply voice overrides (same pattern as the old creator)
    for (final entry in _characterVoices.entries) {
      final card = _members.firstWhere(
        (c) => _stableId(c) == entry.key,
        orElse: () => _members.first,
      );
      if (entry.value.isNotEmpty && entry.value != card.ttsVoice) {
        card.ttsVoice = entry.value;
        // Library mutation intentionally skipped during group creation (private GroupMember rows
        // already captured the voice from source card at duplicate time; avoids subtle "library pollution"
        // side-effect per "never allow" + safety invariant. User can edit voice on the private group member later).
        // await repo.updateCharacter(card);  -- removed to prevent library side-effect
      }
    }

    if (enterChat) {
      // Full "Create & Enter" path.
      final chatService = Provider.of<ChatService>(context, listen: false);
      await chatService.setActiveGroup(group, groupRepo: groupRepo);
      await chatService.startNewChat();

      if (mounted) {
        Navigator.of(
          context,
        ).pushReplacement(MaterialPageRoute(builder: (_) => const ChatPage()));
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Group "$name" created!')));
      }
    } else {
      // "Create Only (don't enter chat yet)"
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        messenger.showSnackBar(
          SnackBar(content: Text('Group "$name" created.')),
        );
        Navigator.of(context).pop();
      }
    }
  }
}
