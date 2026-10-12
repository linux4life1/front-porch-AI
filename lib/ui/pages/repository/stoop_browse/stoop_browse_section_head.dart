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

import 'package:front_porch_ai/ui/pages/repository/stoop_glass.dart';

/// The hub's uppercase amber eyebrow (.hub-pick-eyebrow) heading a section.
class StoopBrowseSectionHead extends StatelessWidget {
  final String glyph;
  final String label;
  final double topPad;

  const StoopBrowseSectionHead(
    this.glyph,
    this.label, {
    super.key,
    this.topPad = 18,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, topPad, 16, 10),
      child: Row(
        children: [
          Text(glyph, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              color: stoopAmberText(context),
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
