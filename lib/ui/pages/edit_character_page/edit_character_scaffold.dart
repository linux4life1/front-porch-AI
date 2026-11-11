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
import 'package:front_porch_ai/ui/widgets/greyed_out.dart';

/// The editor's four tabs, in order and with their icons. The group editor
/// (Edit group) shows the same four.
const kEditCharacterTabs = [
  Tab(icon: Icon(Icons.person_outline, size: 18), text: 'Details'),
  Tab(icon: Icon(Icons.chat_bubble_outline, size: 18), text: 'Dialogue'),
  Tab(icon: Icon(Icons.menu_book_outlined, size: 18), text: 'Lorebook'),
  Tab(icon: Icon(Icons.public, size: 18), text: 'Worlds'),
];

/// A [Tab] greyed out with a tooltip. It reports the tab's own height, so
/// the bar is as tall as the 1:1 editor's.
class _GreyedTab extends StatelessWidget implements PreferredSizeWidget {
  const _GreyedTab(this.tooltip, this.tab);

  final String tooltip;
  final Tab tab;

  @override
  Size get preferredSize => tab.preferredSize;

  @override
  Widget build(BuildContext context) => GreyedOut(tooltip: tooltip, child: tab);
}

/// The Worlds tab's index in [kEditCharacterTabs].
const kEditCharacterWorldsTab = 3;

/// The character editor's chrome: AppBar with the save action, the four-tab
/// TabBar, the tab bodies and the floating token badge.
class EditCharacterScaffold extends StatelessWidget {
  /// Names the page: "Edit <name>" (a character, or the group).
  final String characterName;
  final String saveLabel;
  final bool popWithCardOnSave;
  final VoidCallback onSave;
  final TabController tabController;

  /// The floating token badge; the group editor has none.
  final ValueNotifier<int>? tokenNotifier;

  /// Details, Dialogue, Lorebook, Worlds — in TabBar order.
  final List<Widget> tabs;

  /// A group member's editor greys the Worlds tab out with this tooltip: it
  /// stays in the bar but cannot be selected.
  final String? worldsLockedTooltip;

  const EditCharacterScaffold({
    super.key,
    required this.characterName,
    required this.saveLabel,
    required this.popWithCardOnSave,
    required this.onSave,
    required this.tabController,
    this.tokenNotifier,
    required this.tabs,
    this.worldsLockedTooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      appBar: AppBar(
        backgroundColor: AppColors.cardOf(context),
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.iconSecondary(context)),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Row(
          children: [
            Icon(
              Icons.edit_note,
              color: AppColors.formAccentOf(context),
              size: 22,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Edit $characterName',
                style: TextStyle(
                  color: AppColors.textPrimary(context),
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ElevatedButton.icon(
              onPressed: onSave,
              icon: Icon(
                popWithCardOnSave
                    ? Icons.arrow_forward_rounded
                    : Icons.save_outlined,
                size: 18,
              ),
              label: Text(saveLabel),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.formAccentOf(context),
                foregroundColor: AppColors.onAccentOf(context),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
              ),
            ),
          ),
        ],
        bottom: TabBar(
          controller: tabController,
          labelColor: AppColors.formAccentOf(context),
          unselectedLabelColor: AppColors.textTertiary(context),
          indicatorColor: AppColors.formAccentOf(context),
          indicatorWeight: 3,
          tabs: [
            for (var i = 0; i < kEditCharacterTabs.length; i++)
              if (i == kEditCharacterWorldsTab && worldsLockedTooltip != null)
                _GreyedTab(worldsLockedTooltip!, kEditCharacterTabs[i])
              else
                kEditCharacterTabs[i],
          ],
        ),
      ),
      body: Stack(
        children: [
          TabBarView(
            controller: tabController,
            // A greyed-out tab cannot be swiped to either.
            physics: worldsLockedTooltip == null
                ? null
                : const NeverScrollableScrollPhysics(),
            children: tabs,
          ),
          if (tokenNotifier != null)
            Positioned(
              right: 24,
              bottom: 24,
              child: ValueListenableBuilder<int>(
                valueListenable: tokenNotifier!,
                builder: (context, tokens, child) =>
                    _tokenBadge(context, tokens),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tokenBadge(BuildContext context, int estimatedTokens) {
    final color = estimatedTokens > 4000
        ? AppColors.negativeAccentOf(context)
        : estimatedTokens > 2000
        ? AppColors.porchTerracottaOf(context)
        : AppColors.formAccentOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.token, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            '~$estimatedTokens tokens',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
