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

import 'dart:isolate';

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/app_version.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat_import_busy.dart';
import 'package:front_porch_ai/services/chat/fpchat_cast.dart';
import 'package:front_porch_ai/services/chat/fpchat_codec.dart';
import 'package:front_porch_ai/services/chat/fpchat_format.dart';
import 'package:front_porch_ai/services/chat/session_state.dart';
import 'package:front_porch_ai/utils/character_id.dart';

import 'chat_importer.dart';
import 'package_extras.dart';
import 'package_images.dart';
import 'transfer_host.dart';

/// Exports the open chat (SillyTavern JSONL, or a full `.fpchat` package)
/// and moves a character's chats as packages: AI Enhance's "bring your
/// chats along" step and `.porch` character files.
///
/// Moving chats is deliberately a round-trip through the `.fpchat`
/// exporter and [ChatImporter] (maintainer direction, 2026-08-13) rather
/// than a hand-rolled row copier: the codec already carries messages,
/// swipes, realism stamps, journal cards, growth rings, objectives and
/// images, the importer seeds live realism so the copies cannot bleed into
/// each other, and its background RAG backfill re-embeds the copied
/// history — a second implementation of any of that would be exactly the
/// parallel path the project bans.
///
/// Neither saves nor repaints on its own: the chat switches it drives and
/// the importer it hands packages to do both.
class ChatPackager {
  ChatPackager(this._session, this._host, {required ChatImporter importer})
    : _importer = importer,
      _extras = PackageExtras(_session, _host);

  final ChatSessionState _session;
  final TransferHost _host;
  final ChatImporter _importer;
  final PackageExtras _extras;

  /// A `.porch` export or import is opening chats in turn. Not part of the
  /// turn-busy guard: the job's own chat moves must still run. It keeps a
  /// second job (desktop or phone) from flipping the shared chat under it.
  bool _movingChats = false;

  /// Export current chat as **SillyTavern JSONL** (one JSON object per line).
  /// Dialogue only — no FPAI stamps. Use [exportToFpchat] for a full package.
  ///
  /// Phase 2: real `.jsonl` rather than a single JSON wrapper so ST and other
  /// tools that expect JSONL chats can import without conversion.
  String? exportToSillyTavern() {
    if (_session.messages.isEmpty) return null;
    final personaName = _host.personas.persona.name.trim();
    final userName = personaName.isEmpty ? 'User' : personaName;
    final charName =
        _session.activeCharacter?.name ??
        _session.activeGroup?.name ??
        'Character';
    return encodeSillyTavernJsonl(
      List<ChatMessage>.from(_session.messages),
      userName: userName,
      characterName: charName,
    );
  }

  /// Export current chat as a `.fpchat` zip (full timeline). Returns null if empty.
  Future<Uint8List?> exportToFpchat() async {
    if (_session.messages.isEmpty) return null;
    if (_session.activeCharacter == null && _session.activeGroup == null) {
      return null;
    }

    final laneA = <Map<String, dynamic>>[];
    final extras = <Map<String, dynamic>>[];
    final images = <String, List<int>>{};

    for (var i = 0; i < _session.messages.length; i++) {
      final m = _session.messages[i];
      laneA.add(laneAMessage(m));
      extras.add(messagesExtraEntry(i, m));
      await collectFpchatMessageImage(m, images);
    }

    final char = _session.activeCharacter;
    final growth = await _extras.exportGrowth();
    final objectives = await _extras.exportObjectives();
    final group = _session.activeGroup;
    final fpai = <String, dynamic>{
      'version': 1,
      'kind': 'timeline',
      'app_version': appVersion,
      'schema_version': _host.db().schemaVersion,
      'stamp_version': kFpchatStampVersion,
      'character': {
        if (char != null) ...{
          'name': char.name,
          'stable_group_id': char.stableGroupId,
        },
        if (group != null) 'group_id': group.id,
        if (group != null) 'group_name': group.name,
      },
      'session': _host.captureSessionHead(),
      kFpchatCastKey: _captureCastForPackage(),
      'messages_extra': extras,
      'journal': await _extras.exportJournalCards(),
      if (growth.isNotEmpty) 'growth': growth,
      if (objectives.isNotEmpty) 'objectives': objectives,
    };

    final root = <String, dynamic>{
      'format': kFpchatFormatId,
      'version': kFpchatFormatVersion,
      'chat_metadata': {'note_prompt': '', 'note_interval': 0},
      'messages': laneA,
      'fpai': fpai,
    };

    // Encode off the UI isolate — large chats freezes the frame otherwise.
    // Copy into plain maps/lists so the isolate transfer is explicit and
    // failures surface as a normal exception to the export UI.
    final payload = Map<String, dynamic>.from(root);
    final imageCopy = <String, List<int>>{
      for (final e in images.entries) e.key: List<int>.from(e.value),
    };
    return Isolate.run(
      () => encodeFpchatZip(chatJson: payload, images: imageCopy),
    );
  }

  /// Thin `fpai.cast`: group roster (lite marked) or live 1:1 scene guests.
  /// Ids + name + tier only — no card blobs. 1:1 guests never rode
  /// `group_realism_state` in the package (that key is group-only).
  List<Map<String, dynamic>> _captureCastForPackage() {
    if (_session.activeGroup != null) {
      return [
        for (final c in _session.groupCharacters)
          encodeFpchatCastMember(
            id: _host.characterIdFor(c),
            name: c.name,
            lite: c.isLite,
          ),
      ];
    }
    return [
      for (final g in _host.sceneGuests.cards)
        encodeFpchatCastMember(
          id: _host.characterIdFor(g),
          name: g.name,
          lite: true,
        ),
    ];
  }

  /// Test hook: seed a transcript so [exportToFpchat] has something to pack.
  void debugSeedTranscript(List<ChatMessage> msgs) {
    _session.messages
      ..clear()
      ..addAll(msgs);
  }

  // ── Moving a character's chats ────────────────────────────────────────

  /// Claims the shared chat for one `.porch` job; false while another job
  /// holds it. Every true must be paired with [endMovingChats].
  bool tryBeginMovingChats() {
    if (_movingChats) return false;
    _movingChats = true;
    return true;
  }

  void endMovingChats() => _movingChats = false;

  /// Every 1:1 chat of [card] as an `.fpchat` package, newest first.
  ///
  /// The exporter reads the open chat, so this opens each one in turn.
  /// Throws [ChatImportBusy] when a turn is live: switching chats must never
  /// happen under a reply that is still streaming or settling.
  Future<List<Uint8List>> exportChatPackagesOf(CharacterCard card) async {
    if (_host.isTurnBusy()) throw ChatImportBusy();
    final sessions = await _host.sessionsFor(card.stableGroupId);
    if (sessions.isEmpty) return const [];
    // Kept in memory: each package is bounded by the codec's own unpacked
    // ceiling, and a typical character has a handful of chats.
    final packages = <Uint8List>[];
    await _host.setActiveCharacter(card);
    for (final s in sessions) {
      await _host.loadSession(s['id'] as String);
      final bytes = await exportToFpchat();
      if (bytes != null) packages.add(bytes);
    }
    return packages;
  }

  /// Restores [packages] (newest first, as [exportChatPackagesOf] lists
  /// them) onto [card] as new chats, oldest first, so the newest is the one
  /// left open. The packages name the exporting card, so the mismatch
  /// callback answers "continue": [card] IS that character, and the point is
  /// keeping the stamps. Returns how many came back with their full state.
  Future<int> importChatPackagesOnto(
    CharacterCard card,
    List<Uint8List> packages, {
    void Function(int done, int total)? onProgress,
  }) async {
    if (packages.isEmpty) return 0;
    final hadChats = (await _host.sessionsFor(card.stableGroupId)).isNotEmpty;
    await _host.setActiveCharacter(card);
    // A card with no chats opens on a greeting chat it saves on the spot.
    // Here that is only a side effect of opening the card to restore into
    // it, so it goes once the restored chats are in; otherwise it stays as an
    // extra "New Conversation" beside them.
    final opening = hadChats ? null : _session.currentSessionId;
    var restored = 0;
    for (final bytes in packages.reversed) {
      final result = await _importer.importChatPackage(
        bytes,
        onCharacterMismatch: (_, _) async => true,
      );
      if (result.fullRestore) restored++;
      onProgress?.call(restored, packages.length);
    }
    if (opening != null && opening != _session.currentSessionId) {
      await _host.deleteSessionQuietly(opening);
    }
    return restored;
  }

  /// Copies every chat of [from] onto [to]; returns how many were copied.
  ///
  /// Two phases with ONE active-card flip each way: export every session
  /// under [from], then import each package under [to]. The packages name
  /// the BASE character, so the importer's mismatch callback answers
  /// "continue" — the enhanced copy IS that character, and the whole point
  /// is keeping the stamps. Imports run oldest-first so the newest chat is
  /// the one left OPEN under [to] when the copy finishes — the user lands
  /// in the enhanced character exactly where they left the original.
  ///
  /// Throws [ChatImportBusy] when a turn is live (same contract as
  /// [ChatImporter.importChatPackage]); the caller owns surfacing that.
  Future<int> copyChatsForEnhance({
    required CharacterCard from,
    required CharacterCard to,
    void Function(int done, int total)? onProgress,
  }) async {
    // Guard BEFORE the export phase, not just inside importChatPackage:
    // phase 1 flips the active character/session, which must never happen
    // under a reply that is still streaming or settling.
    if (_host.isTurnBusy()) throw ChatImportBusy();
    // Same character on both sides would re-import every chat onto its own
    // owner — instant duplication. Unreachable from the wizard (the target
    // is always a fresh duplicate); this guards the web endpoint's
    // arbitrary ids.
    if (from.dbId != null && from.dbId == to.dbId) {
      throw ArgumentError('copyChatsForEnhance needs two different characters');
    }
    // Phase 1 — export under the base card; phase 2 — import under the
    // enhanced card, oldest first (see doc).
    final packages = await exportChatPackagesOf(from);
    return importChatPackagesOnto(to, packages, onProgress: onProgress);
  }
}
