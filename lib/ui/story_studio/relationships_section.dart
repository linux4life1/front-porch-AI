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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/story/story.dart';
import 'package:front_porch_ai/ui/story_studio/studio_buttons.dart';
import 'package:front_porch_ai/ui/story_studio/studio_cards.dart';
import 'package:front_porch_ai/ui/story_studio/studio_theme.dart';
import 'package:front_porch_ai/ui/story_studio/studio_widgets.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// Relationships (sketch S): the matrix stays the size of its cells; read a
/// row as "how this person sees that one"; a tapped cell shows its history.
/// Phones get a list of pairs instead of the grid.
class RelationshipsSection extends StatefulWidget {
  final StoryProject project;

  const RelationshipsSection({super.key, required this.project});

  @override
  State<RelationshipsSection> createState() => _RelationshipsSectionState();
}

class _RelationshipsSectionState extends State<RelationshipsSection> {
  (String, String)? _selected;

  StoryProject get p => widget.project;

  List<String> get _names {
    final names = <String>{for (final m in p.cast) m.name};
    for (final r in p.relationships) {
      if (p.castByName(r.from) != null) names.add(r.from);
      if (p.castByName(r.to) != null) names.add(r.to);
    }
    return names.toList();
  }

  @override
  Widget build(BuildContext context) {
    final names = _names;
    final muted = StudioColors.mutedOf(context);
    final wide = MediaQuery.of(context).size.width >= 760;
    final sel = _selected ?? _firstPair();
    final rel = sel == null ? null : p.relationship(sel.$1, sel.$2);
    final latest = p.relationships
        .expand((r) => r.history)
        .where((h) => h.sceneId.isNotEmpty)
        .lastOrNull;
    return ListView(
      key: const ValueKey('studio-relationships'),
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                latest == null
                    ? 'Nothing recorded yet'
                    : 'After scene ${p.sceneLabelById(latest.sceneId)}',
                style: StudioType.ui(context, size: 12.5, color: muted),
              ),
            ),
            StoryButton(
              'Add pair',
              key: const ValueKey('rel-add'),
              icon: Icons.add,
              onPressed: names.length < 2 ? null : () => _edit(null),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (names.length < 2 || p.relationships.isEmpty)
          StoryEmptyState(
            title: 'No relationships yet',
            detail: p.engineMode == StoryEngineMode.studio
                ? 'Studio records who feels what about whom after every '
                      'scene. Write a scene, or add a pair yourself.'
                : 'The Quick engine does not track relationships. Switch the '
                      'story to Studio under Setup, or add a pair yourself.',
          )
        else if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StoryCard(
                padding: const EdgeInsets.all(10),
                children: [_matrix(names)],
              ),
              const SizedBox(width: 12),
              if (rel != null) Expanded(child: _detail(rel)),
            ],
          )
        else ...[
          for (final r in p.relationships) ...[
            _pairRow(r),
            const SizedBox(height: 6),
          ],
          if (rel != null) ...[const SizedBox(height: 6), _detail(rel)],
        ],
      ],
    );
  }

  (String, String)? _firstPair() {
    final r = p.relationships.firstOrNull;
    return r == null ? null : (r.from, r.to);
  }

  Widget _matrix(List<String> names) {
    final muted = StudioColors.mutedOf(context);
    Widget head(String s) => SizedBox(
      width: 74,
      child: Text(
        s,
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
        style: StudioType.ui(
          context,
          size: 11.5,
          weight: FontWeight.w600,
          color: muted,
        ),
      ),
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const SizedBox(width: 74),
              for (final n in names) ...[const SizedBox(width: 4), head(n)],
            ],
          ),
          for (final a in names) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                head(a),
                for (final b in names) ...[
                  const SizedBox(width: 4),
                  _cell(a, b),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _cell(String a, String b) {
    if (a == b) {
      return Container(
        width: 74,
        height: 46,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: StudioColors.lineOf(context)),
        ),
      );
    }
    final r = p.relationship(a, b);
    final sel = _selected ?? _firstPair();
    final on = sel != null && sel.$1 == a && sel.$2 == b;
    final tone = r == null ? '' : StoryContinuity.tone(r.trust);
    final color = switch (tone) {
      'warm' => StudioColors.tealOf(context),
      'hot' => StudioColors.badOf(context),
      'mid' => StudioColors.honeyOf(context),
      _ => StudioColors.faintOf(context),
    };
    return InkWell(
      key: ValueKey('rel-$a-$b'),
      borderRadius: BorderRadius.circular(7),
      onTap: () => setState(() => _selected = (a, b)),
      child: Container(
        width: 74,
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: StudioColors.cardOf(context),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: on
                ? StudioColors.amberOf(context)
                : StudioColors.lineOf(context),
            width: on ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              r == null || r.feeling.isEmpty ? '—' : r.feeling,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: StudioType.ui(
                context,
                size: 11.5,
                weight: FontWeight.w600,
                color: color,
              ),
            ),
            if (r != null && r.note.isNotEmpty)
              Text(
                r.note,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: StudioType.ui(
                  context,
                  size: 10.5,
                  color: StudioColors.mutedOf(context),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _pairRow(StoryRelationship r) {
    final tone = StoryContinuity.tone(r.trust);
    return StoryCard(
      onTap: () => setState(() => _selected = (r.from, r.to)),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${r.from} → ${r.to}',
                style: StudioType.ui(context, weight: FontWeight.w600),
              ),
            ),
            StoryChip(
              r.feeling.isEmpty ? '—' : r.feeling,
              tone: tone == 'warm'
                  ? 'teal'
                  : tone == 'hot'
                  ? 'bad'
                  : 'honey',
            ),
          ],
        ),
      ],
    );
  }

  Widget _detail(StoryRelationship r) {
    final muted = StudioColors.mutedOf(context);
    final tone = StoryContinuity.tone(r.trust);
    return StoryCard(
      key: const ValueKey('rel-detail'),
      children: [
        Row(
          children: [
            Text(
              '${r.from} → ${r.to}',
              style: StudioType.ui(context, weight: FontWeight.w700),
            ),
            const SizedBox(width: 8),
            StoryChip(
              r.feeling.isEmpty ? '—' : r.feeling,
              tone: tone == 'warm'
                  ? 'teal'
                  : tone == 'hot'
                  ? 'bad'
                  : 'honey',
            ),
            const SizedBox(width: 6),
            StoryChip('trust ${r.trust}/10'),
            const Spacer(),
            StoryButton.ghost('Edit', onPressed: () => _edit(r)),
            StoryMenuButton(
              entries: [
                StoryMenuEntry(
                  'Remove pair…',
                  danger: true,
                  onSelect: () => _remove(r),
                ),
              ],
            ),
          ],
        ),
        if (r.subtext.isNotEmpty)
          Text(
            'Unspoken: ${r.subtext}',
            style: StudioType.ui(context, size: 12, color: muted),
          ),
        if (r.history.isEmpty)
          Text(
            'No history yet.',
            style: StudioType.ui(context, size: 12, color: muted),
          ),
        for (final h in r.history)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 40,
                child: Text(
                  h.sceneId.isEmpty ? '—' : p.sceneLabelById(h.sceneId),
                  style: StudioType.mono(context),
                ),
              ),
              Expanded(
                child: Text(
                  '${h.from} → ${h.to}${h.reason.isEmpty ? '' : ' · ${h.reason}'}',
                  style: StudioType.ui(
                    context,
                    size: 12,
                    color: identical(h, r.history.last)
                        ? StudioColors.inkOf(context)
                        : muted,
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Future<void> _edit(StoryRelationship? r) async {
    final names = _names;
    var from = r?.from ?? names.first;
    var to = r?.to ?? names.firstWhere((n) => n != from, orElse: () => from);
    final feeling = TextEditingController(text: r?.feeling ?? '');
    final note = TextEditingController(text: r?.note ?? '');
    final subtext = TextEditingController(text: r?.subtext ?? '');
    var trust = r?.trust ?? 5;
    final ok = await showStoryDialog<bool>(
      context,
      title: r == null ? 'Add pair' : '${r.from} → ${r.to}',
      width: 460,
      body: StatefulBuilder(
        builder: (ctx, setLocal) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (r == null) ...[
              const StoryKeyLabel('Who'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final n in names)
                    StoryChip(
                      n,
                      selected: n == from,
                      onTap: () => setLocal(() => from = n),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              const StoryKeyLabel('Sees'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final n in names)
                    if (n != from)
                      StoryChip(
                        n,
                        selected: n == to,
                        onTap: () => setLocal(() => to = n),
                      ),
                ],
              ),
              const SizedBox(height: 10),
            ],
            StoryField(controller: feeling, hint: 'Feeling (one or two words)'),
            const SizedBox(height: 8),
            StoryField(controller: note, hint: 'Note (two or three words)'),
            const SizedBox(height: 8),
            StoryField(controller: subtext, hint: 'Unspoken'),
            const SizedBox(height: 10),
            Row(
              children: [
                Text('Trust $trust/10', style: StudioType.ui(ctx, size: 12)),
                Expanded(
                  child: Slider(
                    value: trust.toDouble(),
                    min: 0,
                    max: 10,
                    divisions: 10,
                    onChanged: (v) => setLocal(() => trust = v.round()),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: (ctx) => [
        StoryButton.ghost('Cancel', onPressed: () => Navigator.pop(ctx, false)),
        StoryButton.primary(
          r == null ? 'Add' : 'Save',
          onPressed: () => Navigator.pop(ctx, true),
        ),
      ],
    );
    if (ok != true || !mounted || feeling.text.trim().isEmpty || from == to) {
      return;
    }
    StoryContinuity.shift(
      p,
      from: from,
      to: to,
      feeling: feeling.text,
      note: note.text,
      subtext: subtext.text,
      trust: trust,
      reason: 'Edited by hand.',
    );
    await Provider.of<StoryRepository>(context, listen: false).saveProject(p);
    setState(() => _selected = (from, to));
  }

  Future<void> _remove(StoryRelationship r) async {
    final ok = await showStoryConfirm(
      context,
      title: 'Remove ${r.from} → ${r.to}?',
      body:
          'The feeling and its history are removed. The engine may record '
          'it again after the next scene.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!ok || !mounted) return;
    p.relationships.remove(r);
    await Provider.of<StoryRepository>(context, listen: false).saveProject(p);
    setState(() => _selected = null);
  }
}
