// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'package:flutter/material.dart';

import 'stoop_collapsible.dart';
import 'stoop_identity_sections.dart';

import 'package:front_porch_ai/services/backporch/stoop_card.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_glass.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Collapsible/expandable sections for the Stoop character detail panel.
///
/// Every character field is presented as a [StoopCollapsible] — default
/// collapsed, expand on click — so the panel opens as a tidy index the reader
/// drills into. These builders read the canonical card JSON (the same shape the
/// PNG export embeds): realism + needs live under
/// `extensions → front_porch → realism_engine`, and the lorebook under
/// `character_book`. Each returns an empty box when its data is absent, so a
/// character without that feature shows no empty section.

/// A collapsible holding a plain text body. Renders nothing when [body] is blank.
Widget stoopTextSection(
  BuildContext context,
  String title,
  String body, {
  bool initiallyExpanded = false,
}) {
  if (body.trim().isEmpty) return const SizedBox.shrink();
  return StoopCollapsible(
    title: title,
    initiallyExpanded: initiallyExpanded,
    child: Text(
      body,
      style: TextStyle(color: stoopCream2(context), height: 1.5),
    ),
  );
}

/// The standard collapsible field set for a character — used for a solo card AND
/// for each group member, so a member reads exactly like a single character.
/// Pass [firstMessage] to override the First-message section (the solo view
/// supplies an interactive greeting carousel; members get a plain joined one).
List<Widget> stoopStandardSections(
  BuildContext context,
  Map<String, dynamic> card,
  String name, {
  Widget? firstMessage,
  DateTime? asOf,
}) {
  String s(String key) =>
      stoopResolveMacros((card[key] ?? '').toString(), name);
  final re = stoopRealismEngine(card);
  return [
    stoopTextSection(
      context,
      'Persona',
      [
        s('description'),
        s('personality'),
      ].where((x) => x.isNotEmpty).join('\n\n'),
    ),
    stoopTextSection(context, 'Scenario', s('scenario')),
    firstMessage ?? _defaultFirstMessage(context, card, name),
    stoopTextSection(context, 'Example dialogue', s('mes_example')),
    stoopBirthdaySection(context, re, asOf: asOf),
    stoopAmbitionsSection(context, re),
    stoopPreferencesSection(context, re),
    // Kept with the other two card-authored identity sections and ahead of the
    // engine-gated pair below: what a character owns is theirs whether or not
    // the downloader ever turns the Realism Engine on.
    stoopWardrobeSection(context, re),
    stoopRealismSection(context, re),
    stoopNeedsSection(context, re),
    stoopLorebookSection(context, card, name),
    stoopTextSection(
      context,
      'Advanced',
      [
        if (s('system_prompt').isNotEmpty)
          'System prompt:\n${s('system_prompt')}',
        if (s('post_history_instructions').isNotEmpty)
          'Post-history:\n${s('post_history_instructions')}',
      ].join('\n\n'),
    ),
  ];
}

/// The collapsible field set for a WORLD card — the .fpworld envelope's
/// description, climate, place traits, and lore. Reuses the same section
/// chrome as characters so places read native on the detail panel.
List<Widget> stoopWorldSections(
  BuildContext context,
  Map<String, dynamic> card,
) {
  final name = (card['name'] ?? '').toString();
  final climateOn = stoopWorldClimateEnabled(card);
  final biome = card['biome'];
  final climate = biome is Map
      ? [
          (biome['displayName'] ?? '').toString(),
          (biome['feel'] ?? biome['description'] ?? '').toString(),
        ].where((x) => x.isNotEmpty).join(' — ')
      : '';
  final traits = card['place_traits'];
  final traitLines = traits is Map
      ? [
          for (final e in traits.entries)
            '${e.key.toString().replaceAll('_', ' ')}: ${e.value}',
        ]
      : const <String>[];
  final lore = card['lorebook'];
  // Stranger-uploaded JSON: `is`-check, never `as` — a wrong-typed 'entries'
  // (string, map) crashed the whole detail panel (1.3 sweep).
  final rawEntries = lore is Map ? lore['entries'] : null;
  final valid = rawEntries is List
      ? rawEntries.whereType<Map>().toList()
      : const <Map>[];
  return [
    stoopTextSection(
      context,
      'About this place',
      (card['description'] ?? '').toString(),
      initiallyExpanded: true,
    ),
    if (!climateOn)
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          'Lore only -- no climate, weather, or place traits.',
          style: TextStyle(color: stoopCream2(context), height: 1.5),
        ),
      )
    else ...[
      stoopTextSection(context, 'Climate', climate),
      stoopTextSection(context, 'Traits', traitLines.join('\n')),
    ],
    if (valid.isNotEmpty)
      stoopLorebookEntries(context, 'Lore (${valid.length})', valid, name),
  ];
}

// Static first-message section (first_mes + alternates joined) for contexts
// without an interactive greeting carousel (e.g. a group member).
Widget _defaultFirstMessage(
  BuildContext context,
  Map<String, dynamic> card,
  String name,
) {
  final first = stoopResolveMacros((card['first_mes'] ?? '').toString(), name);
  final rawAlts = card['alternate_greetings'];
  final alts = rawAlts is List
      ? rawAlts
            .map((e) => stoopResolveMacros(e.toString(), name))
            .where((x) => x.isNotEmpty)
            .toList()
      : const <String>[];
  final greetings = [if (first.isNotEmpty) first, ...alts];
  if (greetings.isEmpty) return const SizedBox.shrink();
  return stoopTextSection(
    context,
    greetings.length > 1
        ? 'First message (${greetings.length})'
        : 'First message',
    greetings.join('\n\n———\n\n'),
  );
}

/// Pull the Front Porch realism/needs blob out of a card's extensions. Empty map
/// when the card carries none (e.g. a plain V2 card or a realism-off character).
Map<String, dynamic> stoopRealismEngine(Map<String, dynamic> card) {
  final ext = card['extensions'];
  final fp = ext is Map ? ext['front_porch'] : null;
  final re = fp is Map ? fp['realism_engine'] : null;
  return re is Map ? Map<String, dynamic>.from(re) : const {};
}

int _i(Map re, String key, int fallback) {
  final v = re[key];
  return v is num ? v.toInt() : fallback;
}

/// Pre-seeded relationship/emotion baseline. Only shown when the creator enabled
/// the realism engine on the card.
Widget stoopRealismSection(BuildContext context, Map<String, dynamic> re) {
  if (re['enabled'] != true) return const SizedBox.shrink();
  final emotion = (re['character_emotion'] ?? '').toString();
  final intensity = (re['emotion_intensity'] ?? '').toString();
  final rows = <(String, String)>[
    ('Bond — short-term', '${_i(re, 'short_term_bond', 0)}'),
    ('Bond — long-term', '${_i(re, 'long_term_bond', 0)}'),
    ('Trust', '${_i(re, 'trust_level', 0)}'),
    if (emotion.isNotEmpty)
      ('Emotion', intensity.isNotEmpty ? '$emotion ($intensity)' : emotion),
    ('Time of day', (re['time_of_day'] ?? '—').toString()),
    ('Day count', '${_i(re, 'day_count', 0)}'),
  ];
  return StoopCollapsible(
    title: 'Realism baseline',
    child: _kvList(context, rows),
  );
}

/// Sims-style Needs baseline (starting level) + tick rate (decay per turn). Only
/// shown when the creator enabled the needs simulation on the card.
Widget stoopNeedsSection(BuildContext context, Map<String, dynamic> re) {
  if (re['needs_sim_enabled'] != true) return const SizedBox.shrink();
  const needs = [
    ('Hunger', 'hunger'),
    ('Bladder', 'bladder'),
    ('Energy', 'energy'),
    ('Social', 'social'),
    ('Fun', 'fun'),
    ('Hygiene', 'hygiene'),
    ('Comfort', 'comfort'),
  ];
  final head = TextStyle(
    color: stoopMute(context),
    fontSize: 12,
    fontWeight: FontWeight.w600,
  );
  final cell = TextStyle(color: stoopCream2(context), fontSize: 13);
  TableRow tableRow(List<Widget> cells) => TableRow(
    children: cells
        .map(
          (c) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: c,
          ),
        )
        .toList(),
  );
  return StoopCollapsible(
    title: 'Needs baseline & tick rates',
    child: Table(
      columnWidths: const {
        0: FlexColumnWidth(2),
        1: FlexColumnWidth(1.2),
        2: FlexColumnWidth(1.4),
      },
      children: [
        tableRow([
          Text('Need', style: head),
          Text('Baseline', style: head, textAlign: TextAlign.end),
          Text('Decay/turn', style: head, textAlign: TextAlign.end),
        ]),
        for (final (label, key) in needs)
          tableRow([
            Text(label, style: cell),
            Text(
              '${_i(re, 'needs_baseline_$key', 80)}',
              style: cell,
              textAlign: TextAlign.end,
            ),
            Text(
              '−${_i(re, 'needs_decay_$key', 0)}',
              style: cell,
              textAlign: TextAlign.end,
            ),
          ]),
      ],
    ),
  );
}

/// A character's lorebook entries with triggers (keywords) and content. Empty
/// when the card has no `character_book` entries.
Widget stoopLorebookSection(
  BuildContext context,
  Map<String, dynamic> card,
  String name,
) {
  final book = card['character_book'];
  // Stranger JSON: `is`, never `as` (1.3 sweep — the sibling builders kept
  // crashing after the detail panel was hardened).
  final rawEntries = book is Map ? book['entries'] : null;
  final valid = rawEntries is List
      ? rawEntries.whereType<Map>().toList()
      : const <Map>[];
  if (valid.isEmpty) return const SizedBox.shrink();
  return stoopLorebookEntries(
    context,
    'Lorebook (${valid.length})',
    valid,
    name,
  );
}

/// Renders a collapsible list of lorebook entries (each with its trigger
/// keyword chips + content). Shared by a character's `character_book` and a
/// group's `group_lorebook`.
Widget stoopLorebookEntries(
  BuildContext context,
  String title,
  List<Map> entries,
  String name,
) {
  return StoopCollapsible(
    title: title,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final e in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _lorebookTriggers(context, e),
                const SizedBox(height: 3),
                Text(
                  stoopResolveMacros((e['content'] ?? '').toString(), name),
                  style: TextStyle(color: stoopMute(context), height: 1.45),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

// The entry's trigger keywords as little chips (falls back to its name/label).
Widget _lorebookTriggers(BuildContext context, Map e) {
  final rawKeys = e['keys'];
  final keys = rawKeys is List
      ? rawKeys.map((k) => k.toString()).toList()
      : const <String>[];
  if (keys.isEmpty) {
    return Text(
      (e['name'] ?? e['comment'] ?? 'Entry').toString(),
      style: TextStyle(
        color: stoopCream2(context),
        fontWeight: FontWeight.w600,
        fontSize: 13,
      ),
    );
  }
  return Wrap(
    spacing: 6,
    runSpacing: 4,
    children: [
      for (final k in keys)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: stoopTealSoft(context),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: AppColors.stoopTeal.withValues(alpha: 0.35),
            ),
          ),
          child: Text(
            k,
            style: TextStyle(
              color: stoopTealText(context),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
    ],
  );
}

Widget _kvList(BuildContext context, List<(String, String)> rows) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final (k, v) in rows)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 150,
                child: Text(
                  k,
                  style: TextStyle(color: stoopMute(context), fontSize: 13),
                ),
              ),
              Expanded(
                child: Text(
                  v,
                  style: TextStyle(
                    color: stoopCream2(context),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
    ],
  );
}
