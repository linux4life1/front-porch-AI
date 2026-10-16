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

import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// The creator's bottom Back / Next row (docs/design/creator-ui-spec.md,
/// "Desktop chrome"). While [busy] the whole row dims to 40% and both
/// buttons are disabled: the amber Next keeps its colour when disabled, so
/// without the dim it would look live.
class CreatorNavBar extends StatelessWidget {
  const CreatorNavBar({
    super.key,
    required this.busy,
    required this.showBack,
    required this.onBack,
    required this.onNext,
    required this.nextLabel,
    this.isLast = false,
    this.nextKey,
    this.showNext = true,
  });

  /// A generation or rewrite is running; both buttons are held.
  final bool busy;

  /// Whether the Back button is drawn at all (not on the first step).
  final bool showBack;
  final VoidCallback onBack;

  /// Null holds Next alone (a step that is not ready yet); it dims the same
  /// way.
  final VoidCallback? onNext;

  /// "Next: Greetings", "Save & Finish", ...
  final String nextLabel;

  /// The last step: Next shows a check instead of an arrow.
  final bool isLast;

  /// Key on the Next button, for callers whose tests find it by key.
  final Key? nextKey;

  /// False draws Back alone (World from Wiki after a stopped write).
  final bool showNext;

  @override
  Widget build(BuildContext context) {
    final amber = StudioColors.amberOf(context);
    final amberInk = StudioColors.amberInkOf(context);
    final ink = StudioColors.inkOf(context);
    const label = TextStyle(fontSize: 16, fontWeight: FontWeight.w500);
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 24),
      child: Opacity(
        opacity: busy ? 0.4 : 1,
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 14,
            children: [
              if (showBack)
                SizedBox(
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : onBack,
                    icon: const Icon(Icons.arrow_back, size: 18),
                    label: const Text('Back', style: label),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: ink,
                      disabledForegroundColor: ink,
                      backgroundColor: StudioColors.cardOf(context),
                      side: BorderSide(color: StudioColors.lineOf(context)),
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              if (showNext)
                Opacity(
                  opacity: !busy && onNext == null ? 0.4 : 1,
                  child: SizedBox(
                    width: 280,
                    height: 56,
                    child: ElevatedButton.icon(
                      key: nextKey,
                      onPressed: busy ? null : onNext,
                      iconAlignment: IconAlignment.end,
                      icon: Icon(
                        isLast ? Icons.check : Icons.arrow_forward,
                        size: 18,
                      ),
                      label: Text(nextLabel, style: label),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: amber,
                        foregroundColor: amberInk,
                        disabledBackgroundColor: amber,
                        disabledForegroundColor: amberInk,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
