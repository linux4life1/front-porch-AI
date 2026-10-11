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

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// A word picked in [TokenAlternativesDialog]: the place and the new word.
typedef TokenAltPick = ({TokenAlternative at, String word});

/// The places in one reply where the model nearly wrote something else, each
/// with the words it weighed. Tapping one pops a [TokenAltPick]; when
/// [refusal] is set the words are shown but cannot be picked.
class TokenAlternativesDialog extends StatelessWidget {
  const TokenAlternativesDialog({
    super.key,
    required this.body,
    required this.places,
    this.refusal,
  });

  final String body;
  final List<TokenAlternative> places;
  final String? refusal;

  static String _pct(double p) => '${(p * 100).round()}%';

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.porchAmberOf(context);
    return WarmDialog(
      title: 'Other words it weighed',
      icon: Icons.alt_route,
      accent: accent,
      width: 420,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WarmDialogText(
            refusal ??
                'Pick a word to rewrite the reply from there. The words '
                    'before it stay; the new take is added as a swipe.',
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 380),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: places.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 16, color: AppColors.borderOf(context)),
              itemBuilder: (context, i) => _place(context, places[i], accent),
            ),
          ),
        ],
      ),
      actions: [warmDialogCancel(context, label: 'Close')],
    );
  }

  Widget _place(BuildContext context, TokenAlternative at, Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            style: TextStyle(color: AppColors.textTertiary(context)),
            children: [
              TextSpan(text: tokenAltsLeadIn(body, at)),
              TextSpan(
                text: at.token,
                style: TextStyle(
                  color: AppColors.textPrimary(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
              TextSpan(text: '  ${_pct(at.p)}'),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final alt in at.alts)
              ActionChip(
                label: Text('${alt.token.trim()}  ${_pct(alt.p)}'),
                side: BorderSide(color: accent.withValues(alpha: 0.5)),
                onPressed: refusal != null
                    ? null
                    : () => Navigator.of(
                        context,
                      ).pop<TokenAltPick>((at: at, word: alt.token)),
              ),
          ],
        ),
      ],
    );
  }
}
