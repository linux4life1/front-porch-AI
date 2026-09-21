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

/// Check now / plant / edit / reset plus the settings sheet.
extension GrowthPanelActions on GrowthPanel {
  Widget _actionsRow(BuildContext context, Color accent) {
    final busy = chatService.isGrowthPassRunning;
    // Wrap — three TextButtons in a Row overflow the narrow chat sidebar
    // by ~13px ("Check now · Plant a ring · Reset").
    return Padding(
      padding: const EdgeInsets.only(left: 12),
      child: Wrap(
        spacing: 0,
        runSpacing: 0,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          TextButton.icon(
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: busy ? null : () => chatService.forceGrowthPass(),
            icon: busy
                ? SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: accent,
                    ),
                  )
                : Icon(Icons.refresh, size: 13, color: accent),
            label: Text(
              busy ? 'Checking…' : 'Check now',
              style: TextStyle(fontSize: 11, color: accent),
            ),
          ),
          TextButton.icon(
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () => _plantRing(context),
            icon: Icon(
              Icons.spa,
              size: 13,
              color: AppColors.iconSecondary(context),
            ),
            label: Text(
              'Plant a ring',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary(context),
              ),
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () => _confirmReset(context),
            child: Text(
              'Reset',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.negativeAccentOf(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Dialogs ───────────────────────────────────────────────────────────

  void _showSettings(BuildContext context, StorageService storage) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.cardOf(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          'Growth settings',
          style: TextStyle(fontSize: 16, color: AppColors.textPrimary(context)),
        ),
        content: StatefulBuilder(
          builder: (context, setState) => SizedBox(
            width: 360,
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: storage.memorySettings.growthReviewFirst,
              activeTrackColor: AppColors.porchHoneyOf(context),
              title: Text(
                'Review growth before it applies',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textPrimary(context),
                ),
              ),
              subtitle: Text(
                'Off (default): characters grow on their own. On: proposed '
                'rings wait for your approval.',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textTertiary(context),
                ),
              ),
              onChanged: (v) async {
                await storage.memorySettings.setGrowthReviewFirst(v);
                setState(() {});
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _plantRing(BuildContext context) async {
    final draft = await _RingEditorDialog.show(
      context,
      title: 'Plant a ring for $characterName',
    );
    if (draft == null) return;
    await chatService.plantGrowthRingFor(
      characterId,
      draft.$1,
      category: draft.$2,
    );
  }

  Future<void> _editRing(BuildContext context, GrowthRingData ring) async {
    final draft = await _RingEditorDialog.show(
      context,
      title: 'Edit ring',
      initialContent: ring.content,
      initialCategory: ring.category,
    );
    if (draft == null) return;
    await chatService.editGrowthRing(ring, text: draft.$1, category: draft.$2);
  }

  Future<void> _confirmReset(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardOf(ctx),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          'Reset $characterName\'s growth?',
          style: TextStyle(fontSize: 16, color: AppColors.textPrimary(ctx)),
        ),
        content: Text(
          'Every ring in this chat is removed — including past growth and '
          'the pre-rings archive. The original character card is untouched. '
          'This cannot be undone.',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary(ctx)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.negativeAccentOf(ctx),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await chatService.resetGrowthFor(characterId);
    }
  }
}
