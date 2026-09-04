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

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

// The two sub-controls that ride inside a FeatureRow's `child` slot on the
// Porch Life tab. Lifted out of porch_life_tab.dart when Chaos Mode's row was
// added: the tab was already past the 500-line cap, and CLAUDE.md's rule for
// that case is not "add carefully" but "extract something". Moving these two
// takes the tab back UNDER the cap while it gains a row — the
// character_grid_card precedent.
//
// They are public here rather than private because a file can only hold
// private classes for itself. Nothing else should use them; they are named for
// the rows they belong to.

/// The opt-in that keeps the story clock running with the Realism Engine off.
///
/// It exists as its own switch, rather than reading the Passage of Time row
/// above it, because that row already defaults ON — for years it meant nothing
/// while the engine was off, so nobody chose it in a world where it cost a
/// model call. Treating it as consent would hand every engine-off user a new
/// per-turn call without asking. Hence a separate, deliberate yes, and copy
/// that states the cost in the same breath as the benefit.
class StandaloneClockSwitch extends StatelessWidget {
  const StandaloneClockSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Keep the clock running without the engine',
                style: TextStyle(
                  color: AppColors.textSecondary(context),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'The engine normally judges how long each exchange took as '
                'part of work it is already doing. With it off, the clock '
                'needs one short AI call of its own each turn — so this costs '
                'a little speed. Left off, the clock simply holds still.',
                style: TextStyle(
                  color: AppColors.textTertiary(context),
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}

/// The "away for at least" dropdown that rides the absence-acknowledgement
/// row. Values are clamped to a known item so a hand-edited preference cannot
/// assert the dropdown (carried over verbatim from the old General tab).
class AwayThreshold extends StatelessWidget {
  const AwayThreshold({super.key, required this.storage});

  final StorageService storage;

  @override
  Widget build(BuildContext context) {
    const known = [12, 24, 72, 168];
    return Row(
      children: [
        Text(
          'Away for at least',
          style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 12,
          ),
        ),
        const Spacer(),
        DropdownButton<int>(
          value: known.contains(storage.absenceThresholdHours)
              ? storage.absenceThresholdHours
              : 24,
          dropdownColor: AppColors.cardOf(context),
          style: TextStyle(color: AppColors.textPrimary(context), fontSize: 12),
          items: const [
            DropdownMenuItem(value: 12, child: Text('12 hours')),
            DropdownMenuItem(value: 24, child: Text('a day')),
            DropdownMenuItem(value: 72, child: Text('3 days')),
            DropdownMenuItem(value: 168, child: Text('a week')),
          ],
          onChanged: (v) {
            if (v != null) storage.setAbsenceThresholdHours(v);
          },
        ),
      ],
    );
  }
}

/// Tavily API key under the Porch Life web-search row. Always
/// visible so a key can be pasted before the toggle is useful.
class WebSearchKeyField extends StatefulWidget {
  final StorageService storage;
  const WebSearchKeyField({super.key, required this.storage});

  @override
  State<WebSearchKeyField> createState() => _WebSearchKeyFieldState();
}

class _WebSearchKeyFieldState extends State<WebSearchKeyField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.storage.webSearchSettings.searchApiKey,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      obscureText: true,
      style: TextStyle(color: AppColors.textPrimary(context), fontSize: 13),
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Tavily API key',
        hintStyle: TextStyle(color: AppColors.textTertiary(context)),
      ),
      onChanged: widget.storage.webSearchSettings.setSearchApiKey,
    );
  }
}
