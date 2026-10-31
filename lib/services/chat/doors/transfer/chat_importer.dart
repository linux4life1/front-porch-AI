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

import 'dart:async';
import 'dart:isolate';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/database/database.dart' hide AvatarImage, World;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat_import_busy.dart';
import 'package:front_porch_ai/services/chat/fpchat_cast.dart';
import 'package:front_porch_ai/services/chat/fpchat_codec.dart';
import 'package:front_porch_ai/services/chat/fpchat_format.dart';
import 'package:front_porch_ai/services/chat/group_lite.dart';
import 'package:front_porch_ai/services/chat/session_state.dart';
import 'package:front_porch_ai/utils/character_id.dart';

import 'import_rag_backfill.dart';
import 'package_extras.dart';
import 'package_images.dart';
import 'transfer_host.dart';

/// Imports a `.fpchat` package (or legacy SillyTavern-ish JSON) into a new
/// session of the open chat: transcript, stamps, session head, cast,
/// Journal, Growth and Objectives, then a background RAG backfill.
///
/// Not a notifier: it calls [notify] where the shell repaints.
class ChatImporter {
  ChatImporter(
    this._session,
    this._host, {
    required Future<void> Function() saveChat,
    required void Function() notify,
  }) : _saveChat = saveChat,
       _notify = notify,
       _extras = PackageExtras(_session, _host);

  final ChatSessionState _session;
  final TransferHost _host;
  final Future<void> Function() _saveChat;
  final void Function() _notify;
  final PackageExtras _extras;

  bool _importing = false;

  /// An import is replacing the open chat; sends and edits refuse.
  bool get isImporting => _importing;

  /// Test hook (bridged as `testImportHold`): import awaits this before
  /// mutating so a Send can race it.
  Completer<void>? testImportHold;

  /// Import a `.fpchat` zip or legacy ST-ish JSON bytes into a **new** session.
  ///
  /// [onCharacterMismatch] is called when the package's character id/name does
  /// not match the active card; return true to continue full restore, false to
  /// import transcript only.
  Future<({bool fullRestore, String? warning})> importChatPackage(
    Uint8List bytes, {
    Future<bool> Function(String packageName, String activeName)?
    onCharacterMismatch,
  }) async {
    if (_session.activeCharacter == null && _session.activeGroup == null) {
      throw Exception('No active character or group');
    }
    if (_host.isTurnBusy()) throw ChatImportBusy();
    _importing = true;
    try {
      if (testImportHold != null) await testImportHold!.future;
      return await _importChatPackageBody(bytes, onCharacterMismatch);
    } finally {
      _importing = false;
    }
  }

  Future<({bool fullRestore, String? warning})> _importChatPackageBody(
    Uint8List bytes,
    Future<bool> Function(String packageName, String activeName)?
    onCharacterMismatch,
  ) async {
    // Preserve the currently open chat before replacing in-memory messages.
    if (_session.currentSessionId != null && _session.messages.isNotEmpty) {
      await _saveChat();
    }

    // Stale unauthored RtR from a prior opening must not paint this import.
    // The busy guard does not wait the greeting eval, so a delayed eval
    // is still in flight when the package transcript replaces first_mes.
    await _host.invalidateGreetingEval();

    final decoded = await Isolate.run(() => decodeFpchatBytes(bytes));
    final root = decoded.chatJson;
    final kind = detectFpchatPayload(root);
    if (kind == FpchatPayloadKind.unknown) {
      throw Exception('Unrecognized chat file format');
    }

    final laneA = root['messages'] as List? ?? const [];
    final fpai = root['fpai'] is Map
        ? Map<String, dynamic>.from(root['fpai'] as Map)
        : null;

    var full = kind == FpchatPayloadKind.fpaiTimeline && fpai != null;
    String? warning;
    // Set when a 1:1 package is restored onto a DIFFERENT card and the user
    // (or AI Enhance's copy-chats, which always answers "continue") takes the
    // full restore: every owner-keyed row must move to the LIVE card's
    // stableGroupId, or the diary, rings and quests land under an id no reader
    // ever asks for. Guest-owned rows keep their own id.
    String? ownerRemapFrom;

    if (full) {
      final stampV = (fpai['stamp_version'] as num?)?.toInt() ?? 0;
      if (stampV > kFpchatStampVersion) {
        warning =
            'Package stamp_version $stampV is newer than this app '
            '($kFpchatStampVersion); importing transcript only.';
        full = false;
      }
      final pkgChar = fpai['character'] is Map
          ? Map<String, dynamic>.from(fpai['character'] as Map)
          : null;
      // Symmetric cross-mode guards (review 03d46d9a finding 2):
      // - 1:1 package → open group: dialogue only
      // - group package → open 1:1: dialogue only
      // - group package → different group: dialogue only
      // - 1:1 → wrong card: prompt (or warn)
      if (full && pkgChar != null) {
        final pkgName = (pkgChar['name'] as String? ?? '').trim();
        final pkgId = (pkgChar['stable_group_id'] as String? ?? '').trim();
        final pkgGroupId = (pkgChar['group_id'] as String? ?? '').trim();
        final pkgIsGroup = pkgGroupId.isNotEmpty;
        final openGroup = _session.activeGroup;
        final openIsGroup = openGroup != null;

        if (openIsGroup && !pkgIsGroup) {
          full = false;
          warning =
              'Package is a 1:1 export; open group is "${openGroup.name}" '
              '— importing dialogue only.';
        } else if (!openIsGroup && pkgIsGroup) {
          full = false;
          warning =
              'Package is a group export'
              '${pkgChar['group_name'] != null ? ' ("${pkgChar['group_name']}")' : ''}'
              '; open chat is 1:1 — importing dialogue only.';
        } else if (openIsGroup && pkgIsGroup && pkgGroupId != openGroup.id) {
          full = false;
          warning =
              'Package was exported for group '
              '"${pkgChar['group_name'] ?? pkgGroupId}" but open group is '
              '"${openGroup.name}" — importing dialogue only.';
        } else if (!openIsGroup &&
            _session.activeCharacter != null &&
            !pkgIsGroup) {
          final activeId = _session.activeCharacter!.stableGroupId;
          final mismatch =
              (pkgId.isNotEmpty && pkgId != activeId) ||
              (pkgName.isNotEmpty &&
                  pkgName.toLowerCase() !=
                      _session.activeCharacter!.name.toLowerCase());
          if (mismatch && onCharacterMismatch != null) {
            final cont = await onCharacterMismatch(
              pkgName.isEmpty ? pkgId : pkgName,
              _session.activeCharacter!.name,
            );
            if (!cont) {
              full = false;
              warning = 'Character mismatch — transcript only.';
            }
          } else if (mismatch) {
            warning =
                'Package was exported for "$pkgName" but active card is '
                '"${_session.activeCharacter!.name}". Restoring stamps anyway.';
          }
          if (full && pkgId.isNotEmpty && pkgId != activeId) {
            ownerRemapFrom = pkgId;
          }
        }
      }
    }

    final remapTo = ownerRemapFrom == null
        ? null
        : _host.characterIdFor(_session.activeCharacter!);

    // Phase 0: seed card defaults so save never bleeds prior live state.
    await _host.seedScalars();

    // The messages move too: a reply still stamped with the exporting card's
    // id reads as a scene guest who left, so Regenerate and Continue refuse
    // it, and its rewind puts item cards back under an unread id.
    final extras = full && fpai != null
        ? rekeyFpchatMessageOwner(
            fpai['messages_extra'] as List?,
            ownerRemapFrom,
            remapTo,
          )
        : null;
    final msgs = messagesFromPackage(laneA: laneA, extras: extras);

    // Mint session id BEFORE materializing images so paths land under it.
    _session.currentSessionId = DateTime.now().millisecondsSinceEpoch
        .toString();
    if (full && decoded.images.isNotEmpty) {
      await materializeFpchatImages(
        msgs,
        decoded.images,
        sid: _session.currentSessionId ?? 'import',
        imageGen: _host.imageGen(),
        storage: _host.storage,
      );
    }

    _session.messages
      ..clear()
      ..addAll(msgs);
    // Imported history is not a virgin chat — RAG retrieval must not skip.
    _host.markNewChat(_session.messages.isEmpty);
    _host.computeAbsenceGap();
    await _host.seedChatWorlds();

    if (full && fpai != null) {
      final session = fpai['session'] is Map
          ? Map<String, dynamic>.from(fpai['session'] as Map)
          : null;
      if (session != null) {
        await _host.applySessionHead(session);
      } else if (_session.messages.isNotEmpty) {
        await _host.restoreWalkingBack(_session.messages.length - 1);
      }
      // After seed wiped guests: restore `fpai.cast` on a matching open
      // chat. Mismatched / dialogue-only never reaches here (`full` is false).
      await _applyCastFromPackage(fpai[kFpchatCastKey]);
      // Journal cards (Phase 1)
      final journal = fpai['journal'] as List?;
      if (journal != null) {
        await _extras.importJournalCards(
          _rekeyPackageOwners(journal, ownerRemapFrom, remapTo),
        );
      }
      // Growth rings + objectives (Phase 2)
      if (fpai['growth'] is Map) {
        final growth = Map<String, dynamic>.from(fpai['growth'] as Map);
        growth['rings'] = _rekeyPackageOwners(
          growth['rings'] as List? ?? const [],
          ownerRemapFrom,
          remapTo,
        );
        await _extras.importGrowth(growth);
      }
      final objectives = fpai['objectives'] as List?;
      if (objectives != null) {
        await _extras.importObjectives(
          _rekeyPackageOwners(objectives, ownerRemapFrom, remapTo),
        );
      }
    } else {
      // Transcript-only: journal cursor caught up, blank memory (no thrash).
      _host.catchUpRecap(_session.messages.length);
    }

    await _saveChat();
    unawaited(backfillRagAfterImport(_session, _host));
    _notify();
    return (fullRestore: full, warning: warning);
  }

  /// Restore [fpai.cast] after Phase 0 seed wiped guests. Missing/empty
  /// is a no-op (legacy packages). Unknown ids are skipped — no invented
  /// cards. Dialogue-only imports never call this.
  Future<void> _applyCastFromPackage(dynamic raw) async {
    final cast = parseFpchatCast(raw);
    if (cast.isEmpty) return;
    if (_session.activeGroup != null) {
      var changed = false;
      for (final entry in cast) {
        if (!entry.lite) continue;
        final live = matchFpchatCastMember(_session.groupCharacters, entry);
        if (live == null || live.isLite) continue;
        final stamped = cloneFrontPorchTier(
          live.frontPorchExtensions,
          lite: true,
        );
        live.frontPorchExtensions = stamped;
        if (live.dbId != null) {
          await _host.db().updateGroupMember(
            GroupMembersCompanion(
              id: drift.Value(live.dbId!),
              frontPorchExtensions: drift.Value(
                encodeMemberFrontPorch(stamped),
              ),
            ),
          );
        }
        changed = true;
      }
      if (changed) await _host.reloadGroupRoster();
      return;
    }
    final hostId = _session.activeCharacter != null
        ? _host.characterIdFor(_session.activeCharacter!)
        : '';
    final library = _host.characters()?.characters ?? const <CharacterCard>[];
    for (final entry in cast) {
      if (!entry.lite) continue;
      final lib = matchFpchatCastMember(library, entry);
      if (lib == null || lib.dbId == null) continue;
      if (_host.characterIdFor(lib) == hostId) continue;
      if (_host.sceneGuests.ids.contains(lib.dbId)) continue;
      await _host.enterSceneGuestSilently(lib);
    }
  }

  /// Register a 1:1 Scene Guest without an entrance turn (import + tests).
  Future<void> debugEnterSceneGuestSilent(CharacterCard guest) =>
      _host.enterSceneGuestSilently(guest);

  /// Test hook: live `realism_state` capture key set for stamp-contract guards.
  Map<String, dynamic> debugCaptureRealismState() =>
      _host.captureRealismState();
}

/// Re-stamp `character_id` on package rows owned by [from] so they land under
/// the live card [to]. Returns [rows] untouched when there is nothing to
/// remap (same card — the common case — or a group package). Rows owned by
/// anyone else (scene guests) pass through verbatim.
List<dynamic> _rekeyPackageOwners(
  List<dynamic> rows,
  String? from,
  String? to,
) {
  if (from == null || to == null || from == to) return rows;
  return [
    for (final r in rows)
      if (r is Map && (r['character_id'] as String? ?? '').trim() == from)
        {...Map<String, dynamic>.from(r), 'character_id': to}
      else
        r,
  ];
}
