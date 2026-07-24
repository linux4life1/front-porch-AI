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
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:front_porch_ai/ui/theme/app_colors.dart';

part 'absence_recap_banner.g.dart';

/// Ephemeral per-session dismissed state for the "Previously on…" banner —
/// @riverpod Notifier (project codegen standard). One set of dismissed
/// session ids covers every session; keepAlive because a dismissal should
/// survive the banner unmounting (autoDispose would resurrect it).
@Riverpod(keepAlive: true)
class DismissedAbsenceBanners extends _$DismissedAbsenceBanners {
  @override
  Set<String> build() => <String>{};

  void dismiss(String sessionId) => state = {...state, sessionId};
}

/// "Previously on…" welcome-back banner (living-time-features.md §2).
///
/// Deliberately speaks in the APP's voice — like a game's welcome-back
/// screen — never the character's; only the separate opt-in puts absence
/// awareness in the character's mouth. The phrase is a coarse word bucket
/// ("a few days"), never digits, and everything shown is computed locally
/// from the chat's own last-message timestamp (see AbsenceTracker's
/// privacy contract). Parent gates rendering: banner off / under threshold /
/// fresh chat → this widget is never built. Values arrive as plain
/// constructor params from the legacy Provider tree (the documented
/// widget-boundary bridge — no Provider.of here).
class AbsenceRecapBanner extends ConsumerWidget {
  final String sessionId;
  final String phrase;
  final String recap;

  const AbsenceRecapBanner({
    super.key,
    required this.sessionId,
    required this.phrase,
    required this.recap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dismissed = ref.watch(dismissedAbsenceBannersProvider);
    if (dismissed.contains(sessionId)) return const SizedBox.shrink();

    final amber = AppColors.porchAmberOf(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: amber.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.history, size: 18, color: amber),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'It\'s been $phrase — where we left off:',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary(context),
                  ),
                ),
                if (recap.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    recap.trim(),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: AppColors.textSecondary(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.close,
              size: 16,
              color: AppColors.iconSecondary(context),
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: 'Dismiss',
            onPressed: () => ref
                .read(dismissedAbsenceBannersProvider.notifier)
                .dismiss(sessionId),
          ),
        ],
      ),
    );
  }
}
