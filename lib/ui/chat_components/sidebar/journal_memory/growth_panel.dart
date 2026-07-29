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
import 'package:provider/provider.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/chat/growth_ops.dart';
import 'package:front_porch_ai/services/chat/growth_physics.dart';
import 'package:front_porch_ai/services/chat/growth_store.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/growth_review_dialog.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import '../sidebar_tokens.dart';

/// Growth Rings sidebar panel (docs/design/growth-rings.md; replaced the
/// Character Evolution panel) — the focused character's growth timeline for
/// this chat: rings grouped by tier (Established / Developing / Emerging),
/// a collapsible Past growth section, receipt pills that jump to the message
/// that earned the ring, the cadence slider, the opt-in review toggle
/// (default OFF — autonomous growth), and Check now / Plant a ring / Reset.
/// Follows the focused participant like JournalPanel — every group member
/// (and scene guest) grows their own rings.
class GrowthPanel extends StatelessWidget {
  final ChatService chatService;
  final String characterId;
  final String characterName;

  /// Receipts tap-to-jump (null in tests or hosts without a chat behind).
  final ValueChanged<int>? onJumpToMessage;

  const GrowthPanel({
    super.key,
    required this.chatService,
    required this.characterId,
    required this.characterName,
    this.onJumpToMessage,
  });

  /// Friendly label + accent for a ring category chip.
  static String categoryLabel(String category) => switch (category) {
    'stance' => 'stance',
    'habit' => 'habit',
    'skill' => 'skill',
    'scar' => 'scar',
    GrowthPhysics.kArchiveCategory => 'archive',
    _ => 'trait',
  };

  static Color categoryAccent(BuildContext context, String category) =>
      switch (category) {
        'stance' => AppColors.porchTerracottaOf(context),
        'habit' => AppColors.trustHighOf(context),
        'skill' => AppColors.porchAmberOf(context),
        'scar' => AppColors.fixationAccentOf(context),
        GrowthPhysics.kArchiveCategory => AppColors.textTertiary(context),
        _ => AppColors.porchHoneyOf(context),
      };

  @override
  Widget build(BuildContext context) {
    final storage = Provider.of<StorageService>(context);
    final enabled = storage.characterEvolutionEnabled;
    final accent = AppColors.porchHoneyOf(context);

    // Rings come from the session-scoped sync cache; ListenableBuilder keeps
    // the timeline current after passes/edits (they all notifyListeners).
    return ListenableBuilder(
      listenable: chatService,
      builder: (context, _) {
        final rings = chatService.growthRingsForOwner(characterId);
        final active = rings.where((r) => !r.retired).toList();
        final past = rings.where((r) => r.retired).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SidebarSubHeader(
              icon: Icons.donut_large,
              label: 'Growth · $characterName',
              accent: accent,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (enabled)
                    IconButton(
                      icon: Icon(
                        Icons.settings,
                        size: 14,
                        color: AppColors.iconSecondary(context),
                      ),
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Growth settings',
                      onPressed: () => _showSettings(context, storage),
                    ),
                  SizedBox(
                    height: 28,
                    child: FittedBox(
                      child: Switch(
                        value: enabled,
                        onChanged: (v) =>
                            storage.setCharacterEvolutionEnabled(v),
                        activeTrackColor: accent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (!enabled)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 20),
                child: Text(
                  'Characters grow small, evidence-backed "rings" as you '
                  'chat — the original card is always preserved.',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textTertiary(context),
                  ),
                ),
              ),
            if (enabled) ...[
              const SizedBox(height: 4),
              if (chatService.growthReview.hasPendingFor(
                chatService.currentSessionId,
              ))
                _reviewBanner(context),
              _cadenceSlider(context, storage, accent),
              if (chatService.hasLegacyGrowthBlobFor(characterId))
                Padding(
                  padding: const EdgeInsets.only(left: 20, bottom: 4),
                  child: Text(
                    'Growth recorded under the old system still applies — '
                    'it converts to rings at the next check.',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontStyle: FontStyle.italic,
                      color: AppColors.textTertiary(context),
                    ),
                  ),
                ),
              if (active.isEmpty &&
                  past.isEmpty &&
                  !chatService.hasLegacyGrowthBlobFor(characterId))
                Padding(
                  padding: const EdgeInsets.only(left: 20, top: 2),
                  child: Text(
                    '$characterName hasn\'t grown yet — rings appear as the '
                    'story changes them.',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textTertiary(context),
                    ),
                  ),
                ),
              for (final tier in const ['established', 'developing', 'emerging'])
                ..._tierSection(context, tier, active),
              if (past.isNotEmpty) _pastSection(context, past),
              const SizedBox(height: 6),
              _actionsRow(context, accent),
            ],
          ],
        );
      },
    );
  }

  // ── Sections ──────────────────────────────────────────────────────────

  List<Widget> _tierSection(
    BuildContext context,
    String tier,
    List<GrowthRingData> active,
  ) {
    final rings = active
        .where((r) => GrowthPhysics.tierOf(r) == tier)
        .toList();
    if (rings.isEmpty) return const [];
    final dot = switch (tier) {
      'established' => AppColors.porchHoneyOf(context),
      'developing' => AppColors.porchTerracottaOf(context),
      _ => AppColors.textTertiary(context),
    };
    return [
      Padding(
        padding: const EdgeInsets.only(left: 20, top: 8, bottom: 4),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              tier.toUpperCase(),
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                color: AppColors.textTertiary(context),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Divider(
                height: 1,
                color: AppColors.borderOf(context).withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      ),
      for (final ring in rings)
        Padding(
          padding: const EdgeInsets.only(left: 20, bottom: 6),
          child: _ringCard(context, ring),
        ),
    ];
  }

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
    final chipColor = categoryAccent(context, ring.category);
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 5,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: chipColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  isArchive
                      ? 'PRE-RINGS ARCHIVE'
                      : categoryLabel(ring.category).toUpperCase(),
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

  Widget _reviewBanner(BuildContext context) {
    final honey = AppColors.porchHoneyOf(context);
    return Padding(
      padding: const EdgeInsets.only(left: 20, bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(SidebarTokens.wellRadius),
        onTap: () => GrowthReviewDialog.show(context, chatService.growthReview),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: honey.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(SidebarTokens.wellRadius),
            border: Border.all(color: honey.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              const Text('🌱', style: TextStyle(fontSize: 13)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '$characterName has grown — '
                  '${chatService.growthReview.pending!.totalProposals} '
                  'proposal(s) waiting. Tap to review.',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: honey,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cadenceSlider(
    BuildContext context,
    StorageService storage,
    Color accent,
  ) {
    final value = storage.growthInterval.toDouble();
    return Padding(
      padding: const EdgeInsets.only(left: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Check for growth every',
                style: TextStyle(
                  color: AppColors.textSecondary(context),
                  fontSize: 10,
                ),
              ),
              const Spacer(),
              Text(
                '${storage.growthInterval} messages',
                style: TextStyle(
                  color: accent,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          SizedBox(
            height: 26,
            child: Slider(
              value: value.clamp(2, 20),
              min: 2,
              max: 20,
              divisions: 18,
              activeColor: accent,
              onChanged: (v) => storage.setGrowthInterval(v.round()),
            ),
          ),
        ],
      ),
    );
  }

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
          style: TextStyle(
            fontSize: 16,
            color: AppColors.textPrimary(context),
          ),
        ),
        content: StatefulBuilder(
          builder: (context, setState) => SizedBox(
            width: 360,
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: storage.growthReviewFirst,
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
                await storage.setGrowthReviewFirst(v);
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

/// Compact modal editor for one ring: the sentence + its category.
/// Returns (text, category) or null on cancel.
class _RingEditorDialog extends StatefulWidget {
  final String title;
  final String initialContent;
  final String initialCategory;

  const _RingEditorDialog({
    required this.title,
    this.initialContent = '',
    this.initialCategory = 'trait',
  });

  static Future<(String, String)?> show(
    BuildContext context, {
    required String title,
    String initialContent = '',
    String initialCategory = 'trait',
  }) => showDialog<(String, String)>(
    context: context,
    builder: (_) => _RingEditorDialog(
      title: title,
      initialContent: initialContent,
      initialCategory: initialCategory,
    ),
  );

  @override
  State<_RingEditorDialog> createState() => _RingEditorDialogState();
}

class _RingEditorDialogState extends State<_RingEditorDialog> {
  late final TextEditingController _content = TextEditingController(
    text: widget.initialContent,
  );
  late String _category = kGrowthCategories.contains(widget.initialCategory)
      ? widget.initialCategory
      : 'trait';

  @override
  void dispose() {
    _content.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.porchHoneyOf(context);
    return AlertDialog(
      backgroundColor: AppColors.cardOf(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text(
        widget.title,
        style: TextStyle(fontSize: 16, color: AppColors.textPrimary(context)),
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _content,
              autofocus: true,
              minLines: 2,
              maxLines: 4,
              maxLength: GrowthPhysics.kRingMaxChars,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary(context),
              ),
              decoration: InputDecoration(
                hintText: 'One sentence of change — "Has started guarding '
                    '{{user}}\'s sleep."',
                hintStyle: TextStyle(
                  fontSize: 12,
                  color: AppColors.textTertiary(context),
                ),
                filled: true,
                fillColor: AppColors.surfaceContainerOf(context),
                counterStyle: TextStyle(
                  fontSize: 10,
                  color: AppColors.textTertiary(context),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppColors.borderOf(context)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppColors.borderOf(context)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: accent),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                for (final c in kGrowthCategories)
                  ChoiceChip(
                    label: Text(
                      GrowthPanel.categoryLabel(c),
                      style: TextStyle(
                        fontSize: 11,
                        color: _category == c
                            ? GrowthPanel.categoryAccent(context, c)
                            : AppColors.textSecondary(context),
                      ),
                    ),
                    selected: _category == c,
                    selectedColor: GrowthPanel.categoryAccent(
                      context,
                      c,
                    ).withValues(alpha: 0.18),
                    backgroundColor: AppColors.surfaceContainerOf(context),
                    onSelected: (_) => setState(() => _category = c),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Cancel',
            style: TextStyle(color: AppColors.textSecondary(context)),
          ),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: accent),
          onPressed: _content.text.trim().isEmpty
              ? null
              : () => Navigator.of(
                  context,
                ).pop((_content.text.trim(), _category)),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
