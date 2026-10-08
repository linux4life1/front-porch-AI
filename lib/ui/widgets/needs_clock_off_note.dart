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

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// The one line under every Needs switch while Passage of time is off
/// (docs/design/needs-on-the-clock.md, "Clock off"). With the clock off
/// nothing wears, so bars that sit still are working as meant; without this
/// line they read as broken. The phone says the same words
/// (web_ui/src/components/realism/NeedsClockOffNote.tsx).
///
/// "Off" is the Porch Life Passage of Time switch (`passageOfTimeDefault`),
/// the live clock gate. Pass [clockOn] where the caller already holds it;
/// otherwise the note reads it from [StorageService] and rebuilds when it
/// flips. Pumped without a StorageService (a form tested on its own), the
/// clock reads as on and nothing shows.
class NeedsClockOffNote extends StatelessWidget {
  const NeedsClockOffNote({
    super.key,
    this.clockOn,
    this.padding = const EdgeInsets.only(top: 6),
  });

  static const text =
      'With Passage of time off, hunger, bathroom and energy wear a little each reply; the rest move only when the story says so.';

  final bool? clockOn;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    if (clockOn ?? _liveClockOn(context)) return const SizedBox.shrink();
    return Padding(
      padding: padding,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          height: 1.35,
          color: AppColors.textSecondary(context),
        ),
      ),
    );
  }

  static bool _liveClockOn(BuildContext context) {
    try {
      return context.select<StorageService, bool>(
        (s) => s.realismSettings.passageOfTimeDefault,
      );
    } on ProviderNotFoundException {
      return true;
    }
  }
}
