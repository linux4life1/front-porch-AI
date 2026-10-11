// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Per-reply prompt record: the Context Viewer snapshot of the send that
// produced a reply, stored on that swipe's metadata so the user can inspect
// any reply, not only the last one.

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/context_viewer_snapshot.dart';

/// Swipe-metadata key holding a [ContextViewerSnapshot.toJson] map.
const kReplyContextKey = 'context_snapshot';

/// How many of the most recent stamped replies keep their full section text.
/// Older ones keep only token counts (a long context is ~100 KB of text).
const kReplyContextTextKeep = 20;

/// The prompt record of the swipe [m] is showing, or null when none was kept.
ContextViewerSnapshot? replyContextOf(ChatMessage m) =>
    ContextViewerSnapshot.tryParse(m.activeMetadata?[kReplyContextKey]);

/// Drops section text from every stamped swipe older than the [keep] most
/// recent. Token counts stay. Shared map instances (a message's legacy
/// `metadata` aliasing `swipeMetadata[0]`, a regen copy sharing the record)
/// count once.
void trimReplyContextTexts(
  List<ChatMessage> messages, {
  int keep = kReplyContextTextKeep,
}) {
  final seenMeta = Set<Map>.identity();
  final seenRecord = Set<Map>.identity();
  final replaced = Map<Map, Map<String, dynamic>>.identity();
  var kept = 0;
  for (var i = messages.length - 1; i >= 0; i--) {
    final m = messages[i];
    final metas = [...m.swipeMetadata.reversed, m.metadata];
    for (final meta in metas) {
      if (meta == null || !seenMeta.add(meta)) continue;
      final record = meta[kReplyContextKey];
      if (record is! Map) continue;
      final already = replaced[record];
      if (already != null) {
        meta[kReplyContextKey] = already;
        continue;
      }
      if (!seenRecord.add(record)) continue;
      if (kept < keep) {
        kept++;
        continue;
      }
      final sections = record['sections'];
      if (sections is! Map || sections.isEmpty) continue;
      final trimmed = Map<String, dynamic>.from(record)..remove('sections');
      replaced[record] = trimmed;
      meta[kReplyContextKey] = trimmed;
    }
  }
}
