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

/// Signal emitted by Porch Life's top-bar Collapse/Expand All Details button so
/// rows sync to a batch toggle while still letting users override individual
/// items by clicking their title or subtitle.
typedef ExpandSignal = ({int version, bool expanded});

/// How a feature relates to its parent requirement.
enum FeatureNeed {
  /// No dependency at all.
  alone,

  /// Genuinely cannot function without [FeatureRow.dependsOn].
  needs,

  /// Functions, but feels wrong on its own — shipped paired on purpose.
  pairs,

  /// Foundation engine setting.
  core,
}

/// Clickable cross-subgroup dependency pill rendered on items that depend on a
/// setting outside their own subgroup (e.g. Dreams -> Passage of Time).
class FeatureNeedChip extends StatelessWidget {
  const FeatureNeedChip({
    super.key,
    required this.need,
    required this.text,
    this.onTap,
  });

  final FeatureNeed need;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final amber = AppColors.porchAmberOf(context);
    final bg = amber.withValues(alpha: 0.12);
    final border = amber.withValues(alpha: 0.35);

    final label = Text(
      text,
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
        color: amber,
      ),
    );

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(99),
      ),
      child: onTap == null
          ? label
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: label),
                const SizedBox(width: 4),
                Icon(Icons.north_east, size: 11, color: amber),
              ],
            ),
    );

    if (onTap == null) return chip;

    return Tooltip(
      message: 'Jump to required setting',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: chip,
      ),
    );
  }
}

/// Pairs a parent [FeatureRow] with its [FeatureTreeBranch] children as
/// siblings in the widget tree (so `find.widgetWithText(FeatureRow, ...)` on a
/// child never matches its parent).
class FeatureTreeNode extends StatelessWidget {
  const FeatureTreeNode({
    super.key,
    required this.parent,
    this.active = true,
    this.children = const [],
  });

  final Widget parent;
  final bool active;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return parent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        parent,
        FeatureTreeBranch(active: active, children: children),
      ],
    );
  }
}

/// Visual tree connector container for dependent sub-features nested under
/// their parent toggle. Uses a subtle left vertical rail whose warmth reflects
/// whether the parent requirement is active.
class FeatureTreeBranch extends StatelessWidget {
  const FeatureTreeBranch({
    super.key,
    required this.children,
    this.active = true,
  });

  final List<Widget> children;
  final bool active;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    final railColor = active
        ? AppColors.porchAmberOf(context).withValues(alpha: 0.42)
        : AppColors.borderOf(context);
    final divider = Divider(height: 1, color: AppColors.borderOf(context));

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 460;
        final indent = narrow ? 10.0 : 14.0;
        return Container(
          margin: EdgeInsets.only(left: narrow ? 6 : 10, top: 4, bottom: 4),
          padding: EdgeInsets.only(left: indent),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: railColor, width: 2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) divider,
                children[i],
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Animated collapsible body block shared by [FeatureRow], [ToolsFolderNote],
/// and [SkillsFolderNote]. Toggling is triggered by clicking the row's title
/// or subtitle or the global details button.
class FeatureDetailsSection extends StatelessWidget {
  const FeatureDetailsSection({
    super.key,
    required this.expanded,
    required this.body,
    this.leftIndent = 28,
  });

  final bool expanded;
  final String body;
  final double leftIndent;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 160),
      alignment: Alignment.topLeft,
      child: expanded
          ? Padding(
              padding: EdgeInsets.only(left: leftIndent, top: 6, right: 4),
              child: Text(
                body,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: AppColors.textSecondary(context),
                ),
              ),
            )
          : const SizedBox(width: double.infinity, height: 0),
    );
  }
}
