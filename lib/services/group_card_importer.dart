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

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/group_card.dart';
import 'package:front_porch_ai/utils/group_stable_id.dart';
import 'package:front_porch_ai/models/group_chat.dart';
import 'package:front_porch_ai/models/group_member.dart';
import 'package:front_porch_ai/services/group_chat_repository.dart';
import 'package:front_porch_ai/services/storage_service.dart';

/// Outcome of importing a Group Card.
class GroupImportResult {
  /// True when a group shell was created (at least one member materialized).
  final bool created;
  final String groupName;
  final int successCount;
  final int failCount;
  const GroupImportResult({
    required this.created,
    required this.groupName,
    required this.successCount,
    required this.failCount,
  });
}

/// Materializes a portable [GroupCard] into a private group (group shell + typed
/// group_members rows + private avatars), the mirror of [GroupCardExporter].
///
/// This is the single source of truth for the group-import logic that used to
/// live inline in `home_page._importGroupCard`; the desktop UI and The Stoop's
/// "Download to library" both call it so the two paths can never diverge. It is
/// a clean-break PRIVATE import: it NEVER touches the library/CharacterRepository
/// — all members go to `groups/<id>/avatars/` + group_members rows (UUID keys),
/// and realism/prompts/objectives are remapped to the new UUIDs.
class GroupCardImporter {
  GroupCardImporter(this._groups, this._storage, this._db);

  final GroupChatRepository _groups;
  final StorageService _storage;
  final AppDatabase _db;

  Future<GroupImportResult> importCard(GroupCard groupCard) async {
    final groupId = 'group_${DateTime.now().millisecondsSinceEpoch}';
    int successCount = 0;
    int failCount = 0;

    // Mapping from original exported stable IDs to the new UUIDs for this
    // group's members. Realism, prompts, objectives, relationships etc. are
    // remapped to these UUIDs (correct for the decoupled model).
    final Map<String, String> oldStableIdToNewStableId = {};

    final rawMembers = groupCard.rawMemberData.isNotEmpty
        ? groupCard.rawMemberData
        : groupCard.members.map((c) => c.toJson()).toList();

    for (final raw in rawMembers) {
      File? tempPng;
      try {
        // Build a temporary valid character card PNG from the raw portable data.
        final memberJson = {
          'spec': 'chara_card_v2',
          'spec_version': '2.0',
          'data': raw,
        };
        final jsonStr = jsonEncode(memberJson);
        final b64 = base64Encode(utf8.encode(jsonStr));

        final tempDir = await Directory.systemTemp.createTemp(
          'fp_group_member_',
        );

        // Use the real avatar embedded on export when present.
        final avatarBase64 =
            raw['avatar_base64'] as String? ??
            (raw['data'] as Map?)?['avatar_base64'] as String?;

        if (avatarBase64 != null && avatarBase64.isNotEmpty) {
          final avatarBytes = base64Decode(avatarBase64);
          var avatarImg =
              img.decodePng(avatarBytes) ?? img.decodeImage(avatarBytes);

          if (avatarImg != null) {
            avatarImg.textData ??= {};
            avatarImg.textData!['chara'] = b64;
            tempPng = File(
              path.join(
                tempDir.path,
                'member_${DateTime.now().millisecondsSinceEpoch}.png',
              ),
            );
            await tempPng.writeAsBytes(img.encodePng(avatarImg));
          }
        }

        // Fallback: a deterministic colored placeholder (foreign / old cards).
        if (tempPng == null) {
          final memberName =
              (raw['name'] ?? raw['data']?['name'] ?? 'Character').toString();

          final hash = memberName.codeUnits.fold(0, (a, b) => a + b);
          final r = (80 + (hash % 120)).clamp(60, 200);
          final g = (70 + ((hash * 7) % 130)).clamp(60, 200);
          final b = (90 + ((hash * 13) % 110)).clamp(70, 190);

          final placeholder = img.Image(width: 400, height: 600);
          img.fill(placeholder, color: img.ColorRgb8(r, g, b));
          placeholder.textData ??= {};
          placeholder.textData!['chara'] = b64;

          tempPng = File(
            path.join(
              tempDir.path,
              'member_${DateTime.now().millisecondsSinceEpoch}.png',
            ),
          );
          await tempPng.writeAsBytes(img.encodePng(placeholder));
        }

        // Decoupled private materialization (no library pollution).
        final memberId = const Uuid().v4();
        final avDir = Directory(
          path.join(_storage.groupsDir.path, groupId, 'avatars'),
        );
        await avDir.create(recursive: true);
        final targetAvatar = File(path.join(avDir.path, '$memberId.png'));
        await tempPng.copy(targetAvatar.path);

        final data = (raw['data'] is Map)
            ? Map<String, dynamic>.from(raw['data'] as Map)
            : Map<String, dynamic>.from(raw as Map);
        String jsonOrDefault(dynamic v, [String d = '[]']) {
          if (v == null) return d;
          if (v is String) return v;
          try {
            return jsonEncode(v);
          } catch (_) {
            return d;
          }
        }

        await _db.insertGroupMember(
          GroupMembersCompanion.insert(
            id: memberId,
            groupId: groupId,
            name: (data['name'] ?? data['data']?['name'] ?? 'Unknown')
                .toString(),
            description: Value(
              (data['description'] ?? data['desc'] ?? '').toString(),
            ),
            personality: Value((data['personality'] ?? '').toString()),
            scenario: Value((data['scenario'] ?? '').toString()),
            firstMessage: Value(
              (data['first_mes'] ?? data['firstMessage'] ?? '').toString(),
            ),
            mesExample: Value(
              (data['mes_example'] ?? data['mesExample'] ?? '').toString(),
            ),
            systemPrompt: Value(
              (data['system_prompt'] ?? data['systemPrompt'] ?? '').toString(),
            ),
            postHistoryInstructions: Value(
              (data['post_history_instructions'] ?? '').toString(),
            ),
            alternateGreetings: Value(
              jsonOrDefault(
                data['alternate_greetings'] ?? data['alternateGreetings'],
              ),
            ),
            tags: Value(jsonOrDefault(data['tags'] ?? [])),
            avatarFilename: Value('$memberId.png'),
            ttsVoice: Value(data['tts_voice']?.toString()),
            lorebook: Value(
              data['character_book'] != null
                  ? jsonEncode(data['character_book'])
                  : null,
            ),
            worldNames: Value(jsonOrDefault(data['world_names'] ?? [])),
            frontPorchExtensions: Value(
              (data['extensions'] is Map &&
                      (data['extensions'] as Map)['front_porch'] != null)
                  ? jsonEncode((data['extensions'] as Map)['front_porch'])
                  : null,
            ),
            rawExtensions: Value(
              (data['extensions'] is Map)
                  ? jsonEncode(
                      Map<String, dynamic>.from(data['extensions'] as Map)
                        ..remove('front_porch'),
                    )
                  : null,
            ),
            // Provenance — carry the member's true library origin when the card
            // recorded it (`_origin_library_stable_id`), so a re-imported member
            // stays reconnectable; foreign cards degrade to origin-unknown.
            memberState: Value(
              GroupMember.encodeProvenance(
                originStableId: raw['_origin_library_stable_id'] is String
                    ? (raw['_origin_library_stable_id'] as String).trim()
                    : null,
              ),
            ),
          ),
        );

        final originalStableId = (raw['_original_stable_id'] as String?)?.trim();
        if (originalStableId != null && originalStableId.isNotEmpty) {
          oldStableIdToNewStableId[originalStableId] = memberId;
        }
        successCount++;
      } catch (e) {
        debugPrint('Failed to import one group member: $e');
        failCount++;
      } finally {
        try {
          if (tempPng != null && await tempPng.exists()) {
            await tempPng.delete();
            await tempPng.parent.delete(recursive: true);
          }
        } catch (_) {}
      }
    }

    if (successCount == 0) {
      // Clean up any partially materialized private avatar tree.
      try {
        final orphanDir = Directory(
          path.join(_storage.groupsDir.path, groupId),
        );
        if (await orphanDir.exists()) await orphanDir.delete(recursive: true);
      } catch (_) {}
      return GroupImportResult(
        created: false,
        groupName: groupCard.name,
        successCount: 0,
        failCount: failCount,
      );
    }

    // Seed portable realism + per-character prompts (Path B: prefer the new
    // top-level key, fall back to the legacy location inside realism_state).
    final importedRealism = groupCard.extensions?['realism_state'];
    Map<String, String> importedCharPrompts = groupCard.characterSystemPrompts;
    if (importedCharPrompts.isEmpty && importedRealism is Map) {
      final legacy =
          importedRealism['characterSystemPrompts'] ??
          importedRealism['character_system_prompts'];
      if (legacy is Map) {
        importedCharPrompts = legacy.map(
          (k, v) => MapEntry(k.toString(), (v ?? '').toString()),
        );
      }
    }

    // Remap ID-keyed data using the old→new stable ID mapping built above.
    String finalBaseline = groupCard.baselineRealismState;
    String finalDefaultMember = groupCard.defaultMemberRealismState;
    Map<String, String> finalCharPrompts = importedCharPrompts;
    Map<String, List<Map<String, dynamic>>> finalObjectives =
        groupCard.memberObjectives;

    if (oldStableIdToNewStableId.isNotEmpty) {
      finalBaseline = _remapIdsInJson(
        groupCard.baselineRealismState,
        oldStableIdToNewStableId,
      );
      finalDefaultMember = _remapIdsInJson(
        groupCard.defaultMemberRealismState,
        oldStableIdToNewStableId,
      );

      final remappedPrompts = <String, String>{};
      for (final e in importedCharPrompts.entries) {
        remappedPrompts[oldStableIdToNewStableId[e.key] ?? e.key] = e.value;
      }
      finalCharPrompts = remappedPrompts;

      final remappedObjectives = <String, List<Map<String, dynamic>>>{};
      for (final e in groupCard.memberObjectives.entries) {
        remappedObjectives[oldStableIdToNewStableId[e.key] ?? e.key] = e.value;
      }
      finalObjectives = remappedObjectives;
    }

    final newGroup = GroupChat(
      id: groupId,
      // Preserve the card's portable stable id so the owner can UPDATE the same
      // Stoop post from this device (cross-device). Absent on older cards → left
      // null; a fresh id is generated on first export/share here instead.
      stableId: readGroupStableIdFromExtensions(groupCard.extensions),
      name: groupCard.name,
      turnOrder: groupCard.turnOrder == 'random'
          ? TurnOrder.random
          : TurnOrder.roundRobin,
      autoAdvance: groupCard.autoAdvance,
      directorMode: groupCard.directorMode,
      firstMessage: groupCard.firstMessage,
      scenario: groupCard.scenario,
      systemPrompt: groupCard.systemPrompt,
      groupLorebook: groupCard.groupLorebook ?? '',
      worldIds: groupCard.worldIds,
      inheritCharacterLorebooks: groupCard.inheritCharacterLorebooks,
      chaosModeEnabled: groupCard.chaosModeEnabled,
      chaosNsfwEnabled: groupCard.chaosNsfwEnabled,
      baselineRealismState: finalBaseline.isNotEmpty ? finalBaseline : '{}',
      defaultMemberRealismState: finalDefaultMember.isNotEmpty
          ? finalDefaultMember
          : '{}',
      characterSystemPrompts: finalCharPrompts,
    );

    if (finalObjectives.isNotEmpty) {
      try {
        final currentState = jsonDecode(newGroup.defaultMemberRealismState);
        final mutable = (currentState is Map)
            ? Map<String, dynamic>.from(currentState)
            : <String, dynamic>{};
        mutable['imported_member_objectives'] = finalObjectives;
        newGroup.defaultMemberRealismState = jsonEncode(mutable);
      } catch (_) {}
    }

    await _groups.save(newGroup);

    return GroupImportResult(
      created: true,
      groupName: groupCard.name,
      successCount: successCount,
      failCount: failCount,
    );
  }

  /// Rewrites stable-id keys (and nested `relationships` target ids) in a
  /// realism JSON blob using [mapping]. Handles both `{perChar: {...}}` and a
  /// bare per-char map.
  String _remapIdsInJson(String jsonString, Map<String, String> mapping) {
    if (jsonString.isEmpty || jsonString == '{}') return jsonString;
    try {
      final decoded = jsonDecode(jsonString);
      if (decoded is! Map) return jsonString;

      final Map<String, dynamic> rewritten = {};

      Map<String, dynamic> rewritePerCharMap(Map input) {
        final Map<String, dynamic> out = {};
        for (final entry in input.entries) {
          final oldId = entry.key.toString();
          final newId = mapping[oldId] ?? oldId;
          final value = entry.value;

          if (value is Map && value.containsKey('relationships')) {
            final inner = Map<String, dynamic>.from(value);
            final rels = inner['relationships'];
            if (rels is Map) {
              final newRels = <String, dynamic>{};
              for (final r in rels.entries) {
                final oldTarget = r.key.toString();
                final newTarget = mapping[oldTarget] ?? oldTarget;
                newRels[newTarget] = r.value;
              }
              inner['relationships'] = newRels;
            }
            out[newId] = inner;
          } else {
            out[newId] = value;
          }
        }
        return out;
      }

      if (decoded.containsKey('perChar') && decoded['perChar'] is Map) {
        rewritten['perChar'] = rewritePerCharMap(decoded['perChar'] as Map);
        for (final k in decoded.keys) {
          if (k != 'perChar') rewritten[k] = decoded[k];
        }
      } else {
        rewritten.addAll(rewritePerCharMap(decoded));
      }

      return jsonEncode(rewritten);
    } catch (_) {
      return jsonString;
    }
  }
}
