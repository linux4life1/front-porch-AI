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

/// One face in the desktop cast strip. Tap = focus (never fires a turn).
/// Under the name: the honest presence word (With you / Away / At work —
/// status, not an action; the action moved to the right-click / hold menu
/// and the Character State word), then the **Next** pill: one tap queues
/// this member — full or lite guest — to answer the next turn (Director's
/// Note, quick beat, auto-advance). A queued face wears the filled pill,
/// the amber ring and the NEXT mark; tapping it again cancels. The pill is
/// always the bottom row — a guest's Promote rides above it, so the hold
/// sits at one height for every face.
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

  /// Group members only: where the member is now, shown as a status word.
  /// Null hides the row (host, 1:1 guests).
  final PresenceWhere? presence;

  /// Toggles Away with the presence value to set (true from With you).
  /// Null while a turn is busy; the menu hides the row when null.
  final ValueChanged<bool>? onSetAway;

  /// PR 5b: this member's Chaos Mode is on — a dice rides the face so the
  /// cast bar shows which members Chance Time rolls for without selecting
  /// each one. Web mirrors this on its cast chips.
  final bool chaosOn;

  /// Queues this member for the next turn (or cancels when [queued]).
  /// Null in 1:1 and while a turn is busy: the pill never scripts a turn.
  final VoidCallback? onQueue;

  /// True while this member is the queued speaker. The pill fills, the
  /// face gets the ring.
  final bool queued;

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
    this.chaosOn = false,
    this.onQueue,
    this.queued = false,
  });

  Widget _initial() => Text(
    name.isNotEmpty ? name[0] : '?',
    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
  );

  bool get hasPresenceWord =>
      !isLite &&
      (presence == PresenceWhere.withYou ||
          presence == PresenceWhere.away ||
          presence == PresenceWhere.atWork);

  /// Status only — the presence word describes, it no longer acts. The
  /// Away / Back action lives in the chip menu and on the Character State
  /// word (which has always toggled from there).
  Widget _presenceWord(BuildContext context) {
    final (label, tone) = switch (presence) {
      PresenceWhere.withYou => (
        'With you',
        AppColors.porchAmberOf(context),
      ),
      PresenceWhere.away => ('Away', AppColors.textSecondary(context)),
      PresenceWhere.atWork => ('At work', AppColors.textTertiary(context)),
      _ => ('', AppColors.textTertiary(context)),
    };
    return Tooltip(
      message: 'Status only — right-click this face (or hold) to send away',
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 9, color: tone),
      ),
    );
  }

  Widget _nextPill(BuildContext context) {
    final amber = AppColors.porchAmberOf(context);
    final enabled = onQueue != null;
    final fg = queued ? AppColors.onAccentOf(context) : amber;
    return Tooltip(
      message: queued
          ? 'Queued to speak next — tap to cancel'
          : 'Queue $name to answer the next turn',
      child: GestureDetector(
        onTap: enabled ? onQueue : null,
        child: Container(
          key: ValueKey('cast-chip-queue-${queued ? 'on' : 'off'}'),
          height: 20,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: queued ? amber : Colors.transparent,
            border: Border.all(
              color: enabled || queued ? amber : amber.withValues(alpha: 0.35),
              width: 1,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                queued ? Icons.check : Icons.skip_next,
                size: 10,
                color: enabled ? fg : fg.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 2),
              Text(
                queued ? 'NEXT' : 'Next',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  letterSpacing: queued ? 0.2 : 0,
                  color: enabled ? fg : fg.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMenu(BuildContext context, Offset global) {
    // Away / Back only where the user owns the state: With you ⇄ Away.
    // At work belongs to the clock's shift, same as the old chip's rule.
    final canToggle =
        onSetAway != null &&
        (presence == PresenceWhere.withYou || presence == PresenceWhere.away);
    final items = <String>[
      'focus',
      if (onQueue != null) queued ? 'unqueue' : 'queue',
      if (canToggle) presence == PresenceWhere.withYou ? 'away' : 'back',
      if (isLite && onPromote != null) 'promote',
    ];
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(global.dx, global.dy, global.dx, global.dy),
      items: [
        for (final id in items)
          PopupMenuItem(
            value: id,
            child: Text(switch (id) {
              'focus' => 'Focus',
              'queue' => 'Queue to speak next',
              'unqueue' => 'Cancel queued turn',
              'away' => 'Send away',
              'back' => 'Bring back',
              _ => 'Promote to full member',
            }),
          ),
      ],
    ).then((id) {
      if (!context.mounted || id == null) return;
      switch (id) {
        case 'focus':
          onFocus();
        case 'queue':
        case 'unqueue':
          onQueue?.call();
        case 'away':
          onSetAway?.call(true);
        case 'back':
          onSetAway?.call(false);
        case 'promote':
          onPromote?.call();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onSecondaryTapUp: (d) => _showMenu(context, d.globalPosition),
      onLongPress: () => _showMenu(
        context,
        (context.findRenderObject() as RenderBox?)?.localToGlobal(
              const Offset(0, 40),
            ) ??
            Offset.zero,
      ),
      child: InkWell(
        onTap: onFocus,
        child: SizedBox(
          width: isLite ? 76 : 56,
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
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Queued: an amber ring hugging the face — web mirrors
                    // it with .queued. The member's own colour behind the
                    // initial stays: it is who-they-is, not decoration.
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: queued
                            ? [
                                BoxShadow(
                                  color: AppColors.porchAmberOf(
                                          context,
                                        )
                                        .withValues(alpha: 0.9),
                                  spreadRadius: 2,
                                  blurRadius: 0,
                                ),
                              ]
                            : const [],
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
                    if (chaosOn)
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Tooltip(
                          message: '$name rolls with Chaos Mode',
                          child: Container(
                            padding: const EdgeInsets.all(1.5),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.chaosAccentOf(
                                context,
                              ).withValues(alpha: 0.9),
                            ),
                            child: const Icon(
                              Icons.casino,
                              size: 9,
                              // theme-keep: ink on the chaos gold badge.
                              color: AppColors.onChaosAccent,
                            ),
                          ),
                        ),
                      ),
                  ],
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
              if (hasPresenceWord) _presenceWord(context),
              // The Next pill is always the bottom row — guests stack
              // Promote above it, so "hold for the next turn" sits at one
              // height for every face in the strip.
              if (isLite && onPromote != null)
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
              if (onQueue != null || queued) _nextPill(context),
            ],
          ),
        ),
      ),
    );
  }
}
