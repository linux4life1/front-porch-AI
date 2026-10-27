// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/steps/world_direction_box.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/steps/world_entry_card.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/steps/world_progress_panel.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/steps/world_starting_place_card.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/world_from_wiki_review_actions.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/world_from_wiki_state.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// How many of a place's cards show before "Show the other N".
const int kWorldReviewCardsShown = 6;

/// The last step before Mint: the written world read as a whole, the
/// author's direction sent back around the reviewers, and each entry
/// fixed, rewritten, dropped or kept by hand. Nothing is saved here.
class WorldFromWikiReviewWorldStep extends StatefulWidget {
  const WorldFromWikiReviewWorldStep({super.key, required this.state});

  final WorldFromWikiState state;

  @override
  State<WorldFromWikiReviewWorldStep> createState() =>
      _WorldFromWikiReviewWorldStepState();
}

class _WorldFromWikiReviewWorldStepState
    extends State<WorldFromWikiReviewWorldStep> {
  final Set<String> _expanded = {};
  String? _addOpenFor;
  final _addName = TextEditingController();
  final _addPage = TextEditingController();

  @override
  void dispose() {
    _addName.dispose();
    _addPage.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final tree = state.reviewTree;
    final ink = StudioColors.inkOf(context);
    return SingleChildScrollView(
      key: const ValueKey('world-review-world'),
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: LayoutBuilder(
            builder: (context, box) {
              final wide = box.maxWidth >= 900;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Review the world before you mint it',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Read what was written, fix what you like by hand, or '
                    'tell the wizard what to change and send it back around '
                    'the reviewers. Nothing is saved until Mint World.',
                    style: TextStyle(
                      color: StudioColors.proseOf(context),
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _nameAndDescription(context, wide),
                  const SizedBox(height: 20),
                  WorldStartingPlaceCard(state: state),
                  const SizedBox(height: 20),
                  WorldDirectionBox(state: state),
                  if (state.reviewing) ...[
                    const SizedBox(height: 16),
                    _progress(context),
                  ],
                  if (state.error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      state.error!,
                      key: const Key('world-review-error'),
                      style: TextStyle(color: StudioColors.honeyOf(context)),
                    ),
                  ],
                  const SizedBox(height: 24),
                  _place(
                    context,
                    name: state.nameController.text.trim().isEmpty
                        ? 'The world'
                        : state.nameController.text.trim(),
                    placeKey: '',
                    kind: 'world',
                    description: tree.root.description,
                    climate: state.climateEnabled,
                    entries: tree.root.entries,
                    wide: wide,
                  ),
                  for (final p in tree.places) ...[
                    const SizedBox(height: 24),
                    _place(
                      context,
                      name: p.name,
                      placeKey: p.name,
                      kind: p.parentName.isEmpty
                          ? 'place'
                          : 'place · inside ${p.parentName}',
                      description: p.description,
                      climate: p.hasClimate,
                      entries: p.entries,
                      wide: wide,
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _nameAndDescription(BuildContext context, bool wide) {
    final state = widget.state;
    final ink = StudioColors.inkOf(context);
    InputDecoration deco(String label) => InputDecoration(
      labelText: label,
      filled: true,
      fillColor: StudioColors.bgOf(context),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    );
    final name = TextField(
      controller: state.nameController,
      style: TextStyle(color: ink),
      decoration: deco('World name'),
    );
    final desc = TextField(
      controller: state.descController,
      minLines: 1,
      maxLines: 4,
      style: TextStyle(color: ink),
      decoration: deco('Description'),
    );
    if (!wide) {
      return Column(children: [name, const SizedBox(height: 12), desc]);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: name),
        const SizedBox(width: 16),
        Expanded(child: desc),
      ],
    );
  }

  Widget _progress(BuildContext context) {
    final state = widget.state;
    final bad = StudioColors.badOf(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        color: StudioColors.raiseOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: StudioColors.lineOf(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: WorldProgressPanel(state: state, fallback: 'Working…'),
          ),
          const SizedBox(width: 12),
          OutlinedButton(
            key: const Key('world-review-stop'),
            onPressed: state.abortWrite,
            style: OutlinedButton.styleFrom(
              foregroundColor: bad,
              side: BorderSide(color: bad, width: 1.5),
            ),
            child: const Text('Stop'),
          ),
        ],
      ),
    );
  }

  Widget _place(
    BuildContext context, {
    required String name,
    required String placeKey,
    required String kind,
    required String description,
    required bool climate,
    required List<LorebookEntry> entries,
    required bool wide,
  }) {
    final state = widget.state;
    final ink = StudioColors.inkOf(context);
    final muted = StudioColors.mutedOf(context);
    final amber = StudioColors.amberOf(context);
    final open = _expanded.contains(placeKey);
    final shown = open ? entries : entries.take(kWorldReviewCardsShown);
    final hidden = entries.length - shown.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: StudioColors.lineOf(context)),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: ink,
                          ),
                        ),
                        _chip(context, kind),
                        _chip(
                          context,
                          '${entries.length} card${entries.length == 1 ? '' : 's'}',
                        ),
                        _chip(
                          context,
                          climate ? 'own weather' : 'weather from above',
                        ),
                      ],
                    ),
                    if (description.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        description,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: StudioColors.proseOf(context),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              TextButton(
                key: Key('world-review-add-$placeKey'),
                onPressed: state.busy
                    ? null
                    : () => setState(
                        () => _addOpenFor = _addOpenFor == placeKey
                            ? null
                            : placeKey,
                      ),
                style: TextButton.styleFrom(foregroundColor: amber),
                child: const Text('+ Add a card here'),
              ),
            ],
          ),
        ),
        if (_addOpenFor == placeKey) ...[
          const SizedBox(height: 10),
          _addRow(context, placeKey),
        ],
        const SizedBox(height: 12),
        if (entries.isEmpty)
          Text('No cards here yet.', style: TextStyle(color: muted))
        else
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              for (final e in shown)
                SizedBox(
                  width: wide ? 520 : double.infinity,
                  child: WorldEntryCard(
                    key: ValueKey('card-$placeKey-${e.name}'),
                    state: state,
                    entry: e,
                  ),
                ),
            ],
          ),
        if (hidden > 0 || (open && entries.length > kWorldReviewCardsShown))
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Center(
              child: TextButton(
                key: Key('world-review-more-$placeKey'),
                onPressed: () => setState(() {
                  if (!_expanded.remove(placeKey)) _expanded.add(placeKey);
                }),
                style: TextButton.styleFrom(foregroundColor: muted),
                child: Text(
                  open
                      ? 'Show fewer'
                      : 'Show the other $hidden card${hidden == 1 ? '' : 's'} in $name',
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _addRow(BuildContext context, String placeKey) {
    final state = widget.state;
    final ink = StudioColors.inkOf(context);
    final amber = StudioColors.amberOf(context);
    InputDecoration deco(String hint) => InputDecoration(
      isDense: true,
      hintText: hint,
      hintStyle: TextStyle(color: StudioColors.mutedOf(context)),
      filled: true,
      fillColor: StudioColors.bgOf(context),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: StudioColors.cardOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: amber),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Add a card here: a name, and which wiki page to read '
            '(the name itself when blank)',
            style: TextStyle(
              fontSize: 12,
              color: StudioColors.mutedOf(context),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 240,
                child: TextField(
                  key: Key('world-review-add-name-$placeKey'),
                  controller: _addName,
                  style: TextStyle(color: ink),
                  decoration: deco('Kurosaki Clinic'),
                ),
              ),
              SizedBox(
                width: 300,
                child: TextField(
                  key: Key('world-review-add-page-$placeKey'),
                  controller: _addPage,
                  style: TextStyle(color: ink),
                  decoration: deco('wiki page title (optional)'),
                ),
              ),
              FilledButton(
                key: Key('world-review-add-send-$placeKey'),
                onPressed: state.busy
                    ? null
                    : () {
                        final name = _addName.text.trim();
                        if (name.isEmpty) return;
                        state.addCard(
                          place: placeKey,
                          name: name,
                          page: _addPage.text,
                        );
                        _addName.clear();
                        _addPage.clear();
                        setState(() => _addOpenFor = null);
                      },
                style: FilledButton.styleFrom(
                  backgroundColor: amber,
                  foregroundColor: StudioColors.bgOf(context),
                ),
                child: const Text('Write it'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: StudioColors.raiseOf(context),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: StudioColors.lineOf(context)),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 11, color: StudioColors.proseOf(context)),
    ),
  );
}
