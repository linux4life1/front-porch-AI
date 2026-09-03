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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/database/database.dart';
import 'journal_physics.dart';

/// Recap length instruction (words). The recap must stay plain prose —
/// the growth pass and the prompt summaryBlock consume it directly.
const int kRecapMaxWords = 200;

/// Prompt-side ask for new memories per pass. Verbose models (GLM-5.2 on
/// Nano-GPT planted ~40 adds per pass) blow the 4000-token response budget.
/// The recap is now instructed FIRST (see the ordering comment in the
/// format section) so a blown budget costs trailing memory beats instead
/// of decapitating the recap; this cap remains the first line of defense
/// that keeps passes inside budget at all.
const int kJournalMaxNewMemories = 6;

/// The Journal — maintenance-pass prompt building (extracted from
/// journal_maintenance.dart so that file stays under the size cap; pure
/// functions, all context passed in).
///
/// One prompt, two closing format sections: the XML-tag instructions
/// (default, any model) or the tool-calling instructions ([toolsMode], for
/// backends that accept the kJournalTools schemas). Everything above the
/// format section — recap, numbered card handles, the salience-annotated
/// window, the rules — is byte-identical between transports, so the two
/// paths can never drift in what the model is told.
String buildJournalPrompt({
  required String ownerName,
  required String userName,
  required String recap,
  required List<JournalMemoryData> cards,
  required List<ChatMessage> window,
  required int windowStart,
  required bool includeRecap,
  required bool toolsMode,
}) {
  final b = StringBuffer();

  b.writeln(
    'You are $ownerName. You privately keep a journal about this '
    'conversation with $userName. Below are your current journal entries '
    'and what has happened since you last wrote. Update your journal.',
  );
  b.writeln();

  b.writeln('Your current recap of where things stand:');
  b.writeln(recap.isEmpty ? '(you have not written a recap yet)' : recap);
  b.writeln();

  b.writeln('Your current journal entries:');
  if (cards.isEmpty) {
    b.writeln('(none yet)');
  } else {
    for (var i = 0; i < cards.length; i++) {
      final c = cards[i];
      final feeling = c.emotionLabel == null ? '' : ', felt ${c.emotionLabel}';
      b.writeln(
        '[${i + 1}] (${c.category}$feeling'
        '${c.pinned ? ', pinned' : ''}'
        '${JournalPhysics.isPassLockedCard(c) ? ', locked' : ''}) '
        '${c.content}',
      );
    }
  }
  b.writeln();

  b.writeln('New events since you last wrote:');
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
    '- Edit in place: add new entries, revise entries that changed, retire '
    'entries that became wrong or irrelevant. Never restate an existing '
    'entry as a new one — revise it instead. Do not retire or rewrite '
    'locked entries (calendar birthdays, item placements, promises and '
    'milestones) — those are written by the app, not remembered as plot.',
  );
  b.writeln(
    '- Capture what mattered: add a memory for each promise made, thing '
    'learned about $userName, relationship shift, or moment that stood out — '
    'the annotated lines above are the significant beats. If there are more '
    'beats than the cap below allows, keep the most important and let the '
    'rest wait. Skip idle small talk, but do not finish a pass with no new '
    'memory when something worth remembering happened.',
  );
  b.writeln(
    '- Add at most $kJournalMaxNewMemories new memories in this update — '
    'pick the beats that mattered most; the rest can wait for your next '
    'entry.',
  );
  b.writeln(
    '- Each memory is one sentence, first person, at most 40 words. '
    '${toolsMode ? 'Reference the message numbers it came from in msgs.' : 'Cite the message numbers it came from with msgs="...".'}',
  );
  b.writeln(
    '- Categories: about_user (things learned about $userName), about_us '
    '(the relationship), moment (something that happened), promise.',
  );

  // RECAP FIRST in both transports (2026-08-10). The recap used to be
  // instructed LAST, so whenever a busy pass hit the response budget the
  // truncation decapitated exactly the recap — ops landed, "Where we are"
  // stayed stale, and the maintenance warning fired ("pass produced ops but
  // NO recap"), live in the maintainer's own log. Truncation has to cost
  // SOMETHING; ordering chooses the cheaper casualty: a lost trailing
  // memory is one one-sentence beat, while the lost recap is the per-turn
  // "Where we are" the prompt and the growth pass read — and a pass that
  // produced ops advances the cursor, so neither victim gets a retry.
  // Both parsers are order-independent, so only the instruction moves.
  if (toolsMode) {
    b.writeln(
      '- Use ONLY the provided tools (add_memory, revise_memory, '
      'retire_memory, pin_memory'
      '${includeRecap ? ', write_recap' : ''}). No plain-text reply.',
    );
    b.writeln();
    if (includeRecap) {
      b.writeln(
        'Start with exactly one write_recap call: where things stand now — '
        'present tense, your voice, at most $kRecapMaxWords words. Never '
        'skip the write_recap call, even when you add few or no memories. '
        'Then add your memories with add_memory.',
      );
    } else {
      b.writeln('Do not call write_recap.');
    }
  } else {
    b.writeln('- Emit only the tags below. No other commentary.');
    b.writeln();
    b.writeln('Format — one tag per operation:');
    if (includeRecap) {
      b.writeln(
        '<recap>Where things stand now — present tense, your voice, at most '
        '$kRecapMaxWords words.</recap>',
      );
    }
    b.writeln(
      '<memory action="add" category="moment" msgs="12,14">first-person '
      'memory text</memory>',
    );
    b.writeln(
      '<memory action="revise" id="3" feeling="proud">replacement '
      'text</memory>',
    );
    b.writeln('<memory action="retire" id="2"/>');
    b.writeln('<memory action="pin" id="5"/>');
    if (includeRecap) {
      b.writeln();
      b.writeln(
        'Open with exactly one <recap> tag, then write your <memory> tags. '
        'Never skip the recap, even when you add few or no memories.',
      );
    } else {
      b.writeln();
      b.writeln('Do not write a <recap> tag.');
    }
  }

  return b.toString();
}

/// Engine-stamped emotion intensity for a message (mild/moderate/strong),
/// from the realism_state metadata. Shared by the salience annotation here
/// and the maintenance pass's deterministic emotion stamping.
String? journalIntensityOf(ChatMessage m) {
  final state = m.activeMetadata?['realism_state'];
  if (state is Map) {
    final intensity = state['emotionIntensity'];
    if (intensity is String && intensity.isNotEmpty) return intensity;
  }
  return null;
}

/// Deterministic per-message salience annotation from the engine-stamped
/// metadata that already exists (nothing here asks the model anything).
/// Shared with the growth pass prompt (growth_prompt.dart) so both
/// background passes annotate the window identically.
String? salienceLineOf(ChatMessage m) {
  final meta = m.activeMetadata;
  if (meta == null) return null;
  final parts = <String>[];

  final emotion = meta['emotion_label'];
  if (emotion is String && emotion.isNotEmpty) {
    final intensity = journalIntensityOf(m);
    parts.add('felt $emotion${intensity == null ? '' : ' ($intensity)'}');
  }
  final bond = meta['bond_delta'];
  if (bond is int && bond != 0) {
    final reason = meta['bond_reason'];
    parts.add(
      'bond ${bond > 0 ? '+' : ''}$bond'
      '${reason is String && reason.isNotEmpty ? ' — $reason' : ''}',
    );
  }
  final trust = meta['trust_delta'];
  if (trust is int && trust != 0) {
    final reason = meta['trust_reason'];
    parts.add(
      'trust ${trust > 0 ? '+' : ''}$trust'
      '${reason is String && reason.isNotEmpty ? ' — $reason' : ''}',
    );
  }
  final repair = meta['trust_repair_verdict'];
  if (repair is String && repair.isNotEmpty) {
    parts.add('trust repair: $repair');
  }
  final chance = meta['chance_time_event'];
  if (chance is String && chance.isNotEmpty) {
    parts.add('unexpected event: $chance');
  }
  if (parts.isEmpty) return null;
  return parts.join('; ');
}
