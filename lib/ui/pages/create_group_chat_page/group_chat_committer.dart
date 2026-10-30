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

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'package:front_porch_ai/database/database.dart' as db;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/utils.dart';

import 'create_group_chat_page.dart';

/// Persists a validated wizard draft as a new group: private member copies,
/// typed GroupMember rows, realism blobs, then the GroupChat itself.
class GroupChatCommitter {
  const GroupChatCommitter({
    required this.repo,
    required this.groupRepo,
    required this.storage,
    required this.database,
  });

  final CharacterRepository repo;
  final GroupChatRepository groupRepo;
  final StorageService storage;
  final db.AppDatabase database;

  Future<GroupChat> commit(GroupWizardDraft d, String name) async {
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
    final lb = Lorebook(entries: List.from(d.groupLoreEntries));
    final groupLoreJson = jsonEncode(lb.toJson());

    String baselineJson = '{}';
    String defaultMemberJson = '{}';

    final groupId = 'group_${DateTime.now().millisecondsSinceEpoch}';

    // Persist decoupled members to private storage + typed table (extends this existing method;
    // reuses generalized duplicateCharacter for copy+ V2 embed into groups/<id>/avatars/).
    // No new private methods. Library untouched (sole bridge remains explicit "Separate...").
    for (final source in d.members) {
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
      final id = d.stableId(source);
      // Record source-id → mid so the realism/baseline blobs (built after this
      // loop) and per-member prompts are keyed by the id the runtime reads.
      memberIdMap[id] = mid;
      final promptCtrl = d.characterSystemPrompts[id];
      if (promptCtrl != null && promptCtrl.text.trim().isNotEmpty) {
        charPrompts[mid] = promptCtrl.text.trim();
      }
      final seed = d.memberRealismSeeds[id] ?? d.defaultRealismSeedFor(source);
      final memberFp = groupMemberExtensions(
        source,
        seed,
        realismEnabled: d.realismEnabled,
      );

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
          // The Members step's Voice pick (characterVoices): never written
          // to the library card.
          ttsVoice: Value(memberVoiceFromPick(d.characterVoices, id, source)),
          lorebook: Value(
            source.lorebook != null
                ? jsonEncode(source.lorebook!.toJson())
                : null,
          ),
          worldNames: Value(jsonEncode(source.allWorldNames)),
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
    if (d.realismEnabled) {
      final seeds = <String, Map<String, dynamic>>{
        for (final c in d.members)
          d.stableId(c):
              d.memberRealismSeeds[d.stableId(c)] ?? d.defaultRealismSeedFor(c),
      };
      final blobs = buildGroupRealismBlobs(
        seeds: remapSeedsToMemberIds(seeds, memberIdMap),
        needsEnabled: d.needsSimEnabled,
        timeOfDay: d.globalTimeOfDay,
        dayCount: d.globalDayCount,
        storyStartDate: d.globalStoryStartDate,
        storyStartTime: d.globalStoryStartTime,
        alternateGreetings: d.altGreetings,
        greetingSeeds: d.altGreetingSeeds,
      );
      defaultMemberJson = blobs.defaultMemberJson;
      baselineJson = blobs.baselineJson;
    }

    final group = GroupChat(
      id: groupId,
      name: name,
      // characterIds removed (clean break). Members persisted above to group_members + private avatars.
      turnOrder: d.turnOrder,
      autoAdvance: d.autoAdvance,
      directorMode: d.directorMode,
      firstMessage: d.firstMessageController.text.trim(),
      alternateGreetings: List.from(d.altGreetings),
      greetingSeeds: List.from(d.altGreetingSeeds),
      scenario: d.scenarioController.text.trim(),
      characterSystemPrompts: charPrompts,
      worldIds: d.worldChoice.fields.worldIds,
      loreWorldIds: d.worldChoice.fields.loreWorldIds,
      groupLorebook: groupLoreJson,
      inheritCharacterLorebooks: d.inheritCharacterLorebooks,
      chaosModeEnabled: d.chaosModeEnabled,
      chaosNsfwEnabled: d.chaosNsfwEnabled,
      baselineRealismState: baselineJson,
      defaultMemberRealismState: defaultMemberJson,
    );

    await groupRepo.save(group);

    return group;
  }
}
