// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "Where chats start" on the Review step of World from Wiki / World from
// Character: the minted world needs the place its chats begin in. Pick one
// of the places the run wrote, or name a new one (the only way when the run
// wrote none). Mint stays off until it is set.

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/character_creator/world_from_wiki/world_from_wiki_state.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

class WorldStartingPlaceCard extends StatelessWidget {
  const WorldStartingPlaceCard({super.key, required this.state});

  final WorldFromWikiState state;

  @override
  Widget build(BuildContext context) {
    final pick = state.startPick;
    final names = state.writtenPlaceNames;
    final shown = pick.shown(names);
    final naming = names.isEmpty || shown == '';
    final problem = pick.problem(names);
    final ink = StudioColors.inkOf(context);
    InputDecoration deco(String? label, {String? hint}) => InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: StudioColors.bgOf(context),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    );
    return Container(
      key: const Key('world-starting-place-card'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: StudioColors.raiseOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: problem == null
              ? StudioColors.lineOf(context)
              : StudioColors.honeyOf(context),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.star_rounded,
                size: 18,
                color: StudioColors.amberOf(context),
              ),
              const SizedBox(width: 8),
              Text(
                'Where chats start',
                style: TextStyle(fontWeight: FontWeight.w700, color: ink),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            names.isEmpty
                ? 'Name the place inside this world where chats begin. It '
                      'is made with the world, and you can add more places '
                      'later.'
                : 'Chats that get this world begin in this place, with the '
                      'world\'s lore and weather.',
            style: TextStyle(color: StudioColors.proseOf(context), height: 1.4),
          ),
          const SizedBox(height: 12),
          if (names.isNotEmpty)
            DropdownButtonFormField<String>(
              key: const Key('world-starting-place-pick'),
              // ignore: deprecated_member_use
              value: shown,
              isExpanded: true,
              hint: const Text('Pick a place'),
              decoration: deco(null),
              dropdownColor: StudioColors.cardOf(context),
              items: [
                for (final n in names)
                  DropdownMenuItem(
                    value: n,
                    child: Text(n, style: TextStyle(color: ink)),
                  ),
                DropdownMenuItem(
                  value: '',
                  child: Text(
                    'A new place…',
                    style: TextStyle(color: StudioColors.amberOf(context)),
                  ),
                ),
              ],
              onChanged: (v) {
                pick.placeName = v;
                state.notify();
              },
            ),
          if (naming) ...[
            if (names.isNotEmpty) const SizedBox(height: 12),
            TextField(
              key: const Key('world-starting-place-new-name'),
              controller: pick.nameController,
              style: TextStyle(color: ink),
              decoration: deco('Starting place', hint: 'e.g. The Tea Rooms'),
              onChanged: (_) => state.notify(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: pick.descController,
              minLines: 1,
              maxLines: 3,
              style: TextStyle(color: ink),
              decoration: deco('What is it like there? (optional)'),
            ),
          ],
          if (problem != null) ...[
            const SizedBox(height: 8),
            Text(
              problem,
              key: const Key('world-starting-place-problem'),
              style: TextStyle(color: StudioColors.honeyOf(context)),
            ),
          ],
        ],
      ),
    );
  }
}
