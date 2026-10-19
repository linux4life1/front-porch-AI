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

import 'package:front_porch_ai/services/chat/chat.dart' show PocketSection;
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// What the add-item dialog hands back to its caller.
typedef PocketItemAdd = ({
  String name,
  PocketSection section,
  bool gift,
  bool correction,
});

/// Add one item to a character's Pockets & Wardrobe by hand — the other half
/// of the ✕ eraser. Three fictions, kept honest by the buttons:
///
///  * **They're wearing this** (Wearing selected) — record correction: the
///    item is on them, next reply they're just dressed, no surprise. Add
///    quietly is hidden here — a magic sundress is the wrong fiction.
///  * **Hand to them** (Carrying / Set aside) — the user gives it in-scene;
///    it lands in their hands and the next reply has them accept it knowing
///    where it came from.
///  * **Add quietly** (Carrying / Set aside) — the Easter egg: the item
///    appears out-of-band, and the next reply has them SURPRISED by something
///    they cannot account for ("how did I end up with this?").
///
/// Item text follows the same "name (state)" chip convention the character
/// editor and the sidebar row already teach — nothing new to learn.
Future<PocketItemAdd?> showPocketItemDialog(
  BuildContext context, {
  required String characterName,
  PocketSection initialSection = PocketSection.carrying,
}) {
  return showDialog<PocketItemAdd>(
    context: context,
    builder: (context) => _PocketItemDialog(
      characterName: characterName,
      initialSection: initialSection,
    ),
  );
}

class _PocketItemDialog extends StatefulWidget {
  final String characterName;
  final PocketSection initialSection;

  const _PocketItemDialog({
    required this.characterName,
    required this.initialSection,
  });

  @override
  State<_PocketItemDialog> createState() => _PocketItemDialogState();
}

class _PocketItemDialogState extends State<_PocketItemDialog> {
  final _controller = TextEditingController();
  late PocketSection _section = widget.initialSection;

  bool get _wearing => _section == PocketSection.worn;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit({required bool gift, bool correction = false}) {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop((
      name: name,
      section: correction ? PocketSection.worn : _section,
      gift: correction ? false : gift,
      correction: correction,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final amber = AppColors.porchAmberOf(context);
    return AlertDialog(
      backgroundColor: AppColors.surfaceOf(context),
      title: Text(
        'Add an item',
        style: TextStyle(fontSize: 16, color: AppColors.textPrimary(context)),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textPrimary(context),
            ),
            decoration: InputDecoration(
              hintText: _wearing ? 'red sundress' : 'brass key (scuffed)',
              hintStyle: TextStyle(color: AppColors.textTertiary(context)),
              isDense: true,
            ),
            onSubmitted: (_) => _wearing
                ? _submit(gift: false, correction: true)
                : _submit(gift: false),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            children: [
              for (final (label, section) in const [
                ('Wearing', PocketSection.worn),
                ('Carrying', PocketSection.carrying),
                ('Set aside', PocketSection.setAside),
              ])
                ChoiceChip(
                  label: Text(label, style: const TextStyle(fontSize: 11)),
                  selected: _section == section,
                  selectedColor: amber.withValues(alpha: 0.25),
                  onSelected: (_) => setState(() => _section = section),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _wearing
                ? '"They\'re wearing this" puts it on them as a record '
                      'correction — next reply they\'re just dressed.'
                : '"Hand to ${widget.characterName}" gives it in-scene — '
                      'they\'ll know it came from you. "Add quietly" slips '
                      'it in; they\'ll be surprised to find it.',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary(context),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Cancel',
            style: TextStyle(color: AppColors.textSecondary(context)),
          ),
        ),
        if (!_wearing)
          TextButton(
            onPressed: () => _submit(gift: false),
            child: Text('Add quietly', style: TextStyle(color: amber)),
          ),
        if (_wearing)
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: amber,
              foregroundColor: AppColors.onAccentOf(context),
            ),
            onPressed: () => _submit(gift: false, correction: true),
            child: const Text("They're wearing this"),
          )
        else
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: amber,
              foregroundColor: AppColors.onAccentOf(context),
            ),
            onPressed: () => _submit(gift: true),
            child: Text('Hand to ${widget.characterName}'),
          ),
      ],
    );
  }
}
