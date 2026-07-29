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

import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'sidebar_tokens.dart';

/// THE one collapsible card of the warm-porch sidebar (replaces the five
/// hand-rolled InkWell+chevron headers, the lone ExpansionTile, the two
/// always-open sections, and the headerless strip of the old design).
///
/// Header: animated chevron + emoji glyph + bold title + optional ellipsized
/// subtitle (the collapsed-state one-liner, e.g. "Fond · Trusting · Evening")
/// + trailing widgets (switches/gears) that never toggle expansion.
/// Expanded body sits under a hairline accent divider.
///
/// Dumb/local-state by design: the parent (SidebarBody) resolves the
/// persisted expansion default and persists changes via [onExpansionChanged],
/// so goldens only need mock prefs.
class PorchAccordion extends StatefulWidget {
  /// Persistence key ('character_state' | 'journal_memory' | 'story_tools').
  final String id;
  final String emoji;
  final String title;

  /// Collapsed-state one-liner shown next to the title.
  final String? subtitle;

  /// Section accent, already resolved for the current brightness by the
  /// caller (e.g. AppColors.porchTerracottaOf(context)).
  final Color accent;

  /// Header controls (master switch, gear) — wrapped so taps never toggle
  /// the accordion.
  final Widget? trailing;

  final bool initiallyExpanded;
  final ValueChanged<bool>? onExpansionChanged;
  final Widget child;

  const PorchAccordion({
    super.key,
    required this.id,
    required this.emoji,
    required this.title,
    this.subtitle,
    required this.accent,
    this.trailing,
    this.initiallyExpanded = false,
    this.onExpansionChanged,
    required this.child,
  });

  @override
  State<PorchAccordion> createState() => PorchAccordionState();
}

class PorchAccordionState extends State<PorchAccordion> {
  late bool _expanded = widget.initiallyExpanded;

  void _toggle() {
    setState(() => _expanded = !_expanded);
    widget.onExpansionChanged?.call(_expanded);
  }

  /// Programmatically expand (used via a GlobalKey when a header switch turns
  /// a feature ON — e.g. enabling Realism should reveal the stats it just
  /// turned on, matching the old sections' auto-expand-on-enable behavior).
  void expand() {
    if (_expanded) return;
    setState(() => _expanded = true);
    widget.onExpansionChanged?.call(true);
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    // Material (not Container+decoration) so nested ExpansionTile/ListTile
    // ink and splash paint on this surface — Container's DecoratedBox sits
    // between ListTiles and the scaffold Material and triggers Flutter's
    // "ink may be invisible" assertion in debug.
    return Padding(
      padding: const EdgeInsets.only(bottom: SidebarTokens.sectionGap),
      child: Material(
        color: AppColors.cardOf(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SidebarTokens.cardRadius),
          side: BorderSide(
            color: _expanded
                ? accent.withValues(alpha: 0.25)
                : AppColors.borderOf(context).withValues(alpha: 0.15),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          InkWell(
            onTap: _toggle,
            borderRadius: BorderRadius.circular(SidebarTokens.cardRadius),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Row(
                children: [
                  AnimatedRotation(
                    turns: _expanded ? 0.25 : 0.0,
                    duration: const Duration(milliseconds: 150),
                    child: Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: AppColors.iconSecondary(context),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(widget.emoji, style: const TextStyle(fontSize: 13)),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            widget.title,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: AppColors.textPrimary(context),
                            ),
                          ),
                        ),
                        if (widget.subtitle != null &&
                            widget.subtitle!.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              widget.subtitle!,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10,
                                color: AppColors.textTertiary(context),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Spacer(),
                  if (widget.trailing != null)
                    // Opaque so switch/gear taps never toggle expansion.
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {},
                      child: widget.trailing!,
                    ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 150),
            alignment: Alignment.topCenter,
            child: _expanded
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: accent.withValues(alpha: 0.2),
                      ),
                      Padding(
                        padding: SidebarTokens.bodyPadding.copyWith(top: 10),
                        child: widget.child,
                      ),
                    ],
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
        ),
      ),
    );
  }
}
