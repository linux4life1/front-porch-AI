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

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/chat/growth_milestones.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/theme/milestone_palette.dart';

import 'milestone_overlay.dart';

/// Loads one owner's Moments (docs/design/boons-and-bogies.md §7) and
/// re-reads them whenever [ChatService.milestoneRevision] moves, so the
/// Boons & Bogies line's header dot and its MOMENTS section draw from one
/// list. The web line (ChatSidebar) does the same through
/// GET /api/chat/tools/growth/moments.
class MomentsLoader extends StatefulWidget {
  const MomentsLoader({
    super.key,
    required this.chat,
    required this.ownerId,
    required this.builder,
  });

  final ChatService chat;
  final String ownerId;
  final Widget Function(BuildContext, List<MilestoneView>) builder;

  @override
  State<MomentsLoader> createState() => _MomentsLoaderState();
}

class _MomentsLoaderState extends State<MomentsLoader> {
  String _key = '';
  List<MilestoneView> _moments = const [];

  void _maybeLoad() {
    // No owner (the line is gated off): touch nothing on the chat — the
    // revision is a bridge member, and the golden fakes render this line.
    if (widget.ownerId.isEmpty) {
      _key = '';
      _moments = const [];
      return;
    }
    final key = '${widget.ownerId}|${widget.chat.milestoneRevision}';
    if (key == _key) return;
    _key = key;
    unawaited(
      widget.chat
          .milestoneViewsFor(widget.ownerId)
          .then((list) {
            if (mounted && _key == key) setState(() => _moments = list);
          })
          .catchError((Object e) {
            debugPrint('[Moments] read failed: $e');
          }),
    );
  }

  @override
  Widget build(BuildContext context) {
    _maybeLoad();
    return widget.builder(context, _moments);
  }
}

/// "2 new" — the unread dot on the Boons & Bogies header.
class MomentsUnreadDot extends StatelessWidget {
  const MomentsUnreadDot({super.key, required this.moments});

  final List<MilestoneView> moments;

  @override
  Widget build(BuildContext context) {
    final unread = moments.where((m) => !m.seen || m.pending).length;
    if (unread == 0) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        color: MilestonePalette.gold,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$unread new',
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: MilestonePalette.onGold,
        ),
      ),
    );
  }
}

/// The MOMENTS section of the Boons & Bogies line: newest first; a pending
/// one is answered here (ASKS · Reject · Accept), a decided one replays its
/// celebration.
class MomentsSection extends StatefulWidget {
  const MomentsSection({super.key, required this.chat, required this.moments});

  final ChatService chat;
  final List<MilestoneView> moments;

  @override
  State<MomentsSection> createState() => _MomentsSectionState();
}

class _MomentsSectionState extends State<MomentsSection> {
  /// The line under the header when an Accept could not land (the bogey cap
  /// is full) — the web section shows the same words in the same place.
  String? _notice;

  void _onOutcome(MilestoneView view, MilestoneOutcome outcome) {
    if (!mounted) return;
    setState(
      () => _notice = outcome == MilestoneOutcome.bogeyCapFull
          ? '${view.ownerName.isEmpty ? 'This character' : view.ownerName} '
                'already carries three bogies — overcome one first.'
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.moments.isEmpty) return const SizedBox.shrink();
    final tertiary = AppColors.textTertiary(context);
    return Padding(
      padding: const EdgeInsets.only(left: 20, top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'MOMENTS',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: tertiary,
            ),
          ),
          if (_notice != null)
            Text(_notice!, style: TextStyle(fontSize: 11, color: tertiary)),
          const SizedBox(height: 4),
          for (final m in widget.moments)
            _MomentRow(chat: widget.chat, view: m, onOutcome: _onOutcome),
        ],
      ),
    );
  }
}

class _MomentRow extends StatelessWidget {
  const _MomentRow({
    required this.chat,
    required this.view,
    required this.onOutcome,
  });

  final ChatService chat;
  final MilestoneView view;
  final void Function(MilestoneView, MilestoneOutcome) onOutcome;

  String get _detail => [
    view.text,
    view.statusLabel,
    if (view.receipt.isNotEmpty)
      view.receipt.replaceFirst(RegExp(r'^(Seen|Coped) in '), ''),
  ].where((s) => s.isNotEmpty).join(' · ');

  /// Replay raises the card on the chat; the chat page's [MilestonePrompt]
  /// opens it, like any other moment (opening it here too would stack two).
  Future<void> _replay(BuildContext context) => chat.replayMilestone(view.id);

  @override
  Widget build(BuildContext context) {
    final primary = AppColors.textPrimary(context);
    final tertiary = AppColors.textTertiary(context);
    final unread = !view.seen || view.pending;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: unread ? MilestonePalette.gold : null,
              border: unread
                  ? null
                  : Border.all(color: AppColors.borderOf(context)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      if (view.pending)
                        const WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: _AsksTag(),
                        ),
                      TextSpan(text: view.title),
                    ],
                  ),
                  style: TextStyle(fontSize: 12.5, color: primary),
                ),
                Text(
                  _detail,
                  maxLines: 2,
                  overflow: TextOverflow.fade,
                  style: TextStyle(fontSize: 10.5, color: tertiary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          if (view.pending) ...[
            _pill(context, 'Reject', () => _answer(false)),
            const SizedBox(width: 4),
            _pill(context, 'Accept', () => _answer(true), gold: true),
          ] else
            _pill(context, 'Replay', () => _replay(context)),
        ],
      ),
    );
  }

  Future<void> _answer(bool accept) async =>
      onOutcome(view, await chat.answerMilestone(view.id, accept: accept));

  Widget _pill(
    BuildContext context,
    String label,
    VoidCallback onTap, {
    bool gold = false,
  }) {
    return SizedBox(
      height: 32,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: const Size(0, 32),
          backgroundColor: gold ? MilestonePalette.gold : null,
          foregroundColor: gold
              ? MilestonePalette.onGold
              : AppColors.textPrimary(context),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
            side: gold
                ? BorderSide.none
                : BorderSide(color: AppColors.borderOf(context)),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _AsksTag extends StatelessWidget {
  const _AsksTag();

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(right: 4),
    padding: const EdgeInsets.symmetric(horizontal: 5),
    decoration: BoxDecoration(
      color: MilestonePalette.gold,
      borderRadius: BorderRadius.circular(4),
    ),
    child: const Text(
      'ASKS',
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w800,
        color: MilestonePalette.onGold,
      ),
    ),
  );
}
