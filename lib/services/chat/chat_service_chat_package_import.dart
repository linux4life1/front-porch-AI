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

/// `.fpchat` import. Export stays on [ChatServiceChatPackage].
extension ChatServiceChatPackageImport on ChatService {
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
    if (_activeCharacter == null && _activeGroup == null) {
      throw Exception('No active character or group');
    }
    if (_isTurnBusy) throw ChatImportBusy();
    _isImporting = true;
    try {
      if (testImportHold != null) await testImportHold!.future;
      return await _importChatPackageBody(bytes, onCharacterMismatch);
    } finally {
      _isImporting = false;
    }
  }

  Future<({bool fullRestore, String? warning})> _importChatPackageBody(
    Uint8List bytes,
    Future<bool> Function(String packageName, String activeName)?
    onCharacterMismatch,
  ) async {
    // Preserve the currently open chat before replacing in-memory messages.
    if (_currentSessionId != null && _messages.isNotEmpty) {
      await _saveChat();
    }

    // Stale unauthored RtR from a prior opening must not paint this import.
    // _isTurnBusy does not wait _isProcessingGreeting, so a delayed eval
    // is still in flight when the package transcript replaces first_mes.
    await _invalidateGreetingEval();

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
        final openIsGroup = _activeGroup != null;

        if (openIsGroup && !pkgIsGroup) {
          full = false;
          warning =
              'Package is a 1:1 export; open group is "${_activeGroup!.name}" '
              '— importing dialogue only.';
        } else if (!openIsGroup && pkgIsGroup) {
          full = false;
          warning =
              'Package is a group export'
              '${pkgChar['group_name'] != null ? ' ("${pkgChar['group_name']}")' : ''}'
              '; open chat is 1:1 — importing dialogue only.';
        } else if (openIsGroup &&
            pkgIsGroup &&
            pkgGroupId != _activeGroup!.id) {
          full = false;
          warning =
              'Package was exported for group '
              '"${pkgChar['group_name'] ?? pkgGroupId}" but open group is '
              '"${_activeGroup!.name}" — importing dialogue only.';
        } else if (!openIsGroup && _activeCharacter != null && !pkgIsGroup) {
          final activeId = _activeCharacter!.stableGroupId;
          final mismatch =
              (pkgId.isNotEmpty && pkgId != activeId) ||
              (pkgName.isNotEmpty &&
                  pkgName.toLowerCase() !=
                      _activeCharacter!.name.toLowerCase());
          if (mismatch && onCharacterMismatch != null) {
            final cont = await onCharacterMismatch(
              pkgName.isEmpty ? pkgId : pkgName,
              _activeCharacter!.name,
            );
            if (!cont) {
              full = false;
              warning = 'Character mismatch — transcript only.';
            }
          } else if (mismatch) {
            warning =
                'Package was exported for "$pkgName" but active card is '
                '"${_activeCharacter!.name}". Restoring stamps anyway.';
          }
          if (full && pkgId.isNotEmpty && pkgId != activeId) {
            ownerRemapFrom = pkgId;
          }
        }
      }
    }

    // Phase 0: seed card defaults so save never bleeds prior live state.
    await _seedLiveRealismForImportedSession();

    final extras = full && fpai != null
        ? fpai['messages_extra'] as List?
        : null;
    final msgs = messagesFromPackage(laneA: laneA, extras: extras);

    // Mint session id BEFORE materializing images so paths land under it.
    _currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();
    if (full && decoded.images.isNotEmpty) {
      await _materializePackageImages(msgs, decoded.images);
    }

    _messages
      ..clear()
      ..addAll(msgs);
    // Imported history is not a virgin chat — RAG retrieval must not skip.
    _isNewChat = _messages.isEmpty;
    _computeAbsenceGap(const []);
    await _seedChatWorldsForNewSession();

    if (full && fpai != null) {
      final session = fpai['session'] is Map
          ? Map<String, dynamic>.from(fpai['session'] as Map)
          : null;
      if (session != null) {
        await _applySessionHeadFromPackage(session);
      } else if (_messages.isNotEmpty) {
        await _restoreRealismStateWalkingBack(fromIndex: _messages.length - 1);
      }
      final remapTo = ownerRemapFrom == null
          ? null
          : _getCharacterIdFromCard(_activeCharacter!);
      // Journal cards (Phase 1)
      final journal = fpai['journal'] as List?;
      if (journal != null) {
        await _importJournalCardsFromPackage(
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
        await _importGrowthFromPackage(growth);
      }
      final objectives = fpai['objectives'] as List?;
      if (objectives != null) {
        await _importObjectivesFromPackage(
          _rekeyPackageOwners(objectives, ownerRemapFrom, remapTo),
        );
      }
    } else {
      // Transcript-only: journal cursor caught up, blank memory (no thrash).
      _summary = '';
      _summaryLastIndex = _messages.length;
    }

    await _saveChat();
    unawaited(_scheduleRagBackfillAfterImport());
    notifyListeners();
    return (fullRestore: full, warning: warning);
  }

  Future<void> _materializePackageImages(
    List<ChatMessage> msgs,
    Map<String, List<int>> images,
  ) async {
    if (images.isEmpty) return;
    final igs = _imageGenService;
    final sid = _currentSessionId ?? 'import';
    var seq = 0;
    for (final m in msgs) {
      final md = m.activeMetadata;
      if (md == null) continue;
      final old = md['image_path'] as String?;
      if (old == null) continue;
      final base = path.basename(old);
      final raw = images[base];
      if (raw == null) continue;
      final bytes = Uint8List.fromList(raw);
      seq++;
      // Strip prior fpchat_ prefixes; cap stem + keep extension (Windows MAX_PATH).
      final cleanBase = stripFpchatImagePrefixes(base);
      final preferred = cappedFpchatImageName(sid, seq, cleanBase);
      String? dest;
      if (igs != null) {
        dest = await igs.saveImageToDisk(bytes, preferred);
      }
      if (dest == null) {
        final dir = Directory(
          path.join(_storageService.chatsDir.path, 'images'),
        );
        await dir.create(recursive: true);
        dest = path.join(dir.path, preferred);
        var n = 1;
        while (await File(dest!).exists()) {
          dest = path.join(
            dir.path,
            cappedFpchatImageName(sid, seq, cleanBase, collision: n),
          );
          n++;
        }
        await File(dest).writeAsBytes(bytes, flush: true);
      }
      md['image_path'] = dest;
      m.activeMetadata = md;
    }
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

  Future<void> _importJournalCardsFromPackage(List<dynamic> journal) async {
    final sid = _currentSessionId;
    if (sid == null) return;
    final maxCards = _storageService.memorySettings.journalMaxCards;
    for (final raw in journal) {
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      final cid = (m['character_id'] as String? ?? '').trim();
      final content = (m['content'] as String? ?? '').trim();
      if (cid.isEmpty || content.isEmpty) continue;
      final sources =
          (m['source_message_ids'] as List?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          const <int>[];
      final heat = (m['heat'] as num?)?.toDouble();
      final pinned = m['pinned'] == true;
      await _journalStore.addCard(
        sessionId: sid,
        characterId: cid,
        content: content,
        category: m['category'] as String? ?? 'moment',
        emotionLabel: m['emotion_label'] as String?,
        emotionIntensity: m['emotion_intensity'] as String?,
        sourcePositions: sources,
        kind: m['kind'] as String?,
        heat: heat,
        pinned: pinned,
        maxCards: maxCards,
        extraMetadata: m['metadata'] is String
            ? null
            : (m['metadata'] is Map
                  ? Map<String, dynamic>.from(m['metadata'] as Map)
                  : null),
      );
    }
  }

  /// Kick existing MemoryService window backfill after import (fire-and-forget).
  ///
  /// Chunks one window at a time with an `_isGenerating` re-check so a Send
  /// never sits behind hundreds of import embeds on the ONNX FIFO queue.
  /// Works for 1:1 and group via [_getCharacterId] (group bucket).
  ///
  /// Contract: if the whole backfill is paused for generation, remaining
  /// windows stay missing until this loop resumes or the live post-gen path
  /// fills gaps (idempotent). Half-embedded is safe — never blocks Send.
  Future<void> _scheduleRagBackfillAfterImport() async {
    final sid = _currentSessionId;
    final mem = _memoryService;
    if (sid == null || mem == null) return;
    if (!mem.isOperational) return;
    final charId = _getCharacterId();
    if (charId.isEmpty) return;

    await _awaitHistoryHydrated();
    if (_currentSessionId != sid) return;
    final formatted = _formatMessagesForRagEmbedding(_messages);
    final offset = _history.basePosition;
    // Bound wall-clock work: each successful window resets stall; null-embed
    // / abort only retry a limited number of times so we never busy-spin the
    // event loop (Muse review of 03d46d9a).
    var stallStreak = 0;
    const maxStall = 40;
    for (var i = 0; i < 50000; i++) {
      // User left this chat / imported another — stop writing orphans.
      if (_currentSessionId != sid) {
        debugPrint(
          '[fpchat] RAG backfill stopped — session changed away from $sid',
        );
        return;
      }
      if (_isGenerating) {
        stallStreak++;
        if (stallStreak > maxStall) {
          debugPrint(
            '[fpchat] RAG backfill paused for generation too long — '
            'leaving remaining windows for live catch-up',
          );
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 400));
        continue;
      }
      try {
        final pass = await mem.embedMessageWindow(
          sessionId: sid,
          characterId: charId,
          formattedMessages: formatted,
          totalMessageCount: formatted.length,
          positionOffset: offset,
          maxWindows: 1,
          shouldContinue: () => !_isGenerating && _currentSessionId == sid,
        );
        if (pass.aborted) {
          stallStreak++;
          if (stallStreak > maxStall) return;
          await Future<void>.delayed(const Duration(milliseconds: 400));
          continue;
        }
        if (!pass.hasMore) return;
        if (pass.stored == 0) {
          // Null embed / skip — backoff, do not Duration.zero spin.
          stallStreak++;
          if (stallStreak > maxStall) {
            debugPrint(
              '[fpchat] RAG backfill giving up after repeated empty passes',
            );
            return;
          }
          await Future<void>.delayed(const Duration(milliseconds: 200));
          continue;
        }
        stallStreak = 0;
      } catch (e) {
        debugPrint('[fpchat] RAG backfill after import failed: $e');
        return;
      }
      // ~one frame — enough yield without starving the event loop.
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
  }

  /// Test hook: live `_captureRealismState` key set for stamp-contract guards.
  @visibleForTesting
  Map<String, dynamic> debugCaptureRealismStateForFpchat() =>
      _captureRealismState();
}
