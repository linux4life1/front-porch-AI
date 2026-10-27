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

import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/chat/scene/scene_backdrop.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/utils/world_cover.dart';

/// How long a move from one place to the next takes to show.
const Duration kSceneBackdropTransition = Duration(milliseconds: 1200);

/// The Setting place's picture behind the chat, under the Ambient Stage,
/// with the same veil the built-in backgrounds wear so the bubbles stay
/// readable over any photo.
///
/// A change of place is a dissolve: the new picture fades in over the old
/// one and settles from a touch larger to its true size, the way a scene
/// cut reads on film, so a move from the tea rooms to the square is seen
/// and not just read in the sidebar. The first picture of a chat appears
/// at once; a re-saved picture of the same place dissolves too. Under
/// reduce motion the swap is instant. The cover is decoded once per
/// picture, never per frame, and nothing here is a tap.
class SceneBackdropLayer extends StatefulWidget {
  const SceneBackdropLayer({super.key, required this.backdrop});

  final SceneBackdrop backdrop;

  @override
  State<SceneBackdropLayer> createState() => _SceneBackdropLayerState();
}

class _SceneBackdropLayerState extends State<SceneBackdropLayer> {
  String? _decodedCover;
  Uint8List? _bytes;

  Uint8List? _bytesFor(String cover) {
    if (!identical(cover, _decodedCover) && cover != _decodedCover) {
      _decodedCover = cover;
      _bytes = decodeWorldCoverBytes(cover);
    }
    return _bytes;
  }

  @override
  Widget build(BuildContext context) {
    final backdrop = widget.backdrop;
    final bytes = _bytesFor(backdrop.cover);
    final still = MediaQuery.disableAnimationsOf(context);
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedSwitcher(
              duration: still ? Duration.zero : kSceneBackdropTransition,
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              layoutBuilder: _stacked,
              transitionBuilder: _dissolve,
              child: bytes == null
                  ? const SizedBox.expand(key: ValueKey('scene_backdrop_none'))
                  : Image.memory(
                      bytes,
                      key: ValueKey(
                        'scene_backdrop_${backdrop.placeId}_'
                        '${backdrop.version}',
                      ),
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      // A picture that will not decode shows the ground
                      // behind it; the editor's thumbnail reports the same
                      // file, so nothing is logged twice here.
                      errorBuilder: (_, _, _) => const SizedBox.expand(),
                    ),
            ),
            // The veil the built-in backgrounds wear, outside the dissolve
            // so the chat never darkens twice while two pictures overlap.
            ColoredBox(color: InkColors.dim(0.45)),
          ],
        ),
      ),
    );
  }

  /// Both pictures fill the layer while they overlap; the outgoing one
  /// stays under the incoming.
  static Widget _stacked(Widget? current, List<Widget> previous) =>
      Stack(fit: StackFit.expand, children: [...previous, ?current]);

  /// Fade in while settling from 1.04 to true size. The switcher runs the
  /// outgoing picture's animation backwards, so it fades out while easing
  /// the same touch larger, and the two meet in the middle.
  static Widget _dissolve(Widget child, Animation<double> animation) =>
      FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 1.04, end: 1.0).animate(animation),
          child: child,
        ),
      );
}
