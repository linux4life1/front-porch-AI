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

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/chat/birthday.dart';
import 'package:front_porch_ai/services/chat/chat.dart' show Pockets;
import 'package:front_porch_ai/ui/pages/repository/repository.dart'
    show StoopCollapsible;
import 'package:front_porch_ai/ui/pages/repository/stoop_glass.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// The Stoop card panel's IDENTITY sections — the card-authored phrase lists
/// (Ambitions, Likes & Dislikes) a reader wants before downloading a stranger's
/// character.
///
/// Split out of stoop_card_sections.dart, which was at 472 lines and could not
/// carry another section. They share a shape anyway: read one list out of the
/// card's extensions, render it as glyphed lines, show nothing when absent.
///
/// None of this needs a backend change. `StoopCardDetail.card` carries the whole
/// card blob and the `/api/stoop/*` relay returns the upstream body verbatim, so
/// these fields were already arriving at both clients inside
/// `extensions.front_porch.realism_engine`.

/// Coerce one authored phrase list out of untrusted card JSON.
///
/// `is List` rather than `as List?`, and the reason is not hypothetical: this
/// card came off the wire from a stranger's upload, and the `as` form throws on
/// a present-but-wrong-typed value, taking down the WHOLE detail panel instead
/// of omitting one section. Caught in review by Grok, 2026-08-07.
/// Most phrases one section will render, and the longest each may be. A card
/// is a stranger's upload: type-checking it is not enough when the payload can
/// carry fifty thousand entries or a multi-megabyte string, either of which
/// freezes the detail panel for whoever opened it (Grok, 2026-08-07).
const _maxStoopPhrases = 24;
const _maxStoopPhraseChars = 160;

List<String> stoopPhrases(Object? raw) {
  final out = <String>[];
  for (final a in raw is List ? raw : const []) {
    if (out.length >= _maxStoopPhrases) break;
    if (a is! String) continue;
    final s = a.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (s.isEmpty) continue;
    out.add(
      // The `$` was backslash-escaped here, in a NON-raw string, so this branch
      // emitted the literal text `${s.substring(...)}…` instead of the phrase.
      // Only a phrase over 160 characters reaches it, which is why it survived:
      // every card anyone looked at was under the limit, and the one that was
      // not would have shown a line of Dart source to whoever opened it.
      s.length > _maxStoopPhraseChars
          ? '${s.substring(0, _maxStoopPhraseChars).trimRight()}…'
          : s,
    );
  }
  return out;
}

/// One glyphed line per phrase — the shared row shape for every list here.
List<Widget> _phraseRows(
  BuildContext context,
  String glyph,
  List<String> items,
) => [
  for (final a in items)
    Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(glyph, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              a,
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: AppColors.textPrimary(context),
              ),
            ),
          ),
        ],
      ),
    ),
];

Widget _subLabel(BuildContext context, String text) => Padding(
  padding: const EdgeInsets.only(bottom: 4),
  child: Text(
    text.toUpperCase(),
    style: TextStyle(
      fontSize: 10,
      letterSpacing: 0.8,
      fontWeight: FontWeight.w600,
      color: AppColors.textSecondary(context),
    ),
  ),
);

/// Hub-style birthday line: `March 15, 1998 — age 28`.
///
/// Same rules as [BirthdayMath] / hub.frontporchai.app: `YYYY-MM-DD`, Feb 29
/// never valid, age is the calendar delta to [asOf] (UTC today when omitted —
/// the hub has no story clock). Returns null for absent, wrong-typed, or
/// invalid values so a section can vanish without taking the panel down.
String? stoopBirthdayText(Object? raw, {DateTime? asOf}) {
  if (raw is! String) return null;
  final reading = BirthdayMath.read(raw, asOf ?? DateTime.now().toUtc());
  if (reading == null) return null;
  final b = reading.birth;
  return '${BirthdayMath.monthName(b.month)} ${b.day}, ${b.year} — age ${reading.age}';
}

/// Calendar birthday, as authored on the card.
///
/// Ungated like the other identity sections: a birthday travels with the card
/// whether or not the Realism Engine is on. Opens by default, matching the
/// hub's `textSection('Birthday', …, true)`.
Widget stoopBirthdaySection(
  BuildContext context,
  Map<String, dynamic> re, {
  DateTime? asOf,
}) {
  final line = stoopBirthdayText(re['birthday'], asOf: asOf);
  if (line == null) return const SizedBox.shrink();
  return StoopCollapsible(
    title: 'Birthday',
    initiallyExpanded: true,
    child: Text(
      line,
      style: TextStyle(color: stoopCream2(context), height: 1.5),
    ),
  );
}

/// The character's long-term ambitions, as authored on the card.
///
/// Deliberately NOT gated on `re['enabled']` the way the realism and needs
/// sections are. Ambitions are identity — they travel with the card and steer
/// the character's quests whenever Objectives is on, which is independent of
/// the Realism Engine. Copying the `enabled` guard by reflex would silently
/// hide real authored content on every card whose creator left the engine off.
/// The honest gate is "the author wrote some", matching the sections file's
/// contract that a section is absent when its data is.
///
/// Text only: a downloaded-to-nowhere card has no story yet, so there is no
/// progress and no stage word to show. Reusing the sidebar's AmbitionsRow here
/// would render a permanently-empty bar reading "just beginning" on every card.
Widget stoopAmbitionsSection(BuildContext context, Map<String, dynamic> re) {
  final items = stoopPhrases(re['ambitions']);
  if (items.isEmpty) return const SizedBox.shrink();
  return StoopCollapsible(
    title: 'Ambitions (${items.length})',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _phraseRows(context, '🧭', items),
    ),
  );
}

/// What the character is drawn to and put off by — the everyday lists only.
///
/// The 18+ pair is deliberately NOT shown here. The Stoop card page is browsed
/// by anyone signed in, and a reader has not necessarily opted into 18+ content
/// just by opening a card. The data still travels with the card and still works
/// the moment it is downloaded — this is a display decision, not a strip.
/// Same gating logic as ambitions above: shown when the author wrote some, not
/// when the Realism Engine happens to be on.
Widget stoopPreferencesSection(BuildContext context, Map<String, dynamic> re) {
  final likes = stoopPhrases(re['likes']);
  final dislikes = stoopPhrases(re['dislikes']);
  if (likes.isEmpty && dislikes.isEmpty) return const SizedBox.shrink();
  return StoopCollapsible(
    title: 'Likes & Dislikes (${likes.length + dislikes.length})',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (likes.isNotEmpty) ...[
          _subLabel(context, 'Drawn to'),
          ..._phraseRows(context, '♥', likes),
        ],
        if (likes.isNotEmpty && dislikes.isNotEmpty) const SizedBox(height: 8),
        if (dislikes.isNotEmpty) ...[
          _subLabel(context, 'Put off by'),
          ..._phraseRows(context, '✕', dislikes),
        ],
      ],
    ),
  );
}

/// What the character starts a chat already wearing and carrying.
///
/// Not read through [stoopPhrases] like its neighbours, and it cannot be: this
/// field is a MAP of two lists whose entries may each be a bare string OR a
/// `{name, state}` object, so the phrase reader returns empty for every card
/// forever — silently, since an absent section looks exactly like a card whose
/// author wrote no wardrobe.
///
/// [Pockets.fromJson] is that reader, and reusing it rather than writing a
/// map-aware coercion here is the point: it already tolerates both entry
/// shapes, already collapses whitespace, already caps names at 60 characters,
/// and already bounds each list with `.take(8)` on the RAW list — which is what
/// keeps a hostile upload with fifty thousand entries from freezing the panel,
/// the same concern `_maxStoopPhrases` exists for. It also means the Stoop
/// shows a downloader exactly the items the runtime would honour, rather than a
/// longer list the app would then trim.
///
/// Ungated, like the two sections above: a wardrobe travels with the card and
/// works the moment it is downloaded, independent of the Realism Engine.
Widget stoopWardrobeSection(BuildContext context, Map<String, dynamic> re) {
  final p = Pockets.fromJson(re['inventory']);
  final worn = p.wornDisplay;
  final carrying = p.carryingDisplay;
  if (worn.isEmpty && carrying.isEmpty) return const SizedBox.shrink();
  return StoopCollapsible(
    title: 'Pockets & Wardrobe (${worn.length + carrying.length})',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (worn.isNotEmpty) ...[
          _subLabel(context, 'Wearing'),
          ..._phraseRows(context, '🧥', worn),
        ],
        if (worn.isNotEmpty && carrying.isNotEmpty) const SizedBox(height: 8),
        if (carrying.isNotEmpty) ...[
          _subLabel(context, 'Carrying'),
          ..._phraseRows(context, '🎒', carrying),
        ],
      ],
    ),
  );
}
