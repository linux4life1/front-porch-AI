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

part of 'growth_panel.dart';

/// Past-growth fold and one ring card plus its overflow menu.
extension GrowthPanelCards on GrowthPanel {
  Widget _pastSection(BuildContext context, List<GrowthRingData> past) {
    // Material so ExpansionTile's internal ListTile has a paint surface —
    // without it, Flutter asserts when a parent PorchAccordion DecoratedBox
    // sits between this ListTile and the nearest Material (ink invisible).
    return Material(
      type: MaterialType.transparency,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.only(left: 20, right: 4),
          childrenPadding: const EdgeInsets.only(left: 20, bottom: 4),
          dense: true,
          visualDensity: VisualDensity.compact,
          title: Text(
            'Past growth (${past.length})',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textTertiary(context),
            ),
          ),
          children: [
            for (final ring in past)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Opacity(
                  opacity: 0.65,
                  child: _ringCard(context, ring, isPast: true),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _ringCard(
    BuildContext context,
    GrowthRingData ring, {
    bool isPast = false,
  }) {
    final isArchive = ring.category == GrowthPhysics.kArchiveCategory;
    final chipColor = GrowthPanel.categoryAccent(context, ring.category);
    final emerging = !isPast && GrowthPhysics.tierOf(ring) == 'emerging';
    final receipts = GrowthStore.receiptsOf(ring);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.deepWellOf(context),
        borderRadius: BorderRadius.circular(SidebarTokens.wellRadius),
        border: Border.all(
          color: AppColors.borderOf(context).withValues(alpha: 0.5),
          style: emerging ? BorderStyle.none : BorderStyle.solid,
        ),
      ),
      foregroundDecoration: emerging
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(SidebarTokens.wellRadius),
              border: Border.all(
                color: AppColors.borderOf(context).withValues(alpha: 0.7),
              ),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: chipColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  isArchive
                      ? 'PRE-RINGS ARCHIVE'
                      : GrowthPanel.categoryLabel(ring.category).toUpperCase(),
                  style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: chipColor,
                  ),
                ),
              ),
              const Spacer(),
              if (ring.pinned)
                Icon(
                  Icons.push_pin,
                  size: 11,
                  color: AppColors.porchHoneyOf(context),
                ),
              _ringMenu(context, ring, isPast: isPast),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            ring.content,
            maxLines: isArchive ? 3 : null,
            overflow: isArchive ? TextOverflow.ellipsis : null,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.3,
              color: AppColors.textPrimary(context),
            ),
          ),
          if (!isPast || receipts.isNotEmpty) const SizedBox(height: 5),
          Row(
            children: [
              if (!isPast)
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: ring.strength.clamp(0.0, 1.0),
                      minHeight: 3,
                      backgroundColor: AppColors.borderOf(
                        context,
                      ).withValues(alpha: 0.4),
                      valueColor: AlwaysStoppedAnimation(
                        AppColors.porchAmberOf(context),
                      ),
                    ),
                  ),
                )
              else
                const Spacer(),
              if (receipts.isNotEmpty) const SizedBox(width: 8),
              for (final pos in receipts.take(3))
                Padding(
                  padding: const EdgeInsets.only(left: 3),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: onJumpToMessage == null
                        ? null
                        : () => onJumpToMessage!(pos),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.porchAmberOf(
                          context,
                        ).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '#$pos',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: AppColors.porchAmberOf(context),
                        ),
                      ),
                    ),
                  ),
                ),
              if (receipts.length > 3)
                Padding(
                  padding: const EdgeInsets.only(left: 3),
                  child: Text(
                    '+${receipts.length - 3}',
                    style: TextStyle(
                      fontSize: 9,
                      color: AppColors.textTertiary(context),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _ringMenu(
    BuildContext context,
    GrowthRingData ring, {
    required bool isPast,
  }) {
    return PopupMenuButton<String>(
      icon: Icon(
        Icons.more_horiz,
        size: 14,
        color: AppColors.iconSecondary(context),
      ),
      padding: EdgeInsets.zero,
      iconSize: 14,
      color: AppColors.surfaceContainerOf(context),
      onSelected: (action) async {
        switch (action) {
          case 'pin':
            await chatService.setGrowthRingPinned(ring.id, !ring.pinned);
            break;
          case 'edit':
            await _editRing(context, ring);
            break;
          case 'retire':
            await chatService.retireGrowthRing(ring.id);
            break;
          case 'restore':
            await chatService.unretireGrowthRing(ring);
            break;
          case 'delete':
            await chatService.deleteGrowthRing(ring.id);
            break;
        }
      },
      itemBuilder: (_) => [
        if (!isPast) ...[
          PopupMenuItem(
            value: 'pin',
            child: Text(ring.pinned ? 'Unpin' : 'Pin (never fades)'),
          ),
          const PopupMenuItem(value: 'edit', child: Text('Edit wording')),
          const PopupMenuItem(value: 'retire', child: Text('Retire to past')),
        ] else ...[
          const PopupMenuItem(value: 'restore', child: Text('Bring back')),
          const PopupMenuItem(value: 'delete', child: Text('Delete forever')),
        ],
      ],
    );
  }
}
