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
import 'package:flutter/services.dart';

import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// A chip list on the facts card (docs/design/creator-ui-spec.md, "Chip"):
/// 34px chips, `raise` fill, radius 10, 13px ink, a 14px muted remove ×,
/// and a "+ add" chip (1px amber, amber 13 / 700) that opens a one-line box
/// in its place. Enter adds; an empty Enter or Escape closes it.
class ProfileChipList extends StatefulWidget {
  const ProfileChipList({
    super.key,
    required this.values,
    required this.onChanged,
    this.enabled = true,
  });

  final List<String> values;
  final ValueChanged<List<String>> onChanged;
  final bool enabled;

  @override
  State<ProfileChipList> createState() => _ProfileChipListState();
}

class _ProfileChipListState extends State<ProfileChipList> {
  final _box = TextEditingController();
  final _focus = FocusNode();
  bool _adding = false;

  @override
  void didUpdateWidget(ProfileChipList old) {
    super.didUpdateWidget(old);
    // Locked while it was open: close it, nothing typed is added.
    if (!widget.enabled && _adding) {
      _box.clear();
      _adding = false;
    }
  }

  /// Escape closes the add box without adding.
  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent || e.logicalKey != LogicalKeyboardKey.escape) {
      return KeyEventResult.ignored;
    }
    _box.clear();
    setState(() => _adding = false);
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    _box.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit(String text) {
    final t = text.trim();
    if (t.isNotEmpty && !widget.values.contains(t)) {
      widget.onChanged([...widget.values, t]);
    }
    _box.clear();
    setState(() => _adding = false);
  }

  @override
  Widget build(BuildContext context) {
    final amber = StudioColors.amberOf(context);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final v in widget.values) _chip(context, v),
        if (_adding && widget.enabled)
          SizedBox(
            width: 220,
            height: 34,
            child: Focus(
              onKeyEvent: _onKey,
              child: TextField(
                key: const ValueKey('profile-chip-add-box'),
                controller: _box,
                focusNode: _focus,
                autofocus: true,
                style: TextStyle(
                  fontSize: 13,
                  color: StudioColors.inkOf(context),
                ),
                onSubmitted: _submit,
                onTapOutside: (_) => _submit(_box.text),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: StudioColors.raiseOf(context),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 9,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          )
        else if (widget.enabled)
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() => _adding = true),
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: amber),
              ),
              child: Center(
                widthFactor: 1,
                child: Text(
                  '+ add',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: amber,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _chip(BuildContext context, String value) => Container(
    height: 34,
    padding: const EdgeInsets.only(left: 10, right: 4),
    decoration: BoxDecoration(
      color: StudioColors.raiseOf(context),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: StudioColors.inkOf(context)),
          ),
        ),
        IconButton(
          tooltip: 'Remove $value',
          onPressed: widget.enabled
              ? () => widget.onChanged([...widget.values]..remove(value))
              : null,
          icon: const Icon(Icons.close, size: 14),
          color: StudioColors.mutedOf(context),
          disabledColor: StudioColors.mutedOf(context),
          constraints: const BoxConstraints.tightFor(width: 26, height: 26),
          padding: EdgeInsets.zero,
        ),
      ],
    ),
  );
}
