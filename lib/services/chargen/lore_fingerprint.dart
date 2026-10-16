// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Which lorebook entries the user changed by hand. The generator stamps each
// entry it writes with a fingerprint of its text in the entry's free
// `extensions` map (which already round-trips the database and card files);
// an entry whose text no longer matches is the user's, and a rewrite keeps
// it. An entry with no stamp counts as hand-edited too: if some path drops
// the map, nothing the user wrote is lost.

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:front_porch_ai/models/models.dart';

/// Key in `LorebookEntry.extensions` holding the generated text's sha1.
const kLoreGeneratedKey = 'fp_generated';

/// The sha1 of [entry]'s name, keys and content.
String loreEntryFingerprint(LorebookEntry entry) => sha1
    .convert(utf8.encode(jsonEncode([entry.name, entry.keys, entry.content])))
    .toString();

/// Stamp every entry of [book] as written by the generator, as it is now.
void stampLoreFingerprints(Lorebook? book) {
  if (book == null) return;
  for (final e in book.entries) {
    e.extensions = {
      ...e.extensions,
      kLoreGeneratedKey: loreEntryFingerprint(e),
    };
  }
}

/// Whether [entry] is not the generator's text as it wrote it.
bool isHandEdited(LorebookEntry entry) =>
    entry.extensions[kLoreGeneratedKey] != loreEntryFingerprint(entry);

/// [generated] in place of [current]'s generated entries. Hand-edited
/// entries stay where they are; each generated entry the rewrite dropped
/// gives its slot to the next new one, and the rest follow at the end. A new
/// entry named like a kept one, or a second always-on premise, is left out.
/// [current]'s book settings (scan depth, budget, recursion, extensions)
/// are kept.
Lorebook mergeRewrittenLorebook({
  required Lorebook current,
  required Lorebook generated,
}) {
  final kept = current.entries.where(isHandEdited).toList();
  final keptNames = {for (final e in kept) e.name.trim().toLowerCase()};
  final keptAnchor = kept.any((e) => e.constant);
  final fresh = generated.entries
      .where(
        (e) =>
            !keptNames.contains(e.name.trim().toLowerCase()) &&
            !(keptAnchor && e.constant),
      )
      .iterator;
  final out = <LorebookEntry>[];
  for (final e in current.entries) {
    if (isHandEdited(e)) {
      out.add(e);
    } else if (fresh.moveNext()) {
      out.add(fresh.current);
    }
  }
  while (fresh.moveNext()) {
    out.add(fresh.current);
  }
  return Lorebook(
    entries: out,
    scanDepth: current.scanDepth,
    tokenBudget: current.tokenBudget,
    recursiveScanning: current.recursiveScanning,
    extensions: Map<String, dynamic>.from(current.extensions),
  );
}
