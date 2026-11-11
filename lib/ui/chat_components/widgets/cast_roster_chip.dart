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

import 'dart:io';

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/chat_components/sidebar/character_state/presence_word.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// One face in the desktop cast strip. Soft guests carry the amber GUEST
/// mark and the **only** Promote control (member card / Lite NPC banner
/// stay status-only). A group member also carries the Away / Back control
/// ([presence] + [onSetAway]), the only place the user sets it by hand.
/// Matches the web CastBar.
class CastRosterChip extends StatelessWidget {
  final String name;
  final Color color;
  final bool isFocused;
  final bool isLite;
  final File? imageFile;
  final bool promoteEnabled;
  final VoidCallback onFocus;
  final VoidCallback? onPromote;

  /// Group members only: where the member is now. Away / Back shows for
  /// With you and Away (never At work, which the clock derives) and when
  /// [onSetAway] is given; null hides it, as on the web.
  final PresenceWhere? presence;

  /// Taps the control with the away value to set (true from With you).
  /// Null while a turn is busy: the service refuses until post-gen settles.
  final ValueChanged<bool>? onSetAway;

  /// Whether this chip draws the Away / Back control at all.
  bool get hasAwayControl =>
      !isLite &&
      (presence == PresenceWhere.withYou || presence == PresenceWhere.away);

  const CastRosterChip({
    super.key,
    required this.name,
    required this.color,
    required this.isFocused,
    required this.isLite,
    this.imageFile,
    this.promoteEnabled = true,
    required this.onFocus,
    this.onPromote,
    this.presence,
    this.onSetAway,
  });

  Widget _initial() => Text(
    name.isNotEmpty ? name[0] : '?',
    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
  );

  Widget _awayButton(BuildContext context) {
    final onScene = presence == PresenceWhere.withYou;
    final callback = onSetAway;
    final color = AppColors.formAccentOf(context);
    return Tooltip(
      message: onScene ? 'Mark as away' : 'Bring back',
      child: SizedBox(
        height: 20,
        child: TextButton(
          key: const ValueKey('cast-chip-away'),
          onPressed: callback == null ? null : () => callback(onScene),
          style: TextButton.styleFrom(
            foregroundColor: color,
            disabledForegroundColor: AppColors.textTertiary(context),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            minimumSize: const Size(0, 18),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
          child: Text(
            onScene ? 'Away' : 'Back',
            style: const TextStyle(fontSize: 9),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onFocus,
      child: SizedBox(
        width: isLite ? 72 : 48,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isFocused ? color : Colors.transparent,
                  width: 2,
                ),
              ),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: color,
                // No portrait, or only the flat placeholder a character
                // made without one carries: the initial.
                child: RealPortrait(
                  file: imageFile,
                  portrait: (_, file) => ClipOval(
                    child: Image.file(
                      file,
                      width: 32,
                      height: 32,
                      cacheWidth: kPortraitAvatarDecodeWidth,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _initial(),
                    ),
                  ),
                  noPortrait: (_) => _initial(),
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 9,
                color: isFocused
                    ? AppColors.textPrimary(context)
                    : AppColors.textTertiary(context),
              ),
            ),
            if (hasAwayControl) _awayButton(context),
            if (isLite) ...[
              Text(
                'GUEST',
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                  color: AppColors.porchAmberOf(context),
                ),
              ),
              if (onPromote != null)
                SizedBox(
                  height: 20,
                  child: TextButton(
                    onPressed: promoteEnabled ? onPromote : null,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.onAccentOf(context),
                      backgroundColor: AppColors.formAccentOf(context),
                      disabledForegroundColor: AppColors.onAccentOf(
                        context,
                      ).withValues(alpha: 0.5),
                      disabledBackgroundColor: AppColors.formAccentOf(
                        context,
                      ).withValues(alpha: 0.4),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      minimumSize: const Size(0, 18),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('Promote', style: TextStyle(fontSize: 9)),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
