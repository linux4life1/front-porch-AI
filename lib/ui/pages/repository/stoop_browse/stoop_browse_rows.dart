// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/backporch/backporch.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_card_tile.dart';

/// A horizontally-scrolling row of compact tiles (.hub-pickrow).
class StoopBrowsePickRow extends StatelessWidget {
  final List<StoopCard> cards;
  final ValueChanged<StoopCard> onOpen;

  const StoopBrowsePickRow({
    super.key,
    required this.cards,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 210,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        itemCount: cards.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, i) => SizedBox(
          width: 156,
          child: StoopCardTile(
            card: cards[i],
            compact: true,
            onTap: () => onOpen(cards[i]),
          ),
        ),
      ),
    );
  }
}

/// The main browse grid, as a sliver.
class StoopBrowseGridSliver extends StatelessWidget {
  final List<StoopCard> cards;
  final ValueChanged<StoopCard> onOpen;

  const StoopBrowseGridSliver({
    super.key,
    required this.cards,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 230,
          childAspectRatio: kStoopCardTileAspectRatio,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        delegate: SliverChildBuilderDelegate(
          (_, i) =>
              StoopCardTile(card: cards[i], onTap: () => onOpen(cards[i])),
          childCount: cards.length,
        ),
      ),
    );
  }
}
