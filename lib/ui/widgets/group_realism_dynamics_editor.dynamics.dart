// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

part of 'group_realism_dynamics_editor.dart';

extension _GroupRealismDynamicsSection on _GroupRealismDynamicsEditorState {
  Widget _buildDynamicsSection() {
    final members = widget.members;
    if (members.length < 2) return const SizedBox.shrink();
    if (members.length > 4) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.cardOf(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderOf(context)),
        ),
        child: Text(
          'Group Dynamics (hidden intra-group feelings) are available for groups '
          'of 4 or fewer, per the engine limits. Larger groups use different '
          'social-dynamics modeling.',
          style: TextStyle(
            color: AppColors.textTertiary(context),
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Group Dynamics',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Pre-seed how members privately feel toward each other (hidden, '
            '-300..+300). These influence behavior in small groups.',
            style: TextStyle(color: AppColors.textSecondary(context)),
          ),
          const SizedBox(height: 16),
          ...members.map((source) {
            final rels =
                (_seedsByMid[source.mid]?['relationships'] as Map?)?.map(
                  (k, v) => MapEntry(k.toString(), (v as num).toInt()),
                ) ??
                const <String, int>{};
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _avatar(source, 16),
                      const SizedBox(width: 10),
                      Text(
                        'How ${source.name} feels about others',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary(context),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...members.where((t) => t.mid != source.mid).map((target) {
                    final value = rels[target.mid] ?? 0;
                    final color = relationshipScaleColor(context, value);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _avatar(target, 13),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                target.name,
                                style: TextStyle(
                                  color: AppColors.textPrimary(context),
                                ),
                              ),
                            ),
                            Text(
                              value > 0 ? '+$value' : '$value',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: color,
                              ),
                            ),
                          ],
                        ),
                        SliderTheme(
                          data: SliderThemeData(
                            activeTrackColor: color,
                            inactiveTrackColor: AppColors.borderOf(context)
                                .withValues(alpha: 0.3),
                            thumbColor: color,
                            trackHeight: 4,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 8,
                            ),
                          ),
                          child: Slider(
                            value: value.toDouble().clamp(-300, 300),
                            min: -300,
                            max: 300,
                            divisions: 120,
                            label: '$value',
                            onChanged: (v) => _updateRelationship(
                              source.mid,
                              target.mid,
                              v.round(),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            relationshipTierName(value),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: color,
                            ),
                          ),
                        ),
                      ],
                    );
                  }),
                  Divider(color: AppColors.borderOf(context)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
