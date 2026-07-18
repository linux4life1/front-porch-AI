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

import 'package:front_porch_ai/models/chat_message.dart';
import 'package:front_porch_ai/database/database.dart';

import 'growth_physics.dart';
import 'journal_prompt.dart' show salienceLineOf;

/// Growth Rings — pass prompt building (pure functions, all context passed
/// in; the journal_prompt.dart pattern).
///
/// One prompt, two closing format sections: XML-tag instructions (default,
/// any model) or tool-calling instructions ([toolsMode], for backends that
/// accept the kGrowthTools schemas). Everything above the format section is
/// byte-identical between transports, so the two paths can never drift in
/// what the model is told.
///
/// Distill mode (design §8): when [legacyBlob] is non-empty the prompt also
/// shows the previously-accumulated evolved text and asks the model to
/// distill the DIFFERENCE from the original personality into starter rings —
/// the one-time migration off the old rewrite system.

/// How much of the base personality the prompt shows (context anchor so the
/// model never re-states original traits as "growth").
const int kGrowthBaseCap = 1200;

/// Max hot journal cards shown for grounding.
const int kGrowthJournalCardCap = 8;

/// Starter rings the distill migration asks for.
const int kDistillMaxRings = 6;

String buildGrowthPrompt({
  required String ownerName,
  required String userName,
  required String basePersonality,
  required String recap,
  required List<GrowthRingData> activeRings,
  required List<JournalMemoryData> journalCards,
  required List<ChatMessage> window,
  required int windowStart,
  required String legacyBlob,
  required bool toolsMode,
}) {
  final distill = legacyBlob.trim().isNotEmpty;
  final b = StringBuffer();

  b.writeln(
    'You track how $ownerName — a roleplay character — is growing and '
    'changing through their story with $userName. Below are '
    '$ownerName\'s core personality, the growth rings recorded so far, and '
    'what has happened since the last check. Update the growth record.',
  );
  b.writeln();

  b.writeln('$ownerName\'s core personality (fixed — never restate it as growth):');
  b.writeln(_trimTo(basePersonality, kGrowthBaseCap));
  b.writeln();

  if (recap.isNotEmpty) {
    b.writeln('Where the story stands:');
    b.writeln(recap);
    b.writeln();
  }

  b.writeln('Current growth rings:');
  if (activeRings.isEmpty) {
    b.writeln('(none yet)');
  } else {
    for (var i = 0; i < activeRings.length; i++) {
      final r = activeRings[i];
      b.writeln(
        '[${i + 1}] (${r.category}, ${GrowthPhysics.tierOf(r)}'
        '${r.pinned ? ', pinned' : ''}) ${r.content}',
      );
    }
  }
  b.writeln();

  if (distill) {
    b.writeln(
      'Previously accumulated growth (recorded under an older system, now '
      'being converted to rings):',
    );
    b.writeln(legacyBlob.trim());
    b.writeln();
    b.writeln(
      'FIRST: compare that accumulated growth against the core personality '
      'above and distill the DIFFERENCE — the ways $ownerName actually '
      'changed — into at most $kDistillMaxRings new rings. Skip anything '
      'already true in the core personality.',
    );
    b.writeln();
  }

  if (journalCards.isNotEmpty) {
    b.writeln('$ownerName\'s recent journal entries (for grounding):');
    for (final c in journalCards.take(kGrowthJournalCardCap)) {
      b.writeln('- ${c.content}');
    }
    b.writeln();
  }

  b.writeln('New events since the last check:');
  for (var i = 0; i < window.length; i++) {
    final m = window[i];
    if (m.characterId == '__director__') continue;
    b.writeln('#${windowStart + i} ${m.sender}: ${m.displayText}');
    final salience = salienceLineOf(m);
    if (salience != null) b.writeln('    ($salience)');
  }
  b.writeln();

  b.writeln('Rules:');
  b.writeln(
    '- A ring is a DURABLE change in who $ownerName is — a shifted trait, a '
    'new stance toward $userName, a formed habit, a learned skill, or a '
    'lasting scar. One-off events belong in the journal, not here.',
  );
  b.writeln(
    '- Prefer reinforcing an existing ring that showed up again over adding '
    'a near-duplicate. Retire a ring these events contradicted or that '
    '$ownerName has outgrown.',
  );
  b.writeln(
    '- Each ring is one sentence, third person, at most 30 words, using '
    '{{char}} for $ownerName and {{user}} for $userName. '
    '${toolsMode ? 'Cite the message numbers that show it in src.' : 'Cite the message numbers that show it with src="...".'}',
  );
  b.writeln(
    '- Categories: trait (who they are), stance (how they relate to '
    '$userName), habit, skill, scar (lasting mark from a painful event).',
  );
  b.writeln(
    '- Add at most ${distill ? kDistillMaxRings : GrowthPhysics.kMaxNewRingsPerPass} '
    'new ring(s). If nothing durable changed, emit nothing at all — most '
    'checks should find no new growth.',
  );

  if (toolsMode) {
    b.writeln(
      '- Use ONLY the provided tools (add_ring, reinforce_ring, revise_ring, '
      'retire_ring). No plain-text reply. If there is nothing to record, '
      'call no tools.',
    );
  } else {
    b.writeln('- Emit only the tags below. No other commentary.');
    b.writeln();
    b.writeln('Format — one tag per operation:');
    b.writeln(
      '<ring action="add" category="stance" src="12,14">third-person '
      'ring text</ring>',
    );
    b.writeln('<ring action="reinforce" id="3" src="18"/>');
    b.writeln('<ring action="revise" id="3">replacement text</ring>');
    b.writeln('<ring action="retire" id="2"/>');
  }

  return b.toString();
}

/// The [Character Growth] injection block for one owner — deterministic
/// tier-prefixed lines, strongest first, budget-capped (design §4.5). Empty
/// string when there is nothing to inject. When a [legacyBlob] is still
/// waiting to be distilled it is injected as the growth text instead (no
/// behavior cliff mid-migration).
String buildGrowthInjection({
  required String charName,
  required List<GrowthRingData> activeRings,
  required String legacyBlob,
}) {
  if (legacyBlob.trim().isNotEmpty) {
    return '\n\n[Character Growth — the following reflects how $charName has '
        'changed through interactions. These traits build on the original '
        'personality above.]\n${legacyBlob.trim()}';
  }
  if (activeRings.isEmpty) return '';
  final shown = GrowthPhysics.injectionSelection(activeRings);
  final lines = shown.map(
    (r) => '- ${GrowthPhysics.injectionLine(r, charName: charName)}',
  );
  return '\n\n[Character Growth — how $charName has changed through this '
      'story. These build on the original personality above; the plainly '
      'stated ones are settled parts of who $charName is now.]\n'
      '${lines.join('\n')}';
}

String _trimTo(String text, int cap) {
  final t = text.trim();
  if (t.length <= cap) return t;
  return '${t.substring(0, cap).trim()}…';
}
