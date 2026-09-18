// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of '../chat_service.dart';

/// `.fpchat` full timeline export/import I/O (Phase 1–2).
extension ChatServiceChatPackage on ChatService {
  /// Export current chat as a `.fpchat` zip (full timeline). Returns null if empty.
  Future<Uint8List?> exportToFpchat() async {
    if (_messages.isEmpty) return null;
    if (_activeCharacter == null && _activeGroup == null) return null;

    final laneA = <Map<String, dynamic>>[];
    final extras = <Map<String, dynamic>>[];
    final images = <String, List<int>>{};

    for (var i = 0; i < _messages.length; i++) {
      final m = _messages[i];
      laneA.add(laneAMessage(m));
      extras.add(messagesExtraEntry(i, m));
      await _collectMessageImages(m, images);
    }

    final char = _activeCharacter;
    final growth = await _exportGrowthForPackage();
    final objectives = await _exportObjectivesForPackage();
    final fpai = <String, dynamic>{
      'version': 1,
      'kind': 'timeline',
      'app_version': appVersion,
      'schema_version': _db.schemaVersion,
      'stamp_version': kFpchatStampVersion,
      'character': {
        if (char != null) ...{
          'name': char.name,
          'stable_group_id': char.stableGroupId,
        },
        if (_activeGroup != null) 'group_id': _activeGroup!.id,
        if (_activeGroup != null) 'group_name': _activeGroup!.name,
      },
      'session': _captureSessionHeadForPackage(),
      'messages_extra': extras,
      'journal': await _exportJournalCardsForPackage(),
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

  Future<void> _collectMessageImages(
    ChatMessage m,
    Map<String, List<int>> images,
  ) async {
    final md = m.activeMetadata;
    if (md == null) return;
    final imagePath = md['image_path'] as String?;
    if (imagePath == null || imagePath.isEmpty) return;
    try {
      final f = File(imagePath);
      if (await f.exists()) {
        final name = path.basename(imagePath);
        images[name] = await f.readAsBytes();
      }
    } catch (e) {
      debugPrint('[fpchat] skip image $imagePath: $e');
    }
  }

  Future<List<Map<String, dynamic>>> _exportJournalCardsForPackage() async {
    final sid = _currentSessionId;
    if (sid == null) return const [];
    final owners = <String>{
      if (_activeCharacter != null) _getCharacterIdFromCard(_activeCharacter!),
      for (final c in _groupCharacters) _getCharacterIdFromCard(c),
    }..removeWhere((e) => e.isEmpty);
    final out = <Map<String, dynamic>>[];
    for (final oid in owners) {
      final cards = await _journalStore.cardsFor(sid, oid);
      for (final c in cards) {
        List<int> sources = const [];
        final rawSources = c.sourceMessageIds;
        if (rawSources != null && rawSources.isNotEmpty) {
          try {
            final decoded = jsonDecode(rawSources);
            if (decoded is List) {
              sources = decoded.map((e) => (e as num).toInt()).toList();
            }
          } catch (_) {}
        }
        Map<String, dynamic>? metaMap;
        final rawMeta = c.metadata;
        if (rawMeta != null && rawMeta.isNotEmpty) {
          try {
            final decoded = jsonDecode(rawMeta);
            if (decoded is Map) {
              metaMap = Map<String, dynamic>.from(decoded);
            }
          } catch (_) {}
        }
        out.add({
          'character_id': c.characterId,
          'content': c.content,
          'category': c.category,
          'emotion_label': c.emotionLabel,
          'emotion_intensity': c.emotionIntensity,
          'source_message_ids': sources,
          'pinned': c.pinned,
          'heat': c.heat,
          'metadata': ?metaMap,
          'kind': JournalPhysics.cardKind(c),
        });
      }
    }
    return out;
  }
}
