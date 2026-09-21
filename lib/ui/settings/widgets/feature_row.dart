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

import 'package:front_porch_ai/ui/theme/theme.dart';

/// How a feature relates to the thing it sits next to, stated honestly on the
/// row itself. The audit (docs/design/feature-independence.md) found several
/// features that run perfectly well with the Realism Engine off but whose
/// switches were hidden inside it — these chips exist so a user never has to
/// guess again.
enum FeatureNeed {
  /// No dependency at all.
  alone,

  /// Genuinely cannot function without [FeatureRow.dependsOn].
  needs,

  /// Functions, but feels wrong on its own — shipped paired on purpose.
  pairs,

  /// The thing others can lean on.
  core,
}

/// One switchable feature inside a [FeatureGroupCard].
///
/// Deliberately dumb: it renders state and reports taps. The dependency
/// bookkeeping (is my requirement satisfied? offer to turn both on) belongs to
/// the tab, which owns the flags.
class FeatureRow extends StatelessWidget {
  const FeatureRow({
    super.key,
    required this.icon,
    required this.label,
    required this.blurb,
    required this.value,
    required this.onChanged,
    this.need = FeatureNeed.alone,
    this.dependsOn,
    this.satisfied = true,
    this.child,
    this.showChildWhenOff = false,
  });

  final IconData icon;
  final String label;
  final String blurb;
  final bool value;
  final ValueChanged<bool> onChanged;
  final FeatureNeed need;

  /// Display name of the feature this one leans on (chip text).
  final String? dependsOn;

  /// False when [dependsOn] is switched off — the row explains itself instead
  /// of silently doing nothing.
  final bool satisfied;

  /// Optional sub-control (a dropdown, a slider) shown under the blurb while
  /// the feature is on. Set [showChildWhenOff] when the control must stay
  /// reachable with the switch off (Tavily key: you paste it before the
  /// lookup is useful).
  final Widget? child;

  /// When true, [child] is shown even if [value] is false.
  final bool showChildWhenOff;

  String get _chipText => switch (need) {
    FeatureNeed.alone => 'works alone',
    FeatureNeed.core => 'core',
    FeatureNeed.needs => 'needs ${dependsOn ?? ''}',
    FeatureNeed.pairs => 'pairs with ${dependsOn ?? ''}',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // An unmet requirement GATES the row: the switch goes dead and the whole
    // row dims, so the hierarchy is obvious at a glance. It deliberately does
    // NOT nag — a stack of "X is on, but Y is off" banners was the first
    // draft and read as a wall of complaints (maintainer, 2026-08-07).
    final gated = need == FeatureNeed.needs && !satisfied;

    return Opacity(
      opacity: gated ? 0.45 : 1,
      child: Padding(
        padding: EdgeInsets.only(
          top: 10,
          bottom: 10,
          // Dependants sit indented under the row they hang off.
          left: need == FeatureNeed.needs ? 16 : 0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    icon,
                    size: 18,
                    color: AppColors.iconSecondary(context),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Text(label, style: theme.textTheme.titleSmall),
                          _NeedChip(need: need, text: _chipText),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        blurb,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          color: AppColors.textSecondary(context),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Gated rows render a dead switch: the requirement, not a
                // banner, is what tells the user why.
                Switch(value: value, onChanged: gated ? null : onChanged),
              ],
            ),
            if (child != null && !gated && (value || showChildWhenOff))
              Padding(
                padding: const EdgeInsets.only(left: 28, top: 8),
                child: child,
              ),
          ],
        ),
      ),
    );
  }
}

class _NeedChip extends StatelessWidget {
  const _NeedChip({required this.need, required this.text});

  final FeatureNeed need;
  final String text;

  @override
  Widget build(BuildContext context) {
    final amber = AppColors.porchAmberOf(context);
    // Green reads "no strings attached" against the amber chrome — it is a
    // semantic state marker, not decoration.
    final independent = AppColors.resolve(
      context,
      const Color(0xFF9FD49F),
      const Color(0xFF3F7A46),
    ); // theme-keep: dependency legend (independent vs coupled)

    final (Color fg, Color bg, Color border) = switch (need) {
      FeatureNeed.alone => (
        independent,
        independent.withValues(alpha: 0.12),
        independent.withValues(alpha: 0.35),
      ),
      FeatureNeed.core => (
        amber,
        amber.withValues(alpha: 0.22),
        amber.withValues(alpha: 0.9),
      ),
      _ => (
        amber,
        amber.withValues(alpha: 0.12),
        amber.withValues(alpha: 0.35),
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        need == FeatureNeed.core ? text.toUpperCase() : text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: fg,
        ),
      ),
    );
  }
}

/// A titled group of [FeatureRow]s ("Time & World", "Memory & Heart", …).
class FeatureGroupCard extends StatelessWidget {
  const FeatureGroupCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.rows,
  });

  final String title;
  final String subtitle;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final divider = Divider(height: 1, color: AppColors.borderOf(context));

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        border: Border.all(color: AppColors.borderOf(context)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary(context),
                ),
              ),
            ],
          ),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) divider,
            rows[i],
          ],
        ],
      ),
    );
  }
}
