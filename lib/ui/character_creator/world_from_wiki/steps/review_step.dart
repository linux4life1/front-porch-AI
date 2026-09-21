// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/character_creator/world_from_wiki/world_from_wiki_state.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

class WorldFromWikiReviewStep extends StatelessWidget {
  const WorldFromWikiReviewStep({super.key, required this.state});

  final WorldFromWikiState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('world-review'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 24, 32, 8),
          child: Text(
            'Sign the cards they proposed. Default is off — no select-all. '
            '${state.signed.length} of ${state.proposed.length} signed'
            '${state.catalogTitleCount > 0 ? ' (${state.catalogTitleCount} index pages).' : '.'}',
            style: TextStyle(
              color: AppColors.textSecondary(context),
              height: 1.4,
            ),
          ),
        ),
        if (state.proposed.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              'No cards. Go back and Scout again.',
              style: TextStyle(color: AppColors.textTertiary(context)),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: state.proposed.length,
              itemBuilder: (context, i) {
                final card = state.proposed[i];
                final on = state.signed.contains(i);
                final group = card.group.isEmpty ? '' : ' · ${card.group}';
                final sources = card.sourceTitles.join(', ');
                return CheckboxListTile(
                  value: on,
                  activeColor: AppColors.porchAmberOf(context),
                  title: Text(card.name),
                  subtitle: Text(
                    '${card.role.name}$group'
                    '${sources.isEmpty ? '' : '\n$sources'}',
                  ),
                  isThreeLine: sources.isNotEmpty,
                  onChanged: (v) => state.toggleSigned(i, v == true),
                );
              },
            ),
          ),
      ],
    );
  }
}
