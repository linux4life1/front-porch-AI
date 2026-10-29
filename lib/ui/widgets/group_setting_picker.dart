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

import 'package:front_porch_ai/models/world.dart';
import 'package:front_porch_ai/services/chat/weather_biomes.dart';
import 'package:front_porch_ai/services/world_chain.dart';
import 'package:front_porch_ai/services/world_repository.dart';
import 'package:front_porch_ai/services/world_store/world_store.dart';
import 'package:front_porch_ai/ui/pages/worlds/world_library_rows.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/ui/widgets/group_setting_picker/group_setting_tiles.dart';

/// Where a group's new chats meet: one world (radio), the place inside it
/// the chats start at (its starred place unless another is picked), and any
/// lore-only worlds. Shared by the Create Group wizard, Edit Group and the
/// in-chat Group Settings so the three can never disagree.
class GroupSettingPicker extends StatefulWidget {
  const GroupSettingPicker({
    super.key,
    required this.value,
    required this.onChanged,
    required this.places,
    required this.weatherOf,
    this.suggestedBy = const {},
  });

  final GroupWorldChoice value;
  final ValueChanged<GroupWorldChoice> onChanged;

  /// Every world and place in the library (`WorldRepository.placeWorlds`).
  final List<World> places;

  /// The climate a slot id brings, for display; null when it has none.
  final String? Function(String id) weatherOf;

  /// World id → the members whose cards already link it.
  final Map<String, List<String>> suggestedBy;

  @override
  State<GroupSettingPicker> createState() => _GroupSettingPickerState();
}

class _GroupSettingPickerState extends State<GroupSettingPicker> {
  late bool _loreOpen = widget.value.loreIds.isNotEmpty;

  World? _lookup(String id) {
    for (final w in widget.places) {
      if (w.id == id) return w;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final rows = libraryDisplayOrder(widget.places);
    final roots = linkableWorldsOf(rows, _lookup);
    if (roots.isEmpty) {
      return Text(
        'No worlds in your library yet. Make one on the Worlds page, then '
        'come back to set where the group meets.',
        style: TextStyle(color: AppColors.textSecondary(context)),
      );
    }
    final ordered = [
      ...roots.where((w) => widget.suggestedBy.containsKey(w.id)),
      ...roots.where((w) => !widget.suggestedBy.containsKey(w.id)),
    ];
    final setting = widget.value.settingId == null
        ? null
        : _lookup(widget.value.settingId!);
    final root = setting == null ? null : topWorldOf(setting, _lookup);

    final worlds = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const GroupPickerHeading('World'),
        for (final w in ordered) ...[
          _worldTile(w, rows, selected: root?.id == w.id),
          const SizedBox(height: 8),
        ],
        GroupChoiceTile(
          key: const ValueKey('group-setting-world-none'),
          title: 'No world',
          subtitle: 'No weather, no world lore',
          selected: root == null,
          onTap: () => _emit(settingId: null),
        ),
      ],
    );
    final start = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const GroupPickerHeading('Start at'),
        _placePanel(context, root, rows),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, c) => c.maxWidth >= 640
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: worlds),
                    const SizedBox(width: 16),
                    Expanded(child: start),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [worlds, const SizedBox(height: 16), start],
                ),
        ),
        const SizedBox(height: 16),
        _loreSection(context, roots, root),
        const SizedBox(height: 16),
        _summary(context),
      ],
    );
  }

  Widget _worldTile(World w, List<World> rows, {required bool selected}) {
    final placeCount = placesInside(w, rows, _lookup).length;
    final facts = w.lorebook.enabledEntryCount;
    final weather = widget.weatherOf(startingPlaceOf(w, _lookup).id);
    final who = widget.suggestedBy[w.id];
    return GroupChoiceTile(
      key: ValueKey('group-setting-world-${w.id}'),
      title: w.name,
      subtitle: [
        weather ?? 'No weather',
        placeCount == 0
            ? 'no places yet'
            : '$placeCount place${placeCount == 1 ? '' : 's'}',
        '$facts fact${facts == 1 ? '' : 's'}',
      ].join(' · '),
      chips: [if (who != null && who.isNotEmpty) 'Linked by ${who.join(', ')}'],
      selected: selected,
      onTap: () {
        if (selected) return;
        _emit(settingId: w.id);
      },
    );
  }

  Widget _placePanel(BuildContext context, World? root, List<World> rows) {
    Widget note(String text) => Padding(
      padding: const EdgeInsets.all(12),
      child: Text(
        text,
        style: TextStyle(color: AppColors.textSecondary(context)),
      ),
    );
    final Widget body;
    if (root == null) {
      body = note(
        'No world picked. New chats have no weather and no world lore.',
      );
    } else {
      final places = placesInside(root, rows, _lookup);
      if (places.isEmpty) {
        body = note(
          'This world has no places yet. Chats start in the world itself. '
          'Add places on the Worlds page.',
        );
      } else {
        final star = startingPlaceOf(root, _lookup);
        final picked = widget.value.settingId == root.id
            ? star.id
            : widget.value.settingId;
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final p in places)
              GroupChoiceTile(
                key: ValueKey('group-setting-place-${p.id}'),
                framed: false,
                indent: worldChain(p, _lookup).length - 2,
                title: p.name,
                subtitle: p.description.trim().isEmpty
                    ? null
                    : _firstLine(p.description),
                chips: [if (p.id == star.id) 'Default'],
                leading: Icon(
                  p.id == star.id ? Icons.star_rounded : Icons.star_border,
                  size: 16,
                  color: p.id == star.id
                      ? AppColors.formAccentOf(context)
                      : AppColors.textTertiary(context),
                ),
                selected: p.id == picked,
                // The starred place is stored as the world itself, so the
                // group follows the star if the author moves it later.
                onTap: () => _emit(settingId: p.id == star.id ? root.id : p.id),
              ),
          ],
        );
      }
    }
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: body,
    );
  }

  Widget _loreSection(BuildContext context, List<World> roots, World? root) {
    final options = [
      for (final w in roots)
        if (w.id != root?.id) w,
    ];
    final count = widget.value.loreIds.length;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: const ValueKey('group-setting-lore-toggle'),
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() => _loreOpen = !_loreOpen),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Also read lore from '
                      '${count == 0 ? '(none)' : '($count)'}',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary(context),
                      ),
                    ),
                  ),
                  Icon(
                    _loreOpen ? Icons.expand_less : Icons.expand_more,
                    color: AppColors.textTertiary(context),
                    semanticLabel: _loreOpen ? 'Collapse' : 'Expand',
                  ),
                ],
              ),
            ),
          ),
          if (_loreOpen) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                'These worlds add their lorebook only. They never set the '
                'weather or the starting place.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textSecondary(context),
                ),
              ),
            ),
            if (options.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Text(
                  'No other worlds in your library.',
                  style: TextStyle(color: AppColors.textTertiary(context)),
                ),
              ),
            for (final w in options)
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
                child: GroupChoiceTile(
                  key: ValueKey('group-setting-lore-${w.id}'),
                  kind: GroupChoiceKind.checkbox,
                  framed: false,
                  title: w.name,
                  subtitle: 'Lore only · no weather',
                  selected: widget.value.loreIds.contains(w.id),
                  onTap: () => _toggleLore(w.id),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _summary(BuildContext context) {
    return Container(
      key: const ValueKey('group-setting-summary'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Text(
        groupSettingSummary(widget.value, _lookup, widget.weatherOf),
        style: TextStyle(color: AppColors.textPrimary(context)),
      ),
    );
  }

  void _emit({required String? settingId}) {
    widget.onChanged(
      GroupWorldChoice(
        settingId: settingId,
        loreIds: [
          for (final id in widget.value.loreIds)
            if (settingId == null ||
                _lookup(settingId) == null ||
                topWorldOf(_lookup(settingId)!, _lookup).id != id)
              id,
        ],
      ),
    );
  }

  void _toggleLore(String id) {
    final lore = [...widget.value.loreIds];
    if (!lore.remove(id)) lore.add(id);
    widget.onChanged(
      GroupWorldChoice(settingId: widget.value.settingId, loreIds: lore),
    );
  }

  static String _firstLine(String text) {
    final line = text.trim().split('\n').first.trim();
    return line.length > 90 ? '${line.substring(0, 89)}…' : line;
  }
}

/// One plain sentence saying where new chats start and what they read.
String groupSettingSummary(
  GroupWorldChoice choice,
  World? Function(String id) lookup,
  String? Function(String id) weatherOf,
) {
  final setting = choice.settingId == null ? null : lookup(choice.settingId!);
  final buf = StringBuffer();
  if (setting == null) {
    buf.write('New chats start with no world.');
  } else {
    final root = topWorldOf(setting, lookup);
    final start = setting.id == root.id
        ? startingPlaceOf(root, lookup)
        : setting;
    buf.write(
      start.id == root.id
          ? 'New chats start in ${root.name}.'
          : 'New chats start at ${start.name} in ${root.name}.',
    );
    final weather = weatherOf(start.id);
    buf.write(weather == null ? ' No weather.' : ' Weather: $weather.');
  }
  final lore = [for (final id in choice.loreIds) ?lookup(id)?.name];
  if (lore.isNotEmpty) {
    final names = lore.length == 1
        ? lore.first
        : '${lore.sublist(0, lore.length - 1).join(', ')} and ${lore.last}';
    final them = lore.length == 1 ? 'it' : 'them';
    buf.write(' Also reads lore from $names, with no weather from $them.');
  }
  return buf.toString();
}

/// The picker's `weatherOf`: the climate a slot's chain authors, named.
String? Function(String id) groupWeatherLabels(WorldRepository repo) => (id) {
  final author = repo.climateAuthorFor(id);
  if (author == null) return null;
  return Biome.resolve(
    biomeId: author.biomeId,
    biomeJson: author.biomeJson,
  ).displayName;
};
