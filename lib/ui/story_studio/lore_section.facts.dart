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

part of 'lore_section.dart';

const _factCategories = ['Body', 'Object', 'Promise', 'Place', 'Fact'];

/// The continuity ledger: one row per fact with its category, "from 3.3",
/// and a ⋯ menu to edit, retire or forget it.
extension _LoreFacts on _LoreSectionState {
  Widget _continuityTab() {
    if (p.continuity.isEmpty) {
      return StoryEmptyState(
        title: 'No facts yet',
        detail: p.engineMode == StoryEngineMode.studio
            ? 'Studio records hard facts after every scene: scars, objects, '
                  'promises, places. Add one yourself with Add fact.'
            : 'The Quick engine does not keep a ledger. Switch the story to '
                  'Studio under Setup, or add facts yourself.',
      );
    }
    final live = p.continuity.where((f) => !f.isRetired).toList();
    final retired = p.continuity.where((f) => f.isRetired).toList();
    return StoryCard(
      children: [
        for (final f in live) _factRow(f),
        for (final f in retired) _factRow(f),
      ],
    );
  }

  Widget _factRow(ContinuityFact f) {
    final muted = StudioColors.mutedOf(context);
    final from = f.sceneId.isEmpty ? '' : p.sceneLabelById(f.sceneId);
    final until = f.isRetired ? p.sceneLabelById(f.retiredSceneId) : '';
    return Row(
      children: [
        StoryChip(
          f.isRetired ? 'Retired' : f.category,
          tone: f.isRetired ? '' : 'honey',
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: f.key,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(text: ' · ${f.value}'),
                if (f.entity.isNotEmpty)
                  TextSpan(
                    text: '  (${f.entity})',
                    style: TextStyle(color: muted),
                  ),
              ],
            ),
            style:
                StudioType.ui(
                  context,
                  size: 12.5,
                  color: f.isRetired ? muted : StudioColors.inkOf(context),
                ).copyWith(
                  decoration: f.isRetired ? TextDecoration.lineThrough : null,
                ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          f.isRetired
              ? '$from → $until'
              : (from.isEmpty ? 'always' : 'from $from'),
          style: StudioType.mono(context, size: 11.5),
        ),
        StoryMenuButton(
          key: ValueKey('fact-menu-${f.key}'),
          entries: [
            StoryMenuEntry('Edit…', onSelect: () => _editFact(f)),
            if (!f.isRetired)
              StoryMenuEntry(
                'Retire from scene…',
                onSelect: () => _retireFact(f),
              ),
            StoryMenuEntry(
              'Forget…',
              danger: true,
              divider: true,
              onSelect: () => _forgetFact(f),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _editFact(ContinuityFact? f) async {
    var category = f?.category ?? 'Fact';
    final key = TextEditingController(text: f?.key ?? '');
    final value = TextEditingController(text: f?.value ?? '');
    final entity = TextEditingController(text: f?.entity ?? '');
    final ok = await showStoryDialog<bool>(
      context,
      title: f == null ? 'Add fact' : 'Edit fact',
      width: 460,
      body: StatefulBuilder(
        builder: (ctx, setLocal) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in _factCategories)
                  StoryChip(
                    c,
                    selected: c == category,
                    onTap: () => setLocal(() => category = c),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            StoryField(
              controller: key,
              hint: 'What (e.g. Teodor\'s left hand)',
            ),
            const SizedBox(height: 8),
            StoryField(controller: value, hint: 'Is (e.g. burned, bandaged)'),
            const SizedBox(height: 8),
            StoryField(controller: entity, hint: 'Who or where it belongs to'),
          ],
        ),
      ),
      actions: (ctx) => [
        StoryButton.ghost('Cancel', onPressed: () => Navigator.pop(ctx, false)),
        StoryButton.primary(
          f == null ? 'Add' : 'Save',
          onPressed: () => Navigator.pop(ctx, true),
        ),
      ],
    );
    if (ok != true || !mounted || key.text.trim().isEmpty) return;
    if (f == null) {
      StoryContinuity.record(
        p,
        ContinuityFact(
          category: category,
          key: key.text.trim(),
          value: value.text.trim(),
          entity: entity.text.trim(),
        ),
      );
    } else {
      f
        ..category = category
        ..key = key.text.trim()
        ..value = value.text.trim()
        ..entity = entity.text.trim();
    }
    await _save();
    rebuildState(() {});
  }

  Future<void> _retireFact(ContinuityFact f) async {
    final refs = p.orderedScenes.toList();
    final picked = await showStoryDialog<String>(
      context,
      title: 'Retire “${f.key}” from which scene?',
      width: 460,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final r in refs)
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => Navigator.pop(context, r.scene.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    SizedBox(
                      width: 44,
                      child: Text(
                        p.sceneLabel(r.act, r.index),
                        style: StudioType.mono(context),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        r.scene.title,
                        overflow: TextOverflow.ellipsis,
                        style: StudioType.ui(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      actions: (ctx) => [
        StoryButton.ghost('Cancel', onPressed: () => Navigator.pop(ctx)),
      ],
    );
    if (picked == null || !mounted) return;
    f.retiredSceneId = picked;
    await _save();
    rebuildState(() {});
  }

  Future<void> _forgetFact(ContinuityFact f) async {
    final ok = await showStoryConfirm(
      context,
      title: 'Forget “${f.key}”?',
      body:
          'The writer stops being told this. Scenes already written keep '
          'their text.',
      confirmLabel: 'Forget',
      destructive: true,
    );
    if (!ok || !mounted) return;
    p.continuity.remove(f);
    await _save();
    rebuildState(() {});
  }
}
