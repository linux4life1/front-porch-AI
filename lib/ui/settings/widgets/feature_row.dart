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

import 'feature_tree.dart';

export 'feature_tree.dart'
    show
        ExpandSignal,
        FeatureDetailsSection,
        FeatureNeed,
        FeatureNeedChip,
        FeatureTreeBranch,
        FeatureTreeNode;

/// One switchable (or segmented) feature inside a [FeatureGroupCard].
///
/// Renders a three-tier hierarchy — Title, crisp 1-line [subtitle] (always
/// visible), and detailed [blurb] body text (expanded by default; toggled by
/// clicking the title/subtitle or via [expandDetailsSignal]).
///
/// Dependency badges are shown *only* when [showDependencyBadge] is true (for
/// requirements outside the item's own subgroup).
class FeatureRow extends StatefulWidget {
  const FeatureRow({
    super.key,
    required this.icon,
    required this.label,
    this.subtitle,
    required this.blurb,
    required this.value,
    this.onChanged = _noop,
    this.trailing,
    this.need = FeatureNeed.alone,
    this.dependsOn,
    this.satisfied = true,
    this.showDependencyBadge = false,
    this.child,
    this.showChildWhenOff = false,
    this.onDependencyTap,
    this.expandDetailsSignal,
    this.highlighted = false,
  });

  static void _noop(bool _) {}

  final IconData icon;
  final String label;

  /// Always-visible 1-line summary of what this setting does.
  final String? subtitle;

  /// Detailed body explanation; expanded by default and collapsible via title/
  /// subtitle click or [expandDetailsSignal].
  final String blurb;
  final bool value;
  final ValueChanged<bool> onChanged;

  /// Optional custom trailing control (e.g., segmented unit picker) used in
  /// place of the standard [Switch].
  final Widget? trailing;
  final FeatureNeed need;

  /// Display name of the cross-subgroup feature this one leans on.
  final String? dependsOn;

  /// False when [dependsOn] is switched off — the row dims and disables.
  final bool satisfied;

  /// True only for dependencies outside this row's own subgroup.
  final bool showDependencyBadge;

  /// Optional sub-control (a dropdown, a text field) shown while active (or
  /// always when [showChildWhenOff] is true). Kept visible even when [blurb]
  /// is collapsed.
  final Widget? child;

  /// When true, [child] is shown even if [value] is false.
  final bool showChildWhenOff;

  /// Called when a cross-subgroup `needs ...` chip is tapped to jump to its
  /// parent toggle.
  final VoidCallback? onDependencyTap;

  /// Parent batch signal to expand or collapse all row body sections.
  final ExpandSignal? expandDetailsSignal;

  /// Briefly highlights this row after a dependency jump.
  final bool highlighted;

  @override
  State<FeatureRow> createState() => _FeatureRowState();
}

class _FeatureRowState extends State<FeatureRow> {
  bool _detailsExpanded = true;

  @override
  void initState() {
    super.initState();
    if (widget.expandDetailsSignal != null) {
      _detailsExpanded = widget.expandDetailsSignal!.expanded;
    }
  }

  @override
  void didUpdateWidget(covariant FeatureRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextSignal = widget.expandDetailsSignal;
    final prevSignal = oldWidget.expandDetailsSignal;
    if (nextSignal != null && nextSignal.version != prevSignal?.version) {
      _detailsExpanded = nextSignal.expanded;
    }
  }

  void _toggleDetails() => setState(() => _detailsExpanded = !_detailsExpanded);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gated = widget.need == FeatureNeed.needs && !widget.satisfied;
    final isCore = widget.need == FeatureNeed.core;
    final amber = AppColors.porchAmberOf(context);
    final showChip =
        widget.showDependencyBadge &&
        widget.need == FeatureNeed.needs &&
        (widget.dependsOn?.isNotEmpty ?? false);

    final decoration = widget.highlighted
        ? BoxDecoration(
            color: amber.withValues(alpha: 0.12),
            border: Border.all(color: amber.withValues(alpha: 0.7)),
            borderRadius: BorderRadius.circular(10),
          )
        : isCore
        ? BoxDecoration(
            color: AppColors.surfaceContainerOf(
              context,
            ).withValues(alpha: 0.55),
            border: Border.all(color: amber.withValues(alpha: 0.35)),
            borderRadius: BorderRadius.circular(10),
          )
        : null;

    final inner = Padding(
      padding: EdgeInsets.symmetric(
        vertical: 10,
        horizontal: (isCore || widget.highlighted) ? 10 : 0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Keep Text(label) and Switch/trailing in this primary Row without
          // wrapping Text(label) in an inner Row so Row-ancestor lookups find
          // the control cleanly.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  widget.icon,
                  size: 18,
                  color: isCore ? amber : AppColors.iconSecondary(context),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      button: true,
                      toggled: _detailsExpanded,
                      hint: _detailsExpanded
                          ? 'Click to hide details'
                          : 'Click to show details',
                      child: InkWell(
                        onTap: _toggleDetails,
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 1),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  Text(
                                    widget.label,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimary(context),
                                    ),
                                  ),
                                  if (showChip)
                                    FeatureNeedChip(
                                      need: widget.need,
                                      text: 'needs ${widget.dependsOn}',
                                      onTap: widget.onDependencyTap,
                                    ),
                                ],
                              ),
                              if (widget.subtitle != null &&
                                  widget.subtitle!.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  widget.subtitle!,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    height: 1.35,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.textPrimary(
                                      context,
                                    ).withValues(alpha: 0.86),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              widget.trailing ??
                  Switch(
                    value: widget.value,
                    onChanged: gated ? null : widget.onChanged,
                  ),
            ],
          ),
          FeatureDetailsSection(expanded: _detailsExpanded, body: widget.blurb),
          if (widget.child != null &&
              !gated &&
              (widget.value || widget.showChildWhenOff))
            Padding(
              padding: const EdgeInsets.only(left: 28, top: 8),
              child: widget.child,
            ),
        ],
      ),
    );

    return Opacity(
      opacity: gated ? 0.48 : 1,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        margin: isCore || widget.highlighted
            ? const EdgeInsets.only(top: 4, bottom: 4)
            : EdgeInsets.zero,
        decoration: decoration,
        child: inner,
      ),
    );
  }
}

/// A collapsible titled group of [FeatureRow]s ("The Engine", "Time & World", …).
class FeatureGroupCard extends StatefulWidget {
  const FeatureGroupCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.rows,
    this.accentTint,
    this.forceExpandVersion = 0,
  });

  final String title;
  final String subtitle;
  final List<Widget> rows;

  /// Theme-backed tint blended gently into the card surface and border to
  /// visually distinguish categories in both light and dark modes.
  final Color? accentTint;

  /// Incremented by the parent when a dependency jump targets a row inside
  /// this group so it auto-opens.
  final int forceExpandVersion;

  @override
  State<FeatureGroupCard> createState() => _FeatureGroupCardState();
}

class _FeatureGroupCardState extends State<FeatureGroupCard> {
  bool _expanded = true;

  @override
  void didUpdateWidget(covariant FeatureGroupCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.forceExpandVersion != oldWidget.forceExpandVersion) {
      _expanded = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseCard = AppColors.cardOf(context);
    final baseBorder = AppColors.borderOf(context);
    final tint = widget.accentTint;
    final isLight = AppColors.isLight(context);
    final cardBg = tint == null
        ? baseCard
        : Color.alphaBlend(
            tint.withValues(alpha: isLight ? 0.055 : 0.045),
            baseCard,
          );
    final borderColor = tint == null
        ? baseBorder
        : Color.alphaBlend(tint.withValues(alpha: 0.24), baseBorder);
    final divider = Divider(height: 1, color: borderColor);
    final headingColor = AppColors.porchAmberOf(context);

    return Material(
      type: MaterialType.transparency,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: cardBg,
          border: Border.all(color: borderColor),
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
                child: Row(
                  children: [
                    AnimatedRotation(
                      turns: _expanded ? 0.25 : 0.0,
                      duration: const Duration(milliseconds: 150),
                      child: Icon(
                        Icons.chevron_right,
                        size: 20,
                        color: headingColor,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 10,
                        runSpacing: 2,
                        children: [
                          Text(
                            widget.title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: headingColor,
                            ),
                          ),
                          Text(
                            widget.subtitle,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: AppColors.textSecondary(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              alignment: Alignment.topCenter,
              child: _expanded
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          divider,
                          for (var i = 0; i < widget.rows.length; i++) ...[
                            if (i > 0) divider,
                            widget.rows[i],
                          ],
                        ],
                      ),
                    )
                  : const SizedBox(width: double.infinity, height: 0),
            ),
          ],
        ),
      ),
    );
  }
}
