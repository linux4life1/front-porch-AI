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

import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/chat/scene/scene_backdrop.dart';
import 'package:front_porch_ai/services/chat/scene/scene_backdrop_transition.dart';
import 'package:front_porch_ai/services/chat/scene/scene_rng.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/utils/world_cover.dart';
import 'scene_backdrop_game.dart';

/// The Setting place's picture behind the chat, under the Ambient Stage,
/// on a Flame game of its own ([SceneBackdropGame]) that plays the move
/// from one place to the next by the story's weather
/// (`scene_backdrop_transition.dart`), with the place's name on a card
/// while the move runs. The first picture of a chat shows at once; under
/// reduce motion a move is a still swap and the name shows briefly. The
/// cover is decoded once per picture off the UI thread; the game ticks
/// only while a move runs. Nothing here is a tap or a Tab stop.
class SceneBackdropLayer extends StatefulWidget {
  const SceneBackdropLayer({
    super.key,
    required this.backdrop,
    required this.conditionOf,
  });

  final SceneBackdrop backdrop;

  /// The story's weather condition when a move starts (null: none), which
  /// picks the move. Called then, not on every rebuild.
  final String? Function() conditionOf;

  @override
  State<SceneBackdropLayer> createState() => _SceneBackdropLayerState();
}

class _SceneBackdropLayerState extends State<SceneBackdropLayer> {
  late final SceneBackdropGame _game = SceneBackdropGame(
    paints: (
      veil: InkColors.dim(0.45),
      light: kSceneEffectPaintsDark.flash,
      fog: kSceneEffectPaintsDark.fog,
    ),
  )..onMoving = _onMoving;

  String? _shownCover;
  ui.Image? _image;
  ui.Image? _retiring;
  int _request = 0;
  bool _moving = false;
  bool _still = false;
  String? _title;
  Duration _titleFor = Duration.zero;

  @override
  void initState() {
    super.initState();
    _load(widget.backdrop, first: true);
  }

  @override
  void didUpdateWidget(SceneBackdropLayer old) {
    super.didUpdateWidget(old);
    if (widget.backdrop != old.backdrop) _load(widget.backdrop, first: false);
  }

  @override
  void dispose() {
    _retiring?.dispose();
    _image?.dispose();
    super.dispose();
  }

  Future<void> _load(SceneBackdrop backdrop, {required bool first}) async {
    if (backdrop.cover == _shownCover) return;
    final request = ++_request;
    final bytes = decodeWorldCoverBytes(backdrop.cover);
    if (bytes == null) return;
    final ui.Image image;
    try {
      image = await decodeImageFromList(bytes);
    } catch (e, st) {
      debugPrint(
        'SceneBackdropLayer: could not decode a place picture: $e\n$st',
      );
      return;
    }
    if (!mounted || request != _request) {
      image.dispose();
      return;
    }
    _shownCover = backdrop.cover;
    final still = _still;
    final instant = first || still;
    final kind = sceneMoveKindFor(widget.conditionOf());
    _retiring?.dispose();
    _retiring = _image;
    _image = image;
    _game.show(
      image,
      kind: kind,
      seed: fnv1a32(backdrop.placeId),
      instant: instant,
    );
    if (instant) {
      _retiring?.dispose();
      _retiring = null;
      if (!first) _showStillTitle(backdrop.placeName);
    } else {
      setState(() {
        _title = backdrop.placeName;
        _titleFor = Duration(
          milliseconds: (sceneMoveDuration(kind) * 1000).round(),
        );
      });
    }
  }

  void _onMoving(bool moving) {
    if (!mounted) return;
    setState(() => _moving = moving);
    if (!moving) {
      _retiring?.dispose();
      _retiring = null;
      _title = null;
    }
  }

  void _showStillTitle(String name) {
    setState(() {
      _title = name;
      _titleFor = const Duration(
        milliseconds: (kSceneMoveStillTitle * 1000) ~/ 1,
      );
    });
  }

  void _titleDone() {
    if (mounted && !_moving) setState(() => _title = null);
  }

  @override
  Widget build(BuildContext context) {
    _still = MediaQuery.disableAnimationsOf(context);
    final title = _title;
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          fit: StackFit.expand,
          children: [
            ExcludeFocus(child: GameWidget(game: _game, autofocus: false)),
            if (title != null && (_moving || _still))
              _PlaceTitleCard(
                key: ValueKey('scene_move_title_$title'),
                name: title,
                duration: _titleFor,
                still: _still,
                onEnd: _titleDone,
              ),
          ],
        ),
      ),
    );
  }
}

/// The place's name on a pill over the picture while the move runs: in
/// by a quarter of the move, out from four fifths, on the timeline both
/// surfaces share. A still swap fades it in and out over its own time.
class _PlaceTitleCard extends StatelessWidget {
  const _PlaceTitleCard({
    super.key,
    required this.name,
    required this.duration,
    required this.still,
    required this.onEnd,
  });

  final String name;
  final Duration duration;
  final bool still;

  /// Called when the card's time is up, on the widget clock.
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: const Alignment(0, 0.6),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: duration,
        onEnd: onEnd,
        builder: (context, p, child) {
          final alpha = still
              ? (p < 0.2 ? p / 0.2 : (p > 0.75 ? (1 - p) / 0.25 : 1.0))
              : sceneMoveTitle(p);
          return Opacity(opacity: alpha.clamp(0, 1), child: child);
        },
        child: Semantics(
          liveRegion: true,
          label: name,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: InkColors.dim(0.6),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              name,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: InkColors.onImage,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
