// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Pure format helpers for the `.fpchat` dual-lane chat package.
///
/// Lane A: ST-friendly `messages` (name / is_user / mes).
/// Lane B: optional `fpai` suitcase with per-turn stamps + session head.
///
/// No I/O, no Flutter — unit-testable and safe for isolate decode.
library;

import 'dart:convert';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// On-disk / package format id.
const String kFpchatFormatId = 'fpai_chat';

/// Package container extension (zip of chat.json + images/).
const String kFpchatExtension = 'fpchat';

/// Logical JSON schema version for the outer envelope.
const int kFpchatFormatVersion = 1;

/// Version of the `realism_state` key contract. Bump when
/// [_captureRealismState] adds/removes keys that importers must understand.
const int kFpchatStampVersion = 1;

/// Keys written by ChatService._captureRealismState (plus optional needs).
/// Guard test must stay in sync — see fpchat_stamp_keys_test.dart.
const Set<String> kFpchatRealismStateCoreKeys = {
  'affectionScore',
  'relationshipTier',
  'longTermScore',
  'longTermTier',
  'turnsSinceLongTermCheck',
  'shortTermDeltasSummary',
  // From captureCadenceAndFeelings:
  'turnsSinceDecayCheck',
  'interCharacterRelationships',
  'characterEmotion',
  'emotionIntensity',
  'timeOfDay',
  'dayCount',
  'startDayOfWeek',
  'storyClock',
  'storyStartDate',
  'arousalLevel',
  'cooldownTurnsRemaining',
  'cooldownTurnsTotal',
  'trustLevel',
  'pendingTrustRepair',
  'activeFixation',
  'fixationLifespan',
  'spatialStance',
  'withUser',
  // Optional when present:
  'pockets',
  'needs',
};

/// Result of detecting an import payload.
enum FpchatPayloadKind {
  /// Full FPAI timeline (fpai block present and valid).
  fpaiTimeline,

  /// ST-ish single JSON with messages[] only.
  sillyTavernIsh,

  unknown,
}

/// Detect payload kind from decoded JSON (not zip).
FpchatPayloadKind detectFpchatPayload(Map<String, dynamic> root) {
  final fpai = root['fpai'];
  if (fpai is Map) {
    final v = fpai['version'];
    if (v is int && v >= 1) return FpchatPayloadKind.fpaiTimeline;
    if (v is num && v.toInt() >= 1) return FpchatPayloadKind.fpaiTimeline;
  }
  if (root['format'] == kFpchatFormatId && root['messages'] is List) {
    // Envelope without fpai → still our format, transcript-ish.
    return FpchatPayloadKind.sillyTavernIsh;
  }
  // Covers ST-ish single JSON and JSONL-normalized roots.
  if (root['messages'] is List) return FpchatPayloadKind.sillyTavernIsh;
  return FpchatPayloadKind.unknown;
}

/// Build Lane A message map from a [ChatMessage] (ST-friendly).
Map<String, dynamic> laneAMessage(ChatMessage m) => {
  'name': m.sender,
  'is_user': m.isUser,
  'mes': m.text,
  'send_date': DateTime.now().millisecondsSinceEpoch,
};

/// SillyTavern chat JSONL — one JSON object per line (Phase 2).
///
/// First optional header line may carry user/character names without `mes`.
/// Message lines use `name` / `is_user` / `mes` (and optional swipes).
String encodeSillyTavernJsonl(
  List<ChatMessage> messages, {
  String userName = 'User',
  String characterName = 'Character',
}) {
  final buf = StringBuffer();
  final created = DateTime.now().millisecondsSinceEpoch;
  buf.writeln(
    jsonEncode({
      'user_name': userName,
      'character_name': characterName,
      'create_date': created,
    }),
  );
  for (var i = 0; i < messages.length; i++) {
    final m = messages[i];
    // Interop lane: strip think-blocks so ST does not show monologues.
    // (Full .fpchat keeps raw text for honest FPAI round-trip.)
    final cleanMes = stripThinkTags(m.text);
    final cleanSwipes = [for (final s in m.swipes) stripThinkTags(s)];
    final line = <String, dynamic>{
      'name': m.sender,
      'is_user': m.isUser,
      'mes': cleanMes,
      'send_date': created + i,
      'extra': <String, dynamic>{},
    };
    if (cleanSwipes.length > 1) {
      line['swipes'] = cleanSwipes;
      final idx = m.swipeIndex.clamp(0, cleanSwipes.length - 1);
      line['swipe_id'] = idx;
      line['mes'] = cleanSwipes[idx];
    }
    buf.writeln(jsonEncode(line));
  }
  return buf.toString();
}

/// Parse ST JSONL (or return null if this is not multi-line ST chat JSONL).
///
/// On success returns a root map with `messages` list suitable for
/// [messagesFromPackage] / [detectFpchatPayload].
Map<String, dynamic>? tryParseSillyTavernJsonl(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  // Single JSON object with messages[] is the Phase-1 ST-ish form — not JSONL.
  if (!trimmed.contains('\n')) return null;

  final lines = trimmed.split(RegExp(r'\r?\n'));
  final msgs = <Map<String, dynamic>>[];
  String? userName;
  String? charName;
  var parsed = 0;

  for (final line in lines) {
    final t = line.trim();
    if (t.isEmpty) continue;
    if (!t.startsWith('{')) return null;
    Map<String, dynamic> obj;
    try {
      final d = jsonDecode(t);
      if (d is! Map) return null;
      obj = Map<String, dynamic>.from(d);
    } catch (_) {
      return null;
    }
    parsed++;
    final hasMes = obj.containsKey('mes') || obj.containsKey('message');
    final looksHeader =
        !hasMes &&
        (obj.containsKey('user_name') ||
            obj.containsKey('character_name') ||
            obj.containsKey('chat_metadata'));
    if (looksHeader) {
      userName = obj['user_name'] as String? ?? userName;
      charName = obj['character_name'] as String? ?? charName;
      continue;
    }
    if (!hasMes) continue;
    final mes = (obj['mes'] ?? obj['message'] ?? '').toString();
    final name = (obj['name'] ?? obj['send_name'] ?? '').toString();
    final isUser =
        obj['is_user'] == true ||
        obj['isUser'] == true ||
        (obj['is_name'] == true &&
            name.toLowerCase() == (userName ?? 'user').toLowerCase());
    final entry = <String, dynamic>{
      'name': name.isEmpty
          ? (isUser ? (userName ?? 'User') : (charName ?? 'Char'))
          : name,
      'is_user': isUser,
      'mes': mes,
      'send_date': ?obj['send_date'],
    };
    // Carry ST swipes when present so reimport / ST tools keep alternates.
    final swipes = obj['swipes'];
    if (swipes is List && swipes.isNotEmpty) {
      entry['swipes'] = swipes.map((e) => e.toString()).toList();
      entry['swipe_id'] = (obj['swipe_id'] as num?)?.toInt() ?? 0;
    }
    msgs.add(entry);
  }
  if (parsed < 2 || msgs.isEmpty) return null;
  return {'messages': msgs};
}

/// Build messages_extra entry for index [i].
Map<String, dynamic> messagesExtraEntry(int i, ChatMessage m) {
  final map = <String, dynamic>{
    'i': i,
    'swipes': List<String>.from(m.swipes),
    'swipe_index': m.swipeIndex,
    'swipe_durations': List<int>.from(m.swipeDurations),
  };
  if (m.characterId != null) map['character_id'] = m.characterId;
  if (m.metadata != null) {
    map['metadata'] = Map<String, dynamic>.from(m.metadata!);
  }
  if (m.swipeMetadata.any((e) => e != null)) {
    map['swipe_metadata'] = m.swipeMetadata
        .map((e) => e != null ? Map<String, dynamic>.from(e) : null)
        .toList();
  }
  return map;
}

/// Rebuild [ChatMessage] list from Lane A + optional messages_extra.
List<ChatMessage> messagesFromPackage({
  required List<dynamic> laneA,
  List<dynamic>? extras,
}) {
  final byIndex = <int, Map<String, dynamic>>{};
  if (extras != null) {
    for (final e in extras) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      final i = (m['i'] as num?)?.toInt();
      if (i != null) byIndex[i] = m;
    }
  }

  final out = <ChatMessage>[];
  for (var i = 0; i < laneA.length; i++) {
    final raw = laneA[i];
    if (raw is! Map) continue;
    final a = Map<String, dynamic>.from(raw);
    final extra = byIndex[i];
    final text = (a['mes'] ?? a['text'] ?? '').toString();
    final sender = (a['name'] ?? a['sender'] ?? '').toString();
    final isUser = a['is_user'] == true || a['isUser'] == true;

    if (extra != null) {
      final swipes =
          (extra['swipes'] as List?)?.map((e) => e.toString()).toList() ??
          [text];
      final durations =
          (extra['swipe_durations'] as List?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          List<int>.filled(swipes.length, 0);
      final swipeMeta = (extra['swipe_metadata'] as List?)
          ?.map((e) => e != null ? Map<String, dynamic>.from(e as Map) : null)
          .toList();
      out.add(
        ChatMessage(
          text: text,
          sender: sender,
          isUser: isUser,
          characterId:
              extra['character_id'] as String? ?? a['character_id'] as String?,
          swipes: swipes,
          swipeIndex: (extra['swipe_index'] as num?)?.toInt() ?? 0,
          swipeDurations: durations,
          metadata: extra['metadata'] != null
              ? Map<String, dynamic>.from(extra['metadata'] as Map)
              : null,
          swipeMetadata: swipeMeta,
        ),
      );
    } else {
      // Lane-A-only (JSONL / ST-ish): honour swipes when the line carries them.
      final swipesRaw = a['swipes'];
      if (swipesRaw is List && swipesRaw.isNotEmpty) {
        final swipes = swipesRaw.map((e) => e.toString()).toList();
        final idx = ((a['swipe_id'] ?? a['swipe_index']) as num?)?.toInt() ?? 0;
        final safe = idx.clamp(0, swipes.length - 1);
        out.add(
          ChatMessage(
            text: swipes[safe],
            sender: sender,
            isUser: isUser,
            swipes: swipes,
            swipeIndex: safe,
            swipeDurations: List<int>.filled(swipes.length, 0),
          ),
        );
      } else {
        out.add(ChatMessage(text: text, sender: sender, isUser: isUser));
      }
    }
  }
  return out;
}

Map<String, dynamic> decodeChatJson(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! Map) {
    throw FormatException('chat.json root must be an object');
  }
  return Map<String, dynamic>.from(decoded);
}
