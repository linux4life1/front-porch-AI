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

import 'package:front_porch_ai/models/character/trait_kit.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/theme/chat_colors.dart';

/// Boons & Bogies card kit editor — the structured sibling of
/// [ChipListEditor] (docs/design/boons-and-bogies.md §4). One row per
/// entry: kind, text, starting tier, and the pin that protects a seeded
/// flaw from fading. The 6-entry cap (ruling 11) is enforced HERE: the
/// parse layer truncates, but an author who hits the wall should see it.
///
/// Same visual language as the identity chip lists: caps and counts are
/// honest, entry stays open for rapid writing.
class TraitKitEditor extends StatefulWidget {
  const TraitKitEditor({
    super.key,
    required this.values,
    required this.onChanged,
    this.helper,
  });

  final List<TraitKitEntry> values;
  final ValueChanged<List<TraitKitEntry>> onChanged;
  final String? helper;

  @override
  State<TraitKitEditor> createState() => _TraitKitEditorState();
}

class _TraitKitEditorState extends State<TraitKitEditor> {
  final Map<int, TextEditingController> _controllers = {};
  final Map<int, FocusNode> _focus = {};

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final f in _focus.values) {
      f.dispose();
    }
    super.dispose();
  }

  bool get _full => widget.values.length >= TraitKitEntry.maxEntries;
  int get _bogies => widget.values.where((e) => e.isBogey).length;

  TextEditingController _controllerFor(int index) =>
      _controllers.putIfAbsent(index, () => TextEditingController());

  FocusNode _focusFor(int index) =>
      _focus.putIfAbsent(index, () => FocusNode());

  /// Rewriting earlier rows shifts indices; rebuild controllers from the
  /// values the parent currently holds (text edits commit on every keystroke
  /// and the parent echoes back the same list). A shifted row's controller
  /// can hold the DELETED row's words, so an unfocused field re-syncs to
  /// what the list actually holds — focused means the author is mid-word,
  /// and their keystroke always wins.
  void _syncControllers() {
    final stale = _controllers.keys.where((i) => i >= widget.values.length);
    for (final i in stale.toList()) {
      _controllers.remove(i)?.dispose();
      _focus.remove(i)?.dispose();
    }
  }

  void _replace(List<TraitKitEntry> next) => widget.onChanged(next);

  void _add() {
    if (_full) return;
    _replace([
      ...widget.values,
      const TraitKitEntry(kind: TraitKitEntry.kindBoon, text: ''),
    ]);
  }

  void _remove(int index) {
    final next = [...widget.values]..removeAt(index);
    _replace(next);
    _syncControllers();
  }

  void _update(int index, TraitKitEntry Function(TraitKitEntry) edit) {
    final next = [...widget.values];
    next[index] = edit(next[index]);
    _replace(next);
  }

  @override
  Widget build(BuildContext context) {
    final honey = AppColors.porchHoneyOf(context);
    final bogey = ChatColors.bogeyOf(context);
    final textSecondary = AppColors.textSecondary(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'BOONS & BOGIES',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
                color: textSecondary,
              ),
            ),
            const Spacer(),
            Text(
              '${widget.values.length} of ${TraitKitEntry.maxEntries}',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: _full ? bogey : textSecondary,
              ),
            ),
          ],
        ),
        if (widget.helper != null) ...[
          const SizedBox(height: 4),
          Text(
            widget.helper!,
            style: TextStyle(fontSize: 11, color: textSecondary),
          ),
        ],
        const SizedBox(height: 8),
        for (var i = 0; i < widget.values.length; i++)
          _row(context, i, honey, bogey),
        const SizedBox(height: 6),
        Row(
          children: [
            TextButton.icon(
              onPressed: _full ? null : _add,
              icon: const Icon(Icons.add, size: 15),
              label: Text('Add ${_full ? '— kit is full' : 'trait'}'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: honey,
              ),
            ),
          ],
        ),
        if (_bogies > 3)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'A chat runs at most 3 active bogies — past the third, seeding '
              'drops the extras.',
              style: TextStyle(fontSize: 10.5, color: bogey),
            ),
          ),
      ],
    );
  }

  Widget _row(BuildContext context, int i, Color honey, Color bogey) {
    final entry = widget.values[i];
    final accent = entry.isBogey ? bogey : honey;
    final controller = _controllerFor(i);
    final focus = _focusFor(i);
    if (!focus.hasFocus && controller.text != entry.text) {
      controller.text = entry.text;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: accent.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            _kindToggle(i, entry),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focus,
                maxLength: TraitKitEntry.maxTextChars,
                style: const TextStyle(fontSize: 12.5),
                decoration: const InputDecoration(
                  counterText: '',
                  isDense: true,
                  border: InputBorder.none,
                  hintText: 'e.g. reads a room in one breath',
                ),
                onChanged: (v) => _update(i, (e) => _withText(e, v)),
              ),
            ),
            _tierMenu(i, entry),
            IconButton(
              tooltip: entry.pinned
                  ? 'Pinned — a seeded flaw never fades. Tap to unpin.'
                  : 'Pin so the seeded trait never fades',
              visualDensity: VisualDensity.compact,
              iconSize: 15,
              icon: Icon(
                entry.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                color: entry.pinned ? accent : AppColors.iconSecondary(context),
              ),
              onPressed: () => _update(i, (e) => _with(e, pinned: !e.pinned)),
            ),
            IconButton(
              tooltip: 'Remove',
              visualDensity: VisualDensity.compact,
              iconSize: 15,
              icon: Icon(Icons.close, color: AppColors.textTertiary(context)),
              onPressed: () => _remove(i),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kindToggle(int i, TraitKitEntry entry) => PopupMenuButton<String>(
    tooltip: 'Kind',
    initialValue: entry.kind,
    position: PopupMenuPosition.under,
    padding: EdgeInsets.zero,
    itemBuilder: (context) => const [
      PopupMenuItem(value: TraitKitEntry.kindBoon, child: Text('Boon')),
      PopupMenuItem(value: TraitKitEntry.kindBogey, child: Text('Bogey')),
    ],
    onSelected: (kind) => _update(
      i,
      // Kind decides the pin default too — a bogey arrives pinned unless
      // the author says otherwise (docs/design/boons-and-bogies.md §4).
      (e) => _with(
        e,
        kind: kind,
        pinned: kind == TraitKitEntry.kindBogey && e.text == ''
            ? true
            : e.pinned,
      ),
    ),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color:
            (entry.isBogey
                    ? ChatColors.bogeyOf(context)
                    : AppColors.porchHoneyOf(context))
                .withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            entry.kindLabel,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: entry.isBogey
                  ? ChatColors.bogeyOf(context)
                  : AppColors.porchHoneyOf(context),
            ),
          ),
          // A badge you cannot tell is a dropdown is a badge you poke at
          // blindly; the web twin is a select with its native arrow, so
          // this chip grows one too.
          Icon(
            Icons.arrow_drop_down,
            size: 15,
            color: entry.isBogey
                ? ChatColors.bogeyOf(context)
                : AppColors.porchHoneyOf(context),
          ),
        ],
      ),
    ),
  );

  // One label per tier for every surface — closed control and menu both
  // read from this table, so they cannot drift (ruling 2 vocabulary).
  static const Map<String, String> _tierBuys = {
    TraitKitEntry.tierEmerging: 'starts faint',
    TraitKitEntry.tierDeveloping: 'a known habit',
    TraitKitEntry.tierEstablished: 'core to them',
  };

  static String tierLabel(String tier) =>
      '${TraitKitEntry.seedTierNameFor(tier)} — '
      '${_tierBuys[tier] ?? _tierBuys[TraitKitEntry.tierEmerging]}';

  Widget _tierMenu(int i, TraitKitEntry entry) => PopupMenuButton<String>(
    tooltip: 'Starting tier',
    initialValue: entry.tier,
    position: PopupMenuPosition.under,
    padding: const EdgeInsets.symmetric(horizontal: 6),
    // The closed control spells out the current tier in full — a chevron
    // alone hid what the trait seeds at, and the web select never did.
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          tierLabel(entry.tier),
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
        const Icon(Icons.unfold_more, size: 14),
      ],
    ),
    itemBuilder: (context) => [
      // Ladder name (ruling 2) + what the seed buys the trait; the tier
      // wire value rides on `value:`, never on the label.
      for (final tier in const [
        TraitKitEntry.tierEmerging,
        TraitKitEntry.tierDeveloping,
        TraitKitEntry.tierEstablished,
      ])
        PopupMenuItem(value: tier, child: Text(tierLabel(tier))),
    ],
    onSelected: (tier) => _update(i, (e) => _with(e, tier: tier)),
  );

  static TraitKitEntry _withText(TraitKitEntry e, String text) =>
      _with(e, text: text);

  static TraitKitEntry _with(
    TraitKitEntry e, {
    String? kind,
    String? text,
    String? tier,
    bool? pinned,
  }) => TraitKitEntry(
    kind: kind ?? e.kind,
    text: text ?? e.text,
    tier: tier ?? e.tier,
    pinned: pinned ?? e.pinned,
    linkedTo: e.linkedTo,
  );
}
