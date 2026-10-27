// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Worlds library grid: one card per top-level world, laid out like the
// old max-extent SliverGrid, plus the open world's places panel spanning
// the full width directly beneath the row that holds its card.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:front_porch_ai/models/models.dart';

class WorldLibraryGrid extends StatelessWidget {
  const WorldLibraryGrid({
    super.key,
    required this.worlds,
    required this.openId,
    required this.cardBuilder,
    required this.panelBuilder,
  });

  final List<World> worlds;

  /// The world whose places panel is showing, if any.
  final String? openId;
  final Widget Function(BuildContext context, World world) cardBuilder;
  final Widget Function(BuildContext context, World world) panelBuilder;

  static const double _maxCardWidth = 380;
  static const double _gap = 16;

  /// A card needs this much room for its cover, description, the places
  /// toggle and the chips, whatever its width.
  static const double _minCardHeight = 236;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.crossAxisExtent;
        // Same column rule as SliverGridDelegateWithMaxCrossAxisExtent.
        final columns = math.max(1, (width / (_maxCardWidth + _gap)).ceil());
        final cardWidth = (width - _gap * (columns - 1)) / columns;
        final cardHeight = math.max(cardWidth / 1.2, _minCardHeight);
        final rows = <List<World>>[
          for (var i = 0; i < worlds.length; i += columns)
            worlds.sublist(i, math.min(i + columns, worlds.length)),
        ];
        // Each entry is a row of cards, or the panel after the open row.
        final items = <Widget Function(BuildContext)>[];
        for (final row in rows) {
          items.add(
            (context) => Padding(
              padding: const EdgeInsets.only(bottom: _gap),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < row.length; i++) ...[
                    if (i > 0) const SizedBox(width: _gap),
                    SizedBox(
                      width: cardWidth,
                      height: cardHeight,
                      child: cardBuilder(context, row[i]),
                    ),
                  ],
                ],
              ),
            ),
          );
          final open = row.where((w) => w.id == openId).firstOrNull;
          if (open != null) {
            items.add(
              (context) => Padding(
                padding: const EdgeInsets.only(bottom: _gap),
                child: panelBuilder(context, open),
              ),
            );
          }
        }
        return SliverList.builder(
          itemCount: items.length,
          itemBuilder: (context, index) => items[index](context),
        );
      },
    );
  }
}
