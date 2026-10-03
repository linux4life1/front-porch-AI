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
import 'package:front_porch_ai/ui/story_studio/story_studio.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// Who feels what about whom: a grid (a row reads "how this person sees
/// that one"), a list on narrow screens, and the history of the pair you
/// tap.
class RelationshipsSection extends StatefulWidget {
  final StoryProject project;

  const RelationshipsSection({super.key, required this.project});

  @override
  State<RelationshipsSection> createState() => _RelationshipsSectionState();
}

class _RelationshipsSectionState extends State<RelationshipsSection> {
  String? _from;
  String? _to;

  StoryProject get p => widget.project;

  /// People who appear in at least one relationship, cast order.
  List<String> get _people {
    final named = {
      for (final r in p.relationships) ...[r.from, r.to],
    };
    return [
      for (final c in p.cast)
        if (named.contains(c.name)) c.name,
    ];
  }

  Color _tone(BuildContext context, StoryRelationship r) =>
      switch (StoryContinuity.tone(r.trust)) {
        'warm' => AppColors.journalAccentOf(context),
        'hot' => AppColors.negativeAccentOf(context),
        _ => AppColors.porchHoneyOf(context),
      };

  @override
  Widget build(BuildContext context) {
    if (p.relationships.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            p.engineMode == StoryEngineMode.studio
                ? 'Relationships appear once the story bible is built, and '
                      'move as scenes are written.'
                : 'The Quick engine does not track relationships. Switch the '
                      'story to Studio to get this screen.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary(context)),
          ),
        ),
      );
    }
    final people = _people;
    final selected = _from != null && _to != null
        ? p.relationship(_from!, _to!)
        : null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 620;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            WarmCard(
              padding: const EdgeInsets.all(12),
              child: narrow ? _list(context) : _matrix(context, people),
            ),
            if (selected != null) ...[
              const SizedBox(height: 12),
              _detail(context, selected),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  narrow
                      ? 'Tap a row for its history.'
                      : 'Read a row as “how this person sees that one”. Tap '
                            'a cell for its history.',
                  style: TextStyle(
                    color: AppColors.textTertiary(context),
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _matrix(BuildContext context, List<String> people) {
    final head = TextStyle(
      color: AppColors.textTertiary(context),
      fontSize: 11.5,
      fontWeight: FontWeight.w600,
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const FixedColumnWidth(96),
        columnWidths: const {0: FixedColumnWidth(90)},
        children: [
          TableRow(
            children: [
              const SizedBox(),
              for (final name in people)
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: Text(
                    name.split(' ').first,
                    textAlign: TextAlign.center,
                    style: head,
                  ),
                ),
            ],
          ),
          for (final from in people)
            TableRow(
              children: [
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: Text(from.split(' ').first, style: head),
                ),
                for (final to in people)
                  Padding(
                    padding: const EdgeInsets.all(3),
                    child: from == to
                        ? _selfCell(context)
                        : _cell(context, from, to),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _selfCell(BuildContext context) => Container(
    height: 46,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(7),
      border: Border.all(
        color: AppColors.borderOf(context).withValues(alpha: 0.5),
        style: BorderStyle.solid,
      ),
    ),
  );

  Widget _cell(BuildContext context, String from, String to) {
    final r = p.relationship(from, to);
    final on = _from == from && _to == to;
    return InkWell(
      borderRadius: BorderRadius.circular(7),
      onTap: r == null
          ? null
          : () => setState(() {
              _from = from;
              _to = to;
            }),
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: AppColors.cardOf(context),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: on
                ? AppColors.porchAmberOf(context)
                : AppColors.borderOf(context),
            width: on ? 2 : 1,
          ),
        ),
        child: r == null
            ? Center(
                child: Text(
                  '—',
                  style: TextStyle(color: AppColors.textTertiary(context)),
                ),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    r.feeling,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _tone(context, r),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (r.note.isNotEmpty)
                    Text(
                      r.note,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textTertiary(context),
                        fontSize: 10.5,
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _list(BuildContext context) => Column(
    children: [
      for (final r in p.relationships)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(
            '${r.from} → ${r.to}',
            style: TextStyle(
              color: AppColors.textPrimary(context),
              fontSize: 13,
            ),
          ),
          subtitle: Text(
            r.note,
            style: TextStyle(
              color: AppColors.textTertiary(context),
              fontSize: 11.5,
            ),
          ),
          trailing: Text(
            r.feeling,
            style: TextStyle(
              color: _tone(context, r),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          onTap: () => setState(() {
            _from = r.from;
            _to = r.to;
          }),
        ),
    ],
  );

  Widget _detail(BuildContext context, StoryRelationship r) {
    return WarmCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '${r.from} → ${r.to}',
                style: TextStyle(
                  color: AppColors.textPrimary(context),
                  fontWeight: FontWeight.w700,
                ),
              ),
              StoryChip(
                r.feeling,
                tone: switch (StoryContinuity.tone(r.trust)) {
                  'warm' => 'teal',
                  'hot' => 'bad',
                  _ => 'honey',
                },
              ),
              StoryChip('trust ${r.trust}/10'),
              if (r.subtext.isNotEmpty)
                Text(
                  'Subtext: ${r.subtext}',
                  style: TextStyle(
                    color: AppColors.textTertiary(context),
                    fontSize: 12,
                  ),
                ),
              TextButton(
                onPressed: () => _edit(context, r),
                child: const Text('Edit'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (r.history.isEmpty)
            Text(
              'No moves yet.',
              style: TextStyle(
                color: AppColors.textTertiary(context),
                fontSize: 12,
              ),
            ),
          for (final h in r.history)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  SizedBox(
                    width: 36,
                    child: Text(
                      h.sceneId.isEmpty ? '—' : p.sceneLabelById(h.sceneId),
                      style: TextStyle(
                        color: AppColors.textTertiary(context),
                        fontSize: 12,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '${h.from} → ${h.to}'
                      '${h.reason.isEmpty ? '' : ' · ${h.reason}'}',
                      style: TextStyle(
                        color: AppColors.textSecondary(context),
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, StoryRelationship r) async {
    final feeling = TextEditingController(text: r.feeling);
    final note = TextEditingController(text: r.note);
    final subtext = TextEditingController(text: r.subtext);
    var trust = r.trust;
    final ok = await showWarmDialog<bool>(
      context,
      title: '${r.from} → ${r.to}',
      width: 420,
      content: StatefulBuilder(
        builder: (context, setLocal) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppTextField(
              controller: feeling,
              decoration: const InputDecoration(labelText: 'Feeling'),
            ),
            const SizedBox(height: 8),
            AppTextField(
              controller: note,
              decoration: const InputDecoration(labelText: 'Note'),
            ),
            const SizedBox(height: 8),
            AppTextField(
              controller: subtext,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Unspoken'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  'Trust $trust',
                  style: TextStyle(color: AppColors.textSecondary(context)),
                ),
                Expanded(
                  child: Slider(
                    value: trust.toDouble(),
                    min: 0,
                    max: 10,
                    divisions: 10,
                    activeColor: AppColors.porchAmberOf(context),
                    onChanged: (v) => setLocal(() => trust = v.round()),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        warmDialogCancel(context, value: false),
        warmDialogConfirm(
          context,
          label: 'Save',
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
    if (ok != true || !context.mounted) return;
    StoryContinuity.shift(
      p,
      from: r.from,
      to: r.to,
      feeling: feeling.text,
      note: note.text,
      subtext: subtext.text,
      trust: trust,
      reason: 'Edited by hand.',
    );
    await Provider.of<StoryRepository>(context, listen: false).saveProject(p);
    setState(() {});
  }
}
