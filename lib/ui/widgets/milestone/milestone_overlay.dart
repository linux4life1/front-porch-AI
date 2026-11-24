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

import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import 'package:front_porch_ai/database/database.dart' show GrowthMomentData;
import 'package:front_porch_ai/services/chat/growth_milestones.dart';
import 'package:front_porch_ai/services/chat/milestone_burst.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/widgets/warm_dialog.dart';

import 'milestone_burst_game.dart';
import 'milestone_card.dart';

/// Opens the milestone card for [moment] (§7): through the warm-dialog
/// path, the celebration behind it. Closing without an answer leaves a
/// pending moment waiting in Moments.
Future<void> showMilestoneCard(
  BuildContext context,
  ChatService chat,
  GrowthMomentData moment,
) async {
  await showWarmDialogOf<void>(
    context,
    builder: (_) => MilestoneOverlay(
      view: chat.milestoneViewOf(moment),
      replaying: chat.milestoneReplaying,
      onAnswer: (accept) => chat.answerMilestone(moment.id, accept: accept),
    ),
  );
  if (chat.milestoneShowing?.id == moment.id) chat.dismissMilestone();
}

/// The card over its celebration. Reduce motion: no particles, the badge
/// already stamped. Plain inputs (the words, whether it replays, how to
/// answer), so a widget test drives it without a live chat.
class MilestoneOverlay extends StatefulWidget {
  const MilestoneOverlay({
    super.key,
    required this.view,
    required this.replaying,
    required this.onAnswer,
  });

  final MilestoneView view;
  final bool replaying;
  final Future<MilestoneOutcome> Function(bool accept) onAnswer;

  @override
  State<MilestoneOverlay> createState() => _MilestoneOverlayState();
}

class _MilestoneOverlayState extends State<MilestoneOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _badge = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  );
  MilestoneBurstGame? _game;
  bool _busy = false;
  String? _notice;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final still = MediaQuery.disableAnimationsOf(context);
    final kind = burstKindForWire(widget.view.kind);
    if (still || kind == null) {
      _badge.value = 1;
      return;
    }
    _game = MilestoneBurstGame(
      burst: MilestoneBurst.plan(kind, burstSeedFor(widget.view.id)),
      cardWidth: 340,
    );
    Future<void>.delayed(
      Duration(milliseconds: (kBurstBadgeAt * 1000).round()),
      () {
        if (mounted) _badge.forward();
      },
    );
  }

  @override
  void dispose() {
    _badge.dispose();
    super.dispose();
  }

  Future<void> _answer(bool accept) async {
    // Latched before the first await: a second tap that lands before the
    // next frame (the button is not yet disabled) answers nothing.
    if (_busy) return;
    _busy = true;
    setState(() {});
    final outcome = await widget.onAnswer(accept);
    if (!mounted) return;
    if (outcome == MilestoneOutcome.bogeyCapFull) {
      final who = widget.view.ownerName.isEmpty
          ? 'This character'
          : widget.view.ownerName;
      setState(() {
        _busy = false;
        _notice =
            '$who already carries three bogies — overcome one, then accept '
            'this from Moments.';
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    final width = math.min(340.0, MediaQuery.sizeOf(context).width - 32);
    _game?.cardWidth = width;
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          if (_game != null)
            Positioned.fill(
              child: IgnorePointer(child: GameWidget(game: _game!)),
            ),
          Center(
            child: SizedBox(
              width: width,
              child: AnimatedBuilder(
                animation: _badge,
                builder: (_, _) => MilestoneCard(
                  view: view,
                  replaying: widget.replaying,
                  busy: _busy,
                  notice: _notice,
                  badge: Curves.easeOutBack.transform(_badge.value),
                  onAccept: () => _answer(true),
                  onReject: () => _answer(false),
                  onClose: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens the card when the chat raises one (the Chance-Time pending-flag
/// pattern, answered from the chat page's change listener). One open at a
/// time; a new moment opens once the previous card closed.
class MilestonePrompt {
  String? _openId;

  void onChatChanged(BuildContext context, ChatService chat) {
    final m = chat.milestoneShowing;
    if (m == null || _openId != null) return;
    _openId = m.id;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!context.mounted) {
        _openId = null;
        return;
      }
      await showMilestoneCard(context, chat, m);
      _openId = null;
    });
  }
}
